# 前端移植（webhis-front）

> 仓库根 = 项目根 `.agents/paths.env` 的 `WEBHIS_FRONT_DIR`（细节见 [repos-and-map.md](repos-and-map.md) §路径配置）；下文路径均相对该根。
>
> ⚠️ **三份都是实现依据，按序读**：① **迁移文档的 `00-前端布局规范.md`**（界面骨架 / 栅格 / 分区 / 表格 / 按钮 / 尺寸的**具体数值**）；② **仓库 `.agents/rules/*`**（页面 / 样式 / 组件 / 表格 / 权限 / 请求层约束）；③ 本文件（迁移特有的落点与坑）。三者重叠处以 ② 为准。

把遗留 SWT 界面重写为 React 页面/弹窗。**目标不是像素级复刻**：对照遗留截图与源码**核对**标签 / 控件顺序、分区顺序、字段栅格密度、控件类型与映射；**视觉按 antd 4 + 本项目规范 + 既有组件库 / 既有页面观感**实现；**控件元素、字段、功能布局、业务逻辑以遗留源码为准、必须一致**（截图可能不完整，仅作核对参照）。

## 1. 落点与注册

- 页面/弹窗：`src/pages/<mod>/<feature>/`；模块服务层 `src/pages/<mod>/services/*.js`；注册表 `src/pages/<mod>/<mod>ComponentRegistry.js`。
- 懒加载：`@loadable/component` + `src/pages/index.js` 的 `dynamicModule`；registry 的 `switch (componentId)` 返回 `{ component, model }`。
- **`componentId` 必须三处完全一致（含大小写）**：注册表 `case`、`message.json` 的 `componentId`、`componentAction.ts` 的 `componentId`。不一致会导致 i18n / 权限**静默失效**。

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
- **不要因 defer 而省**：注册与权限**不依赖文案** —— `componentId` 先落地（**三处一致**见 §1）；补齐 i18n 时再让 `message.json` 的 `componentId` 对齐。

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
yarn lint:js               # eslint，看【新增】错误/警告
npx tsc --noEmit -p tsconfig.root.json   # 类型检查；跑完删 tsconfig.root.tsbuildinfo
```

> 用 `yarn lint:js`（`yarn lint:ts` 是坏的，指向已改名的 `tsconfig.base.json`）；**无测试框架**。路径别名解析到 packages 的编译产物 `es/`，改 `packages/*/src` 必须 `yarn build:deps`（见 §5）。

提交前手测：新增 / 编辑、必填 / 条件必填、显隐 / 禁用 / 联动、校验提示语、保存 / 删除 / 调价流程与遗留一致。dev 代理（`/his`、`/flow`、`/DCWriterDemo`）配在 `scripts/rspack.dev.js`，不在 `.env`。

> 浏览器端到端走查（含**可选**的 Playwright MCP 驱动方式、清单 P1–P10、证据留存格式）见 **[e2e-verification.md](e2e-verification.md)**；缺 Playwright 不阻塞。

## 8. 布局 / 对齐问题的处置顺序

遇到「标签 / 文本 / 控件没对齐、行距参差、留白怪异」这类问题，**自上而下**判断，前一步能解决就不要往下走：

1. **先用已有组件表达**：先查 `@/base/ui` 与 `src/common`（底层 `@brickio/ui` 可查阅，但 **import 一律走 `@/base/ui`**）里有没有现成组件（表单 / 栅格 / 列表 / 只读展示），能直接用就用，不要自己拼 DOM / 写 CSS。
2. **用组件 props 或仓库既有惯例解决**：能用 props（如 `GridFormAntd` 的 `templateColumns`、分区标题 class、`Collapse`）或仓库既有写法（见 `.agents/rules/componentUseRule.md` §表单控件）表达，就不新增自定义布局代码。
3. **确实要改公用组件时，先量化引用面**：`grep` 统计全仓引用处数——引用面小、且改动能收敛问题（不扩散成新 props / 新分支）才改；引用面大（几十处以上）**不要顺手改**，把「公用组件增强」记为一个独立待办并说明。
4. **页面级临时 CSS 是最后手段**：只在以上都不可行时使用，且要在代码注释 / MR 里写清为什么不能走前三条；作用域挂页面根 class、不用 `!important` 压制。

## 9. 表单与对齐细则（迁移特有坑）

> 通用栅格 / 密度 / 成组对齐见迁移文档的 `00-前端布局规范.md` §3.4；本节只记实现阶段特有的对齐坑。

- **同一表单不要混用 `Field` 与 `FieldGroup`**（规则与判定见 `.agents/rules/componentUseRule.md` §表单控件）：混用 → 行高参差、看起来「标签 / 文本 / 控件没对齐」；行距统一由默认底边距提供，**不要**再写 `margin` / `padding` 去补。 **「输入 + 触发」的控件写法一律以 `.agents/rules/componentUseRule.md` §表单控件 为准**（触发方式、触发图标位置、禁用写法都在该节，本册不复述）——这是迁移时最容易照搬遗留的地方。
- **选择类弹窗**：列表上方的查询 / 搜索行（`searchRow`）放到表格 `toolbar` 的**右侧**（见 `.agents/rules/tableRule.md`「表格工具列、过滤与删除方式」），如果能放下就不单独占行。
- **左右对照的列表必须等高**（规则与判定见 `.agents/rules/tableRule.md`「左右对照列表（等高）」）：`scroll.y` 只是 **max-height**，数据少时列表会塌陷 → 用**固定高度**；固定高度优先用组件现有 props，组件缺这个能力就按「公用组件增强」另立任务。
- **修复后自查**：同一分区内各行行高 / 行距一致（浏览器量各行 y 坐标，确认间隔相等）；左右表 / 上下组件底部对齐，空态与有数据表现一致；`lint` 通过 + 浏览器实测走一遍交互闭环（打开弹窗 → 选择 → 回填）。

## 10. 落地前自查清单

写完一个界面（页面 / 弹窗 / 页签）**立刻**跑一遍，不要靠「感觉差不多」。**规则只维护一处**：条目细则看本仓库 `.agents/rules/*`（唯一来源），数值口径（骨架 / 栅格 / 分区 / 尺寸 / 列宽 / 按钮）看迁移文档 `00-前端布局规范.md`；本节只给**判定方式**，不复制规则正文，两边冲突时以 `.agents/rules/` 为准。

### 10.1 一键机检（可 grep 的项都在脚本里）

```sh
bash .agents/skills/kthis-migration/scripts/check-frontend.sh src/pages/<mod>/<页面目录>
```

- **ERROR 必须清零**（15 项，与脚本逐项对应）：① 禁止导入（`moment` / `lodash` / `@brickio/ui`）；② 样式 `!important`；③ 样式 `nth-child` / `nth-of-type`；④ `scroll={{ x: 'max-content' }}`；⑤ 任何字符串横向滚动 `scroll={{ x: '…' }}`；⑥ 标识列渲染 `×`；⑦ `console.log(`；⑧ `templateColumns` 裸用 `1fr`（去掉 `minmax(...)` 后仍含 `1fr`）；⑨ 列表 `key` 用 index；⑩ effect 的 `context` 写在第二个参数；⑪ **页面主体里渲染 `<Modal` / `<Drawer` / `<…Dialog`**（表单 / 明细必须用 `app/openComponentPopup` 打开）；⑫ **页面主体内嵌新增 / 编辑 / 明细维护表单**（`*Page.jsx` 里同现表单元素 `<GridFormAntd` / `<Field` / `<Form` 与「保存 / 提交」按钮）；⑬ **标识（布尔）列用 `'√'` 字符而不是 `<Icon type="yes-green" />` 图标**（`*Page.jsx`；口径见 `.agents/rules/tableRule.md`「标识（布尔）列只标『是』」）；⑭ **表单弹窗的多列表单给 `GridFormAntd` 设了 `gap`**（水平间距已由 label padding 提供：组内 8px / 组间 16px；再加 `gap="0 16px"` 会把组间拉到 32px，应删掉 `gap`）；⑮ **表单弹窗的复位按钮用了「清除」**（统一 `i18n.reset`「重置」）。
- **WARN 逐条人工确认**（10 项）：① 弹窗内出现 `<Switch`（表单勾选应改 `Checkbox`）；② 页面主体出现 `onFinish=`（确认只是查询条件表单）；③ `vid="` 命名不合 `^[a-z]+_`（应为 `模块_文件名_xxx`）；④ 出现 `FieldGroup`（确认未与 `Field` 混用同一表单）；⑤ `<TableBox` 同行未见 `title=`（会兜底「数据列表」）；⑥ 内联硬编码宽高（`style={{ width|height: … }}`）；⑦ less / css 里硬编码 `width` / `height` px；⑧ `Divider` 同行带 `className` / `style`（换行写法按 §10.2 人工项确认；确认是否必要、能否复用默认样式 / 全局工具类，见 `.agents/rules/pageStyleRule.md`「6. 复用优先与最小化自定义样式（强制）」）；⑨ 主页面使用了 `rowSelection`（确认不是主从表维护、设置页；此类页面主列表应点击行选中，不传 `rowSelection`）；⑩ `placeholder` / `rules.message` / `new Error(...)` 等字符串位置直接传 i18n 对象（应使用 `i18n.xxx.props.text`，否则显示 `[object Object]`）。

### 10.2 人工核对（机检覆盖不到，逐条判定）

| 判定 | 出处 |
| --- | --- |
| 表单（新增 / 编辑 / 明细）在弹窗或侧滑里，列表页只有「查询条件 + 工具条 + 表格」；新增 / 编辑共用一个弹窗 | `.agents/rules/page-norm.md` |
| 工具条分区：`TableBox` 的 `toolbar` 左 = 竖线 + 表级过滤开关（**过滤删除默认开启，默认隐藏 `defunct_ind='Y'` 的已删除行**），右 = 聚合搜索框（`Input.Search`，一个框搜 编码/描述/拼音码）+ **页面级操作按钮（可多个，不限于新增 / 导出 / 打印等）**；行级动作（编辑 / 删除）在操作列，页级动作单独留页面操作行，**同一动作不得两处重复** | `.agents/rules/tableRule.md`「表格工具列、过滤与删除方式」、`.agents/rules/page-norm.md`「1. 主页面」 |
| 页面不渲染 sectionTitle；`TableBox` 的 `title` 要保留（弹窗内传列表区名称） | `.agents/rules/page-norm.md` |
| 弹窗五段式（顶部公共区 → `Tabs` → `Collapse` 分区 → 底部按钮区）、底部按钮居中 | `.agents/rules/page-norm.md`、`00-前端布局规范.md` §3.2 |
| 列表列顺序「序号 → 操作 → 数据列」；**每列显式 `width`**；`scroll={{ x }}` 用数值（各列宽 + `showNumWidth` + 选择列宽） | `.agents/rules/tableRule.md` |
| 行单击 = 选中（避开单元格链接 `stopPropagation`）；**主从表结构的维护、设置页面，主列表默认支持点击行选中（单选）、不显示行首选择列**（`rowSelection` 不传） | `.agents/rules/tableRule.md`「行交互与展示」 |
| 标识列 `'Y'` 渲染 `<Icon type="yes-green" />` 图标、`'N'` 渲染空、日期只到天、长文本 `ellipsis: { showTitle: true }`、表头与单元格不折行 | `.agents/rules/tableRule.md` |
| 常用操作按钮（增 / 删 / 改 / 查）带语义图标；**添加 / 查询 = `type="primary"` + 语义图标 + 文字（文字用 `<span>` 包裹），重置 = 白底 + `UndoOutlined` + 文案「重置」**；危险动作（删除 / 恢复 / 停用 / 终止 / 取消 / 作废 / 撤回）用危险样式，且执行前 `dialog.confirm` 二次确认；按钮颜色语义正确 | `.agents/rules/componentUseRule.md`「Button 颜色约定」「危险操作二次确认」 |
| 控件：`Input` 有 `maxLength`、`InputNumber` 有 min / max / precision、金额 `TextAmount`、拼音码随名称变更自动重算（图标仅手动重算；异步返回需丢弃过期结果）、「输入 + 触发」按规则处理、`ComboBox` 首项 / `valueIsObject`；日期 / 日期时间 / 日期范围的值完整显示（`RangePicker` 约 240px，6 列栅格用 `colSpan={4}`；`DateTimePicker` 约 200px） | `.agents/rules/componentUseRule.md` §表单控件 |
| 同一表单不混用 `Field` / `FieldGroup`；标签列 `auto` + 控件列 `minmax(0,1fr)`、**多列表单不设 `gap`（水平间距由 label padding 提供，组内 8px / 组间 16px）**；危险动作按钮 `type="primary" danger`、行内链接 `type="danger"`；必填 / 校验落 `required` / `rules`（红框 + 字段提示）；`rules.message` / `new Error(...)` / `placeholder` 等只接受字符串的位置用 `i18n.xxx.props.text`；分区用 `Collapse ghost expandIconPosition="end"` | `.agents/rules/componentUseRule.md` §表单控件、§Button 颜色约定、§校验与联动、`.agents/rules/page-norm.md`「2. 对话框」；数值见 `00-前端布局规范.md` §3.3–§3.4 |
| 底部按钮顺序按 `page-norm.md`「2. 对话框」默认口径（辅助动作在前、主操作（`type="primary"`）在末、居中；遗留截图仅作参考）；**复位按钮文案统一「重置」**（`i18n.reset`，不用「清除」）、操作类按钮防抖（新侧不实现快捷键） | `.agents/rules/page-norm.md`「2. 对话框」、`.agents/rules/componentUseRule.md`「按钮防抖（操作类按钮必做）」 |
| `componentId` 三处一致、service 传 `this`、effect 的 `context` 挂在第一个参数、`message.json` 齐全 | 本文 §1–§4 |
| 样式挂页面根 class（BEM + CSS Modules）、复用优先、无内联硬编码宽高；新增 class 前先搜 `src/pages` 同类组件现有写法（含换行写法），`Divider` / `Button` / `Tag` 优先默认样式或全局工具类 | `.agents/rules/pageStyleRule.md`「6. 复用优先与最小化自定义样式（强制）」、`.agents/rules/FrontNormalize.md` |

### 10.3 留痕

体检命令与结果（ERROR 0 / WARN n）写进 `_进度台账.md` 当轮次行——**没跑体检、没留痕，就视为没完成**。静态检查 / 手测命令见 §7；元素级截图与留证见 [e2e-verification.md](e2e-verification.md) §4.1。
