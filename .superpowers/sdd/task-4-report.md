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

- 待提交

## concern

- 当前环境默认 `swift` 指向 Command Line Tools；按 brief 的 `swift test` 会失败，需显式切到 Xcode Developer dir 才能通过。已按仓库当前实际情况验证并作为正式结果记录。
- `npm test` / `npm run build` 输出了 `pyenv: cannot rehash: /Users/lanser/.pyenv/shims isn't writable`，但命令本身均成功，不构成本任务阻塞。
