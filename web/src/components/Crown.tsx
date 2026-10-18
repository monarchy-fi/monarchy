import { useId, type CSSProperties } from "react";

/** The Monarchy crown, drawn in the current text colour. */
export function Crown({ size = 28, className }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" className={className} aria-hidden="true" fill="currentColor">
      <CrownShapes />
    </svg>
  );
}

/** The crown's shapes, shared by the flat crown and each layer of the solid one. */
function CrownShapes() {
  return (
    <>
      <path d="M8 46 4 18l15 12 13-20 13 20 15-12-4 28z" />
      <rect x="8" y="49" width="48" height="7" />
      <rect x="1" y="13" width="6" height="6" transform="rotate(45 4 16)" />
      <rect x="29" y="5" width="6" height="6" transform="rotate(45 32 8)" />
      <rect x="57" y="13" width="6" height="6" transform="rotate(45 60 16)" />
    </>
  );
}

const LAYERS = 15;

/**
 * The nav's crown: the same crown, given depth by stacking copies of it front to back, so it turns like a
 * solid object. Silver at rest, it spins once and turns gold on hover, then spins back to silver when the
 * pointer leaves. The motion lives in styles.css (.cx).
 */
export function CrownSolid() {
  const shine = `cx-shine-${useId().replace(/:/g, "")}`;
  return (
    <span className="cx" aria-hidden="true">
      <span className="cx-spin">
        {Array.from({ length: LAYERS }, (_, k) => {
          const face = k === 0 || k === LAYERS - 1;
          return (
            <svg key={k} viewBox="0 0 64 64" className={`cx-layer ${face ? "cx-face" : "cx-side"}`} style={{ "--z": k - (LAYERS - 1) / 2 } as CSSProperties} fill="currentColor">
              <CrownShapes />
              {face && (
                <>
                  {/* a light from above and a shadow below, the same over silver or gold */}
                  <linearGradient id={`${shine}-${k}`} gradientUnits="userSpaceOnUse" x1="0" y1="4" x2="0" y2="58">
                    <stop offset="0" stopColor="#fff" stopOpacity="0.85" />
                    <stop offset="0.45" stopColor="#fff" stopOpacity="0" />
                    <stop offset="0.7" stopColor="#000" stopOpacity="0" />
                    <stop offset="1" stopColor="#000" stopOpacity="0.4" />
                  </linearGradient>
                  <g fill={`url(#${shine}-${k})`}>
                    <CrownShapes />
                  </g>
                </>
              )}
            </svg>
          );
        })}
      </span>
    </span>
  );
}
