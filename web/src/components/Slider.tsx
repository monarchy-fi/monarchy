import { useRef, useState, type KeyboardEvent, type PointerEvent, type ReactNode } from "react";

/**
 * A slider with one or more handles. Once grabbed, a handle follows the pointer anywhere on the page,
 * however fast it moves and however far it strays from the bar, until the button is let go. A press on
 * the bar moves the nearest handle there. Arrow keys, Page Up/Down, Home and End work on a focused handle.
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
  const span = Math.max(1e-9, max - min);
  const snap = (v: number) => Math.min(max, Math.max(min, min + Math.round((v - min) / step) * step));
  const at = (clientX: number) => {
    const r = bar.current!.getBoundingClientRect();
    return snap(min + ((clientX - r.left) / Math.max(1, r.width)) * span);
  };
  const set = (i: number, v: number) => {
    if (v !== values[i]) onChange(i, v);
  };

  const down = (e: PointerEvent<HTMLDivElement>) => {
    if (disabled || e.button !== 0) return;
    const v = at(e.clientX);
    // the nearest handle; on a tie (handles stacked) take the one that can move toward the pointer
    let i = 0;
    for (let k = 1; k < values.length; k++) {
      const dk = Math.abs(values[k] - v);
      const di = Math.abs(values[i] - v);
      if (dk < di || (dk === di && v > values[k])) i = k;
    }
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    setActive(i);
    thumbs.current[i]?.focus({ preventScroll: true });
    set(i, v);
  };
  const move = (e: PointerEvent<HTMLDivElement>) => {
    if (active === null || !e.currentTarget.hasPointerCapture(e.pointerId)) return;
    set(active, at(e.clientX));
  };
  const up = (e: PointerEvent<HTMLDivElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
    setActive(null);
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
      onPointerMove={move}
      onPointerUp={up}
      onPointerCancel={up}
      onLostPointerCapture={() => setActive(null)}
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
