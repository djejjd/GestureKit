# GestureKit Agent 工作约定

## 适用范围

本文件约束在 GestureKit 仓库中工作的自动化 agent。项目文档默认使用中文；代码、命令、协议字段和路径保留原始语言。

## 分支与提交

- 不得直接向 `main` 提交或推送代码。
- 所有功能、修复和文档变更必须在独立分支完成，并通过 Pull Request 合并到 `main`。
- 分支使用 `<type>/<简短主题>`，例如 `feat/gesture-configuration`、`fix/provider-capability-disclosure`。
- 一个提交只处理一个可独立理解、测试和回退的逻辑单元。
- Commit 使用 Conventional Commits：`<type>(<scope>): <中文摘要>`；涉及用户行为、配置或协议时，必须在提交正文中说明背景、变更和验证。

## Pull Request

- 创建 PR 前必须同步目标 `main`，运行与本次变更相关的测试。
- PR 描述必须填写背景、用户可感知变化、兼容性与风险、验证结果和发布说明草案。
- 未经用户明确授权，不得自行合并 PR、删除远端分支、创建版本标签或发布 GitHub Release。
- `main` 只接受已通过审查和验证的 PR 合并。

## 发布

- 大版本或功能版本（例如 `v2.1.0` 到 `v2.2.0`）必须说明新增能力、体验改进、修复的上一版本问题、兼容性与迁移路径。
- 补丁版本（例如 `v2.2.0` 到 `v2.2.1`）必须以已修复的问题、影响范围、验证方式为重点。
- 只在 PR 合并后的 `main` 上创建带说明的注释标签；标签推送和 GitHub Release 需要用户明确授权。

## 详细规范

- 提交和发布详情：`docs/contributing/commit-and-release-guide.md`
- PR 模板：`.github/PULL_REQUEST_TEMPLATE.md`
- 发布说明模板：`docs/releases/RELEASE_TEMPLATE.md`
- 产品范围优先服从：`docs/product/` 下对应版本的契约文件。
