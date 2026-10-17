import { useEffect, useId, useRef, useState } from "react";

export type Schedule = { start: number; cliff: number; end: number; step: number };

/** The share of a fixed stream unlocked at time t, 0 to 1. Mirrors Sandfall's _vested. */
export function unlockedAt(s: Schedule, t: number): number {
  if (t < s.cliff) return 0;
  if (t >= s.end) return 1;
  const dur = s.end - s.start;
  if (dur <= 0) return 1;
  if (!s.step) return (t - s.start) / dur;
  const periods = Math.ceil(dur / s.step);
  return Math.min(periods, Math.floor((t - s.start) / s.step)) / periods;
}

const PAD = { l: 52, r: 14, t: 14, b: 26 };
const MAX_STEPS = 400;

function shortDate(ts: number, withTime: boolean) {
  const d = new Date(ts * 1000);
  return withTime
    ? d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
    : d.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "2-digit" });
}

/**
 * How much of a stream is unlocked by when: a line from start to fully vested, with the cliff jump and
 * monthly or weekly steps drawn as they happen on chain. `now` adds a marker for where the stream is today.
 */
export function UnlockChart({ schedule, total, now, height: H = 190 }: { schedule: Schedule; total: number; now?: number; height?: number }) {
  const wrap = useRef<HTMLDivElement>(null);
  const [w, setW] = useState(480);
  const hatch = `hatch-${useId().replace(/:/g, "")}`;
  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setW(Math.max(240, Math.round(e.contentRect.width))));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const { start, cliff, end } = schedule;
  const span = Math.max(1, end - start);
  const x0 = start;
  const x1 = end + span * 0.06;
  const iw = w - PAD.l - PAD.r;
  const ih = H - PAD.t - PAD.b;
  const X = (t: number) => PAD.l + ((t - x0) / (x1 - x0)) * iw;
  const Y = (f: number) => PAD.t + (1 - f) * ih;

  // corner points of the unlock curve
  const pts: [number, number][] = [[start, 0]];
  if (!schedule.step) {
    pts.push([cliff, 0], [cliff, unlockedAt(schedule, cliff)], [end, 1]);
  } else {
    const periods = Math.ceil(span / schedule.step);
    const every = Math.max(1, Math.ceil(periods / MAX_STEPS));
    let prev = 0;
    for (let k = 1; k <= periods; k += every) {
      const t = Math.max(cliff, Math.min(end, start + k * schedule.step));
      const f = unlockedAt(schedule, t);
      if (f !== prev) {
        pts.push([t, prev], [t, f]);
        prev = f;
      }
    }
    if (prev !== 1) pts.push([end, prev], [end, 1]);
  }
  pts.push([x1, 1]);
  const line = pts.map(([t, f], i) => `${i ? "L" : "M"}${X(t).toFixed(1)},${Y(f).toFixed(1)}`).join("");
  const area = `${line}L${X(x1).toFixed(1)},${Y(0)}L${X(start).toFixed(1)},${Y(0)}Z`;

  const short = span < 3 * 86400;
  const amt = (f: number) => {
    const v = total * f;
    return Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(v);
  };
  const ticks = [start, ...(cliff > start && X(cliff) - X(start) > 120 && X(end) - X(cliff) > 110 ? [cliff] : []), end];
  const showNow = now !== undefined && now > start && now < x1;
  const nowF = showNow ? unlockedAt(schedule, now) : 0;

  return (
    <div ref={wrap} className="chart-wrap">
      <svg className="chart" width={w} height={H} viewBox={`0 0 ${w} ${H}`} role="img" aria-label={`Unlock schedule from ${shortDate(start, short)} to ${shortDate(end, short)}`}>
        <defs>
          <pattern id={hatch} width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <line x1="0" y1="0" x2="0" y2="5" stroke="var(--white)" strokeWidth="1" opacity="0.35" />
          </pattern>
        </defs>
        {[0, 0.5, 1].map((f) => (
          <g key={f}>
            <line className="chart-grid" x1={PAD.l} x2={w - PAD.r} y1={Y(f)} y2={Y(f)} strokeDasharray={f ? "2 4" : undefined} />
            <text className="chart-axis" x={PAD.l - 8} y={Y(f) + 3} textAnchor="end">
              {amt(f)}
            </text>
          </g>
        ))}
        <path className="chart-area" d={area} style={{ fill: `url(#${hatch})` }} />
        <path className="chart-line" d={line} />
        {ticks.map((t, i) => (
          <text key={t} className="chart-axis" x={X(t)} y={H - 8} textAnchor={i === 0 ? "start" : i === ticks.length - 1 ? "end" : "middle"}>
            {t === cliff && t !== start && t !== end ? `cliff ${shortDate(t, short)}` : shortDate(t, short)}
          </text>
        ))}
        {showNow && (
          <g>
            <line className="chart-now" x1={X(now)} x2={X(now)} y1={PAD.t} y2={Y(0)} />
            <circle cx={X(now)} cy={Y(nowF)} r="3" fill="var(--white)" />
            <text className="chart-now-label" x={X(now) + (X(now) > w - 90 ? -6 : 6)} y={PAD.t + 9} textAnchor={X(now) > w - 90 ? "end" : "start"}>
              now {Math.round(nowF * 100)}%
            </text>
          </g>
        )}
      </svg>
    </div>
  );
}
