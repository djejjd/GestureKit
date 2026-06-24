# Native Messaging 验证 Spike

目标：验证 Chrome MV3 扩展能通过 `connectNative()` 连接 GestureKit native host shim。

手动验证步骤：

1. 使用 `swift build` 构建 host。
2. 把 manifest 中的 `path` 替换为 `.build/debug/GestureKitHost` 的绝对路径。
3. 把 `REPLACE_WITH_LOCAL_EXTENSION_ID` 替换为本地 unpacked extension 的 ID。
4. 将 manifest 安装到 Chrome native messaging host 的本地测试目录。
5. 从 `extensions/chrome` 加载 Chrome 扩展。
6. 确认扩展能收到 `hello` 消息。

提交到仓库中的 manifest 是模板，不得包含本机专属路径或真实 extension ID。
