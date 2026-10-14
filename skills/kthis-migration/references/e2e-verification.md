# 端到端验证（手动 + 可选 Playwright MCP）

> 前提：新侧**没有可用的测试框架**。前端验证 = 静态检查 + 类型检查 + **起服务用真实浏览器手测**；本文件只管最后一环：起服务后走查界面、留证、采集接口 / 控制台错误，并与遗留表现比对。接口 / 落库核对见 [backend-verification.md](backend-verification.md)，lint / tsc 见 [frontend-porting.md](frontend-porting.md) §7。
>
> **Playwright MCP 是可选项**：本地可能未安装 / 未配置；此时可询问用户是否安装，或直接**手动浏览器走查 + 人工截图**，**不得因此阻塞迁移主任务**。已装则用 `browser_*` 工具手动驱动浏览器完成「登录 → 走到目标界面 → 截图 + 采集 4xx/5xx」，每一步都被模型显式看见、可逐条判断，无需预置脚本。结论只写「做了哪些走查、结果如何」，**不要声称「测试通过」**。

## 1. 起服务

```sh
yarn dev            # 主应用 + packages 同时热更（首选），http://localhost:9000
yarn start          # 仅主应用热更
```

- 后端用真实的 9800（`./startup.sh dev`），或本地 mock；dev 代理（`/his`、`/flow`、`/DCWriterDemo`）配在 `scripts/rspack.dev.js`，**不在 `.env`**（见 frontend-porting §7）。
- 记下前端访问地址（默认 `http://localhost:9000`）。

## 2. 登录一次

> 下面以 Playwright MCP 为例；**无 Playwright 时在浏览器里手动完成同样动作**（后续各节同理）。

```text
browser_navigate  → 前端地址（未登录会被重定向到登录页）
browser_snapshot  → 取出账号 / 密码 / 登录按钮的 ref
browser_fill_form / browser_type → 填账号密码
browser_click / press Enter       → 提交
browser_snapshot                  → 确认已进入主框架
```

登录后**同一浏览器上下文保留会话**，后续直接 navigate 到目标路由即可，不必重复登录。

## 3. 走到目标界面

- 路由形如 `/index/:menu/:page`，**菜单由后端下发**；拿不到确切 URL 时，先到主页再沿菜单点进去（更贴近真实用户路径）。
- 定位与交互用**可访问性树**（Playwright `browser_snapshot`）最稳；不要靠截图 `browser_take_screenshot` 去找元素——截图只用于留证。

## 4. 留证

| 证据 | 工具（有 Playwright 时） | 落点 |
| --- | --- | --- |
| 界面截图 | `browser_take_screenshot`（`scale: "css"`，可给 `filename`） | `<前端>/.e2e/shots/`，**不要混进** `docs/migration/images/` |
| 控制台报错 | `browser_console_messages`（`level: "error"`） | 纳入证据说明 |
| 接口 4xx/5xx | `browser_network_requests`（按 URL 过滤接口）→ `browser_network_request` 看详情 | 纳入证据说明 |

- **无 Playwright 时**：浏览器手动截图存到 `<前端>/.e2e/shots/`，控制台报错与接口 4xx/5xx 用 DevTools 的 Console / Network 面板查看。
- 截图命名建议 `<模块>-<界面>-<态>.png`（`-page` / `-tab` / `-dialog`，新增态加 `add-`；与遗留截图命名口径一致，便于并排比对）。
- **新侧截图与遗留截图分开放**：`docs/migration/images/` 只放遗留 SWT 截图（属文档阶段资产，见 `kthis-migration-plan` 技能的 `references/screenshots.md`）。

## 5. 逐条实测清单（对照遗留 / 设计文档）

每个界面至少覆盖：

| #   | 场景               | 通过标准                                                                                 |
| --- | ------------------ | ---------------------------------------------------------------------------------------- |
| P1  | 打开与初始态       | 列表 / 表单能打开；默认值、只读态、按钮可见性正确                                        |
| P2  | 新增               | 走完新增保存，字段 / 校验 / 提示语与遗留一致                                             |
| P3  | 编辑               | 回填正确；改动落库；**未涉及字段不被覆盖**                                               |
| P4  | 删除 / 停用        | 二次确认文案一致；列表移除；仍在库（`defunct_ind='Y'`，落库核对见 backend-verification） |
| P5  | 必填 / 条件必填    | 缺项被拦并给出正确提示                                                                   |
| P6  | 显隐 / 禁用 / 联动 | 勾选、区间、代码 ↔ 名称等联动与遗留一致                                                  |
| P7  | 校验提示语         | 与设计文档「服务端异常 → 前端提示」一致                                                  |
| P8  | 分页 / 排序 / 筛选 | 首页 / 末页 / 越界 / 排序稳定                                                            |
| P9  | 业务主流程         | 保存 / 删除 / 调价等关键链路整体走通                                                     |
| P10 | 控制台 / 接口      | 无新增 error；关键接口无 4xx/5xx（或已解释）                                             |

## 6. 与遗留行为比对

方法与判定口径同 [backend-verification.md](backend-verification.md) §4：遗留侧先跑一遍（记录界面表现 / 默认值 / 提示语 / 落库结果）→ 新侧同场景逐项对齐（Playwright 或手动）→ 差异判定为「有意的等价替换」还是「实现错误」，判定不了就问用户，不要默默放过。

## 7. 证据留存

附在 MR 描述或 `_进度台账.md`：

```text
端到端验证（<模块> / <分支>）
- 服务：yarn dev ✅（前端 :9000，后端 :9800 / mock）（<时间>）
- 登录：✅（账号 <…>）
- 走查：共 N 个界面；P1–P10 通过 M 项，未通过/未覆盖：<列出 + 原因>
- 截图：`.e2e/shots/<…>.png`（<列出>）
- 控制台 / 接口：新增 error <…>；关键接口 4xx/5xx：<列出 + 结论>
- 遗留比对：场景 <X>，结论 <一致 / 差异及处理>
- 未做/待办：<…>
```

## 8. 坑

- **菜单 / 路由由后端下发**，别凭模块名猜 URL；用可访问性树（Playwright `browser_snapshot`）或直接点菜单进入最稳。
- **弹窗 / 深链不易直达**：从列表点进去（`browser_click`），再用 snapshot 逐层展开。
- `browser_take_screenshot` 的 `scale` 必填，用 `"css"`；`browser_console_messages` 要传 `level`；`browser_network_requests` 要传 `static`。
- 生产构建剥离所有 `console.log`，别指望上线后靠日志排查。
- 会话过期会跳登录页；一旦 snapshot 看到登录页，**重新登录**再继续，别把重定向当成功能异常。
