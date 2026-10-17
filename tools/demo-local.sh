#!/usr/bin/env bash
# One command local demo: anvil + mock Ascend + Monarchy core + MONARCH launch + Lodestar + demo data.
# Leaves anvil running on :8545 so the website (npm run web) has a populated chain.
set -euo pipefail
cd "$(dirname "$0")/.."

export RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
# anvil's first account; never use this key anywhere else
export PRIVATE_KEY=${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
export ASCEND_MODE=mock
# the Team Treasury recipient (anvil's second account); ActivateLodestar requires it to be set explicitly
export TREASURY=${TREASURY:-0x70997970C51812dc3A010C7d01b54f0D7d0dC79C}
PROFILE=${FOUNDRY_PROFILE:-default}

if ! cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
  echo "starting anvil (block time 1s)"
  anvil --block-time 1 --silent &
  ANVIL_PID=$!
  for _ in $(seq 1 50); do cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1 && break; sleep 0.2; done
fi

rm -f deployments/31337.json
for s in DeployMocks DeployCore LaunchOnAscend ActivateLodestar DemoFlow; do
  echo "== $s"
  FOUNDRY_PROFILE=$PROFILE forge script "contracts/script/$s.s.sol:$s" --rpc-url "$RPC_URL" --broadcast --slow -q
done

echo
echo "Local chain ready: deployments/31337.json"
echo "Run 'npm run web' and connect MetaMask to http://127.0.0.1:8545 (chain 31337)."
if [ -n "${ANVIL_PID:-}" ]; then
  echo "anvil is running (pid $ANVIL_PID). Ctrl+C to stop."
  wait "$ANVIL_PID"
fi
