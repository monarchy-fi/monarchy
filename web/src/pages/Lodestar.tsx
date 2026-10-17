import { useState } from "react";
import { useConnection, useReadContract, useReadContracts } from "wagmi";
import { isAddress, parseUnits, stringToHex, type Address } from "viem";
import { iAscendLaunchpadAbi, lodestarAbi, lodestarFactoryAbi } from "../abi";
import { TAGLINES } from "../components/Tiers";
import { TxButton } from "../components/Tx";
import { Addr, Badge, Card, Row, Stat } from "../components/Ui";
import { isSet, useDeployment, ZERO, type Deployment } from "../lib/deployments";
import { date, duration, fmt, pct } from "../lib/format";
import { POLL, useNow } from "../lib/hooks";
import { useLodestarCore } from "../lib/monarchy";
import { NoDeployment } from "./Exile";

export function LodestarPage() {
  const d = useDeployment();
  const [input, setInput] = useState("");
  if (!d) return <NoDeployment />;
  const token = isAddress(input) ? input : isSet(d.token) ? d.token : undefined;
  return (
    <div className="page">
      <header className="page-head">
        <h1>Lodestar</h1>
        <p className="muted">
          A fee router for one Ascend token. It holds the token's creator role, so every creator fee lands here, and
          anyone can route it: token-side fees are burned, and the quote side splits between buyback and burn, holder
          rewards in Exile and a Team Treasury streamed through Sandfall. No fees.
        </p>
      </header>
      <Card title="Token">
        <input
          className="input"
          placeholder={`Token address (default ${isSet(d.token) ? "MONARCH " + d.token : "none"})`}
          value={input}
          onChange={(e) => setInput(e.target.value.trim())}
        />
      </Card>
      {token && <ForToken d={d} token={token} />}
    </div>
  );
}

function ForToken({ d, token }: { d: Deployment; token: Address }) {
  const r = useReadContracts({
    allowFailure: false,
    contracts: [
      { address: d.factory, abi: lodestarFactoryAbi, functionName: "lodestarOf", args: [token] },
      { address: d.factory, abi: lodestarFactoryAbi, functionName: "predict", args: [token, d.quote] },
    ],
    query: POLL.query,
  });
  if (!r.data) return null;
  const [deployed, [predicted, poolId]] = r.data;
  return deployed !== ZERO ? (
    <Router d={d} lodestar={deployed} />
  ) : (
    <Activate d={d} token={token} predicted={predicted} poolId={poolId} />
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
  if (!r.data) return <Card>Loading router…</Card>;
  const [cfg, [pending, eta], preview, tokenBurned, buyQ, buyBurned, holdQ, treasQ, reserve, lockedUntil, isCreator, lastAt] = r.data;
  const [election, owed] = listing.data ?? [0n, 0n];
  const qd = core.quoteMeta?.decimals ?? 6;
  const qs = core.quoteMeta?.symbol ?? "";
  const ts = core.tokenMeta?.symbol ?? "";
  const listingLive = election !== 0n && (election & ((1n << 160n) - 1n)) === BigInt(lodestar);
  const isSteward = !!address && address.toLowerCase() === core.steward?.toLowerCase();
  const lockForever = lockedUntil >= 2n ** 63n;

  return (
    <>
      <Card
        title={`${ts} Lodestar`}
        right={
          <div className="lock-badges">
            {isCreator ? <Badge tone="green">Holds the creator role</Badge> : <Badge tone="red">Not the creator</Badge>}
            {Number(lockedUntil) > now ? <Badge tone="gold">Role locked {lockForever ? "forever" : `until ${date(lockedUntil)}`}</Badge> : <Badge tone="amber">Role not locked</Badge>}
            <Badge tone="grey">No fees</Badge>
          </div>
        }
      >
        <SplitBar burn={cfg.burnBps} holders={cfg.holdersBps} treasury={cfg.treasuryBps} />
        <div className="stats">
          <Stat label="Token fees burned" value={`${fmt(tokenBurned, 18, 0)} ${ts}`} />
          <Stat label="Bought back and burned" value={`${fmt(buyBurned, 18, 0)} ${ts}`} hint={`${fmt(buyQ, qd)} ${qs} spent`} />
          <Stat label="To holders (Exile)" value={`${fmt(holdQ, qd)} ${qs}`} />
          <Stat label="To Team Treasury" value={`${fmt(treasQ, qd)} ${qs}`} />
        </div>
        <div className="summary">
          <Row k="Router" v={<Addr address={lodestar} />} />
          <Row k="Steward" v={<Addr address={core.steward} />} />
          <Row k="Buyback route" v={cfg.swapper === ZERO ? <Badge tone="amber">None: buybacks wait in reserve</Badge> : <Addr address={cfg.swapper} />} />
          <Row k="Max slippage" v={`${pct(cfg.maxSlippageBps)} vs Ascend's EMA price`} />
          <Row k="Listing set-aside" v={listingLive ? <><Badge tone="green">Enrolled</Badge> {fmt(owed, qd)} {qs} saved, {fmt(election >> 168n, qd)} {qs} to go</> : <Badge tone="grey">Not enrolled</Badge>} />
          <Row k="Last distribute" v={Number(lastAt) ? `${duration(now - Number(lastAt))} ago` : "never"} />
        </div>
      </Card>

      <Card title="Distribute" right={<span className="muted">anyone can call this</span>}>
        <p className="muted small">Collects and claims this token's creator fees from Ascend, then routes everything the router holds.</p>
        <div className="stats">
          <Stat label="To burn" value={`${fmt(preview[0], 18, 0)} ${ts}`} />
          <Stat label="Buyback" value={`${fmt(preview[2] + reserve, qd)} ${qs}`} hint={reserve > 0n ? `includes ${fmt(reserve, qd)} waiting in reserve` : undefined} />
          <Stat label="Holders" value={`${fmt(preview[3], qd)} ${qs}`} />
          <Stat label="Treasury" value={`${fmt(preview[4], qd)} ${qs}`} />
        </div>
        <p className="muted small">Plus any fees still sitting in the pool, which distribute collects first.</p>
        <TxButton request={() => ({ ...l, functionName: "distribute" })}>Distribute</TxButton>
      </Card>

      {eta > 0n && (
        <Card title="Pending split change" right={<Badge tone="amber">72 hour timelock</Badge>}>
          <SplitBar burn={pending.burnBps} holders={pending.holdersBps} treasury={pending.treasuryBps} />
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

type Cfg = { burnBps: number; holdersBps: number; treasuryBps: number; swapper: Address; maxSlippageBps: number };

function Steward({ lodestar, cfg, lockedUntil, listingLive }: { lodestar: Address; cfg: Cfg; lockedUntil: bigint; listingLive: boolean }) {
  const l = { address: lodestar, abi: lodestarAbi } as const;
  const [split, setSplit] = useState({ burn: cfg.burnBps / 100, holders: cfg.holdersBps / 100, treasury: cfg.treasuryBps / 100 });
  const [lockDays, setLockDays] = useState(365);
  const sum = split.burn + split.holders + split.treasury;
  const until = BigInt(Math.floor(Date.now() / 1000) + lockDays * 86400);
  return (
    <Card title="Steward controls" right={<span className="muted">only you see this</span>}>
      <h4>Change the split</h4>
      <SplitInputs split={split} setSplit={setSplit} />
      <TxButton
        disabledReason={sum !== 100 ? `Splits add up to ${sum}%, not 100%` : undefined}
        request={() => ({
          ...l,
          functionName: "proposeConfig",
          args: [{ ...cfg, burnBps: Math.round(split.burn * 100), holdersBps: Math.round(split.holders * 100), treasuryBps: Math.round(split.treasury * 100) }],
        })}
      >
        Propose (takes effect after 72 hours)
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

function Activate({ d, token, predicted, poolId }: { d: Deployment; token: Address; predicted: Address; poolId: `0x${string}` }) {
  const { address } = useConnection();
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
  const [treasury, setTreasury] = useState("");
  const [windowDays, setWindowDays] = useState(30);
  const [tiers, setTiers] = useState(DEFAULT_TIERS);
  const [listing, setListing] = useState(true);
  const [cap, setCap] = useState("5000");
  const [lockDays, setLockDays] = useState(365);

  if (!r.data) return null;
  const [creator, pendingCreator, owedQ, owedT] = r.data;
  if (creator === ZERO) return <Card>No Ascend pool found for this token and quote.</Card>;
  const you = !!address && creator.toLowerCase() === address.toLowerCase();
  const handedOver = pendingCreator.toLowerCase() === predicted.toLowerCase();
  const sum = split.burn + split.holders + split.treasury;
  const recipient = isAddress(treasury) ? treasury : address;

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
            <h5>Exile reward tiers</h5>
            <div className="tier-edit">
              {tiers.map((t, i) => (
                <div key={i} className="tier-edit-row">
                  <input className="input input-sm" value={t.name} onChange={(e) => setTiers(tiers.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)))} />
                  <input className="input input-sm" type="number" value={t.days} onChange={(e) => setTiers(tiers.map((x, j) => (j === i ? { ...x, days: Number(e.target.value) } : x)))} />
                  <span className="muted small">days</span>
                  <input className="input input-sm" type="number" step="0.1" value={t.mult} onChange={(e) => setTiers(tiers.map((x, j) => (j === i ? { ...x, mult: Number(e.target.value) } : x)))} />
                  <span className="muted small">x {TAGLINES[t.name] ? `· ${TAGLINES[t.name]}` : ""}</span>
                </div>
              ))}
            </div>
            <div className="form">
              <label>
                Team Treasury recipient
                <input className="input" placeholder={address ?? "0x…"} value={treasury} onChange={(e) => setTreasury(e.target.value.trim())} />
              </label>
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
                Cap
                <input className="input input-sm" value={cap} onChange={(e) => setCap(e.target.value)} />
              </label>
            )}
          </div>
          <TxButton
            disabledReason={
              !you ? "Only the current creator can activate" : !handedOver ? "Do step 1 first" : sum !== 100 ? `Splits add up to ${sum}%` : !recipient ? "Set a treasury recipient" : deskOk.data && deskOk.data !== d.desk ? "Listing desk mismatch" : undefined
            }
            request={() => ({
              address: d.factory,
              abi: lodestarFactoryAbi,
              functionName: "deploy",
              gas: 6_000_000n,
              args: [
                {
                  token,
                  quote: d.quote,
                  cfg: { burnBps: split.burn * 100, holdersBps: split.holders * 100, treasuryBps: split.treasury * 100, swapper: ZERO, maxSlippageBps: 1000 },
                  treasuryRecipient: recipient!,
                  treasuryWindow: windowDays * 86400,
                  tiers: tiers.map((t) => ({ minDuration: Math.round(t.days * 86400), multiplierBps: Math.round(t.mult * 10_000), label: stringToHex(t.name, { size: 32 }) })),
                  enrolListing: listing,
                  listingCap: listing ? parseUnits(cap || "0", 6) : 0n,
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
