# P3 Task 4 Report

## 改动文件

- `scripts/dev/smoke-check.sh`
- `scripts/dev/test-smoke-check.sh`
- `docs/operations/gesturekit-v1-local-install.md`
- `docs/operations/gesturekit-v1-e2e-checklist.md`
- `docs/operations/gesturekit-v1-troubleshooting.md`

## 改动说明

- 新增 `smoke-check.sh` 作为开发命令入口，串起 Swift 构建、`GestureKitHost` 自检、Chrome 扩展构建、native host 安装和 `smoke.html` 打开。
- 新增 `test-smoke-check.sh`，用 dry-run 断言命令链路，覆盖默认 host 路径和最终 `open chrome-extension://<id>/smoke.html`。
- 将本地安装文档改为以 `smoke-check.sh` 为主入口，明确说明该脚本不会自动启动 `GestureKitApp`。
- 将 E2E 清单补充为先跑安装/预检查，再进行人工手势验收，并同步加入脚本测试与 `git diff --check`。
- 新增中文排障文档，覆盖 smoke 入口失败、host 自检失败、扩展构建失败、扩展未连接、`app_unavailable` 和手势识别不稳定等路径。

## 运行过的命令

```bash
zsh scripts/dev/test-smoke-check.sh
swift test
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test'
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build'
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test'
zsh scripts/dev/test-render-native-host-manifest.sh
zsh scripts/dev/test-install-native-host.sh
zsh scripts/dev/test-smoke-check.sh
cd extensions/chrome && npm test
cd extensions/chrome && npm run build
git diff --check
```

## 测试结果

- `zsh scripts/dev/test-render-native-host-manifest.sh`: pass
- `zsh scripts/dev/test-install-native-host.sh`: pass
- `zsh scripts/dev/test-smoke-check.sh`: pass
- `swift test`: 默认 `swift` 解析到 `/Library/Developer/CommandLineTools` 时失败，报错 `no such module 'XCTest'`
- `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test'`: pass, 36 tests passed
- `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build'`: pass
- `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test'`: pass
- `cd extensions/chrome && npm test`: pass, 9 files / 70 tests passed
- `cd extensions/chrome && npm run build`: pass
- `git diff --check`: pass

## commit sha

- `9c2ff24` (`docs: close p3 installation workflow`)

## concern

- 当前环境默认 `swift` 指向 Command Line Tools；按 brief 的 `swift test` 会失败，需显式切到 Xcode Developer dir 才能通过。已按仓库当前实际情况验证并作为正式结果记录。
- `npm test` / `npm run build` 输出了 `pyenv: cannot rehash: /Users/lanser/.pyenv/shims isn't writable`，但命令本身均成功，不构成本任务阻塞。

## follow-up fix

- 修复原因：`smoke-check.sh` 之前直接调用默认 `swift build` / `swift run`，与当前仓库真实可用的 Swift 入口不一致，导致脚本主入口和文档主入口都可能在默认 Command Line Tools 环境下失败。
- 修复内容：
  - `scripts/dev/smoke-check.sh` 现在在未显式设置时默认优先使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，但仍允许外部覆盖 `DEVELOPER_DIR`。
  - `scripts/dev/test-smoke-check.sh` 的 dry-run 断言已改为验证带 `DEVELOPER_DIR` 的真实命令链路。
  - 安装文档、E2E 清单和排障文档里的手工 Swift 命令已同步到与脚本一致的入口策略。
- follow-up 复跑命令：

```bash
zsh scripts/dev/test-render-native-host-manifest.sh
zsh scripts/dev/test-install-native-host.sh
zsh scripts/dev/test-smoke-check.sh
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test'
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build'
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test'
cd extensions/chrome && npm test
cd extensions/chrome && npm run build
git diff --check
```

- follow-up 复跑结果：
  - `zsh scripts/dev/test-render-native-host-manifest.sh`: pass
  - `zsh scripts/dev/test-install-native-host.sh`: pass
  - `zsh scripts/dev/test-smoke-check.sh`: pass
  - `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test'`: pass, 36 tests passed
  - `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build'`: pass
  - `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test'`: pass
  - `cd extensions/chrome && npm test`: pass, 9 files / 70 tests passed
  - `cd extensions/chrome && npm run build`: pass
  - `git diff --check`: pass

## reviewer follow-up fix 2

- 修复原因：
  - `smoke-check.sh` 的 Swift 命令仍依赖调用者当前目录，没有把 SwiftPM 上下文钉死到 repo root。
  - 文档把 `smoke-check.sh` 和 App 启动写成一个线性主流程，但脚本本身不会启动 `GestureKitApp`，导致首次打开 `smoke.html` 时 `app_unavailable` 的语义不清。
  - `test-smoke-check.sh` 只覆盖固定 `DEVELOPER_DIR` 的 happy path，缺少显式 `DEVELOPER_DIR` 和 `--host-path` 覆盖分支。
  - dry-run 输出未按 shell-safe 形式展示真实 argv，遇到带空格路径时不利于排障。
- 修复内容：
  - `scripts/dev/smoke-check.sh` 现在统一用 `swift --package-path "$repo_root"` 执行 `build` 和 `run GestureKitHost --self-test`，不再依赖调用目录。
  - dry-run 输出改为 shell-safe argv；`DEVELOPER_DIR`、`--package-path`、`install-native-host.sh` 绝对路径和带空格 `--host-path` 都会按可复制形式展示。
  - `scripts/dev/test-smoke-check.sh` 现在覆盖三条 dry-run 分支：默认 `DEVELOPER_DIR`、显式注入 `DEVELOPER_DIR`、显式 `--host-path` 覆盖，并把默认 host 路径断言收紧为完整命令。
  - 安装文档、E2E 清单和排障文档统一拆成“阶段一：预检查”和“阶段二：连通性探针”，明确 `app_unavailable` 在 App 未启动时是预期状态，不等同于脚本失败。
- 本轮复跑命令：

```bash
zsh scripts/dev/test-render-native-host-manifest.sh
zsh scripts/dev/test-install-native-host.sh
zsh scripts/dev/test-smoke-check.sh
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test'
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build'
/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test'
cd extensions/chrome && npm test
cd extensions/chrome && npm run build
git diff --check
```

- 本轮复跑结果：
  - `zsh scripts/dev/test-render-native-host-manifest.sh`: pass
  - `zsh scripts/dev/test-install-native-host.sh`: pass
  - `zsh scripts/dev/test-smoke-check.sh`: pass，覆盖默认 `DEVELOPER_DIR`、显式 `DEVELOPER_DIR`、显式 `--host-path` 和 shell-safe dry-run 输出
  - `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test'`: pass，36 tests passed
  - `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build'`: pass
  - `/bin/zsh -lc 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test'`: pass
  - `cd extensions/chrome && npm test`: pass，9 files / 70 tests passed
  - `cd extensions/chrome && npm run build`: pass
  - `git diff --check`: pass
