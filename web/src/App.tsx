import { useEffect, useState } from "react";
import { NavLink, Route, Routes, useLocation } from "react-router-dom";
import { useConnect, useConnection, useConnectors } from "wagmi";
import { Connect } from "./components/Connect";
import { Crown } from "./components/Crown";
import { GateGlyph, HourglassGlyph, StarGlyph } from "./components/NavGlyphs";
import { NetworkNotice, TestnetStrip } from "./components/States";
import { isSet, useDeployment } from "./lib/deployments";
import { short } from "./lib/format";
import { useMock } from "./lib/wagmi";
import { ExilePage } from "./pages/Exile";
import { Home } from "./pages/Home";
import { LodestarPage } from "./pages/Lodestar";
import { NotFound } from "./pages/NotFound";
import { SandfallPage } from "./pages/Sandfall";

const LINKS = [
  { to: "/lodestar", label: "Lodestar", hint: "Fee router", key: "lodestar", glyph: <StarGlyph /> },
  { to: "/exile", label: "Exile", hint: "Locks and rewards", key: "exile", glyph: <GateGlyph /> },
  { to: "/sandfall", label: "Sandfall", hint: "Vesting", key: "sandfall", glyph: <HourglassGlyph /> },
];

// the word, with the tool's mark hidden in front of it until hover
function LinkLabel({ l }: { l: (typeof LINKS)[number] }) {
  return (
    <>
      <span className="nl-word">{l.label}</span>
      <span className="nl-icon" aria-hidden="true">
        {l.glyph}
      </span>
    </>
  );
}

/** The token's contract address, shortened; a click copies the full address. */
function ContractChip({ className }: { className?: string }) {
  const d = useDeployment();
  const [copied, setCopied] = useState(false);
  const token = d && isSet(d.token) ? d.token : undefined;
  if (!token) return null;
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(token);
      setCopied(true);
      setTimeout(() => setCopied(false), 1400);
    } catch {
      // clipboard blocked: the full address is still in the tooltip
    }
  };
  return (
    <button type="button" className={`ca ${className ?? ""}`} onClick={copy} title={`${token}, click to copy`}>
      <span className="ca-k">Contract</span>
      <span className="ca-v">{copied ? "Copied" : short(token)}</span>
    </button>
  );
}

export function App() {
  const [menuOpen, setMenuOpen] = useState(false);
  const { pathname } = useLocation();
  const home = pathname === "/";
  useMockAutoConnect();

  // close the phone menu and go to the top on every navigation
  useEffect(() => {
    setMenuOpen(false);
    window.scrollTo(0, 0);
  }, [pathname]);

  return (
    <div className={`app ${home ? "app-home" : ""}`}>
      <TestnetStrip />
      <header className="nav-wrap">
        <nav className="nav" aria-label="Main">
          <NavLink to="/" className="brand" aria-label="Monarchy home">
            <Crown size={20} className="brand-glyph" />
            <span>MONARCHY</span>
          </NavLink>
          <div className="nav-links">
            {LINKS.map((l) => (
              <NavLink key={l.to} to={l.to} className={`nl nl-${l.key}`}>
                <LinkLabel l={l} />
              </NavLink>
            ))}
          </div>
          <div className="nav-right">
            <ContractChip />
            <Connect className="nav-connect" />
            <button
              className="menu-btn"
              aria-label={menuOpen ? "Close menu" : "Open menu"}
              aria-expanded={menuOpen}
              aria-controls="mobile-menu"
              onClick={() => setMenuOpen((o) => !o)}
            >
              <span className={`burger ${menuOpen ? "open" : ""}`} aria-hidden="true">
                <i />
                <i />
                <i />
              </span>
            </button>
          </div>
        </nav>
        {menuOpen && (
          <div className="menu" id="mobile-menu">
            {LINKS.map((l) => (
              <NavLink key={l.to} to={l.to} className={`menu-link nl nl-${l.key}`}>
                <span className="nl">
                  <LinkLabel l={l} />
                </span>
                <span className="menu-hint">{l.hint}</span>
              </NavLink>
            ))}
            <ContractChip className="menu-ca" />
          </div>
        )}
      </header>
      <NetworkNotice />
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/lodestar" element={<LodestarPage />} />
          <Route path="/exile" element={<ExilePage />} />
          <Route path="/sandfall" element={<SandfallPage />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </main>
      {!home && (
        <footer className="foot">
          <div className="foot-brand">
            <span>MONARCHY</span>
            <span className="foot-sep" aria-hidden="true" />
            <span>Built on Ascend. No fees.</span>
          </div>
          <div className="foot-links">
            <a href="https://docs.monarchy.fi" target="_blank" rel="noreferrer">
              Docs
            </a>
            <a href="https://github.com/monarchy-fi/monarchy" target="_blank" rel="noreferrer">
              GitHub
            </a>
            <a href="https://x.com/monarchyfi" target="_blank" rel="noreferrer">
              X
            </a>
          </div>
        </footer>
      )}
    </div>
  );
}

/** With `?mock` on a dev server, connect anvil's first account as soon as the page loads. */
function useMockAutoConnect() {
  const { status } = useConnection();
  const connectors = useConnectors();
  const connect = useConnect();
  useEffect(() => {
    if (!useMock || status !== "disconnected" || connect.isPending) return;
    const c = connectors[0];
    if (c) connect.mutate({ connector: c });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status, connectors]);
}
