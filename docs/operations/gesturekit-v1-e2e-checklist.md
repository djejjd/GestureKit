# GestureKit V1 端到端验收清单

## 环境

- macOS: 记录实际版本。
- Chrome Stable: 记录实际版本。
- 输入设备: 内置触控板或 Magic Trackpad。
- 显示器: 记录内置屏或外接屏组合。

## 必测功能

- [ ] Chrome 普通网页中，鼠标停在普通 `<a href>` 链接上，三指点按后在当前 tab 右侧打开新 tab。
- [ ] 新 tab `active=true`，Chrome 自动切换到新 tab。
- [ ] 当前 tab 不跳转到被三指点按的链接。
- [ ] 鼠标停在非链接区域，触控板左半区三指点按切到左侧 tab。
- [ ] 鼠标停在非链接区域，触控板右半区三指点按切到右侧 tab。
- [ ] 鼠标停在非链接区域，300ms 内连续两次三指点按关闭当前 tab，且第一下不先切 tab。
- [ ] `javascript:`、`file:` 或 `mailto:` 链接返回 `unsupported_url_scheme`。
- [ ] 多 tab 中间位置三指快速左轻扫，切到左侧相邻 tab。
- [ ] 多 tab 中间位置三指快速右轻扫，切到右侧相邻 tab。
- [ ] 最左侧 tab 三指快速左轻扫循环切到当前窗口最后一个 tab。
- [ ] 最右侧 tab 三指快速右轻扫循环切到当前窗口第一个 tab。
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

## 诊断日志

- 终端运行 `swift run GestureKitApp` 时默认只打印启动/停止摘要、警告和错误；成功手势不会逐条刷屏。
- 本地日志保存在 `~/Library/Logs/GestureKit/GestureKitApp.log`。
- 日志采用小体积轮转：单文件约 1 MB，最多保留 3 个文件。
- 默认不记录每一帧触控板输入；本地文件记录手势完成后的结果、IPC 发布、连接数、错误和影响执行的警告。
- 需要分析“滑一次没反应”等识别问题时，用详细模式启动：

```bash
GESTUREKIT_DEBUG=1 swift run GestureKitApp
```

常用排查命令：

```bash
tail -n 200 ~/Library/Logs/GestureKit/GestureKitApp.log
grep -E "warn|error|gesture_unstable|connections=0|gesture_published" ~/Library/Logs/GestureKit/GestureKitApp.log
```
