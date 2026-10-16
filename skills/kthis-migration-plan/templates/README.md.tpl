# {{MODULE_NAME}}（{{MODULE_NO}} / `{{MODULE_CODE}}`）迁移文档

> 遗留 KTHIS/eHealth → WebHIS（React 前端 + Spring Boot 后端）功能迁移的设计文档。
> 遗留源码 GBK、本文档 UTF-8：**不要直接复制字节**，中文需转码或重录；一切以遗留源码为准。

## 文档索引

文档按**界面 / 功能**聚合；每册按「功能布局（含线框与布局要点）→ 控件顺序 → UI 交互 → 关联事件 → 实现要点 → 关联文档」组织。

| 册 | 文档 | 内容 |
| --- | --- | --- |
| {{VOL_NO}} | [{{VOL_TITLE}}](./{{VOL_FILE}}) | <!-- TODO --> |

## 后端接口文档（索引）

新侧后端仓库按功能维护自动生成的接口文档（端点清单 / 入参出参 / 鉴权约定）。**写前端请求层以后端接口清单为准**，本目录「数据流程与接口」册只作概要视图。

| 文档 | 内容 |
| --- | --- |
| <!-- TODO：后端接口清单（路径或链接） --> | 端点总清单 |

> 跨仓库链接多为**本机工作区绝对路径**，可能只在本机有效；运行期可参考后端 Swagger。

## 页签与分区复用矩阵

多个弹窗 / 页面**共用**的页签与**共享分区**在此汇总：共用内容**各只一册**，共享分区抽入独立的「共享分区与复用矩阵」册**单一维护**，引用方只留差异。

| 复用对象 | 界面 A | 界面 B | 文档 |
| --- | --- | --- | --- |
| <!-- TODO --> |  |  |  |

## 界面截图（遗留 SWT 核对参照）

`images/` 收录遗留 SWT 截图，命名规则 `<功能序号>-<模块代号>-<界面英文名>.png`（如 `{{MODULE_NO}}-{{MODULE_CODE}}-drug-info-tab.png`）。截图目录可为迁移文档根目录下的共享 `images/`，也可放在本模块目录内的 `images/`（大模块可选），以仓库现状为准。

| 截图 | 界面 | 说明 |
| --- | --- | --- |
|  |  |  |

## 逐层映射（遗留 → WebHIS）

| 遗留 | WebHIS |
| --- | --- |
| `ui.<mod>.*` SWT 视图 | `src/pages/<mod>/` React 页面 |
| `model.*` action + `I*Service` | 后端 `webhis-<mod>-api` / `-server` |
| `server.*` impl + iBATIS maps | `webhis-<mod>-server-impl` + MyBatis |
| `Communicate`/`EntryServlet` | JSON REST `/his/<mod>/...` |

## 迁移通用约定

- **逻辑删除** `defunct_ind`：`'Y'`/`'N'`，默认只取 `'N'`。
- **审计字段**：`created_by` / `created_date_time` / `last_updated_by` / `last_updated_date_time`（部分含 `cancelled_*`）。
- **机构 / 院区归属**：保留机构归属字段（具体字段名以遗留表结构为准）。
- **编码**：遗留 GBK、新侧 UTF-8，**不要直接复制字节**，中文需转码或重录。
- **SQL 平移**：iBATIS `#p#` → MyBatis `#{p}`、`$l$` → `${l}`、`isNotEmpty` → `<if test>`。

## 推荐落地流程

1. 读对应分册，在遗留侧把功能端到端跑通（界面 → 事件 → 服务 → SQL → 表）。
2. 逐层映射到新侧（后端接口 + 前端页面）。
3. 页面 / 弹窗按 `componentId` 注册，弹窗用 `app/openComponentPopup` 打开。
4. 排版与分层遵循 [00-前端布局规范](00-前端布局规范.md)，按**布局核对验收清单**逐项通过。
