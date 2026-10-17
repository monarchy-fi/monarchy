import { formatUnits } from "viem";

export function fmt(value: bigint | undefined, decimals = 18, digits = 2): string {
  if (value === undefined) return "…";
  const n = Number(formatUnits(value, decimals));
  if (n !== 0 && Math.abs(n) < 10 ** -digits) return `<${(10 ** -digits).toFixed(digits)}`;
  return n.toLocaleString(undefined, { maximumFractionDigits: digits, minimumFractionDigits: n < 1000 ? Math.min(digits, 2) : 0 });
}

export function compact(value: bigint | undefined, decimals = 18): string {
  if (value === undefined) return "…";
  const n = Number(formatUnits(value, decimals));
  return Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 2 }).format(n);
}

export function short(addr?: string): string {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : "";
}

export function pct(bps: number | bigint | undefined): string {
  if (bps === undefined) return "…";
  return `${(Number(bps) / 100).toLocaleString(undefined, { maximumFractionDigits: 2 })}%`;
}

export function mult(bps: number | bigint): string {
  return `${(Number(bps) / 10_000).toLocaleString(undefined, { maximumFractionDigits: 2 })}x`;
}

export function duration(seconds: number): string {
  if (seconds <= 0) return "now";
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m ${Math.floor(seconds % 60)}s`;
}

export function date(ts: number | bigint): string {
  const n = Number(ts);
  if (n >= 2 ** 63 || n > 1e12) return "forever";
  return new Date(n * 1000).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

export function label(b: string): string {
  // bytes32 tier labels are right-padded with zeros
  const hex = b.replace(/^0x/, "").replace(/(00)+$/, "");
  let s = "";
  for (let i = 0; i < hex.length; i += 2) s += String.fromCharCode(parseInt(hex.slice(i, i + 2), 16));
  return s;
}
