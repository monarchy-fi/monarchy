import type { ReactNode } from "react";
import { useChainId } from "wagmi";
import { explorerAddress } from "../lib/chains";
import { short } from "../lib/format";

export function Card({ title, children, right, className }: { title?: ReactNode; children: ReactNode; right?: ReactNode; className?: string }) {
  return (
    <section className={`card ${className ?? ""}`}>
      {(title || right) && (
        <header className="card-head">
          {title && <h3>{title}</h3>}
          {right}
        </header>
      )}
      {children}
    </section>
  );
}

export function Stat({ label, value, hint }: { label: string; value: ReactNode; hint?: ReactNode }) {
  return (
    <div className="stat">
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {hint && <div className="stat-hint">{hint}</div>}
    </div>
  );
}

export function Badge({ tone, children }: { tone: "gold" | "green" | "amber" | "red" | "grey" | "silver" | "purple"; children: ReactNode }) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}

export function Addr({ address }: { address?: string }) {
  const chainId = useChainId();
  if (!address) return <span className="mono">…</span>;
  const link = explorerAddress(chainId, address);
  return link ? (
    <a className="mono" href={link} target="_blank" rel="noreferrer" title={address}>
      {short(address)}
    </a>
  ) : (
    <span className="mono" title={address}>
      {short(address)}
    </span>
  );
}

export function Row({ k, v }: { k: ReactNode; v: ReactNode }) {
  return (
    <div className="row">
      <span className="row-k">{k}</span>
      <span className="row-v">{v}</span>
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="empty">{children}</p>;
}
