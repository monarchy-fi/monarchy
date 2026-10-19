<div align="center">

<img src="web/public/crown.svg" alt="Monarchy crown" width="88" height="88" />

# Monarchy

### Fee routing, locks and vesting for tokens launched on Ascend

[![CI](https://github.com/monarchy-fi/monarchy/actions/workflows/ci.yml/badge.svg)](https://github.com/monarchy-fi/monarchy/actions/workflows/ci.yml)
[![Tests: 171 passing](https://img.shields.io/badge/Foundry-171%20tests%20passing-111111.svg)](contracts/test)
[![Solidity 0.8.28](https://img.shields.io/badge/Solidity-0.8.28-363636.svg)](foundry.toml)
[![Elysium testnet](https://img.shields.io/badge/Elysium%20testnet-chain%2099801-111111.svg)](https://elysium.kinetiq.xyz/testnet-explorer)
[![Protocol fees: none](https://img.shields.io/badge/protocol%20fees-none-111111.svg)](#how-it-works)
[![License: MIT](https://img.shields.io/badge/License-MIT-111111.svg)](LICENSE)

**Every creator fee burned, bought back, paid to locked holders or streamed to the team in the open. Monarchy takes nothing.**

[Website](https://monarchy.fi) · [Docs](https://docs.monarchy.fi) · [X](https://x.com/monarchyfi) · [Architecture](docs/ARCHITECTURE.md) · [Demo script](docs/DEMO.md) · [Testnet contracts](#live-on-elysium-testnet)

<img src="docs/img/site-home.png" alt="The Monarchy home page: four tabs around a crown along the top with the CA chip on the right, the name MONARCHY above a large spinning crown drawn in text characters, and Steal the Crown in gold with the line The kingdom shares everything. The Monarch doesn't tax. below it" width="840" />

</div>

---

## Why Monarchy

Ascend has no token, and its NFT is capped at 500. People who want a piece of Ascend usually reach for the launchpad's own token, and here there isn't one. Monarchy aims to be that token: a liquid coin whose trading fees flow back to the holders who lock it, built on the same tools it offers every other Ascend project.

On Ascend the creator role collects half of every 1% swap fee, in both the token and the quote asset. Without Monarchy that money sits in one wallet, holders earn nothing for holding, and promises about buybacks or vesting can't be checked on chain. Monarchy replaces those promises with contracts.

## Monarchy runs on Monarchy

The MONARCHY token gets no special treatment. It launches on Ascend like any other token and runs on the same contracts Monarchy offers everyone, with the same zero fees, the same 12 hour timelock and the same 7 day notice before a router can move. Most tokens ask holders to trust the team with the fees; MONARCHY's are handled by code anyone can read and check.

| | How MONARCHY uses it |
|---|---|
| **Lodestar** | Its creator role goes to its own Lodestar, locked there forever. Token-side fees are paid to lockers or burned, and the quote side splits into buyback and burn, holder rewards and the Team Treasury. |
| **Exile** | Holders lock MONARCHY to earn the holder share of every fee, by tier from Peasant to Monarch. |
| **Sandfall** | The Team Treasury share streams to the team in the open, never in one lump. |
| **Garden** | Monarchy's analytics page lists every lock, vesting stream and fee router, MONARCHY's included, live from the contracts at [monarchy.fi/garden](https://monarchy.fi/garden). Locks and streams sit under MONARCHY and Others, every table filters by token address or symbol, and each router shows any change still waiting out its timelock. |

On testnet, Sample Token (SMPL) stands in for MONARCHY with exactly this setup.

## How it works

```mermaid
flowchart LR
    A[Ascend pool<br/>creator fees] --> L(Lodestar)
    L -->|token side, default| E
    L -->|token side, if chosen| B[Burned]
    L -->|quote, burn share| S[AscendSwapper] --> B
    L -->|quote, holder share| E[Exile<br/>3 day drip to lockers]
    L -->|quote, treasury share| T[Sandfall<br/>rolling Team Treasury stream]
```

| | What it does |
|---|---|
| **Lodestar** | A fee router for one Ascend token. The creator launches on Ascend's own site and keeps the dev buy, then hands the token's *creator role* to its Lodestar. Anyone can call `distribute()`, and the team's keeper calls it every 3 hours so fees never pile up into one big payout: token-side fees are all paid to Exile lockers in the token itself (or, if the creator chooses, burned), and quote-side fees split by the creator's percentages into **buyback and burn**, **holder rewards** (Exile) and a **Team Treasury** (streamed through Sandfall). Ascend's listing set-aside stays off, so the creator's whole fee share reaches the router. |
| **Exile** | Locks ERC-20s (including v2 LP), ERC-721s and ERC-1155s. Locks can be extended, never shortened, cancelled or transferred. ERC-20 locks earn holder rewards by tier, paid as a 3 day drip, and stop earning the second they unlock. |
| **Sandfall** | Vesting streams (linear, with an optional cliff, or in daily, weekly or monthly steps) in any non-rebasing ERC-20 or native HYPE, each with a chart of what unlocks by when. The creator decides at creation whether a stream can be cancelled, and the site badges it. Rolling streams back Lodestar's Team Treasury. |

### Exile tiers

| Tier | Lock | Multiplier | |
|---|---|---|---|
| Peasant | 1 day | 0.5x | *Everyone starts somewhere.* |
| Knight | 3 days | 1x | *Sworn to the kingdom.* |
| Duke | 7 days | 2x | *Next in line.* |
| Monarch | 1 month | 4x | *Steal the crown.* |

No lock, no rewards. With four holders each locking 10,000 tokens and fees dripping at 100 USDC a day, holders who keep re-locking for 30 days earn 200, 400, 800 and 1,600 USDC respectively: each tier earns twice the one below it.

## Security model

- **No upgrades.** Each Lodestar is an EIP-1167 clone of a fixed implementation. Nobody can change its code.
- **No sweep.** There is no rescue or withdraw function. Funds can only go to the burn address, Exile, Sandfall or the swapper. Locked tokens and vesting streams can only go to their owners.
- **Slow changes.** Split, swapper and slippage changes, and Exile tier changes, wait behind a 12 hour timelock and expire if not executed within 7 days after it. Anyone can carry a change out once the wait ends, the steward can cancel it before then, and a new proposal restarts the wait. The token's Lodestar page and the Garden show every pending change with its countdown. Settings chosen at activation apply immediately.
- **Locked router.** At activation the creator can lock the creator role to the Lodestar forever (the default on the site and in the activation script), so the router can't be swapped out; without it, the steward can lock it later. Even locked, it can move to the same token's router on a newer Monarchy factory: the factory owner names that factory, the steward proposes the move, and anyone can carry it out after 7 days' notice. On a live chain the factory owner is a multisig, separate from every steward, so no single key can start a move; the deploy script refuses a plain wallet there. For mainnet the plan is a 2-of-2 with one key held by the Ascend team. On testnet the owner is still the deploy wallet. A different successor named meanwhile stops it. A lock can't be placed while a hand-off is pending.
- **Guarded buybacks.** The minimum output is the stricter of a floor at Ascend's on-chain EMA price and one at spot, less the pool fee and a slippage allowance (default 10%, min 1%, max 20%); spot alone is never trusted. Each buy spends at most 0.5% of the pool's quote depth, so it moves the price less than a sandwich pays in fees, and buys are at least 30 minutes apart, so calling `distribute` many times in one block can't push the whole reserve through between a buy and a sell. Bigger amounts and skipped buys wait in reserve and go out in pieces; holders and treasury are still paid. Every buyback must actually deliver its minimum to the burn address. The swapper is chosen by the steward behind the timelock, and a dishonest one could keep the margin above that minimum, so swapper changes are worth watching.
- **Front-run safe activation.** Only the pool's current creator can deploy its Lodestar, at an address derived from the pool id.
- **Fuzz and invariant tested.** Random sequences of locks, payouts, claims, top-ups, cancels, fees and failed buybacks check that Exile stays solvent and never pays out more than it received, that every Sandfall stream stays fully backed, and that every unit of quote a Lodestar handles ends up burned, locked, streamed or held in its buyback reserve.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design and [SECURITY.md](SECURITY.md) for the security reviews and how to report an issue. The contracts have had four internal security reviews but no third-party audit yet.

## Live on Elysium testnet

Sample Token (SMPL) is launched on Ascend's live testnet launchpad, with its creator role held by a Lodestar. Every feature has been exercised on chain through the real PancakeSwap Infinity pool: fee burns, an EMA-guarded buyback, holder rewards dripping to Exile locks at several tiers, the Team Treasury stream, lock extension, a config change waiting out its 12 hour timelock, and a creator role locked to the router forever that refuses to move except through the 7 day upgrade path. A second token, Sample Stock Token (SMPLS), is quoted in a mock stock token and sends its token-side fees to Exile lockers, so lockers earn and claim both SMPLS and the stock token, while the buyback, holder rewards and treasury run in the stock token. Contract sources are verified on the explorer.

| Contract | Address |
|---|---|
| LodestarFactory | [`0x500E6E78AeBAc7b4a8e0684beFC33868126D706c`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x500E6E78AeBAc7b4a8e0684beFC33868126D706c) |
| Lodestar implementation | [`0x7e78E4EAf2371240091b8CC2b7f6754212763c64`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x7e78E4EAf2371240091b8CC2b7f6754212763c64) |
| Exile | [`0x3A3b2500f252BDa21B38fD9260abB7B482E0e2ca`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x3A3b2500f252BDa21B38fD9260abB7B482E0e2ca) |
| Sandfall | [`0x24975F29B1a11E9718ACeD3A25cd6cdbcbc88AFF`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x24975F29B1a11E9718ACeD3A25cd6cdbcbc88AFF) |
| AscendSwapper | [`0x39Cc4Dd18d4D00e996AfE06c7180c173aa768aD0`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x39Cc4Dd18d4D00e996AfE06c7180c173aa768aD0) |
| Sample Token (SMPL) | [`0x3abA3a1FC9ea0AfF716b4663b48e0fe5bf7992DA`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x3abA3a1FC9ea0AfF716b4663b48e0fe5bf7992DA) |
| SMPL Lodestar | [`0x2859676A7ee0125a3c41557D3524e309B29bF84d`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x2859676A7ee0125a3c41557D3524e309B29bF84d) |
| Sample Stock Token (SMPLS, quoted in a mock stock token) | [`0x828CDD440dc05a429c6153ff46c9491fdb2bedae`](https://elysium.kinetiq.xyz/testnet-explorer/address/0x828CDD440dc05a429c6153ff46c9491fdb2bedae) |
| SMPLS Lodestar | [`0xb977Da1493be24762B349F3dB9257B4AAdF74F13`](https://elysium.kinetiq.xyz/testnet-explorer/address/0xb977Da1493be24762B349F3dB9257B4AAdF74F13) |

<details>
<summary>Ascend addresses used</summary>

| | |
|---|---|
| AscendLaunchpad | `0x6d01f6644bbf1b5074472D3e85aa1465B4d2bF3d` |
| ListingDesk | `0x06DbB5eF794BA3C0F6F0ddC6164617Cf21811a77` |
| PancakeSwap Infinity CLPoolManager | `0x12E84206cB53aE0df055482ebc4658635096E1aA` |
| Infinity Vault | `0x2B738A9A69b7a45C9dA6B519f6bE6efBfb912aec` |
| Mock USDC (quote) | `0x84Cc00D13173f7016Bbab22A736dBf75A154cFE2` |
| Mock stock token (SMPLS quote) | `0xa7CDbE6342A2eF5f789BCdd3653c7f48c7F16A51` |

</details>

## Repository layout

```
contracts/src        Lodestar, LodestarFactory, AscendSwapper, Exile, Sandfall, interfaces, mocks
contracts/test       Foundry tests, including a full mock-Ascend integration test
contracts/script     DeployMocks, DeployCore, LaunchOnAscend, ActivateLodestar, DemoFlow
deployments/         <chainId>.json written by the scripts and read by the website
web/                 Vite + React + wagmi site (landing page, Kingdom overview, Lodestar, Exile, Sandfall)
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

# 1. Monarchy core: Exile, Sandfall, Lodestar implementation, AscendSwapper, LodestarFactory.
#    The script refuses to replace a core that deployments/99801.json already records (this repo
#    ships the live testnet one), so a fresh deploy from a clone needs OVERWRITE_DEPLOYMENT=1.
OVERWRITE_DEPLOYMENT=1 npm run deploy:testnet   # writes deployments/99801.json

# 2. A token on Ascend. Either launch on Ascend's site and record it:
TOKEN=0xYourToken npm run launch:testnet
#    or launch from the script (simulate first, then add --broadcast):
npm run launch:testnet
npm run launch:testnet -- --broadcast

# 3. Hand the creator role to the token's Lodestar and activate it (50% holders, 20% buyback,
#    30% treasury, token-side fees to lockers, the four tiers, 7 day treasury stream, no listing
#    set-aside, creator role locked forever).
#    TREASURY is the address that receives the Team Treasury stream; it can never be changed.
#    Buybacks go through the AscendSwapper from deployments/99801.json unless SWAPPER is set.
TREASURY=0xYourTreasury npm run activate:testnet

# 4. The website reads deployments/99801.json
npm run abis && npm run web
```

Mock USDC on Elysium has a public `mint`, so you can fund wallets for trading with
`cast send $QUOTE "mint(address,uint256)" $YOUR_ADDRESS 1000000000000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY`.

If buybacks through the Infinity vault misbehave, Lodestar keeps the buyback share in `buybackReserve` and still pays holders and the treasury. To activate with no buyback route at all, have the factory owner run `setDefaultSwapper(0x0)` at least 12 hours before step 3 (a new default only applies after 12 hours), then run step 3 with `SWAPPER=0x0000000000000000000000000000000000000000`, which asks for the factory's default instead of the deployed AscendSwapper.

The keeper (`.github/workflows/distribute.yml`) calls `distribute()` every 3 hours from a wallet that holds only gas money, set as the `KEEPER_PRIVATE_KEY` Actions secret. Each run checks that `RPC_URL` serves chain 99801, lets `cast` estimate the gas, and fails when the receipt shows a revert, so a broken distribute is a red run rather than a green one. When Exile's reward pool is more than 6 hours behind (after an outage), the run first catches it up with `poke`, one call's worth of hours at a time, so the payouts inside `distribute()` stay light. If `distribute()` fails or a holder payout is parked, it catches up again and tries once more.

## Status and roadmap

| | |
|---|---|
| **Working** | Lodestar, Exile and Sandfall live on Elysium testnet with two demo tokens (USDC and stock quotes); burns, buybacks and token rewards to lockers proven on Ascend's pools; web app for all three at monarchy.fi, with the Garden, an analytics page listing every lock, stream and router; docs at docs.monarchy.fi; CI on every change |
| **In progress** | A testnet redeploy with the latest security review fixes |
| **Before launch** | Third-party security audit, the upgrade multisig shared with the Ascend team, mainnet deploy, Monarchy token launch on Ascend |
| **Next** | kHYPE treasury option, TWAP buybacks, Ascend NFT holder bonus in Exile, other launchpads, an indexer for history and APR charts |

Everything works with Ascend as it is today: a creator launches, then hands over the creator role in two steps. An option on Ascend's launch form to pick a Lodestar up front would make it one step.

## License

[MIT](LICENSE)
