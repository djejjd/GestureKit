export type LinkResolveResult =
  | { status: "success"; url: string; clickAlreadyFired?: boolean; clickProtected?: boolean }
  | { status: "no_target"; detail?: string; reason?: "pointer_target_mismatch" }
  | { status: "non_anchor_navigation"; detail?: string }
  | { status: "unsupported_url_scheme"; detail?: string }
  | { status: "page_unavailable" }
  | { status: "no_recent_pointer"; detail?: string };

export function resolveLinkAtPoint(x: number, y: number): LinkResolveResult {
  const element = document.elementFromPoint(x, y);
  if (!element) {
    return { status: "no_target", detail: `elementFromPoint(${x.toFixed(0)},${y.toFixed(0)}) 返回 null` };
  }

  const anchor = element.closest("a[href]") as HTMLAnchorElement | null;
  if (!anchor) {
    const tag = element.tagName.toLowerCase();
    const id = element.id ? `#${element.id}` : "";
    const cls = element.className && typeof element.className === "string"
      ? `.${element.className.trim().split(/\s+/).slice(0, 2).join(".")}`
      : "";
    const clickable = element.closest("[data-href],[role='link'],button") as HTMLElement | null;
    if (clickable) {
      const ctag = clickable.tagName.toLowerCase();
      return {
        status: "non_anchor_navigation",
        detail: `命中 <${ctag}>，但不是标准 <a href>`
      };
    }
    return {
      status: "no_target",
      detail: `命中 <${tag}${id}${cls}> 但无上级 <a href>`
    };
  }

  let url: URL;
  try {
    url = new URL(anchor.href);
  } catch {
    return { status: "unsupported_url_scheme", detail: `href 解析失败: ${anchor.getAttribute("href")?.slice(0, 50)}` };
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return { status: "unsupported_url_scheme", detail: `协议不支持: ${url.protocol}` };
  }

  return { status: "success", url: url.toString() };
}
