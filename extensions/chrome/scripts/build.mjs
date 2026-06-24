import { build } from "esbuild";

await Promise.all([
  build({
    entryPoints: ["src/background/nativePort.ts"],
    bundle: true,
    format: "esm",
    outfile: "dist/background/nativePort.js",
    sourcemap: false
  }),
  build({
    entryPoints: ["src/content/pointerTracker.ts"],
    bundle: true,
    format: "iife",
    outfile: "dist/content/pointerTracker.js",
    sourcemap: false
  })
]);
