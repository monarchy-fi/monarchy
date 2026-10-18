import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useReadContracts } from "wagmi";
import { exileAbi, lodestarAbi, mockERC20Abi } from "../abi";
import { TokenFeeFlow } from "../components/FeeFlow";
import { GateGlyph, HourglassGlyph, StarGlyph } from "../components/NavGlyphs";
import { NoDeployment } from "../components/States";
import { tagline, TierBadge } from "../components/Tiers";
import { Amt, Card, Skel, Stat, Sym } from "../components/Ui";
import { useDeployment } from "../lib/deployments";
import { fmt, label, mult } from "../lib/format";
import { POLL, usePageTitle } from "../lib/hooks";
import { dayLabel, useDripDays, useLodestarCore } from "../lib/monarchy";
import { days } from "./Home";

// Lodestar burns to this address; Ascend tokens reject 0x…dEaD
const DEAD = "0xdEAD000000000000000042069420694206942069";

/** The overview the landing page leaves out: the promises, where fees go, live numbers, the three tools and the court. */
export function KingdomPage() {
  usePageTitle("Kingdom");
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
    ],
    query: { enabled: !!core.lodestar && !!core.token && core.exilePoolId !== undefined, ...POLL.query },
  });
  const [feeBurned, buybackBurned, holders, treasury, buybackQuote, dead, supply, pool] = stats.data ?? [];
  const now = BigInt(Math.floor(Date.now() / 1000));
  const dripPerDay = pool ? (pool.periodFinish > now ? (pool.rewardRate * 86400n) / 10n ** 18n : 0n) : undefined;
  const drip = useDripDays();
  const burnShare = dead !== undefined && supply ? `${fmt((dead * 10_000n) / supply, 2, 2)}% of supply` : undefined;

  return (
    <div className="page">
      <div className="page-head">
        <h1>Kingdom</h1>
        <p>
          Every token launched on Ascend can run its own kingdom. Creator fees are burned, bought back, paid to locked holders or
          streamed to the team, all in the open, and Monarchy keeps none of it.
        </p>
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

      <TokenFeeFlow />

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
        <Feature to="/lodestar" title="Lodestar" kicker="Fee router" icon={<StarGlyph />} cls="nl-lodestar">
          Holds your token's Ascend creator role. You keep your dev buy. Fees split by your percentages into buyback and burn,
          holder rewards and a Team Treasury.
        </Feature>
        <Feature to="/exile" title="Exile" kicker="Locks and rewards" icon={<GateGlyph />} cls="nl-exile">
          Lock tokens, v2 LP and NFTs. Locks can be extended, never shortened or cancelled. Longer locks earn a bigger share,
          paid as a {dayLabel(drip)} drip.
        </Feature>
        <Feature to="/sandfall" title="Sandfall" kicker="Vesting" icon={<HourglassGlyph />} cls="nl-sandfall">
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
                <div className="tier-bars" aria-hidden="true">
                  {tierBars(t.multiplierBps)}
                </div>
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

/** A tier's multiplier as signal bars: one bar per half x, up to six. */
function tierBars(bps: number): string {
  const n = Math.max(1, Math.min(6, Math.round(bps / 5000)));
  return "▮".repeat(n) + "▯".repeat(6 - n);
}

function Feature({ to, title, kicker, icon, cls, children }: { to: string; title: string; kicker: string; icon: ReactNode; cls: string; children: ReactNode }) {
  return (
    <Link to={to} className={`card feature ${cls}`}>
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

const enc = (s: string) => ("0x" + [...s].map((c) => c.charCodeAt(0).toString(16)).join("").padEnd(64, "0")) as `0x${string}`;
const DEFAULT_TIERS = [
  { minDuration: 86400, multiplierBps: 5000, label: enc("Peasant") },
  { minDuration: 3 * 86400, multiplierBps: 10000, label: enc("Knight") },
  { minDuration: 7 * 86400, multiplierBps: 15000, label: enc("Duke") },
  { minDuration: 30 * 86400, multiplierBps: 30000, label: enc("Monarch") },
];
