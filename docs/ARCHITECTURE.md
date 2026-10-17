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
                 ├─ holdersBps ─▶ Exile.notifyReward ─▶ 7 day drip to lockers by points
                 └─ treasuryBps ▶ Sandfall.topUp ─▶ rolling stream to the Team Treasury
```

## Lodestar

- **Activation.** `LodestarFactory.predict(token, quote)` gives the router address before it exists (EIP-1167 clone, salt = Ascend pool id). The dev calls Ascend's `transferCreator(poolId, router)`, then `factory.deploy(params)`, which in one transaction clones the router, creates its Exile reward pool and Sandfall treasury stream, initializes it, calls `acceptCreator`, enrols the listing set-aside and optionally locks the creator role. `deploy` requires the caller to be the pool's current creator, so nobody can front-run the address with their own settings. The dev keeps the dev-buy tokens; only the fee stream moves.
- **Routing.** `distribute()` tries `collect` (Ascend's keeper may already have collected), calls `claim`, burns all token-side balance, then splits the quote balance (minus any buyback reserve) by the configured basis points. Rounding remainders go to the treasury. It routes by balance, not by return values, so fees claimed by someone else or sent directly are routed too.
- **Buyback safety.** The buyback's minimum output comes from Ascend's on-chain EMA price, less the 1% pool fee and the configured slippage (default 10%, max 20%). If the swap fails or the spot price was pushed up, the buyback amount waits in `buybackReserve` and is retried next time; holders and treasury are still paid. The EMA only moves on swaps, so after a large trade it can trail spot by a few percent; a tighter setting (such as 3%) makes buybacks wait for it to catch up, which is why the default is 10%.
- **Governance.** One steward (the dev). Split, swapper and slippage changes go through `proposeConfig` and can be executed by anyone after 12 hours. `lockCreatorRole(until)` can only extend; `transferCreatorOut` is blocked while locked. There is no sweep or rescue function: funds can only go to the burn address, Exile, Sandfall or the swapper.
- **Listing set-aside.** Enrolling routes 20% of the creator's quote share to Ascend's ListingDesk toward a HyperCore listing, up to a cap. Ascend clears an election on creator change, so the router re-enrols after it takes over.

## Exile

- Points = amount × tier multiplier, chosen by lock length when locking (and `max(old, new)` when extending).
- Rewards accrue Synthetix-style per second, shared by points. Each `notifyReward` drips over 7 days, merging any undistributed remainder, so a lock taken right before a payout only catches a sliver.
- Unlock times round up to the hour. Points expiring in each hour are kept in a bucket, and the pool snapshots the reward index at each hour boundary it passes, so a lock stops earning exactly at unlock even if nobody touches it. A pool idle for more than 720 hours can be caught up with `poke`.
- Tier changes are timelocked 12 hours and only affect new locks. NFT locks hold the item and earn nothing.

## Sandfall

- Fixed streams: linear or monthly steps with an optional cliff. Rolling streams start empty; each `topUp` re-streams the unvested balance plus the new amount over the window (Lodestar's treasury uses 30 days).
- `cancellable` is fixed at creation. Cancelling pays the vested part to the recipient and returns the rest to the creator.

## AscendSwapper

Exact-input buys and sells on Ascend pools through PancakeSwap Infinity: `vault.lock` → `lockAcquired` → `CLPoolManager.swap`, then `sync`/`transfer`/`settle` for the input and `take` for the output. Holds nothing between calls.

## Tests

`forge test` runs 88 tests: Sandfall (17), Exile (28, including a fuzz test), Lodestar (25, including a split fuzz test), AscendSwapper (14, both currency orderings), the Ascend pool-id test vector from a real testnet launch, and a full integration test on mock Ascend. The mocks reproduce the Ascend behaviour the contracts depend on: creator fee split, pull-based claim to the current creator, the two-step creator handover that clears the listing election, the 20% set-aside with carry and cap, and Infinity's lock/settle/take with zero-delta enforcement.
