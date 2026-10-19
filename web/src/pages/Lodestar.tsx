import { useState } from "react";
import { useConnection, useReadContract, useReadContracts } from "wagmi";
import { isAddress, parseUnits, stringToHex, type Address } from "viem";
import { iAscendLaunchpadAbi, lodestarAbi, lodestarFactoryAbi } from "../abi";
import { TierBadge, tagline } from "../components/Tiers";
import { TxButton } from "../components/Tx";
import { Addr, Amt, Badge, Card, Empty, Row, Skel, Stat, Sym } from "../components/Ui";
import { DEFAULT_TREASURY_WINDOW_DAYS, DISTRIBUTE_NOTE } from "../lib/constants";
import { isSet, useDeployment, ZERO, type Deployment } from "../lib/deployments";
import { date, duration, fmt, pct } from "../lib/format";
import { POLL, useNow, usePageTitle } from "../lib/hooks";
import { useLodestarCore, useTokenMeta } from "../lib/monarchy";
import { NoDeployment } from "../components/States";
import { Slider } from "../components/Slider";
import { PageMark } from "../components/NavGlyphs";

/** Lodestar.EXECUTION_WINDOW: how long a ready proposal can still be executed. */
const EXECUTION_WINDOW = 7 * 86400;

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
        <h1>
          <PageMark page="lodestar" />
          Lodestar
        </h1>
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
  // routers and factories from before the upgrade path don't have these, so a failed read means none
  const up = useReadContracts({
    contracts: [
      { ...l, functionName: "upgradeTarget" },
      { ...l, functionName: "upgradeEta" },
      { address: d.factory, abi: lodestarFactoryAbi, functionName: "successor" },
      { ...l, functionName: "upgradeFactory" },
    ],
    query: POLL.query,
  });
  if (!r.data) return <LoadingCard />;
  const upTarget = up.data?.[0]?.result;
  const upEta = up.data?.[1]?.result ?? 0n;
  const successor = up.data?.[2]?.result;
  const upFactory = up.data?.[3]?.result;
  const [cfg, [pending, eta], preview, tokenBurned, buyQ, buyBurned, holdQ, treasQ, reserve, lockedUntil, isCreator, lastAt, tokenToHolders] = r.data;
  const [election, owed] = listing.data ?? [0n, 0n];
  const qd = core.quoteMeta?.decimals ?? 6;
  const qs = core.quoteMeta?.symbol;
  const ts = core.tokenMeta?.symbol;
  // a ready proposal has to be carried out within 7 days (Lodestar.EXECUTION_WINDOW), or it reverts ProposalExpired
  const cfgExpired = eta > 0n && now > Number(eta) + EXECUTION_WINDOW;
  const upExpired = upEta > 0n && now > Number(upEta) + EXECUTION_WINDOW;
  // the move only goes through to the successor it was proposed for
  const successorMoved = !!upFactory && successor !== undefined && successor.toLowerCase() !== upFactory.toLowerCase();
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
            {upEta > 0n && <Badge tone="amber">Upgrade proposed</Badge>}
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
          {Number(lockedUntil) > now && <Row k="Creator role" v={`Locked ${lockForever ? "forever" : `until ${date(lockedUntil)}`}*`} />}
          <Row k="Token-side fees" v={cfg.tokenToHolders ? <Badge tone="gold">All paid to Exile lockers</Badge> : <Badge tone="grey">All burned</Badge>} />
          <Row k="Buyback route" v={cfg.swapper === ZERO ? <Badge tone="amber">None: buybacks wait in reserve</Badge> : <Addr address={cfg.swapper} />} />
          <Row k="Max slippage" v={`${pct(cfg.maxSlippageBps)} vs Ascend's EMA`} />
          <Row k="Listing set-aside" v={listingLive ? <><Badge tone="green">Enrolled</Badge> {fmt(owed, qd)} of {fmt(owed + (election >> 168n), qd)} {qs} saved</> : <Badge tone="grey">Not enrolled</Badge>} />
          <Row k="Last distribute" v={Number(lastAt) ? `${duration(now - Number(lastAt))} ago` : "never"} />
        </div>
        {Number(lockedUntil) > now && (
          <p className="footnote">
            * The one way out is a move to this token's router on a newer Monarchy factory, approved by Monarchy and the steward and announced here 7 days ahead.{" "}
            <a href="https://github.com/monarchy-fi/monarchy#security-model" target="_blank" rel="noreferrer">
              How upgrades work
            </a>
          </p>
        )}
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
          <Row k="Executable" v={Number(eta) > now ? `in ${duration(Number(eta) - now)} (${date(eta)})` : cfgExpired ? `expired ${date(Number(eta) + EXECUTION_WINDOW)}` : `now, until ${date(Number(eta) + EXECUTION_WINDOW)}`} />
          <div className="lock-actions">
            <TxButton disabledReason={Number(eta) > now ? "Timelock still running" : cfgExpired ? "Expired, the steward can propose it again" : undefined} request={() => ({ ...l, functionName: "executeConfig" })}>
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

      {upEta > 0n && upTarget && (
        <Card title="Pending upgrade" right={<Badge tone="amber">7 day notice</Badge>}>
          <p className="muted small">
            The steward has proposed moving this token's creator role, and with it every future fee, to its router on a newer Monarchy factory. Anyone can carry it out once the
            notice ends. Locked tokens and vesting streams stay where they are.
          </p>
          <Row k="New router" v={<Addr address={upTarget} />} />
          <Row k="Executable" v={Number(upEta) > now ? `in ${duration(Number(upEta) - now)} (${date(upEta)})` : upExpired ? `expired ${date(Number(upEta) + EXECUTION_WINDOW)}` : `now, until ${date(Number(upEta) + EXECUTION_WINDOW)}`} />
          <div className="lock-actions">
            <TxButton
              disabledReason={
                Number(upEta) > now ? "The 7 day notice is still running" : upExpired ? "Expired, the steward can propose it again" : successorMoved ? "Monarchy named a different newer factory since" : undefined
              }
              request={() => ({ ...l, functionName: "executeUpgrade" })}
            >
              Execute upgrade
            </TxButton>
            {isSteward && (
              <TxButton className="btn btn-ghost" request={() => ({ ...l, functionName: "cancelUpgrade" })}>
                Cancel upgrade
              </TxButton>
            )}
          </div>
        </Card>
      )}

      {isSteward && <Steward lodestar={lodestar} cfg={cfg} lockedUntil={lockedUntil} listingLive={listingLive} successor={successor} upgradePending={upEta > 0n} />}
    </>
  );
}

type Cfg = { burnBps: number; holdersBps: number; treasuryBps: number; swapper: Address; maxSlippageBps: number; tokenToHolders: boolean };

/** Burn the token-side fees, or pay all of them to Exile lockers. One choice per token, behind the timelock. */
function TokenRoute({ value, onChange, name }: { value: boolean; onChange: (v: boolean) => void; name: string }) {
  return (
    <div className="check-list">
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

function Steward({
  lodestar,
  cfg,
  lockedUntil,
  listingLive,
  successor,
  upgradePending,
}: {
  lodestar: Address;
  cfg: Cfg;
  lockedUntil: bigint;
  listingLive: boolean;
  successor?: Address;
  upgradePending: boolean;
}) {
  const l = { address: lodestar, abi: lodestarAbi } as const;
  const [split, setSplit] = useState({ burn: cfg.burnBps / 100, holders: cfg.holdersBps / 100, treasury: cfg.treasuryBps / 100 });
  const [toHolders, setToHolders] = useState(cfg.tokenToHolders);
  const [sure, setSure] = useState(false);
  const sum = split.burn + split.holders + split.treasury;
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
      {lockedUntil >= 2n ** 63n ? (
        <p className="muted small">Locked for good. The fee stream can only leave this router by an upgrade to a newer Lodestar, below.</p>
      ) : (
        <>
          <p className="muted small">Promise holders the fee stream stays with this router, apart from an upgrade announced 7 days ahead. Current lock: {lockedUntil > 0n ? `until ${date(lockedUntil)}` : "none"}.</p>
          <label className="check">
            <input type="checkbox" checked={sure} onChange={(e) => setSure(e.target.checked)} />
            Lock it for good. I understand I can't unlock it later.
          </label>
          <TxButton className="btn btn-sm" disabledReason={!sure ? "Tick the box first" : undefined} request={() => ({ ...l, functionName: "lockCreatorRole", args: [2n ** 64n - 1n] })}>
            Lock forever
          </TxButton>
        </>
      )}
      <h4>Upgrade to a newer Lodestar</h4>
      {!successor || successor === ZERO ? (
        <p className="muted small">Monarchy hasn't published a newer Lodestar. If it does, you can propose moving the creator role to it here, with 7 days' notice to holders.</p>
      ) : (
        <>
          <p className="muted small">
            Monarchy has published a newer Lodestar. Proposing moves the creator role to this token's router there after 7 days' notice, shown to everyone on this page. You can
            cancel until it is carried out.
          </p>
          <TxButton className="btn btn-sm" request={() => ({ ...l, functionName: "proposeUpgrade" })}>
            {upgradePending ? "Propose again (restarts the 7 days)" : "Propose upgrade"}
          </TxButton>
        </>
      )}
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
type TierChoice = (typeof DEFAULT_TIERS)[number];
/** The lock lengths and multipliers a tier can pick from. Every step stays inside Exile's rules: at least an hour, at most 5x. */
const TIER_DAYS = [1, 2, 3, 5, 7, 14, 21, 30, 45, 60, 90, 180, 365];
const TIER_MULTS = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5];
/** Treasury stream windows on offer, inside Sandfall's 1 to 365 day range. */
const WINDOW_DAYS = [1, 3, 7, 14, 30, 60, 90, 180, 365];
const dayCount = (n: number) => (n === 365 ? "1 year" : `${n} day${n === 1 ? "" : "s"}`);

/** The four tiers with their names fixed: each picks a lock length and a multiplier from a list. A choice that would
 * break the order (each tier longer than the one before, its multiplier no lower) is greyed out, so the table is
 * always one Exile accepts. */
function TierPicker({ tiers, setTiers }: { tiers: TierChoice[]; setTiers: (t: TierChoice[]) => void }) {
  const edit = (i: number, patch: Partial<TierChoice>) => setTiers(tiers.map((t, j) => (j === i ? { ...t, ...patch } : t)));
  return (
    <div className="tier-pick" role="table" aria-label="Exile reward tiers">
      <div className="tier-pick-row tier-pick-head" role="row">
        <span role="columnheader">Tier</span>
        <span role="columnheader">Lock at least</span>
        <span role="columnheader">Multiplier</span>
      </div>
      {tiers.map((t, i) => {
        const prev = tiers[i - 1];
        const next = tiers[i + 1];
        return (
          <div key={t.name} className="tier-pick-row" role="row">
            <span className="tier-pick-name" role="cell">
              <TierBadge name={t.name} />
              <span className="muted small">{tagline(t.name)}</span>
            </span>
            <span role="cell">
              <select className="input input-sm" aria-label={`${t.name} lock length`} value={t.days} onChange={(e) => edit(i, { days: Number(e.target.value) })}>
                {TIER_DAYS.map((n) => (
                  <option key={n} value={n} disabled={(!!prev && n <= prev.days) || (!!next && n >= next.days)}>
                    {dayCount(n)}
                  </option>
                ))}
              </select>
            </span>
            <span role="cell">
              <select className="input input-sm" aria-label={`${t.name} multiplier`} value={t.mult} onChange={(e) => edit(i, { mult: Number(e.target.value) })}>
                {TIER_MULTS.map((m) => (
                  <option key={m} value={m} disabled={(!!prev && m < prev.mult) || (!!next && m > next.mult)}>
                    {m}x
                  </option>
                ))}
              </select>
            </span>
          </div>
        );
      })}
    </div>
  );
}

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
  // the cap is counted in the quote asset, so 50,000 only makes sense as a default for the deployment's USDC.
  // It covers Hyperliquid's 500 HYPE listing floor with room to spare.
  const [cap, setCap] = useState(quote.toLowerCase() === d.quote.toLowerCase() ? "50000" : "");
  const [lockForever, setLockForever] = useState(true);

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
  // the same rules Exile and Sandfall check on deploy, so the button never sends a deploy that has to revert
  const tierProblem = tierRules(tiers);
  const windowBad = !(windowDays >= 1 && windowDays <= 365);
  const capOk = /^\d+(\.\d+)?$/.test(cap) && Number(cap) > 0;

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
            <p className="muted small">
              The four tier names are the same on every Monarchy token, so holders always know what a Duke lock means. Pick how long each tier's
              lock has to be and how big a share it earns.
            </p>
            <TierPicker tiers={tiers} setTiers={setTiers} />
            {tierProblem && <p className="warn small">{tierProblem}</p>}
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
            <p className={badTreasury ? "warn small field-help" : "muted small field-help"}>
              {badTreasury
                ? "That isn't a valid address yet."
                : "This address receives the Team Treasury stream. It can never be changed, not even by the steward, so check it twice."}
            </p>
            <label className="field">
              <span className="field-label">Treasury stream window</span>
              <select className="input" style={{ maxWidth: 220 }} value={windowDays} onChange={(e) => setWindowDays(Number(e.target.value))}>
                {WINDOW_DAYS.map((n) => (
                  <option key={n} value={n}>
                    {dayCount(n)}
                  </option>
                ))}
              </select>
            </label>
            <p className="muted small field-help">
              Each distribute adds the Team Treasury share to a Sandfall stream, which pays it out to the recipient bit by bit over this window
              instead of all at once, so holders can watch it flow. It can't be changed later.
            </p>
            <h5>Creator role</h5>
            <label className="check">
              <input type="checkbox" checked={lockForever} onChange={(e) => setLockForever(e.target.checked)} />
              Lock the creator role to this router forever
            </label>
            <p className="muted small">
              {lockForever
                ? "Holders can see the fee stream can't be moved away from this router, and you can't unlock it later. One exception: a move to this token's router on a newer Monarchy factory, which Monarchy and you both have to approve, announced to holders 7 days ahead."
                : "Without a lock the steward could hand the creator role away later. You can still lock it forever from the steward controls."}
            </p>
            <h5>HyperCore listing savings</h5>
            <label className="check">
              <input type="checkbox" checked={listing} onChange={(e) => setListing(e.target.checked)} />
              Save toward a HyperCore listing
            </label>
            <div className="note-box">
              Ascend can list a token on <b>HyperCore</b>, Hyperliquid's own exchange. If you opt in, <b>20% of the creator's {quoteMeta?.symbol ?? "quote"} fees</b> are
              saved toward that listing until they reach the goal below, and the rest is routed as usual. Reaching the goal doesn't list the token by itself: saving
              stops, and the savings wait until Ascend lists it, then pay for the listing. After that the router also receives half the trading fees from the
              token's HyperCore market. The steward can stop saving at any time, and unspent savings come back to the router.
            </div>
            {listing && (
              <>
                <label className="field">
                  <span className="field-label">Savings goal{quoteMeta ? ` (${quoteMeta.symbol})` : ""}</span>
                  <input className="input" style={{ maxWidth: 220 }} inputMode="decimal" value={cap} onChange={(e) => setCap(e.target.value)} placeholder="Amount to save" />
                </label>
                <p className="muted small field-help">
                  A listing costs at least 500 HYPE in Hyperliquid's listing auction. The savings pay for it up to this goal, and whether Ascend covers
                  any rest is up to Ascend.
                </p>
              </>
            )}
          </div>
          <TxButton
            disabledReason={
              !you
                ? "Only the current creator can activate"
                : !handedOver
                  ? "Do step 1 first"
                  : sum !== 100
                    ? `Splits add up to ${sum}%`
                    : tierProblem
                      ? "Fix the reward tiers"
                      : !recipient
                        ? "Enter the Team Treasury recipient"
                        : windowBad
                          ? "The stream window is 1 to 365 days"
                          : listing && !quoteMeta
                            ? "Reading the quote asset"
                            : listing && !capOk
                              ? "Enter a savings goal"
                              : deskOk.data && deskOk.data !== d.desk
                                ? "Listing desk mismatch"
                                : undefined
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
                  treasuryWindow: Math.round(windowDays * 86400),
                  tiers: tiers.map((t) => ({ minDuration: Math.round(t.days * 86400), multiplierBps: Math.round(t.mult * 10_000), label: stringToHex(t.name, { size: 32 }) })),
                  enrolListing: listing,
                  // the cap is in the pool's quote asset, whatever its decimals
                  listingCap: listing ? parseUnits(cap || "0", quoteMeta?.decimals ?? 18) : 0n,
                  // locked for good: the largest unlock time the router accepts
                  creatorLockUntil: lockForever ? 2n ** 64n - 1n : 0n,
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

/** What Exile's _validateTiers would refuse, in words, or undefined when the tiers are fine. Checked on the
 * values the deploy sends: seconds and basis points, rounded the same way. */
function tierRules(tiers: { name: string; days: number; mult: number }[]): string | undefined {
  if (tiers.length === 0 || tiers.length > 8) return "Use 1 to 8 tiers.";
  const sec = (t: { days: number }) => Math.round(t.days * 86400);
  const bps = (t: { mult: number }) => Math.round(t.mult * 10_000);
  for (let i = 0; i < tiers.length; i++) {
    const t = tiers[i];
    if (!t.name.trim()) return `Tier ${i + 1} needs a name.`;
    if (new TextEncoder().encode(t.name).length > 32) return `"${t.name}" is too long: names fit 32 bytes.`;
    if (!(sec(t) >= 3600)) return `${t.name} must be at least 1 hour long.`;
    if (!(bps(t) >= 1 && bps(t) <= 50_000)) return `${t.name}'s multiplier must be above 0x and at most 5x.`;
    if (i > 0 && !(sec(t) > sec(tiers[i - 1]))) return `${t.name} must be longer than ${tiers[i - 1].name}.`;
    if (i > 0 && bps(t) < bps(tiers[i - 1])) return `${t.name}'s multiplier can't be lower than ${tiers[i - 1].name}'s.`;
  }
  return undefined;
}

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

/** One bar, two handles: left of the first is buyback and burn, between them holder rewards, right of the
 * second the Team Treasury. It always adds up to 100%, and a handle pushes the other one along. */
function SplitInputs({ split, setSplit }: { split: Split; setSplit: (s: Split) => void }) {
  const a = split.burn;
  const b = split.burn + split.holders;
  const set = (na: number, nb: number) => setSplit({ burn: na, holders: nb - na, treasury: 100 - nb });
  return (
    <div className="slider3">
      <Slider
        className="slider3-track"
        max={100}
        values={[a, b]}
        onChange={(i, v) => (i === 0 ? set(v, Math.max(b, v)) : set(Math.min(a, v), v))}
        labels={["Buyback and burn share", "Buyback and holder rewards share, the rest goes to the Team Treasury"]}
        valueTexts={[`${a}%`, `${b}%`]}
      >
        <div className="slider3-bar" aria-hidden="true">
          <div className="seg seg-burn" style={{ width: `${a}%` }} />
          <div className="seg seg-holders" style={{ width: `${b - a}%` }} />
          <div className="seg seg-treasury" style={{ width: `${100 - b}%` }} />
        </div>
      </Slider>
      <div className="slider3-legend">
        <div>
          <span className="lg-k"><i className="dot seg-burn" />Buyback and burn</span>
          <b>{split.burn}%</b>
        </div>
        <div>
          <span className="lg-k"><i className="dot seg-holders" />Holder rewards</span>
          <b>{split.holders}%</b>
        </div>
        <div>
          <span className="lg-k"><i className="dot seg-treasury" />Team Treasury</span>
          <b>{split.treasury}%</b>
        </div>
      </div>
    </div>
  );
}
