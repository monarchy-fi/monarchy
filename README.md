<div align="center">

<img src="web/public/crown.svg" alt="Monarchy crown" width="88" height="88" />

# Monarchy

### Fee routing, locks and vesting for tokens launched on Ascend

[![CI](https://github.com/monarchy-fi/monarchy/actions/workflows/ci.yml/badge.svg)](https://github.com/monarchy-fi/monarchy/actions/workflows/ci.yml)
[![Tests: 131 passing](https://img.shields.io/badge/Foundry-131%20tests%20passing-2E7D5B.svg)](contracts/test)
[![Solidity 0.8.28](https://img.shields.io/badge/Solidity-0.8.28-363636.svg)](foundry.toml)
[![Elysium testnet](https://img.shields.io/badge/Elysium%20testnet-chain%2099801-6930EA.svg)](https://elysium.kinetiq.xyz/testnet-explorer)
[![Protocol fees: none](https://img.shields.io/badge/protocol%20fees-none-C9A24A.svg)](#how-it-works)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Every creator fee burned, bought back, paid to locked holders or streamed to the team in the open. Monarchy takes nothing.**

[Website](https://monarchy.fi) · [Docs](https://docs.monarchy.fi) · [X](https://x.com/monarchyfi) · [Architecture](docs/ARCHITECTURE.md) · [Demo script](docs/DEMO.md) · [Testnet contracts](#live-on-elysium-testnet)

</div>

---

## Why Monarchy

Ascend has no token, and its NFT is capped at 500. People who want a piece of Ascend usually reach for the launchpad's own token, and here there isn't one. Monarchy aims to be that token: a liquid coin whose trading fees flow back to the holders who lock it, built on the same tools it offers every other Ascend project.

On Ascend the creator role collects half of every 1% swap fee, in both the token and the quote asset. Without Monarchy that money sits in one wallet, holders earn nothing for holding, and promises about buybacks or vesting can't be checked on chain. Monarchy replaces those promises with contracts.

## How it works

```mermaid
flowchart LR
    A[Ascend pool<br/>creator fees] --> L(Lodestar)
    L -->|token side| B[Burned]
    L -->|quote, burn share| S[AscendSwapper] --> B
    L -->|quote, holder share| E[Exile<br/>3 day drip to lockers]
    L -->|quote, treasury share| T[Sandfall<br/>rolling Team Treasury stream]
```

| | What it does |
|---|---|
| **Lodestar** | A fee router for one Ascend token. The creator launches on Ascend's own site and keeps the dev buy, then hands the token's *creator role* to its Lodestar. Anyone can call `distribute()`, and the team's keeper calls it every 3 hours so fees never pile up into one big payout: token-side fees are burned, and quote-side fees split by the creator's percentages into **buyback and burn**, **holder rewards** (Exile) and a **Team Treasury** (streamed through Sandfall). Enrols in Ascend's listing set-aside by default. |
| **Exile** | Locks ERC-20s (including v2 LP), ERC-721s and ERC-1155s. Locks can be extended, never shortened, cancelled or transferred. ERC-20 locks earn holder rewards by tier, paid as a 3 day drip, and stop earning the second they unlock. |
| **Sandfall** | Vesting streams (linear, cliff or monthly steps) in any non-rebasing ERC-20 or native HYPE. The creator decides at creation whether a stream can be cancelled, and the site badges it. Rolling streams back Lodestar's Team Treasury. |

### Exile tiers

| Tier | Lock | Multiplier | |
|---|---|---|---|
| Peasant | 1 day | 0.5x | *Everyone starts somewhere.* |
| Knight | 3 days | 1x | *Sworn to the kingdom.* |
| Duke | 7 days | 1.5x | *Next in line.* |
| Monarch | 1 month | 3x | *Steal the crown.* |

No lock, no rewards. With four holders each locking 10,000 tokens and fees dripping at 100 USDC a day, holders who keep re-locking for 30 days earn 250, 500, 750 and 1,500 USDC respectively.

## Security model

- **No upgrades.** Each Lodestar is an EIP-1167 clone of a fixed implementation. Nobody can change its code.
- **No sweep.** There is no rescue or withdraw function. Funds can only go to the burn address, Exile, Sandfall or the swapper. Locked tokens and vesting streams can only go to their owners.
- **Slow changes.** Split, swapper and slippage changes, and Exile tier changes, wait behind a 12 hour timelock and expire if not executed within 7 days after it. Settings chosen at activation apply immediately.
- **Locked router.** The creator role can be locked to the Lodestar for a chosen period, so the router can't be swapped out. A lock can't be placed while a hand-off is pending.
- **Guarded buybacks.** The minimum output comes from Ascend's on-chain EMA price, never the spot price, less the pool fee and a slippage allowance (default 10%, min 1%, max 20%). Each buy spends at most 0.5% of the pool's quote depth, so it moves the price less than a sandwich pays in fees. Bigger amounts and skipped buys wait in reserve and go out in pieces; holders and treasury are still paid. Every buyback must actually deliver its minimum to the burn address. The swapper is chosen by the steward behind the timelock, and a dishonest one could keep the margin above that minimum, so swapper changes are worth watching.
- **Front-run safe activation.** Only the pool's current creator can deploy its Lodestar, at an address derived from the pool id.
- **Fuzz and invariant tested.** Random sequences of locks, payouts, claims, top-ups, cancels, fees and failed buybacks check that Exile stays solvent and never pays out more than it received, that every Sandfall stream stays fully backed, and that every unit of quote a Lodestar handles ends up burned, locked, streamed or held in its buyback reserve.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design and [SECURITY.md](SECURITY.md) to report an issue. The contracts have not been audited yet.

## Live on Elysium testnet

Sample Token (SMPL) is launched on Ascend's live testnet launchpad, with its creator role held by a Lodestar. Every feature has been exercised on chain through the real PancakeSwap Infinity pool: fee burns, an EMA-guarded buyback, holder rewards dripping to Exile locks at several tiers, the Team Treasury stream, lock extension and a config change waiting out its 12 hour timelock. Contract sources are verified on the explorer.

| Contract | Address |
|---|---|
| LodestarFactory | [`0x9B6B1166469431587bF4d0ADf4eB7b7da2079716`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x9B6B1166469431587bF4d0ADf4eB7b7da2079716) |
| Lodestar implementation | [`0x153f4efAe53791120Bc34e09D2333e7bA1B09508`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x153f4efAe53791120Bc34e09D2333e7bA1B09508) |
| Exile | [`0x92a87165f0F4C8C288Cd57918b89274e21394125`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x92a87165f0F4C8C288Cd57918b89274e21394125) |
| Sandfall | [`0xC119BEcefaF9711B1F7311943aeA9E4f0669EFf1`](https://elysium.kinetiq.xyz/testnet-explorer/address/0xC119BEcefaF9711B1F7311943aeA9E4f0669EFf1) |
| AscendSwapper | [`0xDab7bD5CfA4021Fd604948EbF4616690Daaed658`](https://elysium.kinetiq.xyz/testnet-explorer/address/0xDab7bD5CfA4021Fd604948EbF4616690Daaed658) |
| Sample Token (SMPL) | [`0xe43F98f8A8D724609243D5abAB15bBaF072BC633`](https://elysium.kinetiq.xyz/testnet-explorer/address/0xe43F98f8A8D724609243D5abAB15bBaF072BC633) |
| SMPL Lodestar | [`0x618D5678287fdFC0ee83cB35221cCc1F138098F5`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x618D5678287fdFC0ee83cB35221cCc1F138098F5) |

<details>
<summary>Ascend addresses used</summary>

| | |
|---|---|
| AscendLaunchpad | `0x6d01f6644bbf1b5074472D3e85aa1465B4d2bF3d` |
| ListingDesk | `0x06DbB5eF794BA3C0F6F0ddC6164617Cf21811a77` |
| PancakeSwap Infinity CLPoolManager | `0x12E84206cB53aE0df055482ebc4658635096E1aA` |
| Infinity Vault | `0x2B738A9A69b7a45C9dA6B519f6bE6efBfb912aec` |
| Mock USDC (quote) | `0x84Cc00D13173f7016Bbab22A736dBf75A154cFE2` |

</details>

## Repository layout

```
contracts/src        Lodestar, LodestarFactory, AscendSwapper, Exile, Sandfall, interfaces, mocks
contracts/test       Foundry tests, including a full mock-Ascend integration test
contracts/script     DeployMocks, DeployCore, LaunchOnAscend, ActivateLodestar, DemoFlow
deployments/         <chainId>.json written by the scripts and read by the website
web/                 Vite + React + wagmi site (dashboard, Lodestar, Exile, Sandfall)
docs/                Architecture notes and the demo script
tools/               demo-local.sh, export-abis.mjs, offline solc shim
```

## Quickstart

Needs Node 20+ and [Foundry](https://getfoundry.sh) (`curl -L https://foundry.paradigm.xyz | bash && foundryup`).

```bash
git clone --recursive https://github.com/monarchy-fi/monarchy && cd monarchy
npm install
forge test            # or: npm test
```

In a sandbox that can't download solc, use `FOUNDRY_PROFILE=offline` (wraps the solc npm package).

### Run the demo locally (one command)

```bash
npm run demo:local    # anvil + mock Ascend + Monarchy + a demo launch + Lodestar + demo data
npm --prefix web install
npm run web           # http://localhost:5173
```

Point MetaMask or Rabby at `http://127.0.0.1:8545` (chain 31337) and import anvil's first account to act as the creator. On a dev server, `http://localhost:5173/?mock` connects that account without a browser wallet.

The dev server reads the local chain when `deployments/31337.json` exists; a production build always reads Elysium testnet. Set `VITE_CHAIN_ID` to override either.

### The website deploy

The site at monarchy.fi is password protected. The Pages workflow builds the app into one self-contained HTML file, encrypts it with [staticrypt](https://github.com/robinmoisson/staticrypt) using the `SITE_PASSWORD` Actions secret, and serves the same password page as `404.html` so deep links work. The workflow fails if the secret is missing. To try it locally with a throwaway password:

```bash
cd web
SITE_PASSWORD='any-test-password' npm run build:gated   # writes dist/index.html and dist/404.html
```

### Deploy to Elysium testnet

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

# 3. Hand the creator role to the token's Lodestar and activate it (40/40/20 split, the four
#    tiers, 7 day treasury stream, listing set-aside on, creator role locked for a year).
#    TREASURY is the address that receives the Team Treasury stream.
TREASURY=0xYourTreasury npm run activate:testnet

# 4. The website reads deployments/99801.json
npm run abis && npm run web
```

Mock USDC on Elysium has a public `mint`, so you can fund wallets for trading with
`cast send $QUOTE "mint(address,uint256)" $YOUR_ADDRESS 1000000000000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY`.

If buybacks through the Infinity vault misbehave, Lodestar keeps the buyback share in `buybackReserve` and still pays holders and the treasury. To activate with no buyback route at all, have the factory owner run `setDefaultSwapper(0x0)` at least 12 hours before step 3 (a new default only applies after 12 hours).

## Status and roadmap

| | |
|---|---|
| **Working** | Lodestar, Exile and Sandfall live on Elysium testnet; burns and buybacks proven on Ascend's pool; web app for all three; CI on every change |
| **In progress** | monarchy.fi and public docs, site design |
| **Before launch** | Security audit, mainnet deploy, Monarchy token launch on Ascend |
| **Next** | kHYPE treasury option, TWAP buybacks, Ascend NFT holder bonus in Exile, other launchpads, an indexer for history and APR charts |

Everything works with Ascend as it is today: a creator launches, then hands over the creator role in two steps. An option on Ascend's launch form to pick a Lodestar up front would make it one step.

## License

[MIT](LICENSE)
