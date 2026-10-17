# Monarchy

**Ascend to Monarchy.** Fee routing, locks and vesting for tokens launched on [Ascend](https://app.ascendlaunch.xyz) on Kinetiq's Elysium testnet. No fees on anything.

| | What it does |
|---|---|
| **Lodestar** | A fee router for one Ascend token. The dev launches on Ascend's own site and keeps the dev buy, then hands the token's *creator role* to its Lodestar. From then on every creator fee lands in the router, and anyone can call `distribute()`: token-side fees are burned, and quote-side fees split by the creator's percentages into **buyback and burn**, **holder rewards** (Exile) and a **Team Treasury** (streamed through Sandfall). Enrols in Ascend's listing set-aside by default. Split changes wait behind a 12 hour timelock, and the creator role can be locked so the router can't be swapped out. |
| **Exile** | Locks ERC-20s (including v2 LP), ERC-721s and ERC-1155s. Locks can be extended, never shortened, cancelled or transferred. ERC-20 locks earn holder rewards by tier, paid as a 7 day drip, and stop earning the second they unlock. |
| **Sandfall** | Vesting streams (linear, cliff, monthly steps) in any ERC-20 or native HYPE. The creator decides at creation whether a stream can be cancelled, and the UI badges it. Streams aren't transferable. Rolling streams back Lodestar's Team Treasury. |

MONARCH's own tiers:

| Tier | Lock | Multiplier | |
|---|---|---|---|
| Peasant | 1 day | 0.5x | *Everyone starts somewhere.* |
| Knight | 3 days | 1x | *Sworn to the kingdom.* |
| Duke | 7 days | 1.5x | *Next in line.* |
| Monarch | 1 month | 3x | *Steal the crown.* |

No lock, no rewards. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit and [docs/DEMO.md](docs/DEMO.md) for the demo script.

## Repo layout

```
contracts/src        Lodestar, LodestarFactory, AscendSwapper, Exile, Sandfall, interfaces, mocks
contracts/test       Foundry tests (88), including a full mock-Ascend integration test
contracts/script     DeployMocks, DeployCore, LaunchOnAscend, ActivateLodestar, DemoFlow
deployments/         <chainId>.json written by the scripts and read by the website
web/                 Vite + React + wagmi site (dashboard, Lodestar, Exile, Sandfall)
tools/               demo-local.sh, export-abis.mjs, offline solc shim
```

## Build and test

Needs Node 20+ and [Foundry](https://getfoundry.sh) (`curl -L https://foundry.paradigm.xyz | bash && foundryup`).

```bash
git clone --recursive https://github.com/monarchy-fi/monarchy && cd monarchy
npm install
forge test            # or: npm test
```

In a sandbox that can't download solc, use `FOUNDRY_PROFILE=offline` (wraps the solc npm package).

## Run the demo locally (one command)

```bash
npm run demo:local    # anvil + mock Ascend + Monarchy + MONARCH launch + Lodestar + demo data
npm --prefix web install
npm run web           # http://localhost:5173
```

Point MetaMask/Rabby at `http://127.0.0.1:8545` (chain 31337) and import anvil's first account to act as the dev/steward. On a dev server, `http://localhost:5173/?mock` connects that account without a browser wallet.

## Deploy to Elysium testnet

Use a **fresh burner wallet**, never your main wallet. Get testnet HYPE from the [Elysium faucet](https://elysium.kinetiq.xyz/testnet-faucet).

```bash
cp .env.example .env     # set PRIVATE_KEY (the burner), keep the Ascend addresses as they are
set -a; source .env; set +a

# 1. Monarchy core: Exile, Sandfall, Lodestar implementation, AscendSwapper, LodestarFactory
npm run deploy:testnet          # writes deployments/99801.json

# 2. A token on Ascend. Either launch on Ascend's site and record it:
TOKEN=0xYourToken npm run launch:testnet
#    or launch from the script (simulate first, then add --broadcast):
npm run launch:testnet
npm run launch:testnet -- --broadcast

# 3. Hand the creator role to the token's Lodestar and activate it (40/40/20, MONARCH tiers,
#    30 day treasury stream, listing set-aside on, creator role locked for a year)
npm run activate:testnet

# 4. The website reads deployments/99801.json
npm run abis && npm run web
```

Mock USDC on Elysium has a public `mint`, so you can fund wallets for trading with
`cast send $QUOTE "mint(address,uint256)" $YOUR_ADDRESS 1000000000000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY`.

If buybacks through the Infinity vault misbehave on testnet, Lodestar keeps the buyback share in `buybackReserve` and still pays holders and the treasury. To activate with no buyback route at all, have the factory owner run `setDefaultSwapper(0x0)` before step 3.

Ascend addresses used (Elysium testnet, chain 99801):

| | |
|---|---|
| AscendLaunchpad | `0x6d01f6644bbf1b5074472D3e85aa1465B4d2bF3d` |
| ListingDesk | `0x06DbB5eF794BA3C0F6F0ddC6164617Cf21811a77` |
| PancakeSwap Infinity CLPoolManager | `0x12E84206cB53aE0df055482ebc4658635096E1aA` |
| Infinity Vault | `0x2B738A9A69b7a45C9dA6B519f6bE6efBfb912aec` |
| Mock USDC (quote) | `0x84Cc00D13173f7016Bbab22A736dBf75A154cFE2` |

## Status

Testnet demo for the Ascend x Elysium Builder Competition. Not audited. Roadmap: plug-ins for other Elysium launchpads, a kHYPE treasury option, MONARCH treasury buying Ascend NFTs if they're listed, and a "send fees to a router" checkbox on Ascend's launch form.

## License

MIT
