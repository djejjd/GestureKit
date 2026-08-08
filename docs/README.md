# GestureKit 文档索引

命名与目录规范见 [文档体系规范与整改方案](contributing/文档体系规范与整改方案.md) 与 AGENTS.md「文档规范」节。文档文件名用中文；`v1`/`v2` 版本归类的范围 = 版本敏感文档（product 契约、plans 计划、releases 变更），跨版本文档保持主题。

## 目录职责

| 目录 | 职责 | 版本归类 |
|---|---|---|
| `adr/` | 架构决策记录（编号递增） | 跨版本 |
| `architecture/` | 架构/技术设计 | 跨版本 |
| `contributing/` | 贡献与规范 | 跨版本 |
| `operations/` | 安装/排障/检查清单 | 跨版本 |
| `plans/` | 实施计划 | **v1 历史 / v2 当前** |
| `product/` | 产品契约/需求 | **v1 / v2 按版本** |
| `quality/` | 本地排障与事故复盘（git 忽略，不提交） | 跨版本 |
| `releases/` | 发布版本变更记录 | 天然带版本 |
| `research/` | 调研与探针实验 | 跨版本 |
| `ui/` | UI 预览素材（html，非文档） | 跨版本 |

## 文档清单

### ADR（架构决策）
- [0001-使用原生宿主中间层](adr/0001-使用原生宿主中间层.md)
- [0002-使用扩展记录末次指针位置](adr/0002-使用扩展记录末次指针位置.md)
- [0003-沿用V1规则引擎](adr/0003-沿用V1规则引擎.md)

### 架构与设计
- [可靠性可观测平台-架构](architecture/可靠性可观测平台-架构.md)
- [v2-UI信息架构](architecture/v2-UI信息架构.md)
- [v1-技术设计](architecture/v1-技术设计.md)
- [配置派生交互护盾-设计](architecture/配置派生交互护盾-设计.md)
- [控制中心状态与历史-设计](architecture/控制中心状态与历史-设计.md)

### 计划（v2 当前 + v1 历史）
见 [plans/README.md](plans/README.md)。

### 产品契约
- v1：[v1-产品契约](product/v1/v1-产品契约.md)、[v1-需求](product/v1/v1-需求.md)
- v2：[v2.2-配置契约](product/v2/v2.2-配置契约.md)、[v2.3-安装契约](product/v2/v2.3-安装契约.md)、[v2.4-可靠性契约](product/v2/v2.4-可靠性契约.md)

### 运维
- [端到端检查清单](operations/端到端检查清单.md)
- [排障手册](operations/排障手册.md)
- [本地安装](operations/本地安装.md)
- [开源发布检查清单](operations/开源发布检查清单.md)

### 发布记录
- [发布模板](releases/发布模板.md)
- [v2.3.2-变更记录](releases/v2.3.2-变更记录.md)、[v2.3.1-变更记录](releases/v2.3.1-变更记录.md)

### 调研与探针实验
- [macOS触控板输入方案-调研](research/macOS触控板输入方案-调研.md)
- [触控板手势稳定性矩阵](research/触控板手势稳定性矩阵.md)
- [交互护盾-探针实验](research/交互护盾-探针实验.md)
- [页面护盾时序-探针实验](research/页面护盾时序-探针实验.md)
- [Provider-IPC与TCC-探针实验](research/Provider-IPC与TCC-探针实验.md)
- [评审纪要-推荐应用](research/评审纪要-推荐应用.md)

### 贡献与规范
- [文档体系规范与整改方案](contributing/文档体系规范与整改方案.md)
- [提交与发布规范](contributing/提交与发布规范.md)
