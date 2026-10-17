import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  // the app imports ../deployments/*.json from the repo root
  server: { fs: { allow: [".."] } },
});
