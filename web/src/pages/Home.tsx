import { Link } from "react-router-dom";
import { AsciiCrown } from "../components/AsciiCrown";
import { usePageTitle } from "../lib/hooks";
import { useLodestarCore } from "../lib/monarchy";

/**
 * The landing page: one screen, no scroll. The crown draws the eye; the details live on the tool pages. On wide
 * screens the words sit left of the crown; narrower ones stack them with the crown in the middle.
 */
export function Home() {
  usePageTitle();
  const core = useLodestarCore();
  const ts = core.tokenMeta?.symbol;
  return (
    <div className="landing">
      <div className="landing-call">
        <h1 className="wordmark">Monarchy</h1>
        <p className="tagline">
          <span className="tagline-prompt" aria-hidden="true">&gt;</span> Seize the crown<span className="tagline-caret" aria-hidden="true">_</span>
        </p>
        <p className="landing-sub">Fee routing, locks and vesting for every Ascend token. Monarchy takes nothing.</p>
        <div className="hero-cta">
          <Link className="btn btn-lg" to="/exile">
            {ts ? `Lock ${ts}` : "Lock tokens"}
          </Link>
          <Link className="btn btn-ghost btn-lg" to="/lodestar">
            Activate Lodestar
          </Link>
        </div>
      </div>
      <AsciiCrown className="landing-crown" />
      <div className="landing-links">
        <span className="landing-note">Built on Ascend. No fees.</span>
        <span className="landing-out">
          <a href="https://docs.monarchy.fi" target="_blank" rel="noreferrer">
            Docs <span aria-hidden="true">↗</span>
          </a>
          <a href="https://x.com/monarchyfi" target="_blank" rel="noreferrer" aria-label="Monarchy on X">
            <XLogo /> <span aria-hidden="true">↗</span>
          </a>
        </span>
      </div>
    </div>
  );
}

function XLogo() {
  return (
    <svg viewBox="0 0 24 24" width="13" height="13" aria-hidden="true" fill="currentColor">
      <path d="M3 3 L10.2 12.6 L3.2 21 H5.6 L11.3 14.1 L16.4 21 H21 L13.4 10.8 L19.9 3 H17.5 L12.3 9.3 L7.6 3 Z" />
    </svg>
  );
}

export function days(seconds: number): string {
  const d = seconds / 86400;
  if (d === 30) return "1 month";
  return `${d} day${d === 1 ? "" : "s"}`;
}
