# GestureKit 端到端验收清单

## 环境

- macOS: 记录实际版本。
- Chrome Stable: 记录实际版本。
- 输入设备: 内置触控板或 Magic Trackpad。
- 显示器: 记录内置屏或外接屏组合。

## 阶段一：预检查

- [ ] 已按 `docs/operations/local-install.md` 运行 `./scripts/dev/install-local.sh` 并加载 unpacked extension，无需记录或复制扩展 ID。
- [ ] 已运行 `./scripts/dev/health-check.sh`，确认开发环境、构建产物、Native Messaging 均为 `PASS`。
- [ ] 已运行 `./scripts/dev/test-provider-protocol.sh`，确认输出 `provider_protocol_ok`。
- [ ] 如需复查链路但不实际执行，可运行 `./scripts/dev/smoke-check.sh --dry-run`。
- [ ] 如果此时 `smoke.html` 显示 `app_unavailable`，已按“预检查阶段 App 未启动”的预期处理，而不是误判为脚本失败。

## 阶段二：连通性探针

- [ ] 已单独启动 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitApp`。
- [ ] 运行 `./scripts/dev/smoke-check.sh` 并确认 smoke 页面显示 `status: "connected"`，不再出现 `app_unavailable`。
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

## 菜单栏状态与生命周期（P5）

- [ ] 打开菜单栏，确认存在”监听：运行中/已停止”、”连接：未连接/已连接(N)”、”最近手势”、”最近错误”信息项。
- [ ] 点击”刷新状态”，确认菜单中的连接文案刷新。
- [ ] 点击”打开日志目录”，确认能打开 `~/Library/Logs/GestureKit/`。
- [ ] 点击”打开安装说明”，确认能打开仓库 `docs/operations/local-install.md`（需设置 `GESTUREKIT_REPO_ROOT` 环境变量或从仓库目录启动）。
- [ ] 点击”打开排障文档”，确认能打开仓库 `docs/operations/troubleshooting.md`。
- [ ] 在非 Chrome 前台执行三指手势，确认菜单栏”最近错误”显示 `unsupported_app`。
- [ ] 点击”停止监听”，确认菜单栏显示”监听：已停止”，菜单栏标题不变。
- [ ] 点击”启动监听”，确认菜单栏恢复”监听：运行中”。
- [ ] 点击”退出”，确认 App 正常终止。

## 必跑命令

```bash
zsh scripts/dev/test-render-native-host-manifest.sh
zsh scripts/dev/test-install-native-host.sh
zsh scripts/dev/test-install-local.sh
zsh scripts/dev/test-smoke-check.sh
zsh scripts/dev/test-provider-protocol.sh
node --test scripts/e2e/test-link-reliability.mjs
zsh scripts/dev/test-link-reliability.sh --dry-run
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test
cd extensions/chrome
npm ci
npm test
npm run build
git diff --check
```

## 链接可靠性 E2E 控制平面（v2.4-A）

> 通用 CI（quality-gate）≠ 真实触控板验证。通用 CI 只验证自动化测试、构建产物与干跑
> （`--dry-run`）；真实 Chrome 验收是人工关口，只在 `workflow_dispatch` 显式传入
> `run_real_chrome=true` 时执行，默认 `false`。

### 本地前置条件

- macOS 15+，Xcode 安装在 `/Applications/Xcode.app`。
- Google Chrome Stable 安装在 `/Applications/Google Chrome.app`。
- Node.js 23+（预检仅检查 `node` 是否存在，建议 23+）。
- 无需准备用户 profile：runner 使用一次性临时 profile。

### 运行入口

```bash
zsh scripts/dev/test-link-reliability.sh --dry-run   # 干跑：打印命令，不启动 GUI/Chrome
zsh scripts/dev/test-link-reliability.sh             # 真实 Chrome 验收（人工关口）
```

退出码同 runner：`0` = 四个场景全部断言通过，`1` = 某场景断言失败，`2` = 环境预检失败。

### 四个场景与终态

| 场景 | E2E 命令 | 终态 terminalStatus | 说明 |
|---|---|---|---|
| success | e2e success | `succeeded` | guard + action 打开相邻新 tab；断言 source tab URL 不变 + 恰好一个相邻 tab 激活且 URL 为固定目标 `https://example.test/e2e-target` |
| leaseExpiry | e2e leaseExpiry | `lease_released` | lease 过期后普通点击不被 guard 拦截（不打开新 tab，source tab 原地导航离开 fixture） |
| providerUnavailable | e2e providerUnavailable | `provider_unavailable_guard_released` | 关闭 App 走终态路径；绕过真实手势链路（已知缺口，无真实断言） |
| resultUnknown | e2e resultUnknown | `result_unknown` | 无回执走恢复路径；仅断言下一次 success 未被拒绝 |

runner 把每个场景输出为一条脱敏 `LinkReliabilitySummary` JSON 行（stdout），字段：
`scenario`、`gestureSessionId`、`operationId`、`terminalStatus`、`failureStage`、
`durationMs`。query 中的 `token`/`secret`/`key` 等会被脱敏。

### 预检失败下一步（退出码 2）

- `preflight_failed: Chrome 未安装在 <chrome_path>` → 安装 Google Chrome，或设置 `CHROME_PATH` 指向 Chrome 可执行文件后重跑。
- `preflight_failed: Developer 目录不存在: <developer_dir>` → 安装 Xcode，或设置 `DEVELOPER_DIR` 指向正确的 Developer 目录。
- `preflight_failed: Node.js 未找到` → 安装 Node.js 23+。

### 临时 profile 清理语义

runner 会在系统临时目录创建一次性目录：`gesturekit-e2e-chrome-*`（Chrome user-data-dir）、
`gesturekit-e2e-ext-*`（extension 构建产物）、`gesturekit-e2e-fixture-*`（fixture 页面）。
正常结束时 runner 的 `cleanup()` 会删除这三个临时目录并终止 App/Chrome/fixture server 进程。
若 runner 被 SIGKILL 或崩溃，这些目录可能残留；可直接删除 `$TMPDIR/gesturekit-e2e-*` 目录，
不影响任何真实 profile（runner 从不写入用户 profile）。

### 已知真实 Chrome 验收缺口

- 缺口 I1：`providerUnavailable` 与 `resultUnknown` 两个场景走 dispatch 与终态路径，但绕过真实
  三指手势→链接链路（通过杀掉并重启 App 模拟 provider 不可用，而不是合成真实手势）。
- 缺口 I2：runner **不**断言 guard trace（guard-armed-before-click 时序）。success 只断言
  source tab URL 不变 + 恰好一个相邻 tab 打开、激活且 URL 等于固定目标
  `https://example.test/e2e-target`；leaseExpiry 只断言 lease 过期后普通点击不被 guard 拦截
  （不打开新 tab）；providerUnavailable/resultUnknown 无真实断言。这些都是完整断言列表的子集，
  不是原计划的全部六条。

**尚未验证**：真实 Chrome runner（`zsh scripts/dev/test-link-reliability.sh`）尚未在任何机器上
端到端执行过。它只在人工关口（Task 3 Step 5）于开发者本机运行时才算验证通过；通用 CI 的
`swift`/`extension`/`scripts` job 只跑自动化测试与 `--dry-run`，不运行真实 Chrome，不能作为
验证证据。

这些缺口意味着真实 Chrome runner 是**部分回归门**，不是完整替代手动触控板验收。通用 CI
（quality-gate）甚至不运行真实 Chrome；两个自动化层的边界和复用手动清单，见
`docs/operations/troubleshooting.md` 的“链接可靠性 E2E”章节。

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

如果 smoke 页面或 native host 链路异常，先看 `docs/operations/troubleshooting.md`。
