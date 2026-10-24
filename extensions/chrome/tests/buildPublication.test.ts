// @vitest-environment node
import { describe, expect, it } from "vitest";
import { mkdtempSync, cpSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

describe("complete development build publication", () => {
  it("publishes a stable build identity and preserves the old complete output on failure", () => {
    const fixture = mkdtempSync(join(tmpdir(), "gesturekit-build-test-"));
    try {
      cpSync("src", join(fixture, "src"), { recursive: true });
      for (const file of ["manifest.json", "popup.html", "smoke.html"]) cpSync(file, join(fixture, file));
      const build = () => spawnSync(process.execPath, [resolve("scripts/build.mjs")], { cwd: fixture, encoding: "utf8" });
      expect(build().status).toBe(0);
      const markerPath = join(fixture, "dist/build.json");
      const first = JSON.parse(readFileSync(markerPath, "utf8"));
      expect(first).toMatchObject({ schemaVersion: 1, buildId: expect.stringMatching(/^[a-f0-9]{64}$/) });
      const bundle = readFileSync(join(fixture, "dist/background/background.js"), "utf8");
      expect(bundle).toContain(first.buildId);
      expect(build().status).toBe(0);
      expect(JSON.parse(readFileSync(markerPath, "utf8")).buildId).toBe(first.buildId);
      writeFileSync(join(fixture, "src/popup/popup.ts"), "invalid javascript {{{");
      expect(build().status).not.toBe(0);
      expect(JSON.parse(readFileSync(markerPath, "utf8")).buildId).toBe(first.buildId);
      expect(readFileSync(join(fixture, "dist/background/background.js"), "utf8")).toBe(bundle);
      writeFileSync(join(fixture, "src/popup/popup.ts"), 'console.log("new build");');
      expect(build().status).toBe(0);
      expect(JSON.parse(readFileSync(markerPath, "utf8")).buildId).not.toBe(first.buildId);
    } finally { rmSync(fixture, { recursive: true, force: true }); }
  });
});
