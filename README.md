<!-- 状态: completed
创建: 2026-06-23
最后更新: 2026-11-22
关联: CONTRIBUTING.md、docs/operations/本地安装.md -->
# GestureKit

用 Mac 触控板操作 Chrome 标签页。读文章时，三指点按一条链接，就能在右侧标签页打开它，原文留在原处。三指向右轻扫，又能回到刚才读到的位置。

[安装指南](docs/operations/本地安装.md) · [报告问题](https://github.com/djejjd/GestureKit/issues) · [贡献指南](CONTRIBUTING.md) · [MIT 许可证](LICENSE)

## 默认手势

| 在触控板上 | Chrome 中的效果 |
| --- | --- |
| 三指点按网页链接 | 在右侧相邻标签页打开链接 |
| 三指向左 / 向右快速轻扫 | 切到右侧 / 左侧标签页 |
| 三指点按触控板左缘 / 右缘 | 切到左侧 / 右侧标签页 |
| 三指在触控板中央连续点按两次 | 关闭当前标签页 |

标签切换限于当前窗口，到达边缘时循环。打开菜单栏里的 GestureKit 控制中心，可以调整轻扫灵敏度，也可以把手势绑定到恢复已关闭的标签页、复制链接等动作。

## 从源码安装

准备一台带触控板的 Mac、macOS 15 或更新版本、支持 Swift 6.2 的 Xcode、Node.js 与 npm，以及 Google Chrome。

```sh
git clone https://github.com/djejjd/GestureKit.git
cd GestureKit
npm ci --prefix extensions/chrome
./scripts/dev/install-local.sh
```

1. 在 Chrome 打开 `chrome://extensions`，启用「开发者模式」，点击「加载已解压的扩展程序」，选择刚克隆的 `GestureKit/extensions/chrome` 目录。
2. 回到仓库根目录，运行 `./scripts/dev/build-app.sh`，再运行 `open ~/Applications/GestureKit.app` 启动菜单栏应用。
3. 在普通网页上找一条链接，三指点按它。新标签应出现在原标签右侧。若手势没有响应，可运行 `./scripts/dev/health-check.sh` 检查本地连接。

更多安装选项和权限说明见[本地安装指南](docs/operations/本地安装.md)。连接或手势异常时可查阅[排障手册](docs/operations/排障手册.md)。

## 参与开发

菜单栏 App 负责识别触控板手势，Chrome 扩展负责在页面上执行动作，两者通过 Native Messaging host 通信。修改后可在仓库根目录运行测试。运行 Swift 测试前，请先从菜单栏退出 GestureKit，以便测试获取单实例锁。

```sh
swift test
npm test --prefix extensions/chrome
npm run build --prefix extensions/chrome
```

欢迎提交 Issue 或 Pull Request。反馈手势问题时，请说明 Mac 和 Chrome 版本、做了什么手势，以及预期和实际发生的动作。贡献流程和真机验证步骤见[贡献指南](CONTRIBUTING.md)和[端到端检查清单](docs/operations/端到端检查清单.md)。

<details>
<summary>English quick start</summary>

GestureKit brings trackpad shortcuts to Google Chrome on macOS. Tap a link with three fingers to open it in the adjacent tab, swipe to switch tabs, or double-tap the center of the trackpad with three fingers to close the current tab.

On macOS 15 or later, install Xcode with Swift 6.2 and Node.js with npm. Run the source installation commands above, then enable Developer mode at `chrome://extensions` and load `extensions/chrome` as an unpacked extension. Run `./scripts/dev/build-app.sh` and open `~/Applications/GestureKit.app`.

</details>
