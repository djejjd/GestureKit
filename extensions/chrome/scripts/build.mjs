import { build } from "esbuild";
import { parseArgs } from "node:util";
import { createHash, randomUUID } from "node:crypto";
import { existsSync, readdirSync, readFileSync, mkdirSync, writeFileSync, renameSync, rmSync } from "node:fs";
import { resolve, dirname, join } from "node:path";

const { values } = parseArgs({ options: { outdir: { type: "string" } }, strict: false });
const outdir = resolve(values.outdir ?? "dist");
const staging = `${outdir}.staging-${randomUUID()}`;
const backup = `${outdir}.previous-${randomUUID()}`;
const sourceFiles = [];
function collect(path) {
  for (const entry of readdirSync(path, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const child = join(path, entry.name);
    if (entry.isDirectory()) collect(child);
    else if (entry.isFile()) sourceFiles.push(child);
  }
}
collect("src");
for (const path of ["manifest.json", "popup.html", "smoke.html", "package-lock.json"]) if (existsSync(path)) sourceFiles.push(path);
const hash = createHash("sha256");
for (const path of sourceFiles.sort()) hash.update(path).update("\0").update(readFileSync(path)).update("\0");
hash.update(readFileSync(new URL(import.meta.url)));
const hostName = process.env.GESTUREKIT_HOST_NAME;
hash.update(hostName ?? "com.gesturekit.host");
const buildId = hash.digest("hex");
const define = {
  __GESTUREKIT_BUILD_ID__: JSON.stringify(buildId),
  ...(hostName ? { __GESTUREKIT_HOST_NAME__: JSON.stringify(hostName) } : {})
};
let movedPrevious = false;
try {
  mkdirSync(dirname(outdir), { recursive: true });
  // allSettled ensures failed compilers stop writing before temporary output cleanup.
  const results = await Promise.allSettled([
    ["background/background", "esm"], ["content/pointerTracker", "iife"],
    ["popup/popup", "esm"], ["smoke/smoke", "esm"]
  ].map(([entry, format]) => build({
    entryPoints: [`src/${entry}.ts`], bundle: true, format,
    outfile: `${staging}/${entry}.js`, sourcemap: false, define
  })));
  const failure = results.find(result => result.status === "rejected");
  if (failure) throw failure.reason;
  writeFileSync(join(staging, "build.json"), JSON.stringify({ schemaVersion: 1, buildId }) + "\n");
  if (existsSync(outdir)) { renameSync(outdir, backup); movedPrevious = true; }
  try { renameSync(staging, outdir); }
  catch (error) { if (movedPrevious) renameSync(backup, outdir); movedPrevious = false; throw error; }
  if (movedPrevious) rmSync(backup, { recursive: true, force: true });
  console.log(`extension_build_ready buildId=${buildId}`);
} finally {
  rmSync(staging, { recursive: true, force: true });
}
