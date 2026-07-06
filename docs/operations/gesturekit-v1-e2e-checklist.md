# GestureKit V1 端到端验收清单

## 环境

- macOS: 记录实际版本。
- Chrome Stable: 记录实际版本。
- 输入设备: 内置触控板或 Magic Trackpad。
- 显示器: 记录内置屏或外接屏组合。

## 必测功能

- [ ] Chrome 普通网页中，鼠标停在普通 `<a href>` 链接上，三指点按后在当前 tab 右侧后台打开新 tab。
- [ ] 新 tab `active=false`，当前 tab 不失焦。
- [ ] 鼠标停在非链接区域，三指点按返回 `no_target`，不打开页面。
- [ ] `javascript:`、`file:` 或 `mailto:` 链接返回 `unsupported_url_scheme`。
- [ ] 多 tab 中间位置三指左滑，切到左侧相邻 tab。
- [ ] 多 tab 中间位置三指右滑，切到右侧相邻 tab。
- [ ] 最左侧 tab 三指左滑返回 `edge_reached`，不 wrap。
- [ ] 最右侧 tab 三指右滑返回 `edge_reached`，不 wrap。
- [ ] 非 Chrome 前台三指手势返回或记录 `unsupported_app`，不执行 Chrome 动作。
- [ ] `chrome://extensions` 或不可注入页面返回 `page_unavailable`。
- [ ] 关闭 GestureKitApp 后，extension 记录 `app_unavailable` 或 `native_host_disconnected`。

## 必跑命令

```bash
swift test
swift build
swift run GestureKitHost --self-test
cd extensions/chrome
npm test
npm run build
```
