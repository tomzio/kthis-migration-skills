# 遗留侧端到端追踪

迁移的第一步、也是最关键的一步，是在遗留系统里把目标功能**端到端跑通并留下证据**。新侧 UI 技术栈完全不同，照搬实现没有意义；要搬的是**字段、码表、默认值、显隐/禁用、联动、校验、保存/删除/调价流程与其调用顺序**。

> 原则：**代码优先于文档**。文档与源码冲突时信源码。截图（`<前端>/docs/migration/images/`）只用于核对标签与控件顺序，完整功能以代码为准；截图引用前先按页面功能改名（见 `references/screenshots.md`）。

> 路径说明：遗留仓库根目录由**项目根** `.agents/paths.env` 的 `KTHIS_LEGACY_DIR` 决定（缺失时跑 `scripts/setup-paths.sh` 生成）。下文 `<遗留>` 即该目录，`<skill根>` 指本 skill 根目录。

## 遗留架构速览

厚客户端架构，按「项目分层」组织，同一业务域拆成最多 4 个兄弟 Eclipse 项目：

| 层 | 项目 | 内容 |
| --- | --- | --- |
| 模型（客户端+服务端共享） | `com.kompakar.ehealth.model.<mod>.<layer>` | `bo`/`view` DTO、常量、`action` 契约；`server.<mod>.<layer>.service` 的 `I*Service` **接口** |
| 服务端实现 | `com.kompakar.ehealth.server.<mod>.<layer>` | `service` impl、`dao`（`dao/ibatis/maps/*.xml` + SqlMapClient DAO）、`context.xml`（Spring 2.x 装配） |
| UI | `com.kompakar.ehealth.ui.<mod>.*` | SWT/JFace 视图（`plugin.xml` 扩展）；`.biz`=业务、`.mstr`=主数据维护 |
| 三方库封装 | `com.kompakar.ehealth.lib.*` | hibernate/jdbc/poi/json… 的 jar 包装 |

层后缀常见：`.common`（共享）、`.module`（核心）、`.biz`（上层业务）。
通信：客户端把请求对象 Java 序列化后经 `com.kompakar.ehealth.frame.communicate.Communicate` POST 到服务端 `EntryServlet`；UI 调 `model.*` 的 `I*Service` 接口，服务端把 impl 装配为 Spring bean。
核心基础项目：`com.kompakar.ehealth.base`（ThreadLocal `SessionFactory`、cache、i18n、base view）、`com.kompakar.ehealth.frame`（`Communicate`、`InvokeUtil`、日期/字符串工具）。

## 定位入口：从界面到代码

1. **拿到界面标识**：遗留 Editor ID / Page ID / 中文标题（形如 `ui.<mod>.<layer>.<feature>.XxxEditor` 与界面标题）。
2. **找 UI 插件**：在该业务的 `com.kompakar.ehealth.ui.<mod>.*` 项目里搜 Editor/Page 类。
   - 看 `plugin.xml` 的 extension 定义（Editor / View / Page 注册）。
   - 主数据维护通常在 `ui.<mod>.mstr`，业务界面在 `ui.<mod>.biz`。
3. **顺着 UI go through**：SWT 视图 → 控件的监听事件（`SelectionListener` 等）→ 调用的 `action` / `I*Service` 方法。
4. **找服务端实现**：在 `com.kompakar.ehealth.server.<mod>.<layer>` 找对应 `I*Service` 的 impl。
5. **找 SQL**：impl 调 DAO → `dao/ibatis/maps/*.xml` 里的 statement（iBATIS），拿到表名、字段、过滤与连接条件。
6. **对照表结构**：查 Oracle（连接串见 `<遗留>/eHealth/WebContent/WEB-INF/jdbc.properties`，只读）。

跨模块调用走 `com.kompakar.ehealth.model.bridge` 的 `*BridgeService`；地区化 / 三方集成按地区或渠道拆分在 `model.interfaces.*` / `server.webservice.*`（命名常带地区或渠道标识）。

## GBK 检索

源码是 **Java 6 + GBK**。终端出现乱码是预期，不是 bug。按中文关键词或标识符检索时，不能直接 `grep`（字节不匹配），先转码。

```sh
# 单文件转码查看
iconv -f GB18030 -t UTF-8 <文件> | less

# 用随 skill 提供的脚本按中文/标识符检索（内部 iconv + grep；目录省略时默认取路径配置的 KTHIS_LEGACY_DIR）
<skill根>/scripts/grep-gbk.sh "<界面标题或类名>" com.kompakar.ehealth.ui.<mod>.<layer>

# 只列命中文件（不打印行内容），用于快速定位
<skill根>/scripts/grep-gbk.sh "<中文关键词>" <目录> --files
```

> `rg`（ripgrep）在本机通常未安装；脚本用 `find` + `iconv` + `grep` 实现。检索大目录会稍慢，尽量把 `<目录>` 缩到具体项目/子目录。

## 文案与码表

- **界面文案/i18n 原文**在 `com.kompakar.ehealth.ui.i18n.message/src/com/kompakar/ehealth/ui/<mod>/<layer>/i18n/messages.properties`（GBK）。提取后按新侧组件 `message.json` 重录（UTF-8）。
- **码表/下拉**：记录遗留用的 code（常量类，`ICodeMstrConst` / `ICodeMstrDetailConst` / `ISysConst.IND_YES|IND_NO` 等）与展示值。新侧优先复用 `/his/common/dropdown/*` 与既有 search 接口，**code 与遗留保持一致**，不要自建字典。
- **系统参数**：界面行为常由系统参数驱动（参数名多为 `<域>_<语义>` 形式的大写常量）。逐条记录参数名、取值域、影响，新侧用 `getParameters([...])` 读取（详见本模块 00/21 册的系统参数总表）。

## 证据笔记模板

追踪完输出一份简短笔记，供实现与复核：

```
功能：<中文名>（遗留 Editor/Page ID）
入口：<ui 插件路径/类> 
链路：<视图类> → <事件/action> → <I*Service.method> → <server impl#method> → <mapper.xml#statement> → <表>
字段：<字段中文 - 列名 - 类型 - 必填/默认/联动>  (来源: 文件:行)
码表：<下拉/下拉 code 列表>  (来源: ...)
校验：<规则 + 提示语原文>  (来源: ...)
流程：<保存/更新/删除/调价 的调用顺序、事务边界、级联创建/删除>
系统参数：<参数名 = 影响>
新侧落点：后端 webhis-<mod>-*；前端 src/pages/<mod>/...
存疑：<截图/文档与代码不一致处、待确认项>
```

## 常见陷阱

- 同一弹窗类的**「新增」与「编辑」界面不同**（新增态可能只显示主页签、编码可编辑性由参数决定、保存后就地切换到编辑态）。迁移时必须分别还原——见本模块 00 册「新增与编辑的界面差异」。
- 逻辑删除 `defunct_ind`、审计字段、多院区 `entity_mstr_id` 是通用约定，别漏。
- 文档/截图可能滞后于代码（迁移文档可能写着「尚无页面代码」，而工作区其实已落地）。以工作区代码为准。
