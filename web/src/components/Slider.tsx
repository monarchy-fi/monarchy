import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent, type ReactNode } from "react";
import { flushSync } from "react-dom";

/**
 * A slider with one or more handles. Once grabbed, a handle follows the pointer anywhere on the page,
 * however fast it moves and however far it strays from the bar, until the button is let go: the drag is
 * followed on the window, with pointer capture on top where the browser gives it. A grabbed handle keeps
 * its distance from the pointer, and a press on the bar moves the nearest handle there. Arrow keys,
 * Page Up/Down, Home and End work on a focused handle.
 */
export function Slider({
  min = 0,
  max,
  step = 1,
  values,
  onChange,
  labels,
  valueTexts,
  disabled,
  className,
  keyStep,
  children,
}: {
  min?: number;
  max: number;
  step?: number;
  values: readonly number[];
  onChange: (index: number, value: number) => void;
  labels: readonly string[];
  valueTexts?: readonly (string | undefined)[];
  disabled?: boolean;
  className?: string;
  /** takes over the arrow and Page keys, for scales where one step of the bar isn't one step of the value */
  keyStep?: (index: number, dir: -1 | 1, big: boolean) => void;
  /** drawn on the bar, behind the handles */
  children?: ReactNode;
}) {
  const bar = useRef<HTMLDivElement>(null);
  const thumbs = useRef<(HTMLDivElement | null)[]>([]);
  const [active, setActive] = useState<number | null>(null);
  // the drag listeners live on the window for the whole drag, so they read the latest props from here
  const latest = useRef({ values, onChange });
  latest.current = { values, onChange };
  const stop = useRef<(() => void) | null>(null);
  useEffect(() => () => stop.current?.(), []);
  const span = Math.max(1e-9, max - min);
  const snap = (v: number) => Math.min(max, Math.max(min, min + Math.round((v - min) / step) * step));
  const at = (clientX: number) => {
    const r = bar.current!.getBoundingClientRect();
    return snap(min + ((clientX - r.left) / Math.max(1, r.width)) * span);
  };
  const set = (i: number, v: number) => {
    // render each step straight away, so the next pointer move already sees where the handles are
    if (v !== latest.current.values[i]) flushSync(() => latest.current.onChange(i, v));
  };

  const down = (e: PointerEvent<HTMLDivElement>) => {
    if (disabled || e.button !== 0) return;
    e.preventDefault();
    stop.current?.();
    const vals = latest.current.values;
    const grabbed = thumbs.current.findIndex((t) => !!t && t.contains(e.target as Node));
    let i: number;
    // a handle grabbed off-centre keeps its distance from the pointer instead of jumping under it
    let offset = 0;
    // two handles stacked on one spot: the first move decides which, so either can come off the pile
    let pile: number[] = [];
    if (grabbed >= 0) {
      const r = thumbs.current[grabbed]!.getBoundingClientRect();
      offset = e.clientX - (r.left + r.width / 2);
      i = grabbed;
      pile = vals.flatMap((v, k) => (v === vals[grabbed] ? [k] : []));
      if (pile.length < 2) pile = [];
    } else {
      // a press on the bar takes the nearest handle there; on a tie, the one that can move toward the pointer
      const v = at(e.clientX);
      i = 0;
      for (let k = 1; k < vals.length; k++) {
        const dk = Math.abs(vals[k] - v);
        const di = Math.abs(vals[i] - v);
        if (dk < di || (dk === di && v > vals[k])) i = k;
      }
      set(i, v);
    }
    setActive(i);
    thumbs.current[i]?.focus({ preventScroll: true });
    const id = e.pointerId;
    const x0 = e.clientX;
    try {
      e.currentTarget.setPointerCapture(id);
    } catch {
      // the window listeners below carry the drag without it
    }
    const move = (ev: globalThis.PointerEvent) => {
      if (ev.pointerId !== id) return;
      // the button went up somewhere this page never heard about (outside the window, say)
      if (ev.buttons === 0) return end();
      if (pile.length && ev.clientX !== x0) {
        i = ev.clientX < x0 ? Math.min(...pile) : Math.max(...pile);
        pile = [];
        setActive(i);
        thumbs.current[i]?.focus({ preventScroll: true });
      }
      set(i, at(ev.clientX - offset));
    };
    const end = (ev?: Event) => {
      if (ev instanceof globalThis.PointerEvent && ev.pointerId !== id) return;
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", end);
      window.removeEventListener("pointercancel", end);
      window.removeEventListener("blur", end);
      stop.current = null;
      setActive(null);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", end);
    window.addEventListener("pointercancel", end);
    window.addEventListener("blur", end);
    stop.current = end;
  };
  const key = (i: number) => (e: KeyboardEvent<HTMLDivElement>) => {
    if (disabled) return;
    const dirs: Record<string, [-1 | 1, boolean]> = { ArrowLeft: [-1, false], ArrowDown: [-1, false], ArrowRight: [1, false], ArrowUp: [1, false], PageDown: [-1, true], PageUp: [1, true] };
    if (keyStep && e.key in dirs) {
      e.preventDefault();
      keyStep(i, ...dirs[e.key]);
      return;
    }
    const big = Math.max(step, snap(min + span / 10) - min);
    const v = values[i];
    const next: Record<string, number> = {
      ArrowLeft: v - step,
      ArrowDown: v - step,
      ArrowRight: v + step,
      ArrowUp: v + step,
      PageDown: v - big,
      PageUp: v + big,
      Home: min,
      End: max,
    };
    if (!(e.key in next)) return;
    e.preventDefault();
    set(i, snap(next[e.key]));
  };

  return (
    <div
      className={`slider ${active !== null ? "dragging" : ""} ${disabled ? "disabled" : ""} ${className ?? ""}`}
      onPointerDown={down}
    >
      <div ref={bar} className="slider-bar">
        {children ?? (
          <div className="slider-line">
            {values.length === 1 && <div className="slider-fill" style={{ width: `${((values[0] - min) / span) * 100}%` }} />}
          </div>
        )}
        {values.map((v, i) => (
          <div
            key={i}
            ref={(el) => {
              thumbs.current[i] = el;
            }}
            className={`slider-thumb ${active === i ? "on" : ""}`}
            style={{ left: `${((v - min) / span) * 100}%` }}
            role="slider"
            tabIndex={disabled ? -1 : 0}
            aria-label={labels[i]}
            aria-valuemin={min}
            aria-valuemax={max}
            aria-valuenow={v}
            aria-valuetext={valueTexts?.[i]}
            aria-disabled={disabled || undefined}
            onKeyDown={key(i)}
          />
        ))}
      </div>
    </div>
  );
}
