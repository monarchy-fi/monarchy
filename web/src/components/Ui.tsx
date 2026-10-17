import type { CSSProperties, ReactNode } from "react";
import { useChainId } from "wagmi";
import { explorerAddress } from "../lib/chains";
import { compact as compactFmt, fmt, short } from "../lib/format";

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

export function Stat({ label, value, hint, className }: { label: string; value: ReactNode; hint?: ReactNode; className?: string }) {
  return (
    <div className={`stat ${className ?? ""}`}>
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {hint !== undefined && <div className="stat-hint">{hint}</div>}
    </div>
  );
}

/** A shimmering placeholder for a value that is still loading. */
export function Skel({ w = "5em", h, block, style }: { w?: string; h?: string; block?: boolean; style?: CSSProperties }) {
  return <span className={`skel ${block ? "skel-block" : ""}`} style={{ width: w, height: h, ...style }} aria-hidden="true" />;
}

/** A token amount with its symbol, or a placeholder while it loads. */
export function Amt({
  value,
  decimals = 18,
  symbol,
  digits = 2,
  compact,
  w,
}: {
  value: bigint | undefined;
  decimals?: number;
  symbol?: string;
  digits?: number;
  compact?: boolean;
  w?: string;
}) {
  if (value === undefined) return <Skel w={w ?? "6em"} />;
  return (
    <span className="amt">
      {compact ? compactFmt(value, decimals) : fmt(value, decimals, digits)}
      {symbol && <span className="amt-sym"> {symbol}</span>}
    </span>
  );
}

/** A token symbol read from the chain, or a placeholder while it loads. */
export function Sym({ s, w = "3.5em" }: { s?: string; w?: string }) {
  return s ? <>{s}</> : <Skel w={w} />;
}

export function Badge({ tone, children }: { tone: "gold" | "green" | "amber" | "red" | "grey" | "silver" | "purple"; children: ReactNode }) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}

export function Addr({ address }: { address?: string }) {
  const chainId = useChainId();
  if (!address) return <Skel w="7em" />;
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

const EMPTY_GLYPH = ["  .   .   .  ", " /|\\ /|\\ /|\\ ", "+-----------+"].join("\n");

/** A friendly empty state: a faint crown in ASCII, a line of text and an optional action. */
export function Empty({ title, children, action }: { title?: ReactNode; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="empty">
      <span className="empty-glyph" aria-hidden="true">{EMPTY_GLYPH}</span>
      {title && <div className="empty-title">{title}</div>}
      {children && <p className="empty-body">{children}</p>}
      {action && <div className="empty-action">{action}</div>}
    </div>
  );
}

export function Spinner() {
  return <span className="spinner" aria-hidden="true" />;
}
