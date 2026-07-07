import { build } from "esbuild";

await Promise.all([
  build({
    entryPoints: ["src/background/background.ts"],
    bundle: true,
    format: "esm",
    outfile: "dist/background/background.js",
    sourcemap: false
  }),
  build({
    entryPoints: ["src/content/pointerTracker.ts"],
    bundle: true,
    format: "iife",
    outfile: "dist/content/pointerTracker.js",
    sourcemap: false
  }),
  build({
    entryPoints: ["src/popup/popup.ts"],
    bundle: true,
    format: "esm",
    outfile: "dist/popup/popup.js",
    sourcemap: false
  })
]);
