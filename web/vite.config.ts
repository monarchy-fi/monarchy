import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig(({ command }) => ({
  // The production build is one self-contained index.html (all JS and CSS inlined), so the deploy
  // can encrypt the whole app behind a password. See gate/encrypt.mjs.
  plugins: [react(), command === "build" && viteSingleFile()],
  build: { chunkSizeWarningLimit: 4096 },
  // the app imports ../deployments/*.json from the repo root
  server: { fs: { allow: [".."] } },
}));
