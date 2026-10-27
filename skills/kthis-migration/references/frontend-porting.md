# 前端移植（webhis-front）

> 仓库根 = 项目根 `.agents/paths.env` 的 `WEBHIS_FRONT_DIR`（细节见 [repos-and-map.md](repos-and-map.md) §路径配置）；下文路径均相对该根。
>
> ⚠️ **三份都是实现依据，按序读**：① **迁移文档的 `00-前端布局规范.md`**（界面骨架 / 栅格 / 分区 / 表格 / 按钮 / 尺寸的**具体数值**）；② **仓库 `.agents/rules/*`**（页面 / 样式 / 组件 / 表格 / 请求层约束）；③ 本文件（迁移特有的落点与坑）。三者重叠处以 ② 为准。

把遗留 SWT 界面重写为 React 页面/弹窗。**目标不是像素级复刻**：对照遗留截图与源码**核对**标签 / 控件顺序、分区顺序、字段栅格密度、控件类型与映射；**视觉按 antd 4 + 本项目规范 + 既有组件库 / 既有页面观感**实现；**控件元素、字段、功能布局、业务逻辑以遗留源码为准、必须一致**（截图可能不完整，仅作核对参照）。

## 1. 落点与注册

- 页面/弹窗：`src/pages/<mod>/<feature>/`；模块服务层 `src/pages/<mod>/services/*.js`；注册表 `src/pages/<mod>/<mod>ComponentRegistry.js`。
- 懒加载：`@loadable/component` + `src/pages/index.js` 的 `dynamicModule`；registry 的 `switch (componentId)` 返回 `{ component, model }`。
- **`componentId` 必须两处完全一致（含大小写）**：注册表 `case` 与 `message.json` 的 `componentId`。不一致会导致 i18n **静默失效**。

## 2. model 与弹窗

> 基类选型、effect 的 `context` 传参、生命周期（`init` / `refresh`）、弹窗打开与 `uiSetting` 等实现细则以仓库 `.agents/rules/page-norm.md`「模型基类（`@webhis/shared/app/model/*`）」「通用约束（重要）」「1. 主页面」「2. 对话框」为准（唯一来源）；增强 effects（`callService` / `callServiceWithLoading` / `putPromise` / `callSelector` / `callEffect`）见 `docs/referrence/layers&modules.md`。本节只列迁移特有的注意点。

- **最易踩**：effect 的 `context` 挂在第一个参数（action）上，写成第二个参数会运行时抛 `Cannot read properties of undefined (reading 'namespace')`，**且 eslint / tsc 都发现不了**（症状：页签 / 按钮点了没反应）。
- **打开弹窗取返回值用 `putPromise`**（阻塞式）；关窗时解析为 `undefined` / `false`，弹窗在 `confirmPopup` 里 `put({ type: 'app/closePopup', payload: { instanceId, result } })` 回传结果。

## 3. 请求层（两个，别选错）

- 业务统一用 **`@webhis/shared/utils/request`**：`get(url, parameter, requestContext, options)` / `post(url, body, requestContext, options)` / `postWithParameter` / `download` / `requestJson` / `checkErrorCode`。
- **service 方法最后一个参数必须传 `this`**（把 uiContext / page bizContext 带到后台），否则请求上下文与统一消息机制失效。
- `@/utils/request` 是较新的 fetch 版 `Request` 类（拦截器 / 重试 / 超时 / IndexedDB 日志），**业务基本不用，新页面沿用上面那种**。

## 4. i18n（迁移特有：文案来源与分阶段）

> **迁移实现阶段可先写中文字面量，便于开发调试；i18n 作为独立的后续阶段统一补齐。**

- **何时做**：先把功能与交互跑通（文案直接写中文）；待该批界面稳定后，按「i18n 补齐」阶段统一抽成 `message.json`，不阻塞迁移进度。
- **文案来源（补齐时）**：中文文案要从遗留 `messages.properties`（GBK）转码后重录，不要复制字节。
- **补齐时**：**每个菜单页面（页面目录）一份 `message.json`**（主页面 / 弹窗 / 侧滑共用）：`{ componentId, zh_CN: {...}, en_US: {...} }`（**只写 `zh_CN` 即可**，其余语言按需再补）；用 `createMessage` / `getCommonMessage` / `formatMessage`；文案要在**运行时动态取**（render 内 / effect 内），别在组件外部先取成常量，否则切语言不刷新。
- **不要因 defer 而省**：注册**不依赖文案** —— `componentId` 先落地（**三处一致**见 §1）；补齐 i18n 时再让 `message.json` 的 `componentId` 对齐。

## 5. 会踩的坑

> 通用坑的规则正文以仓库 `.agents/rules/*` 为准：`updateState` 改二级结构、effect 的 `context`、表格 `key` / `vid`、ESLint 禁导、生产构建剥离 `console.log` 见 `.agents/rules/page-norm.md`「通用约束（重要）」、`.agents/rules/tableRule.md`「虚拟表格 / 排序表格」、`.agents/rules/FrontNormalize.md`「必读要点（摘要）」。本节只列迁移特有的坑。

- 路径别名 `@brickio/ui/*`、`@webhis/shared/*` 解析到 packages 的**编译产物 `es/`**；改 `packages/*/src` 不会即时生效，需重新构建（见 §7）。
- 路由 / 菜单由后端下发，URL 形如 `/index/:menu/:page`；model 不是自动注册，靠 `appRuntime.model(...)` 逐个注册。

## 6. 布局与样式

> 排版 / 骨架 / 栅格 / 分区 / 表格 / 按钮 / 尺寸**一律以迁移文档的 `00-前端布局规范.md` 为准**；实现约束以 `.agents/rules/pageStyleRule.md`、`.agents/rules/tableRule.md`、`.agents/rules/page-norm.md` 与 `docs/FrontNormalize.md` 为准。本节只记迁移特有项。

- 复用优先：`src/common`（table / advancedForm / combobox / patienttree）与 `@/base/ui`，**不自行造轮子**；能靠组件 props 表达的不写 CSS；禁止 `!important`。
- 「标签 / 文本 / 控件没对齐」类问题按 **§8 处置顺序**判断改哪里，不要上手就写 CSS 或改公用组件。

## 7. 前端命令与验证（无测试框架）

```sh
yarn                       # 安装依赖（postinstall 自动 turbo 构建 packages）
yarn dev                   # 主应用 + packages 同时热更（日常开发用这个），http://localhost:9000
yarn start                 # 仅主应用热更
yarn build:deps            # 改 packages/* 后必须执行，否则主应用拿旧产物
yarn analyze               # 打包体积分析
yarn lint:js               # eslint，看【添加】错误/警告
npx tsc --noEmit -p tsconfig.root.json   # 类型检查；跑完删 tsconfig.root.tsbuildinfo
```

> 用 `yarn lint:js`（`yarn lint:ts` 是坏的，指向已改名的 `tsconfig.base.json`）；**无测试框架**。路径别名解析到 packages 的编译产物 `es/`，改 `packages/*/src` 必须 `yarn build:deps`（见 §5）。

提交前手测：添加 / 编辑、必填 / 条件必填、显隐 / 禁用 / 联动、校验提示语、保存 / 删除 / 调价流程与遗留一致。dev 代理（`/his`、`/flow`、`/DCWriterDemo`）配在 `scripts/rspack.dev.js`，不在 `.env`。

> 浏览器端到端走查（含**可选**的 Playwright MCP 驱动方式、清单 P1–P10、证据留存格式）见 **[e2e-verification.md](e2e-verification.md)**；缺 Playwright 不阻塞。

## 8. 布局 / 对齐问题

对齐 / 行距 / 留白问题按 `.agents/rules/pageStyleRule.md`「6. 复用优先与最小化自定义样式（强制）」的处置顺序执行，本册不复述。迁移时只额外确认：**不要照搬遗留布局**。

## 9. 表单与对齐（迁移特有坑）

> 通用表单控件 / 栅格 / 对齐以 `.agents/rules/componentUseRule.md` §表单控件 与迁移文档 `00-前端布局规范.md` §3.4 为准，本册不复述。

- **不要照搬遗留布局**：`Field` / `FieldGroup` 混用、输入框旁另起 `Button`、手工拼「输入 + 图标」等写法，一律按 `.agents/rules/componentUseRule.md` §表单控件 重写。

## 10. 落地前自查清单

写完一个界面（页面 / 弹窗 / 页签）**立刻**跑一遍，不要靠「感觉差不多」。**规则只维护一处**：条目细则看本仓库 `.agents/rules/*`（唯一来源），数值口径（骨架 / 栅格 / 分区 / 尺寸 / 列宽 / 按钮）看迁移文档 `00-前端布局规范.md`；本节只给**判定方式**，不复制规则正文，两边冲突时以 `.agents/rules/` 为准。

### 10.1 一键机检

```sh
bash .agents/skills/kthis-migration/scripts/check-frontend.sh src/pages/<mod>/<页面目录>
```

- **ERROR 必须清零**；WARN 逐条人工确认。
- 检查项以脚本输出为准；规则出处见 `.agents/rules/*`，本册不复述清单。

### 10.2 人工核对（机检覆盖不到）

> 通用规则正文只在 `.agents/rules/*`；本表只列迁移场景需要额外确认的点 + 指针。

| 判定 | 出处 |
| --- | --- |
| **页面类型与表单形态**：按 `.agents/rules/page-norm.md`「1. 主页面」判定；不确定时问用户「维护表单是否进弹窗」。**A（是）**：维护表单进弹窗（主从表 / 明细列表进侧滑），页面主体只留查询条件 + 工具条 + 表格；**B（否，默认页面形态）**：表单页 / 文档编辑器 / 向导 / 详情 / 查询报表页允许表单在页面主体 | `.agents/rules/page-norm.md`「1. 主页面」 |
| **Editor → Page**：一个 Editor 可含多个 Page，每个 Page 对应一个 WebHIS 页面并单独成册；册名与内容一致，不强行造空主页面册 | `.agents/skills/kthis-migration-plan/references/doc-structure.md` §2 第 2 / 8 条 |
| **迁移落点**：`componentId` 两处一致（registry `case` / `message.json`）、service 传 `this`、`message.json` 齐全、`app/openComponentPopup` | 本文 §1–§4 |

> 其余通用规则（表格 / 控件 / 按钮 / 弹窗结构 / 样式）按 `.agents/rules/*`，本表不重复。

### 10.3 留痕

体检命令与结果（ERROR 0 / WARN n）写进 `_进度台账.md` 当轮次行——**没跑体检、没留痕，就视为没完成**。静态检查 / 手测命令见 §7；元素级截图与留证见 [e2e-verification.md](e2e-verification.md) §4.1。
