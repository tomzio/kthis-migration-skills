# 前端移植（webhis-front）

> 仓库根 = **项目根** `.agents/paths.env` 的 `WEBHIS_FRONT_DIR`（每个开发者不同；缺失时跑 `scripts/setup-paths.sh` 生成）；下文路径均相对该根。
>
> ⚠️ **前端通用规范以 `webhis-front` 技能 + 仓库 `.agents/rules/*` 为强制基准**（`FrontNormalize.md`、`page-norm.md`、`tableRule.md`、`componentUseRule.md`、`componentActionRule.md`、`servicesApiRule.md`、`pageStyleRule.md`）。**生成或修改前端代码时必须遵循**，本文件**只列迁移特有**的落点与坑，避免与上面重复；两者冲突时以 `webhis-front` / `.agents/rules/` 为准。

把遗留 SWT 界面重写为 React 页面/弹窗。**不追求像素级复刻**，按 antd 4 与本项目规范重组，但**控件元素、功能布局、业务逻辑必须与遗留一致**。

## 1. 落点与注册

- 页面/弹窗：`src/pages/<mod>/<feature>/`；模块服务层 `src/pages/<mod>/services/*.js`；注册表 `src/pages/<mod>/<mod>ComponentRegistry.js`。
- 懒加载：`@loadable/component` + `src/pages/index.js` 的 `dynamicModule`；registry 的 `switch (componentId)` 返回 `{ component, model }`。
- **`componentId` 必须三处完全一致（含大小写）**：注册表 `case`、`message.json` 的 `componentId`、`componentAction.ts` 的 `componentId`。不一致会导致 i18n / 权限**静默失效**。
- 目录/命名/样式等通用规则 → 见 `webhis-front` 技能。

## 2. model 与弹窗

- **effect 的 `context` 挂在第一个参数（action）上**，必须写：

  ```js
  *xxx({ payload, context: { namespace } }, { put, select, callService }) { ... }
  ```

  写成 `*xxx(_args, { context: { namespace }, ... })` 会运行时抛 `Cannot read properties of undefined (reading 'namespace')`，**且 eslint / tsc 都发现不了**（症状：页签 / 按钮点了没反应）。
- 生命周期：`init` 只在首次进入；切回页签的刷新由基类调度到 **`refresh` effect**（**不要**在 `init` 里调 `refreshPage`，基类已处理）。
- 基类在 `@webhis/shared/app/model/*`：普通页 `extendPage` / `extendEditablePage`；弹窗 `extendPopup` / `extendEditablePopup`；带患者条 `extendWpbPage` / `extendEditableWpbPage`（`wpbLevel: 'VISIT' | 'PATIENT'`）。
- 增强 effects：`callService`（自动注入 uiContext / bizContext）、`callServiceWithLoading`、`putPromise`（**阻塞式取值，打开弹窗取返回值就用它**）、`callSelector` / `callEffect`。
- 弹窗统一 `app/openComponentPopup` + `componentId`（**禁止直接 import baseUi 的 Dialog**）；关窗时 `putPromise` 解析为 `undefined` / `false`，弹窗在 `confirmPopup` 里 `put({ type: 'app/closePopup', payload: { instanceId, result } })` 回传结果。
- `uiSetting`：`title` / `popupType: 'dialog' | 'slip' | 'slippanel'` / `size: 's' | 'm' | 'l'` / `width`、`minWidth`、`maxWidth` / `noHeader`、`noFooter`。

## 3. 请求层（两个，别选错）

- 业务统一用 **`@webhis/shared/utils/request`**：`get(url, parameter, requestContext, options)` / `post(url, body, requestContext, options)` / `postWithParameter` / `download` / `requestJson` / `checkErrorCode`。
- **service 方法最后一个参数必须传 `this`**（把 uiContext / page bizContext 带到后台），否则请求上下文与统一消息机制失效。
- `@/utils/request` 是较新的 fetch 版 `Request` 类（拦截器 / 重试 / 超时 / IndexedDB 日志），**业务基本不用，新页面沿用上面那种**。

## 4. i18n（迁移特有：文案来源与分阶段）

> **迁移实现阶段可先写中文字面量，便于开发调试；i18n 作为独立的后续阶段统一补齐。**
> （`message.json` / `createMessage` 的完整规范以 `webhis-front` 技能 + `.agents/rules/*` 为准）

- **何时做**：先把功能与交互跑通（文案直接写中文）；待该批界面稳定后，按「i18n 补齐」阶段统一抽成 `message.json`，不阻塞迁移进度。
- **文案来源（补齐时）**：中文文案要从遗留 `messages.properties`（GBK）转码后重录，不要复制字节。
- **补齐时**：每个组件一份 `message.json`：`{ componentId, zh_CN: {...}, en_US: {...} }`（**只写 `zh_CN` 即可**）；用 `createMessage` / `getCommonMessage` / `formatMessage`；文案要在**运行时动态取**（render 内 / effect 内），别在组件外部先取成常量，否则切语言不刷新。
- **不要因 defer 而省**：注册表 `case` 与 `componentAction.ts` 的 `componentId` 仍须**先落地且一致**（权限与注册不依赖 i18n 文案）；补齐 i18n 时让 `message.json` 的 `componentId` 与之对齐，最终**三处完全一致（含大小写）**。

## 5. 会踩的坑

- **禁止用 `updateState` 改二级数据结构**，复杂 state 变更写专门 reducer。
- 表格 `key` 用 `${id}_${index}`，**不要用 index**；`VirtualTable` 的 `vid` 命名 `模块_文件名_xxx`。
- ESLint 禁导：`moment`（用 dayjs）、`lodash` / `lodash/*`（用 `import { x } from 'lodash-es'`）、`@brickio/ui`（用 `@/base/ui`）。
- 路径别名 `@brickio/ui/*`、`@webhis/shared/*` 解析到 packages 的**编译产物 `es/`**；改 `packages/*/src` 必须 `yarn build:deps`（或跑 `yarn dev`）才生效。
- 生产构建剥离所有 `console.log`，调试日志别指望上线还在。
- 路由 / 菜单由后端下发，URL 形如 `/index/:menu/:page`；model 不是自动注册，靠 `appRuntime.model(...)` 逐个注册。

## 6. 布局与样式

> 完整规范以 `webhis-front` 技能 + 仓库 `.agents/rules/pageStyleRule.md`、`docs/FrontNormalize.md` 为准；迁移分册的排版对齐跨模块通用册 `docs/migration/00-前端布局规范.md`。

- 骨架：折叠查询表单 + 结果表格（分页 / 排序 / 状态切换）+ 左分类树 + 操作列；编辑用宽弹窗或多 Tab 表单，子弹窗独立打开。
- **布局紧凑（重点）**：表单用 `GridFormAntd`（`@/base/ui`），不要用零散 `Row`/`Col` 拼。`templateColumns` 里**标签列用 `auto`、控件列用 `minmax(0,1fr)`（不要裸 `1fr`）**，否则控件被拉满、留大片空白。密度：普通弹窗 / 页签**每行 3~4 对「标签 + 控件」**，密集页签 4 对，辅助弹窗至少 3 对；3 对 → `"auto minmax(0,1fr) auto minmax(0,1fr) auto minmax(0,1fr)"`，4 对 → 再重复一组。极短字段（年月 / 百分比 / 时长）用 `minmax(0,120px)` 限宽，**不要拉伸**；长文本（备注 / 诊断）才整行。同分区同行列对齐（标签宽统一、gutter 10）。参考实现：`src/pages/<mod>/<feature>/<XxxDialog>.jsx`（同一分区内 4 对/行）。**成组与对齐**：业务相关 / 事件联动的控件要挨在一起（勾选与联动控件、区间上下限、代码与名称）；同组字段不跨行拆散，放不下时整组挪行，必要时可适当调整控件顺序。
- 复用优先：`src/common`（table / advancedForm / combobox / patienttree）与 `@/base/ui`，**不自行造轮子**；最小化自定义 CSS，禁止 `!important`。

## 7. 验证（无测试框架）

```sh
yarn lint:js                                          # eslint，看【新增】错误/警告
npx tsc --noEmit -p tsconfig.root.json                # 类型检查；跑完删 tsconfig.root.tsbuildinfo
yarn build:deps                                       # 仅当改了 packages/*
yarn dev / yarn start                                 # 起 dev server 手测
```

提交前手测：新增 / 编辑、必填 / 条件必填、显隐 / 禁用 / 联动、校验提示语、保存 / 删除 / 调价流程与遗留一致。dev 代理（`/his`、`/flow`、`/DCWriterDemo`）配在 `scripts/rspack.dev.js`，不在 `.env`。

> 浏览器端到端走查可手动进行；本地若已装 **Playwright MCP**（`browser_*` 工具，**可选**），可自动驱动：登录一次 → 沿菜单/路由进入 → `browser_take_screenshot` 截图 + `browser_console_messages` / `browser_network_requests` 采集报错与接口 4xx/5xx。缺 Playwright 不阻塞，清单（P1–P10）与证据留存格式见 **[e2e-verification.md](e2e-verification.md)**。
