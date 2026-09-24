import { defineConfig } from "vite";

// The Shen.AI Web SDK uses SharedArrayBuffer (WASM threads), which requires the
// page to be cross-origin isolated. These headers enable that in dev/preview.
const crossOriginIsolation = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
};

export default defineConfig({
  worker: { format: "es" },
  server: { headers: crossOriginIsolation },
  preview: { headers: crossOriginIsolation },
});
