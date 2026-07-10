# Provider IPC 与 clean-TCC Spike

日期：2026-07-10

## 结论

当前结论为 `passed_with_notes`。

- SQLite：通过。工程已使用 `CSQLite` system-library target 调用系统 SQLite。
- Unix domain socket：通过。Spike 在仅当前用户可访问的临时目录中创建 `0600` socket。
- HMAC challenge-response：通过。正确响应认证成功，伪造响应被拒绝，认证内容绑定 `providerInstallId` 和 nonce。
- clean-TCC：未验证。虽已运行临时 ad-hoc 签名 App，但它不能作为可重置的正式 TCC 对象，不能据此推断 Input Monitoring 或 Accessibility 的首次授权、撤销和重启行为。

## 原始命令与结果

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SQLiteAvailabilityTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ProviderAuthenticationTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ProviderIPCProbeTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run ProviderIPCProbe
```

最后一条命令输出：

```json
{"challengeAccepted":true,"invalidCredentialRejected":true,"sameUIDThreatModel":"not_resistant_to_compromised_same_uid_process","socketPermissions":"0600","transport":"unix_domain_socket"}
```

## 已确认边界

- Spike 的临时 secret 只用于验证 HMAC 机制，不能作为生产凭据保存方案。
- 同 UID 的已受控进程仍可能读取或模拟用户级资源；`0600` socket 与目录权限不能消除该风险。
- 现有 App 与 native host 仍使用 loopback TCP，尚未迁移到本 Spike 的 transport；因此不得把本结果表述为生产 IPC 已完成。
- 生产迁移前必须补齐凭据保存/轮换/撤销、nonce 重放拒绝、session 过期、Provider 安装实例绑定、旧 socket 清理和 App/host 端到端测试。

## clean-TCC 待执行矩阵

正式签名和打包后，以新安装的 App 执行以下矩阵：

1. Input Monitoring 与 Accessibility 均未授权时首次启动。
2. 两项权限分别授权后的重启。
3. 运行时撤销每项权限后的降级与日志。
4. `TouchBackend.start()`、事件 tap 可选增强和退出后的资源释放。

任何不确定状态必须 fail-closed，并记录可导出的诊断证据。

## 2026-07-10 clean-TCC 执行记录

为避免直接对开发产物下结论，已创建临时 `GestureKitCleanTCC.app`，使用 ad-hoc 签名，并在其中运行独立的 `CleanTCCProbe`。Probe 的执行输出为：

```text
tcc_probe phase=before_request inputMonitoring=true accessibility=true
request_result inputMonitoring=true accessibility=true
tcc_probe phase=after_request inputMonitoring=true accessibility=true
```

这只证明当前运行环境允许两项预检/请求 API，不证明 clean-TCC 场景。`tccutil reset All dev.gesturekit.clean-tcc-spike` 两次都返回 Bundle ID 未被 TCC 识别；LaunchServices 注册后结果未改变。本机 `security find-identity -v -p codesigning` 显示没有有效签名身份，因而不能生成可作为正式 TCC 对象重置的签名 App。

结论：clean-TCC 子矩阵保持未验证。继续该矩阵需要具备有效的 Development 或 Developer ID 签名身份，并以最终安装形态运行；在此之前，不得将 Input Monitoring 或 Accessibility 的授权体验标记为通过。
