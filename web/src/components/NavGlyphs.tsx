import { useId } from "react";

// The marks for each tool in the nav. They stay hidden until the link is hovered, then appear in front of the
// word with their own motion, which lives in styles.css (.nl-*).
const base = { viewBox: "0 0 14 14", fill: "none", stroke: "currentColor", strokeWidth: 1.2, strokeLinecap: "square", "aria-hidden": true } as const;

/** Lodestar, the guiding star: it turns in, a beacon ring pulses out from it and the sky around it twinkles. */
export function StarGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" aria-hidden="true">
      <circle className="star-ring" cx="12" cy="12" r="5" strokeWidth="0.8" />
      <g className="star-body">
        <path d="M7.6 7.6 12 10.5 16.4 7.6 13.5 12 16.4 16.4 12 13.5 7.6 16.4 10.5 12Z" fill="currentColor" fillOpacity="0.45" stroke="none" />
        <path d="M12 2.2 13.5 10.5 21.6 12 13.5 13.5 12 23 10.5 13.5 2.4 12 10.5 10.5Z" fill="currentColor" stroke="none" />
        <circle cx="12" cy="12" r="1.1" fill="#000" stroke="none" />
      </g>
      <g fill="currentColor" stroke="none">
        <path className="star-twinkle" d="M4.2 3.2 4.6 4.4 5.8 4.8 4.6 5.2 4.2 6.4 3.8 5.2 2.6 4.8 3.8 4.4Z" />
        <path className="star-twinkle" d="M20 18.2 20.35 19.25 21.4 19.6 20.35 19.95 20 21 19.65 19.95 18.6 19.6 19.65 19.25Z" />
        <circle className="star-twinkle" cx="20.2" cy="4.6" r="0.6" />
      </g>
    </svg>
  );
}

/** Exile, a portcullis: it drops in front of the word, spikes first. Stretched to the word's width. */
export function GateGlyph() {
  const bars = [3, 11, 19, 27, 35, 43, 51, 59, 67, 75, 83, 91, 97];
  return (
    <svg viewBox="0 0 100 40" preserveAspectRatio="none" fill="none" stroke="currentColor" aria-hidden="true">
      <path d="M0 1.5H100" strokeWidth="3" vectorEffect="non-scaling-stroke" />
      <path d="M0 13H100M0 25H100" strokeWidth="1" vectorEffect="non-scaling-stroke" />
      {bars.map((x) => (
        <path key={x} d={`M${x} 0V34`} strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
      ))}
      {bars.map((x) => (
        <path key={`t${x}`} d={`M${x - 2.2} 33 ${x} 40 ${x + 2.2} 33Z`} fill="currentColor" stroke="none" />
      ))}
    </svg>
  );
}

/** Sandfall, an hourglass: the glass turns over, then sand drips from the top bulb into the bottom. */
export function HourglassGlyph() {
  return (
    <svg {...base}>
      <g className="sand-glass">
        <path d="M2.5 0.8h9M2.5 13.2h9" />
        <path d="M3.5 0.8C3.5 4.2 6.3 5.2 6.3 7S3.5 9.8 3.5 13.2M10.5 0.8C10.5 4.2 7.7 5.2 7.7 7S10.5 9.8 10.5 13.2" />
        <path className="sand-top" d="M4.1 1.9h5.8L7 5.6Z" fill="currentColor" stroke="none" />
        <path className="sand-stream" d="M7 6.4V12.4" strokeWidth="0.7" strokeDasharray="0.5 0.9" />
        <path className="sand-bottom" d="M4.1 12.1h5.8L7 8.4Z" fill="currentColor" stroke="none" />
      </g>
    </svg>
  );
}

/** Kingdom, a castle: it rises in front of the word, its flag waves, light sweeps across the stone and stars sparkle over it. */
export function CastleGlyph() {
  const clip = `castle-${useId().replace(/:/g, "")}`;
  // towers, curtain walls and a roofed keep, with the gate cut out of it
  const shape =
    "M1.5 23V8.5H2.7V10H3.4V8.5H4.6V10H5.3V8.5H6.5V12.5H7.3V14H8.1V12.5H9V9.5H8.5L12 4.5 15.5 9.5H15V12.5H15.9V14H16.7V12.5H17.5V8.5H18.7V10H19.4V8.5H20.6V10H21.3V8.5H22.5V23Z" +
    "M10.3 23V19A1.7 1.7 0 0 1 13.7 19V23Z";
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="0.8" strokeLinejoin="miter" aria-hidden="true">
      <defs>
        <clipPath id={clip}>
          <path d={shape} clipRule="evenodd" />
        </clipPath>
      </defs>
      <path d={shape} fill="currentColor" fillOpacity="0.14" fillRule="evenodd" />
      <path d="M2.6 16.5h2.6M3.6 19.5h2.2M18.8 16.5h2.6M18.2 19.5h2.2M9.6 15.5h1.6M12.8 15.5h1.6" strokeWidth="0.5" opacity="0.6" />
      <path d="M11.15 17.6V23M12 17.3V23M12.85 17.6V23M10.3 20.2h3.4M10.3 21.8h3.4" strokeWidth="0.45" />
      <path d="M3.55 12.6h0.9v2.6h-0.9ZM19.55 12.6h0.9v2.6h-0.9ZM11.45 13V11.6A0.55 0.55 0 0 1 12.55 11.6V13Z" fill="currentColor" stroke="none" />
      <path d="M0.5 23.4H23.5" strokeWidth="0.6" />
      <g clipPath={`url(#${clip})`}>
        <path className="castle-glint" d="M-7 24 1 -1H4.6L-3.4 24Z" fill="currentColor" stroke="none" />
      </g>
      <path d="M12 4.5V0.4" strokeWidth="0.6" />
      <path className="castle-flag" d="M12 0.5 15.8 1.45 12 2.4Z" fill="currentColor" stroke="none" />
      <path className="castle-spark" d="M20.6 1.2 21.05 2.65 22.5 3.1 21.05 3.55 20.6 5 20.15 3.55 18.7 3.1 20.15 2.65Z" fill="currentColor" stroke="none" />
      <path className="castle-spark castle-spark-2" d="M3.6 3.4 3.9 4.3 4.8 4.6 3.9 4.9 3.6 5.8 3.3 4.9 2.4 4.6 3.3 4.3Z" fill="currentColor" stroke="none" />
    </svg>
  );
}

const MARKS = { kingdom: CastleGlyph, lodestar: StarGlyph, exile: GateGlyph, sandfall: HourglassGlyph };

/** A page's mark, drawn left of its title and always in motion. */
export function PageMark({ page }: { page: keyof typeof MARKS }) {
  const Glyph = MARKS[page];
  return (
    <span className={`page-mark mark-live nl-${page}`} aria-hidden="true">
      <Glyph />
    </span>
  );
}
