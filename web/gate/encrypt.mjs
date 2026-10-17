// Encrypts the single-file production build behind a password with staticrypt.
//
//   SITE_PASSWORD=... node gate/encrypt.mjs     (run after `vite build`; see `npm run build:gated`)
//
// dist/index.html becomes an on-brand password page that holds the app as AES-256 ciphertext and
// decrypts it in the browser. dist/404.html is the same page, so GitHub Pages serves the gate (and
// then the app, at the right route) for deep links like /exile.
//
// The password only ever comes from the environment. Never commit it, and never pass it on a
// command line. This script refuses to run without it, so a missing secret can't ship the app
// unencrypted.
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");
const index = join(dist, "index.html");
const template = join(root, "gate", "template.html");

// Not a secret: a fixed salt keeps "remember me" working across deploys while the password stays the same.
const SALT = "584dbca1655abdfb37eaf433f2f4cdb7";
// How long "remember me" lasts on a device, in days.
const REMEMBER_DAYS = "30";
// Strings that only exist in the app bundle. If any survive encryption, something went wrong.
const PLAINTEXT_MARKERS = ["lockERC20", "previewDistribute", "treasuryStreamId"];
const CIPHER_MARKER = "staticryptEncryptedMsgUniqueVariableName";

function fail(msg) {
  console.error(`gate: ${msg}`);
  process.exit(1);
}

const password = process.env.SITE_PASSWORD ?? "";
if (password.trim() === "") fail("SITE_PASSWORD is not set or is empty. Refusing to build an unencrypted site.");
if (password.length < 12) console.warn("gate: warning, SITE_PASSWORD is shorter than 12 characters. A longer one is much harder to guess.");

if (!existsSync(index)) fail("dist/index.html is missing. Run `npm run build` first.");
const html = readFileSync(index, "utf8");
if (html.includes(CIPHER_MARKER)) fail("dist/index.html is already encrypted. Run `npm run build` again first.");
if (!PLAINTEXT_MARKERS.every((m) => html.includes(m))) fail("dist/index.html doesn't look like the app build.");

// Everything readable must be inside index.html. Only public, non-app files may sit next to it.
const PUBLIC_OK = new Set(["index.html", "CNAME", "crown.svg", "og.png", "apple-touch-icon.png"]);
const extra = readdirSync(dist, { recursive: true }).filter((f) => !PUBLIC_OK.has(String(f)));
if (extra.length) fail(`unexpected files in dist would be served unencrypted: ${extra.join(", ")}`);
if (/<script[^>]+src=|<link[^>]+rel="?(stylesheet|modulepreload)/i.test(html)) fail("dist/index.html still loads external scripts or styles. Is vite-plugin-singlefile on?");

// Point the password page's icon and preview links at the deploy's base path and URL (see vite.config.ts).
const base = (process.env.SITE_BASE ?? "").replace(/\/+$/, "") + "/";
const siteUrl = (process.env.SITE_URL || "https://monarchy.fi").replace(/\/+$/, "") + "/";
const templateDir = mkdtempSync(join(tmpdir(), "monarchy-template-"));
const templateFile = join(templateDir, "template.html");
writeFileSync(
  templateFile,
  readFileSync(template, "utf8").replaceAll("https://monarchy.fi/", siteUrl).replace(/(href|src)="\/(?!\/)/g, `$1="${base}`),
);

const require = createRequire(import.meta.url);
const cli = require.resolve("staticrypt/cli/index.js");
const out = mkdtempSync(join(tmpdir(), "monarchy-gate-"));
const res = spawnSync(
  process.execPath,
  [
    cli,
    index,
    "--directory", out,
    "--template", templateFile,
    "--config", "false",
    "--salt", SALT,
    "--remember", REMEMBER_DAYS,
    "--short",
    "--template-error", "That password isn't right. Try again.",
  ],
  // The password goes through the environment, not argv, so it never shows up in a process list.
  { cwd: root, env: { ...process.env, STATICRYPT_PASSWORD: password }, stdio: ["ignore", "inherit", "inherit"] },
);
if (res.status !== 0) fail(`staticrypt failed (exit ${res.status}).`);

const encryptedPath = join(out, "index.html");
if (!existsSync(encryptedPath)) fail("staticrypt produced no output.");
const encrypted = readFileSync(encryptedPath, "utf8");
if (!encrypted.includes(CIPHER_MARKER)) fail("output is missing the ciphertext.");
const leaked = PLAINTEXT_MARKERS.filter((m) => encrypted.includes(m));
if (leaked.length) fail(`output still contains app code (${leaked.join(", ")}).`);
if (encrypted.includes(password)) fail("output contains the password in plain text.");

renameSync(encryptedPath, index);
rmSync(out, { recursive: true, force: true });
rmSync(templateDir, { recursive: true, force: true });
// GitHub Pages has no SPA rewrites: unknown paths get 404.html, which is the same gate.
copyFileSync(index, join(dist, "404.html"));
console.log(`gate: encrypted dist/index.html and dist/404.html (${Math.round(encrypted.length / 1024)} KB).`);
