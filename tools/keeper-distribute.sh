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
#   itself can fix that. A read-only poke first says whether the pool is more than 720 hours behind;
#   if so this script calls Exile.poke(poolId, 720) until the pool reports it is caught up (at most 40
#   times) before distributing. If distribute() still fails, or its receipt says the holders' share was
#   parked (HoldersPayoutFailed), it catches up again and tries once more. If that still fails, the
#   script fails: red is the point.
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
PARKED_TOPIC=$(cast sig-event "HoldersPayoutFailed(uint256)")
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

# True when the last receipt carries HoldersPayoutFailed: the holders' share stayed in the router.
holders_parked() {
  jq -e --arg t "$PARKED_TOPIC" '[.logs[].topics[0]] | index($t) != null' <<<"$LAST_RECEIPT" >/dev/null
}

# A read-only poke: true when one call of 720 buckets reaches the present.
pool_is_current() {
  [ "$(cast call "$EXILE" "poke(uint256,uint256)(bool)" "$PID" 720 --rpc-url "$RPC_URL")" = "true" ]
}

# Poke the router's Exile pool forward, 720 hour buckets at a time, until it reports caught up.
catch_up() {
  local i
  for i in $(seq 1 40); do
    if pool_is_current; then
      echo "Exile pool $PID is caught up"
      return 0
    fi
    echo "Exile pool $PID is behind: poke $i of at most 40"
    send "$EXILE" "poke(uint256,uint256)" "$PID" 720
  done
  echo "::warning::Exile pool $PID is still behind after 40 pokes"
}

if ! pool_is_current; then
  echo "Exile pool $PID is more than 720 hours behind; catching it up before distributing"
  catch_up
fi

if ! distribute; then
  echo "distribute() failed; catching Exile up, then one retry"
  catch_up
  distribute
elif holders_parked; then
  echo "::warning::the holders' share was parked (Exile payout failed); catching Exile up, then one retry"
  catch_up
  distribute
  if holders_parked; then
    echo "::error::the holders' share is still parked after a retry"
    exit 1
  fi
fi
