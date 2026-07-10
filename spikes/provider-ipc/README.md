# Provider IPC Spike

该 Spike 验证 macOS 上的 Unix domain socket、`0600` socket 文件权限，以及绑定 `providerInstallId` 与 nonce 的 HMAC-SHA256 challenge-response。

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run ProviderIPCProbe
```

预期输出为单行 JSON，包含 `transport`、`socketPermissions`、`challengeAccepted` 和 `invalidCredentialRejected`。

安全边界：该 Spike 使用进程内临时随机 secret，只用于验证协议机制。它不代表生产凭据保存、密钥轮换、session 过期或同 UID 已受控进程防护已经完成；这些要求由后续认证 Provider 会话任务实现。
