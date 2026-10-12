# 后端移植（webhis-server）

> 仓库根 = **项目根** `.agents/paths.env` 的 `WEBHIS_SERVER_DIR`（每个开发者不同；缺失时跑 `scripts/setup-paths.sh` 生成）；下文路径均相对该根。

把遗留 `server.*` impl / `dao/ibatis/maps` / 表映射为 WebHIS 后端接口。**Spring Boot 2.7.8 单体 + MyBatis 手写 XML**，Java 8 / UTF-8，入口 `webhis-starter-api`（端口 9800），URL 前缀 `/his/<mod>/...`。

## 四模块分层

每个业务域拆成 4 个 Maven 模块，包名固定：

| 模块 | 包 | 角色 |
| --- | --- | --- |
| `webhis-<mod>-api` | `com.karrytech.webhis.<mod>.api.controller` | `@RestController`，无基类；直接 `@RequestBody` 收 VO、直接 return VO/List |
| `webhis-<mod>-server` | `...<mod>.server.service` | 接口 `I<Name>Service`；VO 放 `.server.vo` |
| `webhis-<mod>-server-impl` | `...<mod>.server.service.impl` / `.server.dao` | impl `<Name>Service extends BaseService`；DAO `<Name>Dao extends MybatisBaseDao`；XML 在 `src/main/resources/mapper/*Dao.xml` |
| `webhis-<mod>-model` | `...<mod>.model` | 实体 `extends BaseModel`；有 JPA 注解但**非 JPA 运行**（内部 active-record：静态 `get(id)` + `finder()`） |

跨域调用直接 `@Autowired` 对方的 `-server` / `-server-impl`（单体，无 Feign）。`webhis-starter-api` 聚合所有 `*-server-impl`。

## 新增接口四步

1. `-api`：加 `@PostMapping`（或 `@GetMapping`）方法，`@RequestMapping("/his/<mod>/<resource>")`。
2. `-server`：加 `I<Name>Service` 方法，必要时加/改 VO（`...server.vo`）。
3. `-server-impl`：实现方法。
4. 需要新 SQL 时：DAO 加方法 + `resources/mapper/<Name>Dao.xml` 加 statement。

约束与惯例：
- **无统一 Result 包装**：controller 直接返回 VO / List / `PageableRespVo<T>`。
- 分页：`PageableRespVo<T>` + `IPageableService.findPageableList(dao, "sqlId", params, page)`；PageHelper 方言固定 oracle。
- MyBatis-Plus 在依赖里但**业务不用**（不继承 `BaseMapper`/`ServiceImpl`）；SQL 全走 `MybatisBaseDao` + 手写 XML + `Crud finder()`。mapper 全局扫描 `classpath*:mapper/*Dao.xml`。
- DAO 方法习惯：`findList` / `findUnique` / `findRowCount` / `call(procName, params)`。
- 存储过程调用（如价格调整 `PrMaterialPriceAdjustMent`）保留 `call(...)` 形式。

## iBATIS 2.x → MyBatis 3 改写

| 遗留 iBATIS | MyBatis 3 |
| --- | --- |
| `#param#` | `#{param}` |
| `$literal$` | `${literal}` |
| `<isNotEmpty property="x">` | `<if test="x != null and x != ''">` |
| `<dynamic prepend="WHERE">` | `<where>` / `<if>` |
| `resultClass` / `resultMap` 列名映射 | `resultType` / `resultMap`，注意 oracle 大写列名 |

**安全**：`${...}` 拼接的表名 / 排序列必须做白名单校验，防注入（遗留 `$...$` 同样风险）。

## 主数据通用约定

- `defunct_ind` 逻辑删除（'Y'/'N'，默认过滤 'N'）；删除/停用走置 'Y'。
- 审计字段 `created_by` / `created_date_time` / `last_updated_by` / `last_updated_date_time`（部分含 `cancelled_*`）。
- 多院区 `entity_mstr_id` 必须保留。
- 编码/中文：**绝不直接拷贝遗留 GBK 字节**，转码或重录（新侧 UTF-8）。

## 认证与会话

- `/his/**` 按序挂 6 个拦截器（`autoconfig/ApiWebMvcConfigurer.addInterceptors`）：限流 → ExtRequest → Session → ExtSession → 日志 → `RequestAuthInterceptor`。前 5 个来自闭源框架 `com.karrytech.framework.require.starter.interceptor.*`；登录会话放 ThreadLocal `com.karrytech.util.session.SessionFactory`。
- **免登录白名单是 `interceptor/RequestAuthInterceptor` 的静态 `IGNORED_PATHS`**（`URIPaths` 只是 AntPath 匹配器）。新增免登录接口必须往白名单加路径，否则 401。
- 14 个收费/退费相关 controller（13 个在 `webhis-pa-api` + `om-api/OrderDetailController`）在方法内调 `createSession()` 自建系统会话（`userMstrId=0`、系统管理员、`entityMstrId=1`），移植这类接口时一并保留；部分把 `@Transactional` 标在 controller 层。
- **无全局 `@ControllerAdvice`**：业务直接 `throw new BizException(...)` 或其子类，由闭源框架统一处理响应。

## 会踩的坑

- **模块名 ≠ 业务归属**：`webhis-charge-*` 里没有业务代码；收费在 `webhis-pa-*` / `webhis-common-*`。迁移前先读代码。
- 包名多为 `com.karrytech.webhis.<mod>`，但 `webhis-emr-*` / `webhis-record-*` 仍是 `com.karrytech.his.*`；`webhis-common-server-impl` 里还留着 `com.kompakar.ehealth.base.util`。
- 响应形态不统一（裸对象/数组 vs `{code,data}`），前端按各端点实际形态处理。
- 构建需 **JDK 8**；必须用仓库根 `settings.xml`（内网 Nexus）。
- `application-jdbc.properties` 里有未解决的 Git 冲突标记，实际生效连接是 `192.168.21.155:1521/testbjhis`（`ihis`）；改库配置前看清生效行。
- macOS 下 Oracle 连内网库要 `startup.sh` 里的 no-socks-proxy `-javaagent`，勿删 `tools/no-socks-proxy-agent.jar`。

## 构建与验证

```sh
./startup.sh dev                                    # 编译 + 启动
mvn -pl webhis-<mod>-server-impl -am install -Dmaven.test.skip=true   # 只构建单模块 + 依赖
```
无真实测试（各 `AppTest` 是桩），一律 `-Dmaven.test.skip=true`；**不要声称测试通过**。验证靠启动服务 + 前端/接口联调手测。

## 参考文档

`<后端>/docs/<功能>/`（00 总览 / 01 表结构 / 02 接口 / 03 模型结构 / 04 清理记录）、`docs/接口清单-迁移新增端点.md`、根 `AGENTS.md`。
