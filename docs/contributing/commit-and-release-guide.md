# GestureKit 提交与发布规范

## 目标

让每次变更具备可审查、可追溯和可回退的记录。Commit 说明独立代码单元，PR 说明完整变更，Release 说明用户可感知的版本变化。

## 标准流程

1. 更新本地 `main`：`git switch main`、`git pull --ff-only origin main`。
2. 创建分支：`git switch -c <type>/<topic>`。
3. 在分支内开发、测试并按逻辑单元提交。
4. 推送分支：`git push -u origin <branch>`。
5. 创建面向 `main` 的 PR，完整填写 PR 模板。
6. 完成审查、CI 和手动验证后合并 PR。
7. 在合并后的 `main` 上创建版本标签并推送。创建标签和 GitHub Release 前须获得用户明确授权。

禁止直接向 `main` 推送功能代码、修复代码或版本标签。

## Commit 格式

```text
<type>(<scope>): <简短中文摘要>

背景：
- 为什么需要此修改。

变更：
- 新增、修改或删除的内容。
- 配置、协议或兼容性影响。

验证：
- 自动化测试和手动验证结果。
```

`type` 使用 `feat`、`fix`、`docs`、`test`、`refactor`、`chore`、`perf` 或 `ci`。

示例：

```text
feat(runtime): 应用可配置的手势绑定

背景：
- 固定规则无法让用户关闭单项手势或即时应用修改。

变更：
- 从 AppConfiguration 构建运行时规则引擎。
- 修改绑定后立即更新识别和动作决策链路。

验证：
- swift test：全部通过。
```

## PR 要求

PR 标题沿用 Commit 类型和简短摘要。正文必须描述背景、变更、新增、修复、不包含范围、用户可感知变化、兼容性风险、验证和发布说明草案。完整字段见 `.github/PULL_REQUEST_TEMPLATE.md`。

## 版本说明

### 功能版本

适用于 `v2.1.0` 到 `v2.2.0`。发布说明必须包含：

- 概述和目标。
- 新增功能。
- 体验改进。
- 相比上一版本修复的问题。
- 兼容性、配置迁移和已知限制。
- 自动化与手动验证结果。

### 补丁版本

适用于 `v2.2.0` 到 `v2.2.1`。发布说明必须包含：

- 修复的问题和触发条件。
- 根因或修复边界。
- 用户影响和兼容性声明。
- 验证方式和结果。

发布说明模板见 `docs/releases/RELEASE_TEMPLATE.md`。
