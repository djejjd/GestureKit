import { build } from "esbuild";
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: {
    "outdir": { type: "string" },
    "e2e-token": { type: "string" }
  },
  strict: false
});

const outdir = values.outdir ?? "dist";
// token 优先取 argv（兼容旧调用），其次取环境变量。runner 通过 GESTUREKIT_E2E_TOKEN
// 传递，避免 token 出现在 argv 中（execSync 失败时会打印完整命令行导致泄漏）。
const e2eToken = values["e2e-token"] ?? process.env.GESTUREKIT_E2E_TOKEN ?? null;
const isE2E = !!(outdir !== "dist" && e2eToken);

// __GESTUREKIT_E2E_TOKEN__ 仅在同时提供 --outdir 和 --e2e-token 时注入
const define = isE2E ? { __GESTUREKIT_E2E_TOKEN__: JSON.stringify(e2eToken) } : {};

const builds = [
  build({
    entryPoints: ["src/background/background.ts"],
    bundle: true,
    format: "esm",
    outfile: `${outdir}/background/background.js`,
    sourcemap: false,
    define
  }),
  build({
    entryPoints: ["src/content/pointerTracker.ts"],
    bundle: true,
    format: "iife",
    outfile: `${outdir}/content/pointerTracker.js`,
    sourcemap: false
  }),
  build({
    entryPoints: ["src/popup/popup.ts"],
    bundle: true,
    format: "esm",
    outfile: `${outdir}/popup/popup.js`,
    sourcemap: false
  }),
  build({
    entryPoints: ["src/smoke/smoke.ts"],
    bundle: true,
    format: "esm",
    outfile: `${outdir}/smoke/smoke.js`,
    sourcemap: false
  })
];

// 仅在 E2E 构建时包含受控页面桥接
if (isE2E) {
  builds.push(
    build({
      entryPoints: ["src/e2e/controlledPageBridge.ts"],
      bundle: true,
      format: "iife",
      outfile: `${outdir}/content/controlledPageBridge.js`,
      sourcemap: false,
      define
    })
  );
}

await Promise.all(builds);
