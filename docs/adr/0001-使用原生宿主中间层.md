# ADR 0001：使用独立 Native Host Shim

日期：2026-06-23

## 状态

已接受，V1 采用。

## 背景

Chrome Native Messaging 的连接方向是 Chrome 扩展调用 `connectNative()` 连接 native host，host 通过 stdio 与 Chrome 通信。GestureKit 主 App 需要常驻采集触控板手势，而 Chrome 的 native host 生命周期受 Chrome 连接影响。

如果让主 App 直接作为 native host，Chrome 启动、断连、host 崩溃和 stdio 协议错误都可能影响主 App 的手势采集生命周期。

## 决策

V1 使用独立 `GestureKit Native Host Shim`：

- Chrome 扩展通过 `connectNative()` 连接 shim。
- Shim 实现 Chrome Native Messaging stdio 协议。
- Shim 通过本地 IPC 连接 GestureKit 主 App。
- 主 App 继续作为常驻菜单栏进程，负责触控板采集、规则配置和本地事件源。

## 后果

收益：

- Chrome 连接生命周期与主 App 生命周期解耦。
- stdio 协议和本地业务逻辑边界清晰。
- 后续可替换或重写 shim，而不影响主 App 核心。

代价：

- 增加一个进程和 IPC 边界。
- 安装和诊断多一步。
- 需要维护 host manifest、shim 二进制和主 App 之间的版本兼容。

## 不采用的方案

不采用主 App 直接主动向 Chrome 扩展发消息，因为这不符合 Chrome Native Messaging 模型。

不采用 `sendNativeMessage()` 作为主通道，因为它更适合短请求，不适合持续推送手势事件。
