# ADR 0002：使用 Extension 记录最近网页 Pointer 位置

日期：2026-06-23

## 状态

已接受，V1 采用。

## 背景

macOS App 可获得的是屏幕坐标或 native point。Chrome content script 的 `document.elementFromPoint(x, y)` 需要的是当前网页 viewport 内的 CSS 像素坐标。

直接把 native 屏幕坐标转换为网页坐标会受到以下因素影响：

- Chrome 窗口位置和大小。
- 标签栏、地址栏、书签栏高度。
- Retina scale、CSS pixel、native point 差异。
- 多显示器、负坐标、不同显示器 scale。
- 页面缩放、全屏、Stage Manager。
- iframe、shadow DOM、PDF viewer 和 Chrome 内部页面。

## 决策

V1 不把 native 屏幕坐标转换为 DOM 坐标作为链接识别主路径。

Chrome content script 在网页内监听 `pointermove` / `mousemove`，记录最近一次 viewport 坐标。三指点按发生时，native 侧只发送手势事件，Chrome 扩展使用最近的网页 pointer 坐标执行链接命中识别。

如果最近 pointer 坐标不存在、过期或不属于当前活跃 tab，则返回明确不可用状态。

## 后果

收益：

- 避免复杂且脆弱的屏幕坐标到 DOM 坐标转换。
- 链接识别发生在网页语义层，符合 Chrome 扩展职责。
- 多显示器和 Retina 场景下风险更低。

代价：

- 鼠标必须曾经在网页区域移动过。
- 坐标可能过期，需要新鲜度阈值。
- Chrome UI 区域、不可注入页面、iframe、closed shadow DOM 仍需降级。

## V1 边界

V1 只保证普通网页、顶层 document、普通 `<a href>` 链接。复杂 iframe、closed shadow DOM 和 JS click handler 导航不作为 V1 阻塞项。
