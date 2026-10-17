import { Link } from "react-router-dom";
import { useReadContracts } from "wagmi";
import { exileAbi, lodestarAbi, mockERC20Abi } from "../abi";
import { Crown } from "../components/Crown";
import { TAGLINES, TierBadge } from "../components/Tiers";
import { Card, Stat } from "../components/Ui";
import { useDeployment } from "../lib/deployments";
import { compact, fmt, label, mult } from "../lib/format";
import { POLL } from "../lib/hooks";
import { useLodestarCore } from "../lib/monarchy";

// Lodestar burns to this address; Ascend tokens reject 0x…dEaD
const DEAD = "0xdEAD000000000000000042069420694206942069";

export function Home() {
  const d = useDeployment();
  const core = useLodestarCore();
  const qd = core.quoteMeta?.decimals ?? 6;
  const qs = core.quoteMeta?.symbol ?? "USDC";
  const ts = core.tokenMeta?.symbol ?? "MONARCH";
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
  const dripPerDay = pool && pool.periodFinish > now ? (pool.rewardRate * 86400n) / 10n ** 18n : 0n;

  return (
    <div className="page">
      <section className="hero">
        <Crown size={72} className="hero-crown" />
        <h1>
          Ascend to <span className="gold">Monarchy</span>
        </h1>
        <p className="hero-sub">Dethrone the Duke. Become the Monarch.</p>
        <p className="hero-body">
          Three tools for every token launched on Ascend, with no fees on any of them. Lodestar routes creator fees to
          buyback and burn, holder rewards and a Team Treasury. Exile locks tokens, LP and NFTs and pays lockers by
          tier. Sandfall streams vesting with a clear cancellable badge.
        </p>
        <div className="hero-cta">
          <Link className="btn" to="/exile">
            Lock {ts}
          </Link>
          <Link className="btn btn-ghost" to="/lodestar">
            Activate Lodestar for your token
          </Link>
        </div>
      </section>

      {!d && (
        <Card>
          <p className="empty">No Monarchy deployment on this network yet. Switch to Elysium Testnet or run the local demo.</p>
        </Card>
      )}

      {d && core.lodestar && (
        <Card title={`${ts} kingdom`} right={<span className="muted">live from Lodestar, refreshes every 2s</span>}>
          <div className="stats">
            <Stat label="Burned" value={`${compact(dead)} ${ts}`} hint={supply ? `${fmt((dead ?? 0n) * 10_000n / supply, 2, 2)}% of supply` : undefined} />
            <Stat label="Burned by buyback" value={`${compact(buybackBurned)} ${ts}`} hint={`${fmt(buybackQuote, qd)} ${qs} spent`} />
            <Stat label="Burned from token fees" value={`${compact(feeBurned)} ${ts}`} />
            <Stat label="Paid to holders" value={`${fmt(holders, qd)} ${qs}`} hint={`${fmt(dripPerDay, qd)} ${qs}/day dripping now`} />
            <Stat label="Team Treasury" value={`${fmt(treasury, qd)} ${qs}`} hint="streamed through Sandfall" />
            <Stat label="Locked points" value={compact(pool?.totalPoints)} hint="amount × tier multiplier" />
          </div>
        </Card>
      )}

      <div className="grid3">
        <Feature to="/lodestar" title="Lodestar" kicker="Fee router">
          Takes over your token's Ascend creator role. The dev keeps the dev buy. Creator fees split by your
          percentages into buyback and burn, holder rewards and Team Treasury, with a 12 hour timelock on changes.
        </Feature>
        <Feature to="/exile" title="Exile" kicker="Locks + rewards">
          Lock ERC-20s, v2 LP, ERC-721s and ERC-1155s. Locks can be extended, never shortened or cancelled. Longer
          locks earn a bigger share, paid out as a 7 day drip.
        </Feature>
        <Feature to="/sandfall" title="Sandfall" kicker="Vesting">
          Linear, cliff or monthly vesting in any token or HYPE. Every stream shows whether its creator can cancel it.
          The Team Treasury streams out here.
        </Feature>
      </div>

      <Card title="The court">
        <div className="tiers">
          {(pool?.tiers ?? DEFAULT_TIERS).map((t) => {
            const name = label(t.label);
            return (
              <div key={name} className={`tier tier-${name.toLowerCase()}`}>
                <TierBadge name={name} />
                <div className="tier-mult">{mult(t.multiplierBps)}</div>
                <div className="tier-len">{days(t.minDuration)} lock</div>
                <div className="tier-tag">{TAGLINES[name] ?? ""}</div>
              </div>
            );
          })}
        </div>
        <p className="muted small">No lock, no rewards. Rewards stop the moment a lock ends.</p>
      </Card>
    </div>
  );
}

function Feature({ to, title, kicker, children }: { to: string; title: string; kicker: string; children: React.ReactNode }) {
  return (
    <Link to={to} className="card feature">
      <div className="kicker">{kicker}</div>
      <h3>{title}</h3>
      <p>{children}</p>
      <span className="gold">Open {title} →</span>
    </Link>
  );
}

export function days(seconds: number): string {
  const d = seconds / 86400;
  if (d === 30) return "1 month";
  return `${d} day${d === 1 ? "" : "s"}`;
}

const enc = (s: string) => ("0x" + [...s].map((c) => c.charCodeAt(0).toString(16)).join("").padEnd(64, "0")) as `0x${string}`;
const DEFAULT_TIERS = [
  { minDuration: 86400, multiplierBps: 5000, label: enc("Peasant") },
  { minDuration: 3 * 86400, multiplierBps: 10000, label: enc("Knight") },
  { minDuration: 7 * 86400, multiplierBps: 15000, label: enc("Duke") },
  { minDuration: 30 * 86400, multiplierBps: 30000, label: enc("Monarch") },
];
