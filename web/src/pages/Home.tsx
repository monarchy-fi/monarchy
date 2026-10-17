import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useReadContracts } from "wagmi";
import { exileAbi, lodestarAbi, mockERC20Abi } from "../abi";
import { Crown } from "../components/Crown";
import { DISTRIBUTE_EVERY_HOURS } from "../lib/constants";
import { HourglassIcon, LockIcon, StarIcon } from "../components/Icons";
import { NoDeployment } from "../components/States";
import { tagline, TierBadge } from "../components/Tiers";
import { Amt, Card, Skel, Stat, Sym } from "../components/Ui";
import { useDeployment } from "../lib/deployments";
import { fmt, label, mult, pct } from "../lib/format";
import { POLL, usePageTitle } from "../lib/hooks";
import { dayLabel, useDripDays, useLodestarCore } from "../lib/monarchy";

// Lodestar burns to this address; Ascend tokens reject 0x…dEaD
const DEAD = "0xdEAD000000000000000042069420694206942069";

export function Home() {
  usePageTitle();
  const d = useDeployment();
  const core = useLodestarCore();
  const qd = core.quoteMeta?.decimals ?? 6;
  const qs = core.quoteMeta?.symbol;
  const ts = core.tokenMeta?.symbol;
  const td = core.tokenMeta?.decimals ?? 18;
  const l = { address: core.lodestar, abi: lodestarAbi } as const;
  const stats = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...l, functionName: "totalTokenBurned" },
      { ...l, functionName: "totalBuybackTokensBurned" },
      { ...l, functionName: "totalHoldersQuote" },
      { ...l, functionName: "totalTreasuryQuote" },
      { ...l, functionName: "totalBuybackQuote" },
      { address: core.token, abi: mockERC20Abi, functionName: "balanceOf", args: [DEAD] },
      { address: core.token, abi: mockERC20Abi, functionName: "totalSupply" },
      { address: d?.exile, abi: exileAbi, functionName: "poolInfo", args: [core.exilePoolId ?? 0n] },
      { ...l, functionName: "config" },
    ],
    query: { enabled: !!core.lodestar && !!core.token && core.exilePoolId !== undefined, ...POLL.query },
  });
  const [feeBurned, buybackBurned, holders, treasury, buybackQuote, dead, supply, pool, cfg] = stats.data ?? [];
  const now = BigInt(Math.floor(Date.now() / 1000));
  const dripPerDay = pool ? (pool.periodFinish > now ? (pool.rewardRate * 86400n) / 10n ** 18n : 0n) : undefined;
  const drip = useDripDays();
  const burnShare = dead !== undefined && supply ? `${fmt((dead * 10_000n) / supply, 2, 2)}% of supply` : undefined;

  return (
    <div className="page page-home">
      <section className="hero">
        <div className="hero-halo" aria-hidden="true" />
        <div className="eyebrow">For tokens launched on Ascend</div>
        <Crown size={84} className="hero-crown" />
        <h1>
          Ascend to <span className="gold-text">Monarchy</span>
        </h1>
        <p className="hero-sub">Dethrone the Duke. Become the Monarch.</p>
        <p className="hero-body">
          Fee routing, locks and vesting for every Ascend token. Creator fees are burned, bought back, paid to locked
          holders or streamed to the team, all in the open.
        </p>
        <div className="hero-cta">
          <Link className="btn btn-lg" to="/exile">
            {ts ? `Lock ${ts}` : "Lock tokens"}
          </Link>
          <Link className="btn btn-ghost btn-lg" to="/lodestar">
            Activate Lodestar for your token
          </Link>
        </div>
        <ul className="seals" aria-label="Guarantees">
          <li className="seal seal-main">
            <span className="seal-big">0%</span>
            <span className="seal-text">
              <b>No fees.</b> Monarchy takes nothing, on any tool.
            </span>
          </li>
          <li className="seal">
            <span className="seal-text">
              <b>No upgrades, no sweep.</b> Funds can only go where the contracts say.
            </span>
          </li>
          <li className="seal">
            <span className="seal-text">
              <b>12 hour timelock</b> on every split or tier change.
            </span>
          </li>
        </ul>
      </section>

      <FeeFlow drip={drip} burn={cfg?.burnBps} holders={cfg?.holdersBps} treasury={cfg?.treasuryBps} />

      {!d && <NoDeployment inline />}

      {d && core.lodestar && (
        <Card
          className="kingdom"
          title={
            <>
              The <Sym s={ts} /> kingdom
            </>
          }
          right={
            <span className="live">
              <i className="live-dot" /> Live from Lodestar
            </span>
          }
        >
          <div className="stats stats-3">
            <Stat className="stat-feature" label="Burned in total" value={<Amt value={dead} decimals={td} symbol={ts} compact />} hint={burnShare ?? <Skel w="7em" />} />
            <Stat label="Paid to holders" value={<Amt value={holders} decimals={qd} symbol={qs} />} hint={dripPerDay === undefined ? <Skel w="8em" /> : `${fmt(dripPerDay, qd)} ${qs ?? ""} a day dripping now`} />
            <Stat label="Team Treasury" value={<Amt value={treasury} decimals={qd} symbol={qs} />} hint="Streamed through Sandfall" />
            <Stat label="Bought back and burned" value={<Amt value={buybackBurned} decimals={td} symbol={ts} compact />} hint={buybackQuote === undefined ? <Skel w="7em" /> : `${fmt(buybackQuote, qd)} ${qs ?? ""} spent`} />
            <Stat label="Burned from token fees" value={<Amt value={feeBurned} decimals={td} symbol={ts} compact />} hint="Sent straight to the burn address" />
            <Stat label="Locked points" value={<Amt value={pool?.totalPoints} decimals={td} compact />} hint="Amount times tier multiplier" />
          </div>
        </Card>
      )}

      <div className="grid3">
        <Feature to="/lodestar" title="Lodestar" kicker="Fee router" icon={<StarIcon />}>
          Holds your token's Ascend creator role. You keep your dev buy. Fees split by your percentages into buyback and
          burn, holder rewards and a Team Treasury.
        </Feature>
        <Feature to="/exile" title="Exile" kicker="Locks and rewards" icon={<LockIcon />}>
          Lock tokens, v2 LP and NFTs. Locks can be extended, never shortened or cancelled. Longer locks earn a bigger
          share, paid as a {dayLabel(drip)} drip.
        </Feature>
        <Feature to="/sandfall" title="Sandfall" kicker="Vesting" icon={<HourglassIcon />}>
          Linear, cliff or monthly vesting in any token or HYPE. Every stream shows whether its creator can cancel it.
        </Feature>
      </div>

      <Card title="The court" right={<span className="muted small">Lock longer, earn more</span>}>
        <div className="tiers">
          {(pool?.tiers ?? DEFAULT_TIERS).map((t) => {
            const name = label(t.label);
            return (
              <div key={name} className={`tier tier-${name.toLowerCase()}`}>
                <TierBadge name={name} />
                <div className="tier-mult">{mult(t.multiplierBps)}</div>
                <div className="tier-len">{days(t.minDuration)} lock</div>
                <div className="tier-tag">{tagline(name) ?? ""}</div>
              </div>
            );
          })}
        </div>
        <p className="muted small">No lock, no rewards. Rewards stop the moment a lock ends.</p>
      </Card>
    </div>
  );
}

/** Ascend pool fees, through Lodestar, out to the four places they can go. */
function FeeFlow({ drip, burn, holders, treasury }: { drip: number; burn?: number; holders?: number; treasury?: number }) {
  const share = (bps?: number) => (bps === undefined ? "Quote share" : `${pct(bps)} of quote fees`);
  const dests = [
    { key: "fire", title: "Burned", tag: "All token-side fees", body: "Sent straight to the burn address." },
    { key: "burn", title: "Buyback and burn", tag: share(burn), body: "Buys the token on Ascend, then burns it." },
    { key: "hold", title: "Exile holders", tag: share(holders), body: `Paid to locked holders by tier, over ${drip} days.` },
    { key: "treas", title: "Sandfall treasury", tag: share(treasury), body: "Streamed to the Team Treasury in the open." },
  ];
  return (
    <section className="flow" aria-labelledby="flow-title">
      <div className="flow-head">
        <h2 id="flow-title">Where the fees go</h2>
        <p className="muted">Every creator fee follows the same public path. Nothing stops at Monarchy.</p>
      </div>
      <div className="flow-body">
        <div className="flow-node flow-src">
          <div className="flow-kicker">Source</div>
          <div className="flow-title">Ascend pool fees</div>
          <p>The creator half of every 1% swap fee, in the token and the quote asset.</p>
        </div>
        <FlowArrow />
        <div className="flow-node flow-hub">
          <Crown size={22} />
          <div className="flow-title">Lodestar</div>
          <p>Called every {DISTRIBUTE_EVERY_HOURS} hours by the team. Anyone can call it. It takes 0%.</p>
        </div>
        <svg className="flow-branch" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
          {[12.5, 37.5, 62.5, 87.5].map((y, i) => (
            <path key={y} className={`branch branch-${dests[i].key}`} d={`M0 50 C 55 50, 45 ${y}, 100 ${y}`} vectorEffect="non-scaling-stroke" />
          ))}
        </svg>
        <FlowArrow className="flow-arrow-split" />
        <ul className="flow-dests">
          {dests.map((x) => (
            <li key={x.key} className={`flow-dest dest-${x.key}`}>
              <i className="dest-dot" />
              <div>
                <div className="flow-title">{x.title}</div>
                <div className="dest-tag">{x.tag}</div>
                <p>{x.body}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function FlowArrow({ className }: { className?: string }) {
  return (
    <svg className={`flow-arrow ${className ?? ""}`} viewBox="0 0 48 24" aria-hidden="true">
      <path d="M2 12 H40" />
      <path d="M34 5 L42 12 L34 19" />
    </svg>
  );
}

function Feature({ to, title, kicker, icon, children }: { to: string; title: string; kicker: string; icon: ReactNode; children: ReactNode }) {
  return (
    <Link to={to} className="card feature">
      <div className="feature-top">
        <span className="feature-icon" aria-hidden="true">
          {icon}
        </span>
        <span className="kicker">{kicker}</span>
      </div>
      <h3>{title}</h3>
      <p>{children}</p>
      <span className="feature-go">
        Open {title} <span aria-hidden="true">→</span>
      </span>
    </Link>
  );
}

export function days(seconds: number): string {
  const d = seconds / 86400;
  if (d === 30) return "1 month";
  return `${d} day${d === 1 ? "" : "s"}`;
}

const enc = (s: string) => ("0x" + [...s].map((c) => c.charCodeAt(0).toString(16)).join("").padEnd(64, "0")) as `0x${string}`;
export const DEFAULT_TIERS = [
  { minDuration: 86400, multiplierBps: 5000, label: enc("Peasant") },
  { minDuration: 3 * 86400, multiplierBps: 10000, label: enc("Knight") },
  { minDuration: 7 * 86400, multiplierBps: 15000, label: enc("Duke") },
  { minDuration: 30 * 86400, multiplierBps: 30000, label: enc("Monarch") },
];
