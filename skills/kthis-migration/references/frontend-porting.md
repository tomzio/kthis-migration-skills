# 前端移植（webhis-front）

> 仓库根 = 项目根 `.agents/paths.env` 的 `WEBHIS_FRONT_DIR`（细节见 [repos-and-map.md](repos-and-map.md) §路径配置）；下文路径均相对该根。
>
> ⚠️ **通用规范以 `webhis-front` 技能 + 仓库 `.agents/rules/*` 为强制基准**（`FrontNormalize.md`、`page-norm.md`、`tableRule.md`、`componentUseRule.md`、`componentActionRule.md`、`servicesApiRule.md`、`pageStyleRule.md`）；**生成或修改前端代码必须遵循**，冲突时以它为准。本文件**只列迁移特有**的落点与坑。

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

> **迁移实现阶段可先写中文字面量，便于开发调试；i18n 作为独立的后续阶段统一补齐。** （`message.json` / `createMessage` 的完整规范以 `webhis-front` 技能 + `.agents/rules/*` 为准）

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
- **表单布局**：同一表单不要混用 `Field` 与 `FieldGroup`（`Form.Item` 自带 24px 底距、`FieldGroup` 没有 → 行距参差、看着没对齐）；左右对照列表要**固定高度**（`scroll.y` 只是 max-height）。细节见 `webhis-front` 技能的 `references/form-layout.md`，本仓库强制版在 `.agents/rules/componentUseRule.md` / `pageStyleRule.md`；**遇到没对齐的问题按 §8 处置顺序判断改哪里**。

## 6. 布局与样式

> 完整规范以 `webhis-front` 技能 + 仓库 `.agents/rules/pageStyleRule.md`、`docs/FrontNormalize.md` 为准；迁移分册的排版对齐跨模块通用册 `docs/migration/00-前端布局规范.md`。

- 骨架：折叠查询表单 + 结果表格（分页 / 排序 / 状态切换）+ 左分类树 + 操作列；编辑用宽弹窗或多 Tab 表单，子弹窗独立打开。
- **布局紧凑（重点）**：表单用 `GridFormAntd`（`@/base/ui`），不要用零散 `Row`/`Col` 拼。`templateColumns` 里**标签列用 `auto`、控件列用 `minmax(0,1fr)`（不要裸 `1fr`）**，否则控件被拉满、留大片空白。密度：普通弹窗 / 页签**每行 3~4 对「标签 + 控件」**，密集页签 4 对，辅助弹窗至少 3 对；3 对 → `"auto minmax(0,1fr) auto minmax(0,1fr) auto minmax(0,1fr)"`，4 对 → 再重复一组。极短字段（年月 / 百分比 / 时长）用 `minmax(0,120px)` 限宽，**不要拉伸**；长文本（备注 / 诊断）才整行。同分区同行列对齐（标签宽统一、gutter 10）。参考实现：`src/pages/<mod>/<feature>/<XxxDialog>.jsx`（同一分区内 4 对/行）。**成组与对齐**：业务相关 / 事件联动的控件要挨在一起（勾选与联动控件、区间上下限、代码与名称）；同组字段不跨行拆散，放不下时整组挪行，必要时可适当调整控件顺序。
- 复用优先：`src/common`（table / advancedForm / combobox / patienttree）与 `@/base/ui`，**不自行造轮子**；最小化自定义 CSS，禁止 `!important`。
- **「标签 / 文本 / 控件没对齐」类问题**（行距参差、留白怪异、控件被拉满等）→ 按 **§8 处置顺序**决定改哪里，不要上手就写 CSS 或改公用组件。

## 7. 验证（无测试框架）

```sh
yarn lint:js                                          # eslint，看【新增】错误/警告
npx tsc --noEmit -p tsconfig.root.json                # 类型检查；跑完删 tsconfig.root.tsbuildinfo
yarn build:deps                                       # 仅当改了 packages/*
yarn dev / yarn start                                 # 起 dev server 手测
```

提交前手测：新增 / 编辑、必填 / 条件必填、显隐 / 禁用 / 联动、校验提示语、保存 / 删除 / 调价流程与遗留一致。dev 代理（`/his`、`/flow`、`/DCWriterDemo`）配在 `scripts/rspack.dev.js`，不在 `.env`。

> 浏览器端到端走查（含**可选**的 Playwright MCP 驱动方式、清单 P1–P10、证据留存格式）见 **[e2e-verification.md](e2e-verification.md)**；缺 Playwright 不阻塞。

## 8. 布局 / 对齐问题的处置顺序

遇到「标签 / 文本 / 控件没对齐、行距参差、留白怪异」这类问题，**自上而下**判断，前一步能解决就不要往下走：

1. **先用已有组件表达**：先查 `@/base/ui` / `@brickio/ui` / `src/common` 里有没有现成组件（表单 / 栅格 / 列表 / 只读展示），能直接用就用，不要自己拼 DOM / 写 CSS。
2. **用组件 props 或仓库既有惯例解决**：能用 props（如 `GridFormAntd` 的 `templateColumns`、分区标题 class、`Collapse`）或仓库既有写法（如「只读文本 + 点击选择」用只读 `Input` + `suffix` 图标）表达，就不新增自定义布局代码。
3. **确实要改公用组件时，先量化引用面**：`grep` 统计全仓引用处数——引用面小、且改动能收敛问题（不扩散成新 props / 新分支）才改；引用面大（几十处以上）**不要顺手改**，把「公用组件增强」记为一个独立待办并说明。
4. **页面级临时 CSS 是最后手段**：只在以上都不可行时使用，且要在代码注释 / MR 里写清为什么不能走前三条；作用域挂页面根 class、不用 `!important` 压制。

## 9. 表单布局与对齐（短规则）

> 下面是**短小自洽**的规则（技能单独加载时也够用）；目标仓库若有自己的强制版本（`.agents/rules/` 下的组件 / 样式规则），**以它为准**。

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

  「输入 + 触发按钮」（如按内容生成助记码）同理用 `suffix` 图标，不要另起一行 `Button`。
- **左右对照的列表必须等高**：`scroll.y` 只是 **max-height**，数据少时列表会塌陷、左右底部不齐 → 用**固定高度**（如两列表容器固定 360px），空态与有数据都要对齐；固定高度优先用组件现有 props，组件缺这个能力就按「公用组件增强」另立任务。表头不要被裁字：列宽按表头文字给足（`width` / `minWidth`）。
- **修复后自查**：同一分区内各行行高 / 行距一致（浏览器量各行 y 坐标，确认间隔相等）；左右表 / 上下组件底部对齐，空态与有数据表现一致；`lint` 通过 + 浏览器实测走一遍交互闭环（打开弹窗 → 选择 → 回填）。
