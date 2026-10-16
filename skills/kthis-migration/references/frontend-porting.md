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

- **何时做**：先把功能与交互跑通（文案直接写中文）；待该批界面稳定后，按「i18n 补齐」阶段统一抽成 `message.json`，不阻塞迁移进度。
- **文案来源（补齐时）**：中文文案要从遗留 `messages.properties`（GBK）转码后重录，不要复制字节。
- **补齐时**：**每个菜单页面（页面目录）一份 `message.json`**（主页面 / 弹窗 / 侧滑共用）：`{ componentId, zh_CN: {...}, en_US: {...} }`（**只写 `zh_CN` 即可**，其余语言按需再补）；用 `createMessage` / `getCommonMessage` / `formatMessage`；文案要在**运行时动态取**（render 内 / effect 内），别在组件外部先取成常量，否则切语言不刷新。
- **不要因 defer 而省**：注册与权限**不依赖文案** —— `componentId` 先落地（**三处一致**见 §1）；补齐 i18n 时再让 `message.json` 的 `componentId` 对齐。

## 5. 会踩的坑

- **禁止用 `updateState` 改二级数据结构**，复杂 state 变更写专门 reducer。
- 表格 `key` 用 `${id}_${index}`，**不要用 index**；`VirtualTable` 的 `vid` 命名 `模块_文件名_xxx`。
- ESLint 禁导：`moment`（用 dayjs）、`lodash` / `lodash/*`（用 `import { x } from 'lodash-es'`）、`@brickio/ui`（用 `@/base/ui`）。
- 路径别名 `@brickio/ui/*`、`@webhis/shared/*` 解析到 packages 的**编译产物 `es/`**；改 `packages/*/src` 不会即时生效，需重新构建（见 §7）。
- 生产构建剥离所有 `console.log`，调试日志别指望上线还在。
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

1. **先用已有组件表达**：先查 `@/base/ui` / `@brickio/ui` / `src/common` 里有没有现成组件（表单 / 栅格 / 列表 / 只读展示），能直接用就用，不要自己拼 DOM / 写 CSS。
2. **用组件 props 或仓库既有惯例解决**：能用 props（如 `GridFormAntd` 的 `templateColumns`、分区标题 class、`Collapse`）或仓库既有写法（如「只读文本 + 点击选择」用只读 `Input` + `suffix` 图标）表达，就不新增自定义布局代码。
3. **确实要改公用组件时，先量化引用面**：`grep` 统计全仓引用处数——引用面小、且改动能收敛问题（不扩散成新 props / 新分支）才改；引用面大（几十处以上）**不要顺手改**，把「公用组件增强」记为一个独立待办并说明。
4. **页面级临时 CSS 是最后手段**：只在以上都不可行时使用，且要在代码注释 / MR 里写清为什么不能走前三条；作用域挂页面根 class、不用 `!important` 压制。

## 9. 表单与对齐细则（迁移特有坑）

> 通用栅格 / 密度 / 成组对齐见迁移文档的 `00-前端布局规范.md` §3.4；本节只记实现阶段特有的对齐坑。

- **同一表单不要混用 `Field` 与 `FieldGroup`**：`Field`（栅格表单项）走 antd `Form.Item`，**自带 24px 底边距**（整行约 54px）；`FieldGroup`（栅格分组）**没有底边距**（整行约 30px）。混用 → 行高参差、看起来「标签 / 文本 / 控件没对齐」。行距统一由默认底边距提供，**不要**再写 `margin` / `padding` 去补。
- **「只读文本 + 点击选择」用只读 `Input` + `suffix` 图标**，不要自建布局 div，也不要用 `FieldGroup` 拼：

  ```jsx
  <Field label="<字段标签>" name="<fieldName>">
    <Input readOnly suffix={<SearchOutlined className={style.suffixIcon} onClick={handleOpen} />} />
  </Field>
  ```

  ```css
  .suffixIcon {
    cursor: pointer;
  }
  ```

  「输入 + 触发按钮」同理用 `suffix` 图标，不要另起一行 `Button`。**拼音码 / 助记码**用输入框 `suffix` 图标（**`id=kticon-font`**）生成；**名称（描述）字段更新时自动触发重算对应拼音码**，无需用户手动点击。
- **选择类弹窗**：列表上方的查询 / 搜索行（`searchRow`）放到表格 `toolbar` 的**右侧**，如果能放下就不单独占行（见迁移文档 `00-前端布局规范.md` §5）。
- **左右对照的列表必须等高**：`scroll.y` 只是 **max-height**，数据少时列表会塌陷、左右底部不齐 → 用**固定高度**（如两列表容器固定 360px），空态与有数据都要对齐；固定高度优先用组件现有 props，组件缺这个能力就按「公用组件增强」另立任务。表头不要被裁字：列宽按表头文字给足（`width` / `minWidth`）。
- **修复后自查**：同一分区内各行行高 / 行距一致（浏览器量各行 y 坐标，确认间隔相等）；左右表 / 上下组件底部对齐，空态与有数据表现一致；`lint` 通过 + 浏览器实测走一遍交互闭环（打开弹窗 → 选择 → 回填）。

## 10. 落地前自查清单

写完一个界面（页面 / 弹窗 / 页签）**立刻**逐条核对 —— 每条都能在代码或截图上判定，不要靠「感觉差不多」。**布局 / 视觉条目的规则出处是迁移文档 `00-前端布局规范.md`（含其 §9 验收清单）**：下面是**代码落地**时的快速核对版，与规范册冲突时以规范册为准。

**结构与列**
- [ ] 表单在**弹窗 / 侧滑**里，不在页面主体；新增 / 编辑同一个弹窗（按入参区分）
- [ ] 弹窗五段式：`Modal` > 顶部公共区 > `Tabs` > `Collapse` 分区 > 底部按钮区
- [ ] 列表列顺序 **序号 → 操作（编辑 / 删除）→ 数据列**；序号跨页连续
- [ ] 页面不显示分区标题；列表页 = 查询条件 + 工具条（左查询 / 右按钮）+ 表格
- [ ] 弹窗底部按钮居中（框架 `FooterPortal` / antd Modal footer 皆居中）

**栅格与分区**
- [ ] 每行 **3~4 对**「标签 + 控件」（密集页签 4 对，辅助弹窗 ≥3 对）
- [ ] `templateColumns`：标签列 `auto`、控件列 `minmax(0,1fr)`（**不裸用 `1fr`**）；极短字段 `minmax(0,120px)`
- [ ] 同一分区标签宽统一；`gutter` 10；控件高 30px
- [ ] 分区用 `Collapse ghost expandIconPosition="end"`；禁用用 `disabled`（不是 `visible`）

**控件**
- [ ] 同一表单**不混用** `Field` / `FieldGroup`（见 §9）
- [ ] 「只读文本 + 点击选择」用只读 `Input` + `suffix` 图标，没有自建布局 div
- [ ] `Input` 有 `maxLength`；`InputNumber` 有 min / max / precision；金额用 `TextAmount`
- [ ] 拼音码用输入框 `suffix` 图标（`id=kticon-font`），名称（描述）更新时自动重算
- [ ] `ComboBox` 的必填 / 非必填空首项、`valueIsObject` 处理正确

**表格与按钮**
- [ ] `rowKey` 不用 index（必要时 `${id}_${index}`）；`VirtualTable` 的 `vid` 为 `模块_文件名_xxx`
- [ ] `scroll={{ y }}` 配容器 `height: 100%`（`kt-tableScroll`）
- [ ] 按钮颜色语义正确（危险操作用 `type="primary" danger` 等）；常用操作按钮（增 / 删 / 改 / 查）带语义图标
- [ ] 删除方式与业务相符（操作列单行删除 / 多选批量删除）；选择类弹窗的搜索行并入表格 `toolbar` 右侧
- [ ] 行单击=单选；表头与单元格默认不折行；日期范围只到天；长文本列 `ellipsis` 悬浮完整
- [ ] 底部按钮顺序与截图核对一致、末尾「清除(L)」；快捷键标 `(A)` 并绑定 Alt+A；操作类按钮有防抖

**样式**
- [ ] 样式挂在页面根 class 下（BEM + CSS Modules）；**无 `!important`**；无内联硬编码宽高
- [ ] 复用优先：公共组件 / 公共 class 都用上了，没自造轮子

**可 grep 的自查**

```sh
grep -rn '!important' src/pages/<mod>/              # 应为 0
grep -rn 'nth-child\|nth-of-type' src/pages/<mod>/  # 选择器应语义化
grep -rnE 'width: ?[0-9]+px' src/pages/<mod>/       # 硬编码宽高逐条确认
```

静态检查与手测命令见 §7；截图与留证见 [e2e-verification.md](e2e-verification.md) §4.1（元素级截图）。
