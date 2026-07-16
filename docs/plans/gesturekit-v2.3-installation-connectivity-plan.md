# GestureKit V2.3 安装与连接闭环实施计划

> **执行要求：** 按任务顺序采用测试先行；每个任务完成后运行指定验证并进行独立审核。

**目标：** 使用稳定扩展 ID、统一安装入口和分阶段 health check，使本地安装与 Chrome/App 连通性无需人工复制扩展 ID 即可完成和诊断。

**架构：** 保留既有 P3 的 host manifest 渲染器、原子安装器、smoke 页面和 `probe_request/probe_response`。新增一处公开扩展公钥与 ID 推导器，所有安装和检查入口从该推导器读取 origin。安装入口只准备环境和 manifest；health check 只报告各阶段状态，不接管 App 生命周期。

**技术栈：** zsh、Node.js、Chrome MV3、Vitest、Swift 6、Swift Package Manager。

## 全局约束

- 以 `docs/product/gesturekit-v2.3-installation-contract.md` 为范围边界。
- 不提交扩展私钥、个人扩展 ID、用户目录下的 manifest 或构建产物。
- 保持 `connectNative()`、`GestureKitHost` 和 App IPC 协议不变。
- 所有写入文件的脚本必须可 dry-run，且实际 manifest 写入保持原子替换。
- 文档与用户输出中文优先；命令、文件路径和协议字段保持原文。

## 文件职责

| 路径 | 职责 |
| --- | --- |
| `extensions/chrome/manifest.json` | 保存公开扩展公钥，作为稳定开发 ID 的唯一来源。 |
| `extensions/chrome/scripts/extension-id.mjs` | 校验公开密钥并推导 Chrome extension ID。 |
| `extensions/chrome/tests/extensionIdentity.test.ts` | 验证 ID 推导格式、稳定性和非法密钥失败。 |
| `scripts/dev/install-local.sh` | 编排 host 构建、扩展构建、manifest 安装和加载扩展提示。 |
| `scripts/dev/health-check.sh` | 输出各安装/连接阶段的可诊断状态。 |
| `scripts/dev/test-install-local.sh` | 验证安装入口 dry-run 与参数透传。 |
| `scripts/dev/test-health-check.sh` | 验证失败阶段和下一步提示。 |
| `docs/operations/gesturekit-v1-local-install.md` | 更新为 V2.3 安装步骤。 |
| `docs/operations/gesturekit-v1-troubleshooting.md` | 更新为 V2.3 health check 排障入口。 |

---

### Task 1：稳定扩展 ID

**文件：**
- 修改：`extensions/chrome/manifest.json`
- 新建：`extensions/chrome/scripts/extension-id.mjs`
- 新建：`extensions/chrome/tests/extensionIdentity.test.ts`

**接口：**
- `node extensions/chrome/scripts/extension-id.mjs [--manifest <path>]` 输出唯一一行 32 位 extension ID。
- 脚本读取 manifest 的 `key`，对 DER public key 的 SHA-256 前 16 字节按 Chrome `a-p` nibble 映射生成 ID。

- [x] **Step 1：写失败测试**
  - 在 `extensionIdentity.test.ts` 构造有效 base64 公钥，断言同一输入两次得到相同的 `/^[a-p]{32}$/` 输出；断言空值和非 base64 值抛出 `invalid extension public key`。
- [x] **Step 2：运行失败测试**
  - 运行：`cd extensions/chrome && npm test -- extensionIdentity`
  - 预期：失败，提示 ID 推导模块不存在。
- [x] **Step 3：实现推导器并写入公开公钥**
  - 使用 Node `crypto.createHash("sha256")`；将十六进制 nibble `0-f` 映射为字符 `a-p`。
  - 在 `manifest.json` 加入公开 `key`，不得加入私钥文件或个人 ID。
  - CLI 仅输出 ID，错误写入 stderr 并以非零状态退出。
- [x] **Step 4：运行测试与真实 manifest 校验**
  - 运行：`cd extensions/chrome && npm test -- extensionIdentity && node scripts/extension-id.mjs`
  - 预期：测试通过，CLI 输出一个 32 位 `a-p` ID。
- [x] **Step 5：提交**
  - `git commit -m "feat(extension): derive stable development extension id"`

### Task 2：统一本地安装入口

**文件：**
- 新建：`scripts/dev/install-local.sh`
- 新建：`scripts/dev/test-install-local.sh`
- 修改：`scripts/dev/install-native-host.sh`
- 修改：`scripts/dev/smoke-check.sh`

**接口：**
- `./scripts/dev/install-local.sh [--host-path <absolute-path>] [--dry-run]` 不接受 `--extension-id`。
- `install-native-host.sh` 与 `smoke-check.sh` 由 extension ID CLI 取得 ID；保留仅供回归测试的显式 ID 覆盖入口，不在用户帮助中展示。

- [ ] **Step 1：写失败 shell 测试**
  - 断言 `install-local.sh --dry-run` 输出 Swift build、扩展 build、推导出的 extension ID、manifest 目标和 `chrome://extensions` 加载路径。
  - 断言输出中不存在 `--extension-id <...>` 或人工复制 ID 提示。
- [ ] **Step 2：运行失败测试**
  - 运行：`zsh scripts/dev/test-install-local.sh`
  - 预期：失败，提示安装入口不存在。
- [ ] **Step 3：实现安装编排**
  - 复用 `smoke-check.sh` 的 `DEVELOPER_DIR` 选择规则和 `print_argv` 格式。
  - 顺序固定为 Swift build、扩展 build、manifest 安装；任一步失败立即退出并写明阶段。
  - 实际执行后输出稳定 ID、manifest 路径、扩展目录和用户仍需手工执行的 Chrome 加载步骤。
- [ ] **Step 4：接入既有脚本并通过测试**
  - 运行：`zsh scripts/dev/test-render-native-host-manifest.sh && zsh scripts/dev/test-install-native-host.sh && zsh scripts/dev/test-smoke-check.sh && zsh scripts/dev/test-install-local.sh`
  - 预期：四项 shell 测试通过。
- [ ] **Step 5：提交**
  - `git commit -m "feat(install): add extension-id-free local installer"`

### Task 3：分阶段健康检查

**文件：**
- 新建：`scripts/dev/health-check.sh`
- 新建：`scripts/dev/test-health-check.sh`
- 修改：`extensions/chrome/src/smoke/smoke.ts`
- 修改：`extensions/chrome/src/background/connectionProbe.ts`
- 修改：`extensions/chrome/tests/connectionProbe.test.ts`

**接口：**
- `./scripts/dev/health-check.sh [--real] [--host-path <absolute-path>]` 默认只检查本机可读状态；`--real` 执行 host 自检和扩展 smoke URL。
- 输出每个阶段的 `PASS`、`WAITING` 或 `FAIL`，并附一个下一步命令或用户操作。

- [ ] **Step 1：写失败测试**
  - 覆盖：缺少 host、manifest origin 不匹配、App 未运行、probe 成功四种结果。
  - 断言每种状态有稳定阶段名和中文下一步，不输出 manifest 全路径或凭据内容。
- [ ] **Step 2：运行失败测试**
  - 运行：`zsh scripts/dev/test-health-check.sh && cd extensions/chrome && npm test -- connectionProbe`
  - 预期：失败，提示 health check 不存在或没有状态映射。
- [ ] **Step 3：实现检查与 smoke 状态映射**
  - 检查 Xcode/Node、host 文件、manifest JSON 和 stable origin；不自动启动 App。
  - 对已打开 smoke 页面复用现有 `probe_request/probe_response`，区分 host 不可用与 App 不可用。
  - `--real` 失败必须返回非零；`WAITING` 仅在 App 未启动的预期场景返回可继续状态。
- [ ] **Step 4：运行针对性测试**
  - 运行：`zsh scripts/dev/test-health-check.sh && cd extensions/chrome && npm test -- connectionProbe && npm run build`
  - 预期：全部通过。
- [ ] **Step 5：提交**
  - `git commit -m "feat(diagnostics): add staged installation health check"`

### Task 4：文档、端到端验收与发布准备

**文件：**
- 修改：`docs/operations/gesturekit-v1-local-install.md`
- 修改：`docs/operations/gesturekit-v1-troubleshooting.md`
- 修改：`docs/operations/gesturekit-v1-e2e-checklist.md`
- 修改：`README.md`
- 修改：`docs/product/gesturekit-v2.3-installation-contract.md`

- [ ] **Step 1：更新首次安装与更新流程**
  - 只保留 `install-local.sh`、`health-check.sh` 和 Chrome 手工加载扩展的步骤。
  - 明确切换分支后无需复制 ID，但应重新执行安装入口以更新 host 路径和 manifest。
- [ ] **Step 2：更新排障表**
  - 按 health check 阶段列出失败原因、下一步命令和预期结果。
  - 移除“记录扩展 ID”“手工传入 `--extension-id`”要求。
- [ ] **Step 3：执行全量验证**
  - 运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
  - 运行：`cd extensions/chrome && npm test && npm run build`
  - 运行：全部 `scripts/dev/test-*.sh`。
- [ ] **Step 4：执行手动验收**
  - 从干净构建产物运行 `install-local.sh`，在 Chrome 手动 Load unpacked 后运行 `health-check.sh --real`。
  - 分别记录 App 未启动的 `WAITING` 与 App 启动后的 `PASS`。
- [ ] **Step 5：提交**
  - `git commit -m "docs(install): document v2.3 deployment workflow"`

## 覆盖检查

- 稳定 extension ID：Task 1。
- 无需手工输入 ID 的安装：Task 2。
- 构建、manifest、host 和 App 连接的分阶段诊断：Task 3。
- 首次安装、更新和真实 Chrome 验收：Task 4。
