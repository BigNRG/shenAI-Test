# Shen.AI SDK – Web test app

This is a plain TypeScript + Vite app. The Web SDK (`@shenai/sdk`) runs as WebAssembly and draws into `<canvas id="mxcanvas">`.

## Run

```bash
npm install
npm run dev          # http://localhost:5173
```

Paste your **Web** API key on the home screen. It's saved in `localStorage`. You can also set it at build time:

```bash
cp .env.example .env.local   # then set VITE_SHENAI_API_KEY=...
```

Production build: `npm run build`, then `npm run preview` (http://localhost:4173).

## Important notes

- **Cross-origin isolation is required.** The SDK uses `SharedArrayBuffer`, so the page must be served with
  `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`.
  `vite.config.ts` sets these for `dev` and `preview`. If you host `dist/` somewhere else, configure the same headers there.
  If they are missing, the home screen shows a warning.
- **The camera needs a secure context.** `http://localhost` works. To test from a phone, serve over HTTPS, for example with an HTTPS tunnel, or with `vite --host` plus a certificate.
- `scripts/copy-sdk.mjs` copies the SDK's `.wasm` and worker files into `public/shenai-sdk/`, where `locateFile` loads them from. This runs automatically before `dev` and `build`.
- For debugging, the SDK instance is exposed as `window.shenai`. The in-page **Event log** shows SDK events.

## Files

- `src/main.ts`: all the logic (SDK loading, settings per mode, polling for the custom UI, results)
- `index.html`, `src/style.css`: UI
