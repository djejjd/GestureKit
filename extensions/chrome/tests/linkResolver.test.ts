import { describe, expect, it } from "vitest";
import { resolveLinkAtPoint } from "../src/content/linkResolver";

describe("resolveLinkAtPoint", () => {
  it("returns absolute http link for anchor at point", () => {
    document.body.innerHTML = `<a id="target" href="/docs">Docs</a>`;
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    document.elementFromPoint = () => anchor;

    const result = resolveLinkAtPoint(10, 20);

    expect(result).toEqual({
      status: "success",
      url: "http://localhost:3000/docs"
    });
  });

  it("returns no_target when point is not inside a link", () => {
    document.body.innerHTML = `<button id="target">Open</button>`;
    const button = document.getElementById("target") as HTMLButtonElement;
    document.elementFromPoint = () => button;

    const result = resolveLinkAtPoint(10, 20);

    expect(result).toEqual({ status: "no_target" });
  });

  it("rejects javascript links", () => {
    document.body.innerHTML = `<a id="target" href="javascript:alert(1)">Bad</a>`;
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    document.elementFromPoint = () => anchor;

    const result = resolveLinkAtPoint(10, 20);

    expect(result).toEqual({ status: "unsupported_url_scheme" });
  });

  it("returns link for child element inside anchor", () => {
    document.body.innerHTML = `<a id="target" href="/image"><img id="child" alt="preview"></a>`;
    const child = document.getElementById("child") as HTMLImageElement;
    document.elementFromPoint = () => child;

    expect(resolveLinkAtPoint(1, 1)).toEqual({
      status: "success",
      url: "http://localhost:3000/image"
    });
  });

  it("rejects file links", () => {
    document.body.innerHTML = `<a id="target" href="file:///tmp/a.txt">File</a>`;
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    document.elementFromPoint = () => anchor;

    expect(resolveLinkAtPoint(1, 1)).toEqual({ status: "unsupported_url_scheme" });
  });
});
