import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { viteSingleFile } from "vite-plugin-singlefile";

// Set by the Pages workflow from actions/configure-pages: "" on a custom domain, "/monarchy" on github.io.
const base = (process.env.SITE_BASE ?? "").replace(/\/+$/, "") + "/";
// Absolute URL for link previews (og:url, og:image).
const siteUrl = (process.env.SITE_URL || "https://monarchy.fi").replace(/\/+$/, "") + "/";

export default defineConfig(({ command }) => ({
  base,
  // vite-plugin-singlefile forces a relative base, so the router gets the real one separately.
  define: { "import.meta.env.VITE_ROUTER_BASE": JSON.stringify(base) },
  // The production build is one self-contained index.html (all JS and CSS inlined), so the deploy
  // can encrypt the whole app behind a password. See gate/encrypt.mjs.
  plugins: [
    react(),
    command === "build" && viteSingleFile(),
    { name: "site-url", transformIndexHtml: (html: string) => html.replaceAll("https://monarchy.fi/", siteUrl) },
  ],
  build: { chunkSizeWarningLimit: 4096 },
  // the app imports ../deployments/*.json from the repo root
  server: { fs: { allow: [".."] } },
}));
