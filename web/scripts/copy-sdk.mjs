// Copies the Shen.AI Web SDK (JS + WASM + worker files) into public/ so Vite
// serves it verbatim. The SDK loads its .wasm next to the module, so it must
// not be bundled/renamed.
import { cpSync, rmSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const src = resolve(root, "node_modules/@shenai/sdk");
const dest = resolve(root, "public/shenai-sdk");

if (!existsSync(src)) {
  console.error("@shenai/sdk is not installed. Run `npm install` first.");
  process.exit(1);
}
rmSync(dest, { recursive: true, force: true });
cpSync(src, dest, { recursive: true });
console.log("Copied Shen.AI SDK to public/shenai-sdk");
