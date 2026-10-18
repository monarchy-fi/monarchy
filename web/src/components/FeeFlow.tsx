import { useReadContract } from "wagmi";
import { lodestarAbi } from "../abi";
import { DISTRIBUTE_EVERY_HOURS } from "../lib/constants";
import { pct } from "../lib/format";
import { POLL } from "../lib/hooks";
import { useDripDays, useLodestarCore } from "../lib/monarchy";

/** The fee flow for the deployment's token, with its live split and token-side route. */
export function TokenFeeFlow() {
  const core = useLodestarCore();
  const drip = useDripDays();
  const cfg = useReadContract({ address: core.lodestar, abi: lodestarAbi, functionName: "config", query: { enabled: !!core.lodestar, ...POLL.query } });
  const c = cfg.data;
  return <FeeFlow drip={drip} burn={c?.burnBps} holders={c?.holdersBps} treasury={c?.treasuryBps} tokenToHolders={c?.tokenToHolders} />;
}

/** Ascend pool fees, through Lodestar, out to the four places they can go. */
export function FeeFlow({ drip, burn, holders, treasury, tokenToHolders }: { drip: number; burn?: number; holders?: number; treasury?: number; tokenToHolders?: boolean }) {
  const share = (bps?: number) => (bps === undefined ? "Quote share" : `${pct(bps)} of quote fees`);
  const dests = [
    tokenToHolders
      ? { key: "fire", mark: "[+]", title: "Exile lockers", tag: "All token-side fees", body: `Paid to locked holders in the token itself, over ${drip} days.` }
      : { key: "fire", mark: "[x]", title: "Burned", tag: "All token-side fees", body: "Sent straight to the burn address, or, if the creator chooses, paid to Exile lockers." },
    { key: "burn", mark: "[x]", title: "Buyback and burn", tag: share(burn), body: "Buys the token on Ascend, then burns it." },
    { key: "hold", mark: "[+]", title: "Exile holders", tag: share(holders), body: `Paid to locked holders by tier, over ${drip} days.` },
    { key: "treas", mark: "[~]", title: "Sandfall treasury", tag: share(treasury), body: "Streamed to the Team Treasury in the open." },
  ];
  return (
    <section className="flow" aria-labelledby="flow-title">
      <div className="flow-head">
        <h2 id="flow-title">Where the fees go</h2>
        <p className="muted">Every creator fee follows the same public path. Nothing stops at Monarchy.</p>
      </div>
      <div className="flow-body">
        <div className="flow-node flow-src ascii-box">
          <div className="flow-kicker">Source</div>
          <div className="flow-title">Ascend pool fees</div>
          <p>The creator half of every 1% swap fee, in the token and the quote asset.</p>
        </div>
        <FlowArrow />
        <div className="flow-node flow-hub ascii-box">
          <span className="flow-glyph" aria-hidden="true">*</span>
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
              <span className="dest-mark" aria-hidden="true">{x.mark}</span>
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
    <div className={`flow-arrow ${className ?? ""}`} aria-hidden="true">
      <span>──▶</span>
    </div>
  );
}

