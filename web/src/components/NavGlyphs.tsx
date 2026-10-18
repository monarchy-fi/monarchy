import { useId } from "react";

// The marks for each tool in the nav. They stay hidden until the link is hovered, then appear in front of the
// word with their own motion, which lives in styles.css (.nl-*).
const base = { viewBox: "0 0 14 14", fill: "none", stroke: "currentColor", strokeWidth: 1.2, strokeLinecap: "square", "aria-hidden": true } as const;

/** Lodestar, the guiding star: it turns in and its short rays flare. */
export function StarGlyph() {
  return (
    <svg {...base}>
      <path d="M7 0.5 8.2 5.8 13.5 7 8.2 8.2 7 13.5 5.8 8.2 0.5 7 5.8 5.8Z" fill="currentColor" stroke="none" />
      <g className="star-ray">
        <path d="M2.4 2.4 3.6 3.6M11.6 2.4 10.4 3.6M2.4 11.6 3.6 10.4M11.6 11.6 10.4 10.4" />
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

/** Sandfall, an hourglass: sand pours from the top bulb into the bottom, then the glass turns over. */
export function HourglassGlyph() {
  return (
    <svg {...base}>
      <g className="sand-glass">
        <path d="M2.5 0.8h9M2.5 13.2h9" />
        <path d="M3.5 0.8C3.5 4.2 6.3 5.2 6.3 7S3.5 9.8 3.5 13.2M10.5 0.8C10.5 4.2 7.7 5.2 7.7 7S10.5 9.8 10.5 13.2" />
        <path className="sand-top" d="M4.3 2.4h5.4L7 6.2Z" fill="currentColor" stroke="none" />
        <path className="sand-stream" d="M7 6.4V12.4" strokeWidth="0.7" strokeDasharray="0.5 0.9" />
        <path className="sand-bottom" d="M4 12.6h6L7 9.5Z" fill="currentColor" stroke="none" />
      </g>
    </svg>
  );
}

/** Kingdom, a castle: it rises in front of the word, its flag waves and a glint of light sweeps across it. */
export function CastleGlyph() {
  const clip = `castle-${useId().replace(/:/g, "")}`;
  const wall =
    "M1 13V4.5H1.8V5.2H2.2V4.5H3V5.2H3.4V4.5H4.2V6.5H4.8V2.8H5.8V3.5H6.5V2.8H7.5V3.5H8.2V2.8H9.2V6.5H9.8V4.5H10.6V5.2H11V4.5H11.8V5.2H12.2V4.5H13V13H8V10.6A1 1 0 0 0 6 10.6V13Z";
  return (
    <svg {...base} strokeWidth={0.7} strokeLinejoin="miter">
      <defs>
        <clipPath id={clip}>
          <path d={wall} />
        </clipPath>
      </defs>
      <path d={wall} fill="currentColor" fillOpacity="0.1" />
      <g clipPath={`url(#${clip})`}>
        <path className="castle-glint" d="M-4 14 1.2 -1H4.6L-0.6 14Z" fill="currentColor" stroke="none" />
      </g>
      <path className="castle-flag" d="M7 2.8V0.3M7 0.4 9.6 1.05 7 1.7Z" fill="currentColor" />
      <path d="M2.2 7.4h0.8v1.5h-0.8ZM11 7.4h0.8v1.5h-0.8Z" fill="currentColor" stroke="none" />
      <path className="castle-spark" d="M12.4 0 12.75 1.05 13.8 1.4 12.75 1.75 12.4 2.8 12.05 1.75 11 1.4 12.05 1.05Z" fill="currentColor" stroke="none" />
    </svg>
  );
}
