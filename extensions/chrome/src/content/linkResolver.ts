export type LinkResolveResult =
  | { status: "success"; url: string; clickAlreadyFired?: boolean; clickProtected?: boolean }
  | { status: "no_target" }
  | { status: "unsupported_url_scheme" }
  | { status: "page_unavailable" };

export function resolveLinkAtPoint(x: number, y: number): LinkResolveResult {
  const element = document.elementFromPoint(x, y);
  if (!element) {
    return { status: "no_target" };
  }

  const anchor = element.closest("a[href]") as HTMLAnchorElement | null;
  if (!anchor) {
    return { status: "no_target" };
  }

  let url: URL;
  try {
    url = new URL(anchor.href);
  } catch {
    return { status: "unsupported_url_scheme" };
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return { status: "unsupported_url_scheme" };
  }

  return { status: "success", url: url.toString() };
}
