# 开源发布检查清单

## 应该提交

- Swift App、Native Host、GestureKitCore 和 Chrome extension 源码。
- Swift 和 TypeScript 测试。
- 协议 schema、fixtures、架构文档、产品契约、安装说明和验收清单。
- 不含本机路径、密钥、扩展 ID 的模板配置。

## 不应该提交

- `.build/`、`node_modules/`、`dist/`、coverage、DerivedData。
- `.obsidian/`、编辑器本地状态、个人工作区配置。
- `.env*`、token、secret、password、私钥、证书。
- `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/` 下安装后的 manifest。
- `~/Library/Logs/GestureKit/` 下的运行日志。
- 写死的 `/Users/...` 路径或个人 Chrome extension ID。

## 发布前命令

```bash
git status --short
git diff --check
rg -n "(/Users/|chrome-extension://[a-z]{32}|token|secret|password)" . \
  -g '!node_modules' -g '!dist' -g '!.build' -g '!.git'
swift test
cd extensions/chrome && npm test && npm run build
```

如果需要推送到 GitHub，先确认网络和远端：

```bash
git remote -v
git ls-remote origin
gh repo view
```
