import { build } from "esbuild";
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: {
    "outdir": { type: "string" }
  },
  strict: false
});

const outdir = values.outdir ?? "dist";

// E2E：允许通过环境变量覆盖 native messaging host 名（独立 host 名，避开用户级真实
// com.gesturekit.host manifest）。仅当设置 GESTUREKIT_HOST_NAME 时注入 esbuild define；
// 生产构建不设置，background.ts 的 typeof 守卫回退到默认 "com.gesturekit.host"。
const hostName = process.env.GESTUREKIT_HOST_NAME;
const hostNameDefine = hostName ? { __GESTUREKIT_HOST_NAME__: JSON.stringify(hostName) } : undefined;

const builds = [
  build({
    entryPoints: ["src/background/background.ts"],
    bundle: true,
    format: "esm",
    outfile: `${outdir}/background/background.js`,
    sourcemap: false,
    ...(hostNameDefine ? { define: hostNameDefine } : {})
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

await Promise.all(builds);
