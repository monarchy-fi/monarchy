# Architecture

```
            Ascend launchpad (Infinity pool hook)
                 │ creator fees, 50% of the 1% swap fee, both assets
                 ▼
  dev ──transferCreator──▶ Lodestar (one clone per token) ◀── distribute() by anyone
                 │
     token fees ─┼─▶ burned (0xdEAD…2069; Ascend tokens reject 0x…dEaD)
                 │
     quote fees ─┼─ burnBps ────▶ AscendSwapper ─▶ buy token ─▶ burned
                 ├─ holdersBps ─▶ Exile.notifyReward ─▶ 3 day drip to lockers by points
                 └─ treasuryBps ▶ Sandfall.topUp ─▶ rolling stream to the Team Treasury
```

## Lodestar

- **Activation.** `LodestarFactory.predict(token, quote)` gives the router address before it exists (EIP-1167 clone, salt = Ascend pool id). The dev calls Ascend's `transferCreator(poolId, router)`, then `factory.deploy(params)`, which in one transaction clones the router, creates its Exile reward pool and Sandfall treasury stream, initializes it, calls `acceptCreator`, enrols the listing set-aside and optionally locks the creator role. `deploy` requires the caller to be the pool's current creator, so nobody can front-run the address with their own settings. The dev keeps the dev-buy tokens; only the fee stream moves.
- **Routing.** `distribute()` tries `collect` (Ascend's keeper may already have collected), tries `claim`, burns all token-side balance, then splits the quote balance (minus any buyback reserve) by the configured basis points. Rounding remainders go to the treasury (or to holders, then buyback, when the treasury share is 0). It routes by balance, not by return values, so fees claimed by someone else or sent directly are routed too. Every outside call is isolated: if collect, claim, the EMA read, the buyback, the Exile payout or the treasury top-up fails, that amount stays in the router (in `buybackReserve`, `holdersReserve` or `treasuryReserve`) and is retried next time while the other steps still run.
- **Buyback safety.** The buyback's minimum output is the stricter of two floors, one at Ascend's on-chain EMA price and one at the pool's spot price, less the 1% pool fee and the configured slippage (default 10%, min 1%, max 20%). Spot alone is never trusted, since a sandwich can move it in the same transaction, so with no EMA the buyback waits; but spot can only tighten the floor, so a dump that leaves the EMA stale and high can't loosen it either. Each buyback spends at most 0.5% of the quote side of the pool's active liquidity, valued at whichever of the EMA and spot prices gives the smaller depth, so it moves the price about 1%, less than the 1% fee a sandwich pays on each leg. Buybacks are also at least 30 minutes apart (`BUYBACK_INTERVAL`): the cap bounds one buy, and without a gap a caller could push several capped pieces through in one block between their own buy and sell. The keeper runs every 3 hours, so the gap costs nothing in the normal flow. Bigger amounts wait in `buybackReserve` and go out in pieces on later distributes. After a skipped attempt the next one halves (down to 1/256), at most once every 30 minutes, and each success doubles it back; attempts that were never priced (no EMA yet) and dust attempts don't count, so neither an EMA-less first day, nor a few wei, nor a burst of calls during one pump can shrink the next real buyback for long. Each buyback is checked by what actually happened: at most the attempted quote left the router and at least the minimum output reached the burn address. A swapper the steward picks could still keep the margin between the fair price and that minimum (up to the fee plus slippage), which is why swapper changes sit behind the timelock. The EMA only moves on swaps, so after a large trade it can trail spot by a few percent; a tighter setting (such as 3%) makes buybacks wait for it to catch up, which is why the default is 10%.
- **Governance.** One steward (the dev). Split, swapper and slippage changes go through `proposeConfig` and can be executed by anyone after 12 hours. `lockCreatorRole(until)` can only extend and is refused while a hand-off is pending, so a pending transfer can't be accepted after the lock; `transferCreatorOut` is blocked while locked, except `transferCreatorOut(0)` to cancel. If the role ever leaves (an expired lock, a hand-out the steward reverses), the current creator hands it back on Ascend and anyone can call `acceptCreator` to complete the return; Ascend's own two-step is the consent. The router is also the admin of its Exile reward pool, so tier changes go through `proposeTiers` and `cancelTiers` on the router and follow `transferSteward`. There is no sweep or rescue function: funds can only go to the burn address, Exile, Sandfall or the swapper. The factory checks that token and quote weren't passed the wrong way round, refuses a second deploy for a pool cheaply instead of burning its gas on the CREATE2 collision, and a new factory default swapper only applies to deploys 12 hours later.
- **Listing set-aside.** Enrolling routes 20% of the creator's quote share to Ascend's ListingDesk toward a HyperCore listing, up to a cap. Ascend clears an election on creator change, so the router re-enrols after it takes over.

## Exile

- Points = amount × tier multiplier, chosen by the time still committed: from now to the unlock time, both when locking and when extending. Keeping Monarch means keeping 30 days ahead; a lock can't hold 3x through one-hour extensions. Tiers must not pay a longer lock less than a shorter one.
- Rewards accrue Synthetix-style per second, shared by points. Each `notifyReward` drips over 3 days, so a lock taken right before a payout only catches a sliver. When a payout lands mid-drip, the new end is weighted by amount: what is still dripping keeps its remaining time, and the payout plus anything that dripped while nobody was locked get a full 3 days. Dust barely moves the end and splitting a payout changes nothing.
- Unlock times near the uint64 limit are rejected rather than rounded, so they can't wrap into the past.
- Unlock times round up to the hour. Points expiring in each hour are kept in a bucket, and the pool snapshots the reward index at each hour boundary it passes, so a lock stops earning exactly at unlock even if nobody touches it. A pool idle for more than 720 hours can be caught up with `poke`.
- Tier changes are timelocked 12 hours and must be executed within 7 days after that. They apply to new locks and to extensions. A tier can't be shorter than one hour or pay more than 5x, so an admin can't add a tier that farms the drip with capital committed for seconds. For a Lodestar token the pool admin is the router, so tier changes belong to whoever is steward. NFT locks hold the item and earn nothing; an ERC-721 address is refused on the token path so it can't be stranded there. Rewards can be claimed to another address (`claimRewardsTo`) in case the reward token refuses the owner's wallet.
- The team runs a keeper (`.github/workflows/distribute.yml`) that calls `distribute` every 3 hours and pays the gas. Small, steady payouts keep the drip rate nearly flat, so there is no pile of pending fees worth timing a lock for, and each buyback stays small next to the depth cap and the EMA guard.
- A reward pool more than 720 hours behind makes lock, claim, extend and withdraw on its locks wait for a `poke` (permissionless, chunked). Lodestar's `distribute` keeps the pool current, and if catching up ever fails inside `distribute`, the holder share waits in `holdersReserve` instead of blocking the other steps.

## Sandfall

- Fixed streams: linear or steps with an optional cliff. Steps count from `start`, not the cliff, and a short last step pays a full equal share. Rolling streams start empty; on each `topUp` the new end is weighted by amount: what was still vesting keeps its remaining time and the new amount gets a full window (Lodestar's treasury uses 7 days). Splitting a top-up into pieces changes nothing.
- Use non-rebasing tokens: balances are measured once, at deposit.
- `claimTo` lets a recipient that can't receive the asset (no native receive, or blocked by the token) claim to another address.
- `cancellable` is fixed at creation. Cancelling returns the unvested rest to the creator; the vested part stays claimable by the recipient, so a recipient that can't receive can't block a cancel. In the `Cancelled` event, `toRecipient` is the amount left claimable, not paid.
- Anyone can create a rolling stream naming any creator, so the site should list a project's streams from the ids stored in its Lodestar, not from `createdBy`.

## AscendSwapper

Exact-input buys and sells on Ascend pools through PancakeSwap Infinity: `vault.lock` → `lockAcquired` → `CLPoolManager.swap`, then `sync`/`transfer`/`settle` for the input and `take` for the output. Holds nothing between calls.

## Tests

`forge test` runs 143 tests: unit tests for each contract, AscendSwapper in both currency orderings, the Ascend pool-id test vector from a real testnet launch, a full integration test on mock Ascend, property fuzz tests (`Fuzz.t.sol`) and stateful invariant suites for Exile, Sandfall and Lodestar (`invariants/`). The mocks reproduce the Ascend behaviour the contracts depend on: creator fee split, pull-based claim to the current creator, the two-step creator handover that clears the listing election, the 20% set-aside with carry and cap, and Infinity's lock/settle/take with zero-delta enforcement.
