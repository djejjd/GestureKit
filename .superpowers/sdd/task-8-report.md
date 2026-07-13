# Task 8 交接报告

## 已交付

- 新增 `ChromeProvider`：活动 tab 的 context snapshot、短期 session-bound opaque `targetRef`、页面身份脱敏、tab/frame/过期校验，以及 `reconcile` 状态查询；URL 和 DOM 标识不会越过 Provider 边界。
- 链接动作在 guard 非 `guard_armed`、target 缺失/失效、tab 或 frame 改变时 fail-closed，且不会调用 `chrome.tabs.create`。
- `V2Dispatcher` 在 ledger acceptance 前验证链接 guard 与 target；失败时只发结构化 `action_result`。
- `interactionGuard` 支持按 session 与 lease 的 release，content script 接收 `gesturekit.guardArm` / `gesturekit.guardRelease`。
- 标准动作 adapter 覆盖相邻标签、关闭标签、后退、前进、刷新；`ChromeApi` 补齐 `goBack`、`goForward`、`reload` 可测试接口。

## 测试证据

- RED：`npm test -- --run tests/chromeProvider.test.ts tests/interactionGuard.test.ts` 在实现前失败，原因分别为缺少 `ChromeProvider` 与 `guard.release`。
- GREEN：`npm test -- --run` 通过，22 个文件、146 项测试。
- `npm run build` exit 0。
- `git diff --check` 无输出。

## 注意事项

- `npx tsc --noEmit` 仍有仓库既存的严格类型错误（背景消息、V1 测试 mock、smoke 等）；Task 8 的显式验收命令 `npm test -- --run` 与 `npm run build` 均通过。
