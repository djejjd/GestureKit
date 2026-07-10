# InteractionShield Spike

该 Spike 验证 `CGEventTap` 能否在短 lease 内拦截左键下压、拖动和释放，从而抑制网页文本选择和图片拖动的默认行为。

默认仅监听：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run InteractionShieldProbe -- --duration-ms 5000
```

显式短时屏蔽：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run InteractionShieldProbe -- --shield-ms 1500 --duration-ms 5000
```

如需留出操作准备时间，可增加 `--shield-delay-ms 3000`；例如运行 7 秒，在第 3 秒到第 4.5 秒间屏蔽左键事件：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run InteractionShieldProbe -- --shield-delay-ms 3000 --shield-ms 1500 --duration-ms 7000
```

屏蔽窗口只在进程启动后的指定毫秒数内生效，之后自动透传输入。运行时必须验证普通点击、文本选择、图片拖动、输入框、跨窗口切换、权限撤销和 event tap 超时。任何权限或 tap 不可用时，V2 保持 `NoopShield`。
