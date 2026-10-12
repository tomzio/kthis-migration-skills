# 三仓库、命令与逐层映射

迁移工作固定横跨三个仓库。**遗留是业务真源，新侧是目标**。每个仓库根目录的 `AGENTS.md` 是最新最权威的本地约定，本文件只做速查与导航。

## 路径配置（每个开发者不同）

三个仓库的绝对路径因机器而异，统一从**项目根** `.agents/paths.env` 读取（唯一配置文件，本机私有、已 gitignore），不要假设固定路径：

| 变量 | 仓库 |
| --- | --- |
| `KTHIS_LEGACY_DIR` | 遗留 KTHIS / eHealth 工作副本 |
| `WEBHIS_FRONT_DIR` | 新前端 webhis-front |
| `WEBHIS_SERVER_DIR` | 新后端 webhis-server |

- 生成 / 校验：`scripts/setup-paths.sh`（自动探测并写出到项目 `.agents/paths.env`；`--legacy/--front/--server <dir>` 显式指定；`--out <file>` 改写出位置；`--print` 仅查看当前值）。
- `.agents/paths.env` 是本机私有文件，已被 `.gitignore` 忽略；模板见 `.agents/paths.env.example`。
- 下文凡写 `<遗留>` / `<前端>` / `<后端>`，均指上述变量解析出的绝对路径；执行 skill 自带脚本用「skill 根目录 + 相对路径」。

## 仓库

| 仓库 | 路径变量 | 说明 |
| --- | --- | --- |
| 遗留 KTHIS / eHealth | `KTHIS_LEGACY_DIR` | SVN 工作副本，~350 个 Eclipse 项目平铺；Java 6 / GBK；Eclipse RCP 3.7 + SWT/JFace 客户端 + `eHealth.war` 服务端（Spring 2.x + iBATIS + Hibernate） |
| 新前端 WebHIS | `WEBHIS_FRONT_DIR` | React 18.3 + antd 4.24 + dva 3.0.0-alpha + @formily 2；rspack（dev）/ webpack（prod）；yarn workspaces monorepo |
| 新后端 WebHIS | `WEBHIS_SERVER_DIR` | Spring Boot 2.7.8 + MyBatis（手写 XML）单体；Maven 多模块；Java 8 / UTF-8；入口 `webhis-starter-api`（端口 9800） |

遗留侧入口说明（**若存在**）：`<遗留>/AGENTS.md`（与同目录 `CLAUDE.md` 内容相同，通常只含项目简介与架构速览；没有也不影响，直接读源码即可）。⚠️ 遗留侧**不一定**有迁移清单或原始分析文档；若另有 `docs/migration/` 之类的原始材料，只作**参考线索**，一律**以源码为准**。

## 常用命令

### 遗留（只读对照）
```sh
# 读取 GBK 源码
iconv -f GB18030 -t UTF-8 <文件> | less
# 按中文/标识符检索（目录省略时默认取路径配置的 KTHIS_LEGACY_DIR）
<skill根>/scripts/grep-gbk.sh "<关键词>" <目录>
```
遗留库是 Oracle；连接串/账号在 `<遗留>/eHealth/WebContent/WEB-INF/jdbc.properties`（对照表结构时**只读**查询）。

### 前端（`WEBHIS_FRONT_DIR`，Node ≥ 18）
```sh
yarn                 # 安装（postinstall 自动 turbo 构建 packages）
yarn start           # rspack dev server，仅主应用热更，http://localhost:9000
yarn dev             # 主应用 + packages 同时热更（日常开发用这个）
yarn build:deps      # 改 packages/* 后必须执行，否则主应用拿旧产物
yarn lint:js         # eslint（唯一有效的 lint:js 用法见下）
yarn analyze         # 打包体积分析
```
- 验证：`yarn lint:js` + `npx tsc --noEmit -p tsconfig.root.json`（跑完删 `tsconfig.root.tsbuildinfo`）。`yarn lint:ts` 是坏的（指向已改名的 `tsconfig.base.json`）。**无测试框架**。
- 路径别名 `@brickio/ui/*`、`@webhis/shared/*` 解析到 packages 的**编译产物 `es/`**，不是 `src/`。改 `packages/*/src` 必须 `yarn build:deps`。

### 后端（`WEBHIS_SERVER_DIR`，JDK 8）
```sh
./startup.sh              # build：编译打包并启动（jar 模式）
./startup.sh dev          # 编译 starter-api + 依赖后 spring-boot:run
./startup.sh stop         # 杀 9800 端口进程
mvn -pl webhis-<mod>-server-impl -am install -Dmaven.test.skip=true   # 只构建某模块
```
- 必须用仓库根 `settings.xml`（内网 Nexus `maven.karrytech.com`，闭源 `com.karrytech.*` 制品只在上面）。
- `mvn` 默认 JDK 21 会编译失败，需 `JAVA_HOME` 指向 jdk-1.8。
- macOS 连内网 Oracle 会被系统 SOCKS 代理干扰；`startup.sh` 会用 `tools/no-socks-proxy-agent.jar`（`-javaagent`）清除，勿删。

## 逐层映射（遗留 → WebHIS）

| 遗留 | WebHIS 后端 / 前端 |
| --- | --- |
| `ui.<mod>.*` SWT 视图（`plugin.xml` 扩展） | 前端 `src/pages/<mod>/...` React 页面/弹窗 |
| `model.<mod>.*` 的 `action` 契约 + `I*Service` 接口 | `webhis-<mod>-api` controller + `webhis-<mod>-server` 的 `I*Service` |
| `model.<mod>.*` 的 `bo` / `view` DTO（可序列化） | `vo`（在 `-api` / `-server`） |
| `server.<mod>.*` impl + `dao/ibatis/maps/*.xml` | `webhis-<mod>-server-impl` impl + `resources/mapper/*Dao.xml` |
| `context.xml`（Spring 2.x 装配） | 注解 DI（`@Autowired`/`@Service`），starter 扫描全部模块 |
| `Communicate`/`EntryServlet` 序列化 HTTP | JSON REST `/his/<mod>/...`，前端用 `@webhis/shared/utils/request` |
| `SessionFactory` ThreadLocal（当前用户/院区） | Spring Security + JWT（后端 `SessionFactory` ThreadLocal） |
| 遗留 i18n `messages.properties`（GBK） | 前端组件级 `message.json`（UTF-8） |

## 模块编码：不要假设沿用

新旧模块编码**常常不一致**：可能被重命名、拆分、合并，也可能新侧凭空新增模块。两个已知陷阱：

- **同名却无业务代码**：新侧可能存在与遗留同名的模块，但其下并没有真实业务代码，功能实际落在相邻 / 其他模块里。
- **一拆多 / 多合一**：同一遗留模块可能被拆到多个新侧模块，或多模块被合并。

**动手前先读新侧代码（包路径 + 目录）确认目标模块，不要按名字推断。**

## 主数据通用约定（迁移时必守）

- 逻辑删除 `defunct_ind`：`'Y'` 无效 / `'N'` 有效，默认过滤 `'N'`；停用/删除置 `'Y'`。
- 审计字段 `created_by` / `created_date_time` / `last_updated_by` / `last_updated_date_time`（部分含 `cancelled_*`）。
- 多院区 `entity_mstr_id` 必须保留。
- 主键常为 `BigDecimal` 序列。
- iBATIS 2.x（`#param#`、`$literal$`、`isNotEmpty`）→ MyBatis 3（`#{param}`、`${literal}`、`if`/`where`）；`$...$` 拼接的表名/排序列必须校验防注入。

## 迁移文档索引

### 前端仓库 `<前端>/docs/`
- `migration/README.md` —— 迁移文档总索引。
- `migration/00-前端布局规范.md` —— 跨模块的**通用前端布局规范**（骨架 / 栅格 / 分区 / 组件映射 / 表格·按钮·尺寸约定 / 通用实现清单 / 验收清单），全仓库只一份，各模块分册引用而不重复。
- `migration/<NN>-<模块名>/` —— 每个功能模块一个目录，按界面聚合、从 00 连续编号（00 总览与通用约定、01 主页面、各弹窗外壳 / 页签 / 辅助弹窗、数据流程与接口、迁移实施计划、共享分区与复用矩阵），可作为「按页签拆分」的参考范例。
- `migration/images/` —— 遗留 SWT 截图，命名 `<功能序号>-<模块代号>-<界面英文名>.png`（模块用**新侧**代号）；**只用于核对标签与控件顺序**，完整功能以代码为准。截图识别 / 命名 / 引用规范见 `references/screenshots.md`，改可用 `scripts/rename-screenshots.sh`。
- `FrontNormalize.md` —— 前端开发规范（命名、组件用法、commit、复用优先/最小化 CSS）。
- `referrence/layers&modules.md` —— model 生命周期/baseModel 继承/增强 effects/callService/putPromise/i18n。
- `referrence/component_{form,layout,data,interaction,others}.md` —— 组件手册。
- `Directory.md`、`wpb总结.md`、`系统参数配置页面api.md`、`操作权限说明文档.md`。

### 后端仓库 `<后端>/docs/`
- `<功能>/00-总览.md`、`01-表结构.md`、`02-接口.md`（**端点清单，写前端请求层以它为准**）、`03-模型结构.md`（VO/模型全量字段）、`04-清理记录与遗留问题.md`（各模块目录结构与文件命名可能略有出入）。
- `接口清单-迁移新增端点.md` —— 迁移提交新增的跨域端点记录。

## 已落地样例（可作模板）

新侧 `src/pages/<mod>/` 下通常已有同类实现，可作为「主页面 + 多 Tab 编辑弹窗」的目录模板（具体命名以工作区为准）：

```text
src/pages/<mod>/<feature>/
├── <Feature>Page.jsx               页面（分类树 + 过滤 + 结果表）
├── <feature>PageModel.js           页面 model（extendPage）
├── <Feature>Dialog.jsx             编辑弹窗外壳（多 Tab）
├── <feature>DialogModel.js         弹窗 model（extendEditablePopup）
├── componentAction.ts              权限/操作声明
├── message.json / dialogMessage.json   i18n
├── sections/                       弹窗内共享分区（跨页签复用）
└── tabs/                           各页签
src/pages/<mod>/services/<feature>.js        服务层（/his/<mod>/**）
src/pages/<mod>/<mod>ComponentRegistry.js    组件注册表
```

**注意**：迁移文档可能写着「尚无页面代码」，但工作区其实已落地——**永远以当前工作区代码为准**，文档随后回填。

## 推荐落地流程

1. 读对应迁移分册，在遗留侧把功能端到端跑通：界面 → 事件 → 服务接口 → SQL → 表。
2. 按映射表逐层移植到新侧（后端接口 + 前端页面/弹窗/model/注册/i18n）。
3. 前端结构：折叠查询表单 + 结果表格（分页/排序/状态切换）+ 分类树 + 右侧抽屉或多 Tab 表单 + 操作列；排版与嵌套遵循对应模块的布局规范册。
4. 页面/弹窗按 `componentId` 注册进 `<mod>ComponentRegistry.js`，弹窗用 `app/openComponentPopup` 打开。
