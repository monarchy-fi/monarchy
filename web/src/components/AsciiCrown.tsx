import { useEffect, useRef } from "react";

// A crown drawn as a cloud of points on its surfaces, turned in 3D and shaded with characters: brighter
// surfaces (facing the light) get denser characters. A z-buffer keeps the nearest point per cell.
const COLS = 72;
const ROWS = 28;
const RAMP = " .,:;-~=+*#%@";

// inner: the inside of the wall, drawn faintly so the near and far sides of the crown read apart
// band: the base band, drawn in lighter strokes so it reads apart from the wall
type P = { x: number; y: number; z: number; nx: number; ny: number; nz: number; inner?: boolean; band?: boolean };

function buildCrown(): P[] {
  const pts: P[] = [];
  const SPIKES = 5;
  // height of the top edge at angle t: five points with dips between them
  const top = (t: number) => {
    const u = ((t * SPIKES) / (2 * Math.PI)) % 1;
    const tri = 1 - Math.abs(2 * u - 1); // 0 at dips, 1 at tips
    return -0.46 + 1.36 * Math.pow(tri, 1.15);
  };
  for (let t = 0; t < Math.PI * 2; t += 0.024) {
    const c = Math.cos(t);
    const s = Math.sin(t);
    const h = top(t);
    // the wall: outer face and inner face, so the far side shows through the open top
    for (let y = -0.62; y <= h; y += 0.032) {
      pts.push({ x: c, y, z: s, nx: c, ny: 0, nz: s });
      pts.push({ x: c * 0.95, y, z: s * 0.95, nx: -c, ny: 0, nz: -s, inner: true });
    }
    // the base band, a little proud of the wall
    for (let y = -1.02; y <= -0.6; y += 0.03) {
      pts.push({ x: c * 1.07, y, z: s * 1.07, nx: c, ny: 0, nz: s, band: true });
    }
    pts.push({ x: c * 1.035, y: -0.6, z: s * 1.035, nx: 0, ny: 1, nz: 0 });
    pts.push({ x: c * 1.035, y: -1.02, z: s * 1.035, nx: 0, ny: -1, nz: 0 });
  }
  // jewels: a ball on each tip and studs around the band
  const ball = (cx: number, cy: number, cz: number, r: number) => {
    for (let a = 0; a < Math.PI; a += 0.32) {
      for (let b = 0; b < Math.PI * 2; b += 0.32) {
        const nx = Math.sin(a) * Math.cos(b);
        const ny = Math.cos(a);
        const nz = Math.sin(a) * Math.sin(b);
        pts.push({ x: cx + nx * r, y: cy + ny * r, z: cz + nz * r, nx, ny, nz });
      }
    }
  };
  for (let i = 0; i < SPIKES; i++) {
    const t = ((i + 0.5) / SPIKES) * Math.PI * 2;
    ball(Math.cos(t), top(t) + 0.08, Math.sin(t), 0.1);
    const b = (i / SPIKES) * Math.PI * 2;
    ball(Math.cos(b) * 1.1, -0.81, Math.sin(b) * 1.1, 0.08);
  }
  return pts;
}

function render(pts: P[], angle: number): string {
  const out = new Array<string>(COLS * ROWS).fill(" ");
  const zbuf = new Float32Array(COLS * ROWS).fill(-Infinity);
  const ca = Math.cos(angle);
  const sa = Math.sin(angle);
  const tilt = 0.3; // look down a little, to see into the crown
  const ct = Math.cos(tilt);
  const st = Math.sin(tilt);
  // light from upper left, toward the viewer
  const lx = -0.45;
  const ly = 0.65;
  const lz = -0.62;
  const dist = 3.4;
  const scale = 26;
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
    const ooz = 1 / (z2 + dist);
    const col = Math.round(COLS / 2 + x1 * scale * 2 * ooz * 1.0);
    const row = Math.round(ROWS / 2 + 1 - y2 * scale * ooz);
    if (col < 0 || col >= COLS || row < 0 || row >= ROWS) continue;
    const i = row * COLS + col;
    if (ooz <= zbuf[i]) continue;
    zbuf[i] = ooz;
    const lum = Math.max(0, nx1 * lx + ny2 * ly + nz2 * lz);
    const top = RAMP.length - 1;
    const k = p.inner ? 1 + Math.round(lum * 3) : p.band ? 5 + Math.round(lum * 3) : 4 + Math.round(lum * (top - 4));
    out[i] = RAMP[Math.min(top, k)];
  }
  let s = "";
  for (let r = 0; r < ROWS; r++) s += out.slice(r * COLS, (r + 1) * COLS).join("") + "\n";
  return s;
}

/** The home page centrepiece: a crown spinning in ASCII. Holds still for reduced motion and off screen. */
export function AsciiCrown({ className }: { className?: string }) {
  const ref = useRef<HTMLPreElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const pts = buildCrown();
    const still = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    let angle = 0.3; // a front-on view with a spike in the middle, also the still frame
    el.textContent = render(pts, angle);
    if (still) return;
    let raf = 0;
    let last = 0;
    let visible = true;
    const io = new IntersectionObserver(([e]) => (visible = e.isIntersecting));
    io.observe(el);
    const tick = (t: number) => {
      raf = requestAnimationFrame(tick);
      if (!visible || document.hidden || t - last < 40) return; // about 25 frames a second
      angle += ((t - (last || t)) / 1000) * 0.9;
      last = t;
      el.textContent = render(pts, angle);
    };
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      io.disconnect();
    };
  }, []);
  return <pre ref={ref} className={`ascii-crown ${className ?? ""}`} aria-label="A crown, turning, drawn in text characters" role="img" />;
}
