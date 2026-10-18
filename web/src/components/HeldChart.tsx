import { useEffect, useId, useRef, useState } from "react";

/** One point of the outlook: how much is still locked and still vesting at time t (seconds). */
export type HeldPoint = { t: number; locked: number; vesting: number };

const PAD = { l: 52, r: 14, t: 14, b: 26 };

const num = (v: number) => Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(v);
const day = (ts: number) => new Date(ts * 1000).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "2-digit" });

/**
 * How much of a token stays put over time: locked in Exile at the bottom, still vesting in Sandfall stacked on
 * top, both falling as locks end and streams pay out. Points are drawn as steps, the way locks release.
 * Hovering shows the amounts on that day.
 */
export function HeldChart({ points, symbol, height: H = 220 }: { points: HeldPoint[]; symbol: string; height?: number }) {
  const wrap = useRef<HTMLDivElement>(null);
  const [w, setW] = useState(640);
  const [hover, setHover] = useState<number>();
  const hatch = `held-${useId().replace(/:/g, "")}`;
  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setW(Math.max(260, Math.round(e.contentRect.width))));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  if (points.length < 2) return null;

  const t0 = points[0].t;
  const t1 = points[points.length - 1].t;
  const top = Math.max(...points.map((p) => p.locked + p.vesting)) || 1;
  const iw = w - PAD.l - PAD.r;
  const ih = H - PAD.t - PAD.b;
  const X = (t: number) => PAD.l + ((t - t0) / Math.max(1, t1 - t0)) * iw;
  const Y = (v: number) => PAD.t + (1 - v / top) * ih;

  // a step after each point: flat until the next one, then straight down to it
  const corners = (val: (p: HeldPoint) => number) => {
    const v: [number, number][] = [];
    points.forEach((p, i) => {
      if (i > 0) v.push([X(p.t), Y(val(points[i - 1]))]);
      v.push([X(p.t), Y(val(p))]);
    });
    return v;
  };
  const path = (v: [number, number][]) => v.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join("");
  const lockedV = corners((p) => p.locked);
  const totalV = corners((p) => p.locked + p.vesting);
  const lockedArea = `${path([...lockedV, [X(t1), Y(0)], [X(t0), Y(0)]])}Z`;
  // the vesting band sits between the two lines: along the total, then back along the locked line
  const vestingBand = `${path([...totalV, ...[...lockedV].reverse()])}Z`;

  const ticks = [t0, t0 + (t1 - t0) / 2, t1];
  const hp = hover !== undefined ? points[hover] : undefined;
  const onMove = (e: React.PointerEvent<SVGSVGElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    const t = t0 + ((e.clientX - r.left - PAD.l) / iw) * (t1 - t0);
    // the step in force at t is the last point at or before it
    let i = 0;
    while (i + 1 < points.length && points[i + 1].t <= t) i++;
    setHover(i);
  };

  return (
    <div ref={wrap} className="chart-wrap held">
      <svg
        className="chart"
        width={w}
        height={H}
        viewBox={`0 0 ${w} ${H}`}
        role="img"
        aria-label={`${symbol} still locked and still vesting, from ${day(t0)} to ${day(t1)}`}
        onPointerMove={onMove}
        onPointerLeave={() => setHover(undefined)}
      >
        <defs>
          <pattern id={hatch} width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <line x1="0" y1="0" x2="0" y2="5" stroke="var(--white)" strokeWidth="1" opacity="0.4" />
          </pattern>
        </defs>
        {[0, 0.5, 1].map((f) => (
          <g key={f}>
            <line className="chart-grid" x1={PAD.l} x2={w - PAD.r} y1={Y(top * f)} y2={Y(top * f)} strokeDasharray={f ? "2 4" : undefined} />
            <text className="chart-axis" x={PAD.l - 8} y={Y(top * f) + 3} textAnchor="end">
              {num(top * f)}
            </text>
          </g>
        ))}
        <path className="held-locked" d={lockedArea} />
        <path d={vestingBand} style={{ fill: `url(#${hatch})` }} />
        <path className="chart-line" d={path(totalV)} />
        <path className="held-locked-line" d={path(lockedV)} />
        {ticks.map((t, i) => (
          <text key={i} className="chart-axis" x={X(t)} y={H - 8} textAnchor={i === 0 ? "start" : i === ticks.length - 1 ? "end" : "middle"}>
            {i === 0 ? "now" : day(t)}
          </text>
        ))}
        {hp && (
          <g>
            <line className="chart-now" x1={X(hp.t)} x2={X(hp.t)} y1={PAD.t} y2={Y(0)} />
            <circle cx={X(hp.t)} cy={Y(hp.locked + hp.vesting)} r="4" fill="var(--white)" stroke="var(--card)" strokeWidth="2" />
          </g>
        )}
        {/* a wide hit area over the plot, so the hover follows the pointer anywhere inside it */}
        <rect x={PAD.l} y={PAD.t} width={iw} height={ih} fill="transparent" />
      </svg>
      {hp && (
        <div className="chart-tip" style={{ left: Math.min(Math.max(X(hp.t), 90), w - 90) }} role="status">
          <b>{hover === 0 ? "Now" : day(hp.t)}</b>
          <span>
            <i className="held-key held-key-locked" /> Locked {num(hp.locked)} {symbol}
          </span>
          <span>
            <i className="held-key held-key-vesting" /> Vesting {num(hp.vesting)} {symbol}
          </span>
        </div>
      )}
    </div>
  );
}
