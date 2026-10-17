// The small marks beside each tool in the nav. Their hover motion lives in styles.css (.nl-*).
const base = { viewBox: "0 0 14 14", fill: "none", stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "square", "aria-hidden": true } as const;

/** Lodestar, the guiding star: four long points and four short rays that flare on hover. */
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

/** Exile, a gate: the bars drop a little on hover while a portcullis falls over the word. */
export function GateGlyph() {
  return (
    <svg {...base}>
      <path d="M1 13V4.5a6 4 0 0 1 12 0V13" />
      <g className="gate-bars">
        <path d="M4 3v7M7 2v8M10 3v7M2.5 6.5h9" />
      </g>
      <path d="M0.5 13.2h13" />
    </svg>
  );
}

/** Sandfall, an hourglass that flips on hover. */
export function HourglassGlyph() {
  return (
    <svg {...base}>
      <path d="M2.5 0.8h9M2.5 13.2h9" />
      <path d="M3.5 0.8c0 3.5 7 3.5 7 6.2s-7 2.7-7 6.2M10.5 0.8c0 3.5-7 3.5-7 6.2s7 2.7 7 6.2" />
      <path className="sand-top" d="M4.8 2.6h4.4L7 5.2Z" fill="currentColor" stroke="none" />
      <path className="sand-bottom" d="M4.6 12.2h4.8L7 9.6Z" fill="currentColor" stroke="none" />
    </svg>
  );
}
