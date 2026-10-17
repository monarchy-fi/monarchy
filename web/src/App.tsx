import { NavLink, Route, Routes } from "react-router-dom";
import { useChainId } from "wagmi";
import { Connect } from "./components/Connect";
import { Crown } from "./components/Crown";
import { useDeployment } from "./lib/deployments";
import { ExilePage } from "./pages/Exile";
import { Home } from "./pages/Home";
import { LodestarPage } from "./pages/Lodestar";
import { SandfallPage } from "./pages/Sandfall";

export function App() {
  const d = useDeployment();
  const chainId = useChainId();
  return (
    <div className="app">
      <nav className="nav">
        <NavLink to="/" className="brand">
          <Crown size={26} />
          <span>Monarchy</span>
        </NavLink>
        <div className="nav-links">
          <NavLink to="/lodestar">Lodestar</NavLink>
          <NavLink to="/exile">Exile</NavLink>
          <NavLink to="/sandfall">Sandfall</NavLink>
        </div>
        <div className="nav-right">
          <span className="net">
            {chainId === 99801 ? "Elysium Testnet" : chainId === 31337 ? "Local" : `Chain ${chainId}`}
            {d?.mode === "mock" && " · mock Ascend"}
          </span>
          <Connect />
        </div>
      </nav>
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/lodestar" element={<LodestarPage />} />
          <Route path="/exile" element={<ExilePage />} />
          <Route path="/sandfall" element={<SandfallPage />} />
        </Routes>
      </main>
      <footer className="foot">
        <span>
          <Crown size={14} /> Monarchy · built on Ascend, Elysium testnet · no fees
        </span>
        <a href="https://github.com/monarchy-fi/monarchy" target="_blank" rel="noreferrer">
          GitHub
        </a>
      </footer>
    </div>
  );
}
