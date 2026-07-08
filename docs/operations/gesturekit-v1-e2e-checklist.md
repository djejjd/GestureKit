# GestureKit V1 端到端验收清单

## 环境

- macOS: 记录实际版本。
- Chrome Stable: 记录实际版本。
- 输入设备: 内置触控板或 Magic Trackpad。
- 显示器: 记录内置屏或外接屏组合。

## 阶段一：预检查

- [ ] 已按 `docs/operations/gesturekit-v1-local-install.md` 加载 unpacked extension，并记录实际扩展 ID。
- [ ] 已运行 `./scripts/dev/smoke-check.sh --extension-id <extension-id>`，确认脚本实际使用的 Swift 入口、host 自检、manifest 安装和 `smoke.html` 打开链路都成功。
- [ ] 如需复查链路但不实际执行，可运行 `./scripts/dev/smoke-check.sh --extension-id <extension-id> --dry-run`。
- [ ] 如果此时 `smoke.html` 显示 `app_unavailable`，已按“预检查阶段 App 未启动”的预期处理，而不是误判为脚本失败。

## 阶段二：连通性探针

- [ ] 已单独启动 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitApp`。
- [ ] 重新打开或刷新 `chrome-extension://<extension-id>/smoke.html` 后，不再出现 `app_unavailable`。
- [ ] App 常驻正常后，再进行以下人工手势验收。

## 必测功能

- [ ] Chrome 普通网页中，鼠标停在普通 `<a href>` 链接上，三指点按后在当前 tab 右侧打开新 tab。
- [ ] 新 tab `active=true`，Chrome 自动切换到新 tab。
- [ ] 当前 tab 不跳转到被三指点按的链接。
- [ ] “防止链接原地跳转”默认关闭。
- [ ] 开启“防止链接原地跳转”后，普通 `http/https` 链接三指点按不触发当前 tab 原地跳转。
- [ ] 关闭“防止链接原地跳转”后，链接点击保护逻辑不再拦截普通链接点击。
- [ ] 如果当前 tab 已经先被页面原生点击跳转，popup 诊断记录“点击已先触发”，且 GestureKit 不再重复打开第二个新 tab。
- [ ] 鼠标停在非链接区域，触控板左侧边缘三指点按切到左侧 tab。
- [ ] 鼠标停在非链接区域，触控板右侧边缘三指点按切到右侧 tab。
- [ ] 鼠标停在非链接区域，触控板中间区域三指单点不切 tab、不关闭 tab。
- [ ] 鼠标停在非链接区域，合法间隔内连续两次三指点按触控板中间区域关闭当前 tab，且第一下不先切 tab。
- [ ] 关闭 GestureKit 三指点按链接打开的新 tab 后，Chrome 回到打开它的来源 tab。
- [ ] 关闭普通中间 tab 后，Chrome 优先切到左侧 tab。
- [ ] 关闭最左侧 tab 后，如果没有来源 tab，Chrome 切到右侧 tab。
- [ ] 快速连续轻碰或明显过短的三指点按不会切 tab 或关闭 tab。
- [ ] `javascript:`、`file:` 或 `mailto:` 链接返回 `unsupported_url_scheme`。
- [ ] 多 tab 中间位置三指快速左轻扫，切到右侧相邻 tab。
- [ ] 多 tab 中间位置三指快速右轻扫，切到左侧相邻 tab。
- [ ] 最右侧 tab 三指快速左轻扫循环切到当前窗口第一个 tab。
- [ ] 最左侧 tab 三指快速右轻扫循环切到当前窗口最后一个 tab。
- [ ] 非 Chrome 前台三指手势返回或记录 `unsupported_app`，不执行 Chrome 动作。
- [ ] `chrome://extensions` 或不可注入页面返回 `page_unavailable`。
- [ ] 关闭 GestureKitApp 后，extension 记录 `app_unavailable` 或 `native_host_disconnected`。

## 扩展设置

- [ ] 点击 Chrome 工具栏 GestureKit 图标，popup 能显示安全模式、高效模式、四类开关、轻扫灵敏度、三个手感参数、连接状态和灵敏度同步状态。
- [ ] 切换到高效模式后，边缘区域宽度显示为 `38%`，后续边缘点按按高效阈值执行。
- [ ] 切换轻扫灵敏度后，popup 的“灵敏度同步”显示最近一次已应用的档位。
- [ ] 关闭“边缘点按切换标签页”后，空白处左/右边缘三指点按不切 tab。
- [ ] 关闭“中间双击关闭标签页”后，中间区域三指双击不关闭 tab。
- [ ] 关闭“快速轻扫切换标签页”后，三指快速左右轻扫不切 tab。
- [ ] 关闭“防止链接原地跳转”后，popup 中该开关保持关闭并写入复制诊断。
- [ ] 点击“恢复安全模式默认值”后，模式回到安全模式，边缘区域宽度显示为 `30%`。
- [ ] popup 显示“轻扫表现”：最近轻扫成功率、主要失败原因、建议、推荐档位和推荐最小距离。
- [ ] 点击“展开”后能看到最近诊断，轻扫失败项包含原因、dx、dy、duration 和灵敏度。
- [ ] 点击“复制诊断”后，剪贴板中包含 `GestureKit Diagnostics`、当前模式、当前灵敏度和推荐结果，且不包含 URL 或网页内容。
- [ ] 点击”清空诊断”后，诊断摘要回到暂无状态。

## 推荐应用闭环（P4）

- [ ] 打开 popup，确认出现”应用推荐设置”按钮（需有足够轻扫诊断数据）。
- [ ] 点击”应用推荐设置”后出现确认对话框；确认后”推荐保存状态”更新为”已保存”或”等待确认”。
- [ ] App 在线时，等待状态变为”已应用”（需 App 返回 settings_ack）。
- [ ] 关闭 App 后再次打开 popup 并刷新，确认状态不会继续误报”已应用”，而是显示”已失效”或相关失败状态。
- [ ] 推荐保存状态和 App 运行时状态在 popup 中明确分开展示，不与连接状态混淆。
- [ ] 复制诊断包含当前识别设置、推荐识别设置和 applyPhase 字段。
- [ ] “应用推荐设置”按钮仅在诊断存在有效推荐时显示；无推荐时隐藏整个推荐区域。

## 必跑命令

```bash
zsh scripts/dev/test-render-native-host-manifest.sh
zsh scripts/dev/test-install-native-host.sh
zsh scripts/dev/test-smoke-check.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test
cd extensions/chrome
npm test
npm run build
git diff --check
```

## 诊断日志

- 终端运行 `swift run GestureKitApp` 时默认只打印启动/停止摘要、警告和错误；成功手势不会逐条刷屏。
- 本地日志保存在 `~/Library/Logs/GestureKit/GestureKitApp.log`。
- 日志采用小体积轮转：单文件约 1 MB，最多保留 3 个文件。
- 默认不记录每一帧触控板输入；本地文件记录手势完成后的结果、IPC 发布、连接数、错误和影响执行的警告。
- Chrome popup 诊断数据只保存在 `chrome.storage.local`，最多保留最近 100 条摘要，不记录原始触控板帧、网页内容、URL 或浏览历史。
- 需要分析“滑一次没反应”等识别问题时，用详细模式启动：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer GESTUREKIT_DEBUG=1 swift run GestureKitApp
```

常用排查命令：

```bash
tail -n 200 ~/Library/Logs/GestureKit/GestureKitApp.log
grep -E "warn|error|gesture_unstable|connections=0|gesture_published" ~/Library/Logs/GestureKit/GestureKitApp.log
```

如果 smoke 页面或 native host 链路异常，先看 `docs/operations/gesturekit-v1-troubleshooting.md`。
