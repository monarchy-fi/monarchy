import { useState } from "react";
import { useConnection, useReadContract, useReadContracts } from "wagmi";
import { isAddress, parseUnits, stringToHex, type Address } from "viem";
import { iAscendLaunchpadAbi, lodestarAbi, lodestarFactoryAbi } from "../abi";
import { tagline } from "../components/Tiers";
import { TxButton } from "../components/Tx";
import { Addr, Amt, Badge, Card, Empty, Row, Skel, Stat, Sym } from "../components/Ui";
import { DEFAULT_TREASURY_WINDOW_DAYS, DISTRIBUTE_NOTE } from "../lib/constants";
import { isSet, useDeployment, ZERO, type Deployment } from "../lib/deployments";
import { date, duration, fmt, pct } from "../lib/format";
import { POLL, useNow, usePageTitle } from "../lib/hooks";
import { useLodestarCore, useTokenMeta } from "../lib/monarchy";
import { NoDeployment } from "../components/States";

export function LodestarPage() {
  usePageTitle("Lodestar");
  const d = useDeployment();
  const [input, setInput] = useState("");
  const [quoteInput, setQuoteInput] = useState("");
  const defaultToken = d && isSet(d.token) ? d.token : undefined;
  const [defaultMeta, defaultQuoteMeta] = useTokenMeta([defaultToken, d?.quote]);
  if (!d) return <NoDeployment />;
  const token = isAddress(input) ? input : defaultToken;
  const badInput = input !== "" && !isAddress(input);
  // Ascend pools can pair with any quote asset (USDC, WHYPE, a tokenized stock...), and the router address
  // depends on the pair, so the quote can be changed here. Empty means the deployment's default.
  const quote = isAddress(quoteInput) ? quoteInput : d.quote;
  const badQuote = quoteInput !== "" && !isAddress(quoteInput);
  return (
    <div className="page">
      <header className="page-head">
        <h1>Lodestar</h1>
        <p className="muted">
          A fee router for one Ascend token. It holds the token's creator role, so every creator fee lands here. Anyone
          can route it. Token-side fees are burned, or, if the creator chooses, all paid to Exile lockers. Quote-side
          fees split between buyback and burn, holder rewards in Exile and a Team Treasury streamed through Sandfall.
          No fees.
        </p>
      </header>
      <Card title="Token">
        <label className="field">
          <span className="field-label">Ascend token address</span>
          <input
            className="input mono-input"
            placeholder={defaultToken ? `${defaultToken}${defaultMeta ? ` (${defaultMeta.symbol})` : ""}` : "0x…"}
            value={input}
            onChange={(e) => setInput(e.target.value.trim())}
            spellCheck={false}
            autoComplete="off"
          />
        </label>
        <p className="muted small field-help">
          {badInput
            ? "That isn't a valid address yet."
            : input
              ? "Showing the token you pasted."
              : defaultToken
                ? <>Showing <b className="text">{defaultMeta?.symbol ?? "the demo token"}</b>. Paste another Ascend token to view or activate its Lodestar.</>
                : "Paste an Ascend token to view or activate its Lodestar."}
        </p>
        <label className="field">
          <span className="field-label">Quote asset (what the pool pairs with)</span>
          <input
            className="input mono-input"
            placeholder={`${d.quote}${defaultQuoteMeta ? ` (${defaultQuoteMeta.symbol})` : ""}`}
            value={quoteInput}
            onChange={(e) => setQuoteInput(e.target.value.trim())}
            spellCheck={false}
            autoComplete="off"
          />
        </label>
        <p className="muted small field-help">
          {badQuote
            ? "That isn't a valid address yet."
            : quoteInput
              ? "Looking for the pool against the quote asset you pasted."
              : <>Pools paired with {defaultQuoteMeta?.symbol ?? "the default quote asset"}. Paste another quote asset if the pool pairs with something else.</>}
        </p>
      </Card>
      {token && <ForToken d={d} token={token} quote={quote} />}
    </div>
  );
}

function ForToken({ d, token, quote }: { d: Deployment; token: Address; quote: Address }) {
  const r = useReadContracts({
    allowFailure: false,
    contracts: [
      { address: d.factory, abi: lodestarFactoryAbi, functionName: "lodestarOf", args: [token] },
      { address: d.factory, abi: lodestarFactoryAbi, functionName: "predict", args: [token, quote] },
    ],
    query: POLL.query,
  });
  if (!r.data) return <LoadingCard />;
  const [deployed, [predicted, poolId]] = r.data;
  return deployed !== ZERO ? (
    <Router d={d} lodestar={deployed} />
  ) : (
    <Activate d={d} token={token} quote={quote} predicted={predicted} poolId={poolId} />
  );
}

// ==================================================================== router dashboard

function Router({ d, lodestar }: { d: Deployment; lodestar: Address }) {
  const { address } = useConnection();
  const core = useLodestarCore(lodestar);
  const now = useNow();
  const l = { address: lodestar, abi: lodestarAbi } as const;
  const r = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...l, functionName: "config" },
      { ...l, functionName: "pendingConfig" },
      { ...l, functionName: "previewDistribute" },
      { ...l, functionName: "totalTokenBurned" },
      { ...l, functionName: "totalBuybackQuote" },
      { ...l, functionName: "totalBuybackTokensBurned" },
      { ...l, functionName: "totalHoldersQuote" },
      { ...l, functionName: "totalTreasuryQuote" },
      { ...l, functionName: "buybackReserve" },
      { ...l, functionName: "creatorLockedUntil" },
      { ...l, functionName: "isCreator" },
      { ...l, functionName: "lastDistributeAt" },
      { ...l, functionName: "totalTokenToHolders" },
    ],
    query: POLL.query,
  });
  const listing = useReadContracts({
    allowFailure: false,
    contracts: [
      { address: d.launchpad, abi: iAscendLaunchpadAbi, functionName: "listingElection", args: [core.poolId ?? "0x"] },
      { address: d.launchpad, abi: iAscendLaunchpadAbi, functionName: "listingOwed", args: [core.poolId ?? "0x"] },
    ],
    query: { enabled: !!core.poolId, ...POLL.query },
  });
  if (!r.data) return <LoadingCard />;
  const [cfg, [pending, eta], preview, tokenBurned, buyQ, buyBurned, holdQ, treasQ, reserve, lockedUntil, isCreator, lastAt, tokenToHolders] = r.data;
  const [election, owed] = listing.data ?? [0n, 0n];
  const qd = core.quoteMeta?.decimals ?? 6;
  const qs = core.quoteMeta?.symbol;
  const ts = core.tokenMeta?.symbol;
  const listingLive = election !== 0n && (election & ((1n << 160n) - 1n)) === BigInt(lodestar);
  const isSteward = !!address && address.toLowerCase() === core.steward?.toLowerCase();
  const lockForever = lockedUntil >= 2n ** 63n;

  return (
    <>
      <Card
        title={
          <>
            <Sym s={ts} /> Lodestar
          </>
        }
        right={
          <div className="lock-badges">
            {isCreator ? <Badge tone="green">Holds the creator role</Badge> : <Badge tone="red">Not the creator</Badge>}
            {Number(lockedUntil) > now ? <Badge tone="gold">Role locked {lockForever ? "forever" : `until ${date(lockedUntil)}`}</Badge> : <Badge tone="amber">Role not locked</Badge>}
            <Badge tone="grey">No fees</Badge>
          </div>
        }
      >
        <SplitBar burn={cfg.burnBps} holders={cfg.holdersBps} treasury={cfg.treasuryBps} />
        <div className="stats stats-4">
          {cfg.tokenToHolders ? (
            <Stat label="Token fees to lockers" value={<Amt value={tokenToHolders} digits={0} symbol={ts} />} hint={tokenBurned > 0n ? `${fmt(tokenBurned, 18, 0)} burned before` : "Dripped to Exile lockers"} />
          ) : (
            <Stat label="Token fees burned" value={<Amt value={tokenBurned} digits={0} symbol={ts} />} hint={tokenToHolders > 0n ? `${fmt(tokenToHolders, 18, 0)} paid to lockers before` : "Sent to the burn address"} />
          )}
          <Stat label="Bought back and burned" value={<Amt value={buyBurned} digits={0} symbol={ts} />} hint={`${fmt(buyQ, qd)} ${qs ?? ""} spent`} />
          <Stat label="To holders (Exile)" value={<Amt value={holdQ} decimals={qd} symbol={qs} />} hint="Dripped to lockers" />
          <Stat label="To Team Treasury" value={<Amt value={treasQ} decimals={qd} symbol={qs} />} hint="Streamed through Sandfall" />
        </div>
        <div className="summary">
          <Row k="Router" v={<Addr address={lodestar} />} />
          <Row k="Steward" v={<Addr address={core.steward} />} />
          <Row k="Token-side fees" v={cfg.tokenToHolders ? <Badge tone="gold">All paid to Exile lockers</Badge> : <Badge tone="grey">All burned</Badge>} />
          <Row k="Buyback route" v={cfg.swapper === ZERO ? <Badge tone="amber">None: buybacks wait in reserve</Badge> : <Addr address={cfg.swapper} />} />
          <Row k="Max slippage" v={`${pct(cfg.maxSlippageBps)} vs Ascend's EMA price`} />
          <Row k="Listing set-aside" v={listingLive ? <><Badge tone="green">Enrolled</Badge> {fmt(owed, qd)} {qs} saved, {fmt(election >> 168n, qd)} {qs} to go</> : <Badge tone="grey">Not enrolled</Badge>} />
          <Row k="Last distribute" v={Number(lastAt) ? `${duration(now - Number(lastAt))} ago` : "never"} />
        </div>
      </Card>

      <Card title="Distribute" right={<span className="muted small">Anyone can call this</span>}>
        <p className="muted small">Collects and claims this token's creator fees from Ascend, then routes everything the router holds.</p>
        <div className="stats stats-4">
          <Stat label={cfg.tokenToHolders ? "Token fees to lockers" : "Token fees to burn"} value={<Amt value={preview[0]} digits={0} symbol={ts} />} />
          <Stat label="Buyback" value={<Amt value={preview[2] + reserve} decimals={qd} symbol={qs} />} hint={reserve > 0n ? `Includes ${fmt(reserve, qd)} waiting in reserve` : undefined} />
          <Stat label="Holders" value={<Amt value={preview[3]} decimals={qd} symbol={qs} />} />
          <Stat label="Treasury" value={<Amt value={preview[4]} decimals={qd} symbol={qs} />} />
        </div>
        <p className="muted small">Plus any fees still sitting in the pool, which distribute collects first.</p>
        <p className="small cadence">{DISTRIBUTE_NOTE}</p>
        <TxButton request={() => ({ ...l, functionName: "distribute" })}>Distribute</TxButton>
      </Card>

      {eta > 0n && (
        <Card title="Pending split change" right={<Badge tone="amber">12 hour timelock</Badge>}>
          <SplitBar burn={pending.burnBps} holders={pending.holdersBps} treasury={pending.treasuryBps} />
          <Row k="Token-side fees" v={pending.tokenToHolders ? "All paid to Exile lockers" : "All burned"} />
          <Row k="Executable" v={Number(eta) > now ? `in ${duration(Number(eta) - now)} (${date(eta)})` : "now"} />
          <div className="lock-actions">
            <TxButton disabledReason={Number(eta) > now ? "Timelock still running" : undefined} request={() => ({ ...l, functionName: "executeConfig" })}>
              Execute
            </TxButton>
            {isSteward && (
              <TxButton className="btn btn-ghost" request={() => ({ ...l, functionName: "cancelConfig" })}>
                Cancel change
              </TxButton>
            )}
          </div>
        </Card>
      )}

      {isSteward && <Steward lodestar={lodestar} cfg={cfg} lockedUntil={lockedUntil} listingLive={listingLive} />}
    </>
  );
}

type Cfg = { burnBps: number; holdersBps: number; treasuryBps: number; swapper: Address; maxSlippageBps: number; tokenToHolders: boolean };

/** Burn the token-side fees, or pay all of them to Exile lockers. One choice per token, behind the timelock. */
function TokenRoute({ value, onChange, name }: { value: boolean; onChange: (v: boolean) => void; name: string }) {
  return (
    <div className="form">
      <label className="check">
        <input type="radio" name={name} checked={!value} onChange={() => onChange(false)} />
        Burn all token-side fees
      </label>
      <label className="check">
        <input type="radio" name={name} checked={value} onChange={() => onChange(true)} />
        Pay all token-side fees to Exile lockers (dripped over 3 days, in the token itself)
      </label>
    </div>
  );
}

function Steward({ lodestar, cfg, lockedUntil, listingLive }: { lodestar: Address; cfg: Cfg; lockedUntil: bigint; listingLive: boolean }) {
  const l = { address: lodestar, abi: lodestarAbi } as const;
  const [split, setSplit] = useState({ burn: cfg.burnBps / 100, holders: cfg.holdersBps / 100, treasury: cfg.treasuryBps / 100 });
  const [toHolders, setToHolders] = useState(cfg.tokenToHolders);
  const [lockDays, setLockDays] = useState(365);
  const sum = split.burn + split.holders + split.treasury;
  const until = BigInt(Math.floor(Date.now() / 1000) + lockDays * 86400);
  return (
    <Card title="Steward controls" right={<span className="muted small">Only the steward sees this</span>}>
      <h4>Change the split</h4>
      <SplitInputs split={split} setSplit={setSplit} />
      <TokenRoute name="steward-token-route" value={toHolders} onChange={setToHolders} />
      <TxButton
        disabledReason={sum !== 100 ? `Splits add up to ${sum}%, not 100%` : undefined}
        request={() => ({
          ...l,
          functionName: "proposeConfig",
          args: [{ ...cfg, burnBps: Math.round(split.burn * 100), holdersBps: Math.round(split.holders * 100), treasuryBps: Math.round(split.treasury * 100), tokenToHolders: toHolders }],
        })}
      >
        Propose (takes effect after 12 hours)
      </TxButton>
      <h4>Lock the creator role</h4>
      <p className="muted small">Promise holders the router can't be swapped out. A lock can only be extended. Current: {lockedUntil > 0n ? date(lockedUntil) : "none"}.</p>
      <div className="extend">
        <input className="input input-sm" type="number" min={1} value={lockDays} onChange={(e) => setLockDays(Number(e.target.value))} />
        <span className="muted small">days</span>
        <TxButton className="btn btn-sm" disabledReason={until <= lockedUntil ? "Must be later than the current lock" : undefined} request={() => ({ ...l, functionName: "lockCreatorRole", args: [until] })}>
          Lock until {date(until)}
        </TxButton>
        <TxButton className="btn btn-sm btn-ghost" disabledReason={lockedUntil >= 2n ** 63n ? "Already forever" : undefined} request={() => ({ ...l, functionName: "lockCreatorRole", args: [2n ** 64n - 1n] })}>
          Lock forever
        </TxButton>
      </div>
      {listingLive && (
        <>
          <h4>Listing set-aside</h4>
          <TxButton className="btn btn-sm btn-ghost" request={() => ({ ...l, functionName: "closeListing" })}>
            Leave the listing set-aside
          </TxButton>
        </>
      )}
    </Card>
  );
}

// ==================================================================== activation wizard

const DEFAULT_TIERS = [
  { name: "Peasant", days: 1, mult: 0.5 },
  { name: "Knight", days: 3, mult: 1 },
  { name: "Duke", days: 7, mult: 1.5 },
  { name: "Monarch", days: 30, mult: 3 },
];

function Activate({ d, token, quote, predicted, poolId }: { d: Deployment; token: Address; quote: Address; predicted: Address; poolId: `0x${string}` }) {
  const { address } = useConnection();
  const [quoteMeta] = useTokenMeta([quote]);
  const lp = { address: d.launchpad, abi: iAscendLaunchpadAbi } as const;
  const r = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...lp, functionName: "poolCreator", args: [poolId] },
      { ...lp, functionName: "pendingCreator", args: [poolId] },
      { ...lp, functionName: "creatorOwedQuote", args: [poolId] },
      { ...lp, functionName: "creatorOwedToken", args: [poolId] },
    ],
    query: POLL.query,
  });
  const deskOk = useReadContract({ ...lp, functionName: "listingDesk" });
  const [split, setSplit] = useState({ burn: 40, holders: 40, treasury: 20 });
  const [toHolders, setToHolders] = useState(false);
  const [treasury, setTreasury] = useState("");
  const [windowDays, setWindowDays] = useState(DEFAULT_TREASURY_WINDOW_DAYS);
  const [tiers, setTiers] = useState(DEFAULT_TIERS);
  const [listing, setListing] = useState(true);
  // the cap is counted in the quote asset, so 5,000 only makes sense as a default for the deployment's USDC
  const [cap, setCap] = useState(quote.toLowerCase() === d.quote.toLowerCase() ? "5000" : "");
  const [lockDays, setLockDays] = useState(365);

  if (!r.data) return <LoadingCard />;
  const [creator, pendingCreator, owedQ, owedT] = r.data;
  if (creator === ZERO)
    return (
      <Card>
        <Empty title="No Ascend pool found">This token has no Ascend pool with this quote asset. Check the address and try again.</Empty>
      </Card>
    );
  const you = !!address && creator.toLowerCase() === address.toLowerCase();
  const handedOver = pendingCreator.toLowerCase() === predicted.toLowerCase();
  const sum = split.burn + split.holders + split.treasury;
  // The stream's recipient can never be changed, so it is never filled in silently: the creator types it
  // or presses "Use my wallet", and the button stays off until the field holds a valid address.
  const recipient = isAddress(treasury) ? treasury : undefined;
  const badTreasury = treasury !== "" && !isAddress(treasury);

  return (
    <Card title="Activate Lodestar" right={<Badge tone="grey">2 transactions</Badge>}>
      <div className="summary">
        <Row k="Ascend pool" v={<span className="mono">{poolId.slice(0, 10)}…</span>} />
        <Row k="Current creator" v={<><Addr address={creator} /> {you && <Badge tone="green">you</Badge>}</>} />
        <Row k="Router address" v={<Addr address={predicted} />} />
      </div>
      {(owedQ > 0n || owedT > 0n) && (
        <p className="warn small">
          This pool has unclaimed creator fees. They move to the router when it takes over. Claim them first on Ascend if you want them yourself.
        </p>
      )}
      <ol className="steps">
        <li className={handedOver ? "done" : ""}>
          <h4>1. Hand the creator role to the router</h4>
          <p className="muted small">On Ascend's launchpad. You keep your dev-buy tokens; only the creator fee stream moves.</p>
          <TxButton
            disabledReason={!you ? "Only the current creator can do this" : handedOver ? "Done" : undefined}
            request={() => ({ ...lp, functionName: "transferCreator", args: [poolId, predicted] })}
          >
            Hand over creator role
          </TxButton>
        </li>
        <li>
          <h4>2. Activate</h4>
          <p className="muted small">Creates the router, its Exile reward pool and its Sandfall treasury stream, and accepts the role, in one transaction.</p>
          <div className="form-block">
            <h5>Split of the quote-side fees</h5>
            <SplitInputs split={split} setSplit={setSplit} />
            <h5>Token-side fees</h5>
            <TokenRoute name="activate-token-route" value={toHolders} onChange={setToHolders} />
            <h5>Exile reward tiers</h5>
            <div className="tier-edit">
              {tiers.map((t, i) => (
                <div key={i} className="tier-edit-row">
                  <input className="input input-sm" value={t.name} onChange={(e) => setTiers(tiers.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)))} />
                  <input className="input input-sm" type="number" value={t.days} onChange={(e) => setTiers(tiers.map((x, j) => (j === i ? { ...x, days: Number(e.target.value) } : x)))} />
                  <span className="muted small">days</span>
                  <input className="input input-sm" type="number" step="0.1" value={t.mult} onChange={(e) => setTiers(tiers.map((x, j) => (j === i ? { ...x, mult: Number(e.target.value) } : x)))} />
                  <span className="muted small">x {tagline(t.name) ? `· ${tagline(t.name)}` : ""}</span>
                </div>
              ))}
            </div>
            <div className="form">
              <label>
                Team Treasury recipient
                <div className="input-row">
                  <input className="input mono-input" placeholder="0x…" value={treasury} onChange={(e) => setTreasury(e.target.value.trim())} spellCheck={false} autoComplete="off" />
                  <button type="button" className="btn btn-ghost btn-sm" disabled={!address} onClick={() => address && setTreasury(address)}>
                    Use my wallet
                  </button>
                </div>
              </label>
            </div>
            <p className={badTreasury ? "warn small" : "muted small"}>
              {badTreasury
                ? "That isn't a valid address yet."
                : "This address receives the Team Treasury stream. It can never be changed, not even by the steward, so check it twice."}
            </p>
            <div className="form">
              <label>
                Treasury stream window (days)
                <input className="input" type="number" min={1} max={365} value={windowDays} onChange={(e) => setWindowDays(Number(e.target.value))} />
              </label>
              <label>
                Lock creator role for (days, 0 = no lock)
                <input className="input" type="number" min={0} value={lockDays} onChange={(e) => setLockDays(Number(e.target.value))} />
              </label>
            </div>
            <label className="check">
              <input type="checkbox" checked={listing} onChange={(e) => setListing(e.target.checked)} />
              Enrol in Ascend's listing set-aside (20% of the creator quote share is saved toward a HyperCore listing until the cap)
            </label>
            {listing && (
              <label>
                Cap{quoteMeta ? ` (${quoteMeta.symbol})` : ""}
                <input className="input input-sm" value={cap} onChange={(e) => setCap(e.target.value)} />
              </label>
            )}
          </div>
          <TxButton
            disabledReason={
              !you ? "Only the current creator can activate" : !handedOver ? "Do step 1 first" : sum !== 100 ? `Splits add up to ${sum}%` : !recipient ? "Enter the Team Treasury recipient" : listing && !quoteMeta ? "Reading the quote asset" : listing && !(Number(cap) > 0) ? "Enter a listing cap" : deskOk.data && deskOk.data !== d.desk ? "Listing desk mismatch" : undefined
            }
            request={() => recipient && ({
              address: d.factory,
              abi: lodestarFactoryAbi,
              functionName: "deploy",
              gas: 6_000_000n,
              args: [
                {
                  token,
                  quote,
                  // the buyback route is the AscendSwapper this deployment recorded, never the factory's default of the day
                  cfg: { burnBps: split.burn * 100, holdersBps: split.holders * 100, treasuryBps: split.treasury * 100, swapper: d.swapper, maxSlippageBps: 1000, tokenToHolders: toHolders },
                  treasuryRecipient: recipient,
                  treasuryWindow: windowDays * 86400,
                  tiers: tiers.map((t) => ({ minDuration: Math.round(t.days * 86400), multiplierBps: Math.round(t.mult * 10_000), label: stringToHex(t.name, { size: 32 }) })),
                  enrolListing: listing,
                  // the cap is in the pool's quote asset, whatever its decimals
                  listingCap: listing ? parseUnits(cap || "0", quoteMeta?.decimals ?? 18) : 0n,
                  creatorLockUntil: lockDays > 0 ? BigInt(Math.floor(Date.now() / 1000) + lockDays * 86400) : 0n,
                },
              ],
            })}
          >
            Activate Lodestar
          </TxButton>
        </li>
      </ol>
    </Card>
  );
}

// ==================================================================== shared

function LoadingCard() {
  return (
    <Card title={<Skel w="9em" h="1.1em" />}>
      <Skel block h="12px" w="100%" style={{ borderRadius: 999, marginBottom: 16 }} />
      <div className="stats stats-4">
        {[0, 1, 2, 3].map((i) => (
          <Skel key={i} block h="84px" w="auto" />
        ))}
      </div>
    </Card>
  );
}

function SplitBar({ burn, holders, treasury }: { burn: number; holders: number; treasury: number }) {
  return (
    <div className="split">
      <div className="split-bar">
        <div className="seg seg-burn" style={{ width: `${burn / 100}%` }} />
        <div className="seg seg-holders" style={{ width: `${holders / 100}%` }} />
        <div className="seg seg-treasury" style={{ width: `${treasury / 100}%` }} />
      </div>
      <div className="split-legend">
        <span><i className="dot seg-burn" /> Buyback and burn {pct(burn)}</span>
        <span><i className="dot seg-holders" /> Holder rewards {pct(holders)}</span>
        <span><i className="dot seg-treasury" /> Team Treasury {pct(treasury)}</span>
      </div>
    </div>
  );
}

type Split = { burn: number; holders: number; treasury: number };
function SplitInputs({ split, setSplit }: { split: Split; setSplit: (s: Split) => void }) {
  const sum = split.burn + split.holders + split.treasury;
  const field = (k: keyof Split, name: string) => (
    <label>
      {name} %
      <input className="input" type="number" min={0} max={100} value={split[k]} onChange={(e) => setSplit({ ...split, [k]: Math.max(0, Math.min(100, Number(e.target.value))) })} />
    </label>
  );
  return (
    <>
      <div className="form form-3">
        {field("burn", "Buyback and burn")}
        {field("holders", "Holder rewards")}
        {field("treasury", "Team Treasury")}
      </div>
      <SplitBar burn={split.burn * 100} holders={split.holders * 100} treasury={split.treasury * 100} />
      {sum !== 100 && <p className="warn small">Adds up to {sum}%. Needs to be exactly 100%.</p>}
    </>
  );
}
