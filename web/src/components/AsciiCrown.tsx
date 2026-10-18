import { useEffect, useRef } from "react";

// A crown drawn as a cloud of points on its surfaces, turned in 3D and shaded with characters: brighter
// surfaces (facing the light) get denser characters, and jewels catch a specular glint. A z-buffer keeps
// the nearest point per cell.
const COLS = 106;
const ROWS = 60;
const RAMP = " .'`,:;-~+=*xo%#&@";
// a JetBrains Mono cell is 0.6em wide; with line-height 1 a cell is this many times taller than wide
const CELL = 1 / 0.6;

// inner: the inside of the wall, drawn faintly so the near and far sides of the crown read apart
// band: the base band, drawn in lighter strokes so it reads apart from the wall
// gem: jewels and pearls, which take a sharp highlight
type P = { x: number; y: number; z: number; nx: number; ny: number; nz: number; inner?: boolean; band?: boolean; gem?: boolean };

const POINTS = 8;
const BASE = -0.62; // where the wall meets the band
const BAND_LOW = -0.92;
const DIP = -0.25; // the top edge between points
const PEAK = 0.85; // how far each point rises above the dips

/** Height of the top edge at angle t: eight points with dips between them. */
function top(t: number) {
  const u = ((t * POINTS) / (2 * Math.PI)) % 1;
  return DIP + PEAK * (1 - Math.abs(2 * u - 1)); // 0 at dips, 1 at tips
}

function buildCrown(): P[] {
  const pts: P[] = [];
  const ball = (cx: number, cy: number, cz: number, r: number, sy = 1) => {
    const step = Math.max(0.12, 0.022 / r);
    for (let a = 0; a <= Math.PI; a += step) {
      for (let b = 0; b < Math.PI * 2; b += step) {
        const nx = Math.sin(a) * Math.cos(b);
        const ny = Math.cos(a);
        const nz = Math.sin(a) * Math.sin(b);
        pts.push({ x: cx + nx * r, y: cy + ny * r * sy, z: cz + nz * r, nx, ny, nz, gem: true });
      }
    }
  };
  for (let t = 0; t < Math.PI * 2; t += 0.014) {
    const c = Math.cos(t);
    const s = Math.sin(t);
    const h = top(t);
    // the wall: outer face and inner face, so the far side shows through the open top
    for (let y = BASE; y <= h; y += 0.02) {
      pts.push({ x: c, y, z: s, nx: c, ny: 0, nz: s });
      pts.push({ x: c * 0.96, y, z: s * 0.96, nx: -c, ny: 0, nz: -s, inner: true });
    }
    // a thin lip along the top edge, so the outline of every point reads crisply
    pts.push({ x: c * 0.98, y: h, z: s * 0.98, nx: c * 0.3, ny: 1, nz: s * 0.3 });
    // the base band, a little proud of the wall
    for (let y = BAND_LOW; y <= BASE; y += 0.02) {
      pts.push({ x: c * 1.07, y, z: s * 1.07, nx: c, ny: 0, nz: s, band: true });
    }
    // rims above and below the band
    pts.push({ x: c * 1.035, y: BASE, z: s * 1.035, nx: 0, ny: 1, nz: 0 });
    pts.push({ x: c * 1.035, y: BAND_LOW, z: s * 1.035, nx: 0, ny: -1, nz: 0 });
  }
  for (let i = 0; i < POINTS; i++) {
    const t = ((i + 0.5) / POINTS) * Math.PI * 2;
    // a ball on every tip, and a jewel set in the wall under it
    ball(Math.cos(t) * 0.98, DIP + PEAK + 0.1, Math.sin(t) * 0.98, 0.1);
    ball(Math.cos(t) * 1.01, -0.02, Math.sin(t) * 1.01, 0.08, 1.35);
    // big and small stones in turn around the band, under the dips
    const b = (i / POINTS) * Math.PI * 2;
    ball(Math.cos(b) * 1.1, (BASE + BAND_LOW) / 2, Math.sin(b) * 1.1, i % 2 === 0 ? 0.095 : 0.055, i % 2 === 0 ? 1.25 : 1);
  }
  // pearls along the top of the band
  for (let i = 0; i < 44; i++) {
    const b = ((i + 0.5) / 44) * Math.PI * 2;
    ball(Math.cos(b) * 1.1, BASE + 0.035, Math.sin(b) * 1.1, 0.03);
  }
  return pts;
}

// light from the upper left, toward the viewer; the highlight uses the half vector with the view
const L = norm(-0.45, 0.5, -0.75);
const H = norm(L[0], L[1], L[2] - 1);
function norm(x: number, y: number, z: number): [number, number, number] {
  const n = Math.hypot(x, y, z);
  return [x / n, y / n, z / n];
}

function render(pts: P[], angle: number, out: string[], zbuf: Float32Array): string {
  out.fill(" ");
  zbuf.fill(-Infinity);
  const ca = Math.cos(angle);
  const sa = Math.sin(angle);
  const tilt = -0.18; // look down a little, to see into the crown
  const ct = Math.cos(tilt);
  const st = Math.sin(tilt);
  const roll = -0.17; // tip the crown so its rim runs from top left down to bottom right
  const cr = Math.cos(roll);
  const sr = Math.sin(roll);
  const dist = 5;
  const scale = 117;
  const top = RAMP.length - 1;
  for (const p of pts) {
    // spin around y
    const x1 = p.x * ca - p.z * sa;
    const z1 = p.x * sa + p.z * ca;
    const nx1 = p.nx * ca - p.nz * sa;
    const nz1 = p.nx * sa + p.nz * ca;
    // tilt around x
    const y2 = p.y * ct - z1 * st;
    const z2 = p.y * st + z1 * ct;
    const ny2 = p.ny * ct - nz1 * st;
    const nz2 = p.ny * st + nz1 * ct;
    // faces pointing away from the viewer are hidden (the camera looks along +z)
    if (nz2 > 0.15) continue;
    // roll around the view axis
    const x3 = x1 * cr - y2 * sr;
    const y3 = x1 * sr + y2 * cr;
    const nx3 = nx1 * cr - ny2 * sr;
    const ny3 = nx1 * sr + ny2 * cr;
    const ooz = 1 / (z2 + dist);
    const col = Math.round(COLS / 2 + x3 * scale * CELL * ooz);
    const row = Math.round(ROWS / 2 - 4 - y3 * scale * ooz);
    if (col < 0 || col >= COLS || row < 0 || row >= ROWS) continue;
    const i = row * COLS + col;
    if (ooz <= zbuf[i]) continue;
    zbuf[i] = ooz;
    const lum = Math.max(0, nx3 * L[0] + ny3 * L[1] + nz2 * L[2]);
    let k: number;
    if (p.inner) k = 2 + Math.round(lum * 5);
    else if (p.gem) {
      const spec = Math.pow(Math.max(0, -(nx3 * H[0] + ny3 * H[1] + nz2 * H[2])), 18);
      k = 6 + Math.round(lum * (top - 8) + spec * 8);
    } else if (p.band) k = 5 + Math.round(lum * 6);
    else k = 4 + Math.round(lum * (top - 4));
    out[i] = RAMP[Math.min(top, k)];
  }
  let s = "";
  for (let r = 0; r < ROWS; r++) s += out.slice(r * COLS, (r + 1) * COLS).join("") + "\n";
  return s;
}

/**
 * The home page centrepiece: a crown turning slowly in ASCII. It sizes its characters to fill the box it
 * sits in, and holds still for reduced motion and while off screen.
 */
export function AsciiCrown({ className }: { className?: string }) {
  const box = useRef<HTMLDivElement>(null);
  const ref = useRef<HTMLPreElement>(null);
  useEffect(() => {
    const el = ref.current;
    const wrap = box.current;
    if (!el || !wrap) return;
    const ro = new ResizeObserver(([e]) => {
      const { width, height } = e.contentRect;
      const fs = Math.min(width / (COLS * 0.6), height / ROWS);
      el.style.fontSize = `${Math.max(3, fs).toFixed(2)}px`;
    });
    ro.observe(wrap);
    const pts = buildCrown();
    const out = new Array<string>(COLS * ROWS);
    const zbuf = new Float32Array(COLS * ROWS);
    const still = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    let angle = 0.7; // a view with a point near the front, also the still frame
    el.textContent = render(pts, angle, out, zbuf);
    if (still) return () => ro.disconnect();
    let raf = 0;
    let last = 0;
    let visible = true;
    const io = new IntersectionObserver(([e]) => (visible = e.isIntersecting));
    io.observe(el);
    const tick = (t: number) => {
      raf = requestAnimationFrame(tick);
      if (!visible || document.hidden || t - last < 40) return; // about 25 frames a second
      angle += ((t - (last || t)) / 1000) * 0.42;
      last = t;
      el.textContent = render(pts, angle, out, zbuf);
    };
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      io.disconnect();
      ro.disconnect();
    };
  }, []);
  return (
    <div ref={box} className={`ascii-crown-box ${className ?? ""}`}>
      <pre ref={ref} className="ascii-crown" aria-label="A crown, turning, drawn in text characters" role="img" />
    </div>
  );
}
