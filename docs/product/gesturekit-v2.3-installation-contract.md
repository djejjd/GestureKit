# GestureKit V2.3 安装与连接闭环契约

> 状态：开发中
>
> 目标：消除本地开发和日常使用中因 Chrome 扩展 ID、Native Messaging manifest、构建产物路径不一致造成的手工配置与连接不确定性。

## 1. 用户目标

用户在首次加载扩展或切换代码分支后，不需要手工查找并复制扩展 ID，也不需要编辑 `com.gesturekit.host.json`。通过一个固定入口可以完成构建、manifest 安装和环境检查，并能明确知道失败发生在构建、Chrome 扩展、native host 还是 App IPC 哪一段。

## 2. 交付范围

V2.3 必须交付：

- Chrome 开发扩展的稳定 ID 来源。仓库只保存用于推导 ID 的公开扩展公钥，不保存私钥、个人扩展 ID 或任何凭据。
- 可读取该稳定 ID 的脚本入口，供 manifest 安装和诊断复用；不再要求调用方传入 `--extension-id`。
- 单一安装入口，负责构建 host、构建扩展、安装 Native Messaging manifest，并输出用户仍需在 Chrome 中执行的“加载已解压扩展”路径。
- 单一 health check，按“开发环境 -> host 自检 -> 扩展构建 -> manifest -> Chrome/App 连通性”分阶段输出通过、待操作或失败结果。
- 更新安装、排障和端到端验收文档，包含首次安装、更新、切换分支和恢复连接的步骤。

## 3. 明确边界

V2.3 不交付：

- 自动绕过 Chrome 的开发者模式或“加载已解压扩展”用户确认。
- 自动启动、停止或杀死 GestureKitApp；health check 只能报告 App 是否可连通。
- 新手势、新浏览器动作、动作换绑、多浏览器支持或 Provider Protocol v2 消息变更。
- Chrome Web Store 打包、签名、自动更新或正式分发。

## 4. 架构约束

- 通信链路保持 `Chrome extension -> connectNative() -> GestureKitHost -> App IPC`。
- Native Messaging manifest 的 `allowed_origins` 必须只包含稳定推导出的单个 Chrome extension origin。
- 扩展 ID 推导和 manifest 写入必须使用同一个权威输入，禁止脚本间硬编码 ID。
- 所有安装脚本必须支持 dry-run；实际写入 manifest 时继续使用原子替换，失败不得留下半写入 JSON。
- health check 失败必须携带阶段、下一步和不泄露本机敏感信息的诊断摘要。

## 5. 验收标准

### 5.1 自动化

- 扩展 ID 推导对已提交公开公钥稳定，且输出满足 Chrome 的 32 位 `a-p` 格式。
- 安装入口在 dry-run 中不再要求或输出人工填写的扩展 ID。
- 安装脚本写入的 manifest 使用推导出的 origin，并保留绝对 host 路径校验和原子写入。
- health check 在缺少 Xcode、缺少 Node 依赖、host 自检失败、manifest 缺失、App 未运行时分别输出可区分结果。
- 既有 shell 测试、`swift test`、`npm test` 和 `npm run build` 保持通过。

### 5.2 手动验收

1. 从干净工作目录运行安装入口，不输入扩展 ID。
2. Chrome 只需手工选择仓库的 `extensions/chrome` 目录加载扩展。
3. 运行 health check：App 未启动时明确显示“等待 App”，启动后显示端到端连接正常。
4. 切换到包含同一公开扩展公钥的分支并重新安装，manifest origin 保持不变，扩展无需重新登记 ID。

## 6. 工作量与发布

预计工作量为 2 至 3 个开发日：稳定 ID 与测试约 0.5 天，安装编排约 0.5 天，health check 约 1 天，真实 Chrome 验收和文档约 0.5 至 1 天。

V2.3.0 仅在四项验收完成并通过 PR 审查后发布。环境适配或安装脚本缺陷以 `v2.3.1` 补丁版本处理，不混入新手势或新动作。
