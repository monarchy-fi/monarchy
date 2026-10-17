#!/usr/bin/env bash
# The keeper's distribute() call, as .github/workflows/distribute.yml runs it every 3 hours.
#
#   RPC_URL=... KEEPER_PRIVATE_KEY=... tools/keeper-distribute.sh [deployments/<chainId>.json] [chainId]
#
# - Sends nothing unless the RPC answers the expected chain id (RPC_URL is a repository variable, so a
#   wrong or hostile RPC must stop the run, not get a signed transaction).
# - Lets cast estimate the gas instead of using a fixed limit, and checks the receipt: a reverted
#   transaction fails this script, where `cast send` alone exits 0 and the run would look green.
# - Recovery: Exile walks every idle hour of its reward pool inside notifyReward, so after a long
#   keeper outage distribute() can need more gas than one block allows, and nothing in distribute()
#   itself can fix that. A read-only poke first says whether the pool is more than a few hours behind
#   (CURRENT_WITHIN); if so this script pokes Exile.MAX_BUCKETS_PER_CALL buckets at a time until the pool
#   reports it is caught up (at most 40 times) before distributing. Catching up first also keeps the
#   payouts inside distribute() light, so cast's gas estimate can't land where a payout runs out of gas
#   inside its try/catch while the outer call succeeds. If distribute() still
#   fails, or its receipt says a holder payout was parked (HoldersPayoutFailed or
#   TokenHoldersPayoutFailed), it catches up again and tries once more. If that still fails, the script
#   fails: red is the point.
set -euo pipefail

FILE=${1:-deployments/99801.json}
CHAIN_ID=${2:-${CHAIN_ID:-99801}}
: "${RPC_URL:?set RPC_URL}"
: "${KEEPER_PRIVATE_KEY:?set KEEPER_PRIVATE_KEY}"

got=$(cast chain-id --rpc-url "$RPC_URL")
if [ "$got" != "$CHAIN_ID" ]; then
  echo "::error::RPC answers chain id '$got', expected $CHAIN_ID. Not sending anything."
  exit 1
fi

LODESTAR=$(jq -r '.lodestar // empty' "$FILE")
if ! [[ "$LODESTAR" =~ ^0x[0-9a-fA-F]{40}$ ]] || [ "$LODESTAR" = "0x0000000000000000000000000000000000000000" ]; then
  echo "::error::$FILE has no lodestar address."
  exit 1
fi
if [ "$(cast code "$LODESTAR" --rpc-url "$RPC_URL")" = "0x" ]; then
  echo "::error::no contract at $LODESTAR on chain $CHAIN_ID."
  exit 1
fi
EXILE=$(cast call "$LODESTAR" "exile()(address)" --rpc-url "$RPC_URL")
PID=$(cast to-dec "$(cast call "$LODESTAR" "exilePoolId()" --rpc-url "$RPC_URL")")
CURRENT_WITHIN=6 # hours; the keeper runs every 3, so a healthy pool is never further behind
MAXB=$(cast to-dec "$(cast call "$EXILE" "MAX_BUCKETS_PER_CALL()" --rpc-url "$RPC_URL")")
PARKED_TOPIC=$(cast sig-event "HoldersPayoutFailed(uint256)")
TOKEN_PARKED_TOPIC=$(cast sig-event "TokenHoldersPayoutFailed(uint256)")
LAST_RECEIPT=""

# send <to> <signature> [args...]: cast estimates the gas; the receipt must say success.
send() {
  local out status hash
  if ! out=$(cast send "$@" --json --rpc-url "$RPC_URL" --private-key "$KEEPER_PRIVATE_KEY"); then
    echo "cast send failed before a receipt came back (estimate or submit)"
    return 1
  fi
  LAST_RECEIPT=$out
  status=$(jq -r '.status' <<<"$out")
  hash=$(jq -r '.transactionHash' <<<"$out")
  if [ "$status" != "0x1" ]; then
    echo "transaction $hash reverted (status $status)"
    return 1
  fi
  echo "transaction $hash confirmed, gas used $(cast to-dec "$(jq -r '.gasUsed' <<<"$out")")"
}

distribute() {
  echo "distribute() on $LODESTAR"
  send "$LODESTAR" "distribute()"
}

# True when the last receipt carries HoldersPayoutFailed or TokenHoldersPayoutFailed: a holder payout
# stayed in the router.
holders_parked() {
  jq -e --arg a "$PARKED_TOPIC" --arg b "$TOKEN_PARKED_TOPIC" \
    '[.logs[].topics[0]] | (index($a) != null) or (index($b) != null)' <<<"$LAST_RECEIPT" >/dev/null
}

# A read-only poke: true when the pool is at most CURRENT_WITHIN hours behind.
pool_is_current() {
  [ "$(cast call "$EXILE" "poke(uint256,uint256)(bool)" "$PID" "$CURRENT_WITHIN" --rpc-url "$RPC_URL")" = "true" ]
}

# Poke the router's Exile pool forward, MAXB hour buckets at a time, until it reports caught up.
catch_up() {
  local i
  for i in $(seq 1 40); do
    if pool_is_current; then
      echo "Exile pool $PID is caught up"
      return 0
    fi
    echo "Exile pool $PID is behind: poke $i of at most 40"
    send "$EXILE" "poke(uint256,uint256)" "$PID" "$MAXB"
  done
  echo "::warning::Exile pool $PID is still behind after 40 pokes"
}

if ! pool_is_current; then
  echo "Exile pool $PID is more than $CURRENT_WITHIN hours behind; catching it up before distributing"
  catch_up
fi

if ! distribute; then
  echo "distribute() failed; catching Exile up, then one retry"
  catch_up
  distribute
  if holders_parked; then
    echo "::error::a holder payout was parked on the retry"
    exit 1
  fi
elif holders_parked; then
  echo "::warning::a holder payout was parked (Exile payout failed); catching Exile up, then one retry"
  catch_up
  distribute
  if holders_parked; then
    echo "::error::a holder payout is still parked after a retry"
    exit 1
  fi
fi
