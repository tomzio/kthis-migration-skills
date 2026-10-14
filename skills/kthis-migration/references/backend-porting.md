# 后端移植（webhis-server）

> 仓库根 = 项目根 `.agents/paths.env` 的 `WEBHIS_SERVER_DIR`（细节见 [repos-and-map.md](repos-and-map.md) §路径配置）；下文路径均相对该根。

把遗留 `server.*` impl / `dao/ibatis/maps` / 表映射为 WebHIS 后端接口。**Spring Boot 2.7.8 单体 + MyBatis 手写 XML**，Java 8 / UTF-8，入口 `webhis-starter-api`（端口 9800），URL 前缀 `/his/<mod>/...`。

> ⚠️ 框架公共类（`BaseModel` / `BaseService` / `MybatisBaseDao` / `BizException` / `PageableRespVo`）**不在本仓库**，来自闭源 `com.karrytech.framework.*` / `com.karrytech.util.*`（内网 Nexus）。查签名用 `javap` 或对应的 `-sources.jar`，不要以为「找不到就是没有」。

## 1. 四模块分层

每个业务域拆成 4 个 Maven 模块，包名固定：

| 模块 | 包 | 角色 |
| --- | --- | --- |
| `webhis-<mod>-api` | `com.karrytech.webhis.<mod>.api.controller` | `@RestController`，无基类；直接 `@RequestBody` 收 VO、直接 return VO/List |
| `webhis-<mod>-server` | `...<mod>.server.service` | 接口 `I<Name>Service`；VO 放 `.server.vo` |
| `webhis-<mod>-server-impl` | `...<mod>.server.service.impl` / `.server.dao` | impl `<Name>Service extends BaseService`；DAO `<Name>Dao extends MybatisBaseDao`；XML 在 `src/main/resources/mapper/*Dao.xml` |
| `webhis-<mod>-model` | `...<mod>.model` | 实体 `extends BaseModel`；有 JPA 注解但**非 JPA 运行**（active-record） |

- 四个模块的 parent 都是根 `pom.xml`（`com.karrytech:webhis-server`），版本用 `${project.version}`。
- 依赖方向：`-api` → `-server`；`-server` → `-model`；`-server-impl` → `-server`；`-model` → `common-model`。跨域调用直接 `@Autowired` 对方的 `-server` / `-server-impl`（单体，无 Feign）。
- 组件扫描是全局的（`ApiApplication` 上的 `@ComponentScan("com.karrytech")`），**没有 `@MapperScan`**。

## 2. 从零新建一个业务模块

模块已存在时跳到 §3；完全新建时四处都要改，漏一处就不生效：

1. **建 4 个模块目录**（参照同域已有模块）：`webhis-<mod>-api` / `-server` / `-server-impl` / `-model`，各带 `pom.xml`（parent = 根 pom，groupId/version 随父）。
2. **声明模块依赖**：`-api` 依赖 `-server`；`-server` 依赖 `-model`；`-server-impl` 依赖 `-server`。需要跨域时再依赖对方的 `-server` / `-server-impl`。
3. **注册进根 `pom.xml` 的 `<modules>`**（4 行都要加），否则根本不参与构建。
4. **注册进启动器** `webhis-starter-api/pom.xml`：依赖该域的 `-api` 与 `-server-impl`（`-server` / `-model` 会传递进来，不必显式加）。
5. **建包结构**：`...<mod>.api.controller` / `...<mod>.server.service` + `.server.vo` / `...<mod>.server.service.impl` + `.server.dao` / `...<mod>.model`。
6. **mapper 目录**：`webhis-<mod>-server-impl/src/main/resources/mapper/`（共享 mapper 放 `<mod>-common-server-impl`）。
7. 编译：`mvn -pl webhis-starter-api -am install -Dmaven.test.skip=true`。

## 3. 新增接口四步

1. `-api`：加 `@PostMapping`（或 `@GetMapping`）方法，`@RequestMapping("/his/<mod>/<resource>")`。
2. `-server`：加 `I<Name>Service` 方法，必要时加/改 VO（`...server.vo`）。
3. `-server-impl`：实现方法。
4. 需要新 SQL 时：DAO 加方法 + `resources/mapper/<Name>Dao.xml` 加 statement。

约束与惯例：

- **无统一 Result 包装**：controller 直接返回 VO / List / `PageableRespVo<T>`。仓库里**两种风格并存**（多数裸返回，少数 `CommonResult.success(...)`），新增时跟随所在模块的既有风格。
- 分页：`PageableRespVo<T>` + `findPageableList(dao, "sqlId", params, pageable)`；PageHelper 方言固定 oracle。
- 存储过程调用（如价格调整类）保留 `call(procName, params)` 形式。

## 4. model 层（active-record）

- 实体 `extends BaseModel`（闭源 `com.karrytech.framework.require.model.BaseModel`），带 `@Entity` / `@Table` / `@Id` / `@Column`；**有 JPA 注解但不是 JPA 运行**。
- 主键统一 **`BigDecimal`**。
- 写入是 active-record：`insert()` / `update()` / `save()` / `delete()` / `refresh()`（继承自闭源 `BaseCrudModel`）。
- **`get(id)` / `finder()` 不是基类方法**，每个实体自己声明静态方法，例如 `public static X get(BigDecimal id) { return Crud.crud(X.class).get(id); }`、`public static CrudFinder<X> finder() { return Crud.finder(X.class); }`。
- **审计字段由框架自动填**：`created_by` / `created_date_time` / `last_updated_by` / `last_updated_date_time` 是带注解的字段，`CrudDao.beforeModify` 从当前会话取值。框架**只覆盖未被显式标记修改的字段**：
  - 业务 setter 必须同时标脏：`this.x = v; this.setModified("x");`
  - 想让框架强制覆盖该字段（例如审计字段），先 `setModified("createdBy", false)` 复位。
- 逻辑删除**没有专用方法**，就是普通字段 `defunctInd`（`'Y'`/`'N'`）；删除/停用 = 置 `'Y'`，查询默认过滤 `'N'`。
- 多院区 `entityMstrId` 也是普通字段，写入与过滤都要显式处理。

## 5. 事务

- `@Transactional` 在 **controller 与 `-server-impl` service 都用**（service 更多）；事务管理在 `ApiApplication` 上 `@EnableTransactionManagement(proxyTargetClass = true)`。
- 仓库内**没有 `readOnly = true` 惯例**；只在需要回滚时标注，异常回滚写 `@Transactional(rollbackFor = Exception.class)`。
- 一次业务操作跨多表/多实体写入时，事务边界放在 `-server-impl` 的入口方法上；controller 层一般只做参数处理与组合，避免把长事务摊到 controller。

## 6. 异常与错误码

- 业务异常 `BizException`（`com.karrytech.framework.require.model.exception.BizException`，继承 `RuntimeException`，带 `errorCode`，默认 `"ERROR"`）。
- 抛法：`throw new BizException("<ERROR_CODE>", "<提示>")`，或 `throw new BizException(Messages.get("<key>"))`。
- 需要专门 catch 时可定义子类（仓库内已有少量，如「余额不足」类），放在本模块的 `exception` 包。
- **仓库内没有 `@ControllerAdvice` / `@ExceptionHandler`**：响应由闭源框架统一处理，**不要自己加全局异常处理器**。

## 7. 系统参数（后端读取）

- 注入 `ICommonCoreService`，用 `getParameterValue(String parameterName)` 取值；内部按当前会话的 `entityMstrId` 取该院区的参数值。
- **参数名用常量类里的常量**（如 `IParameterNameConst` 中的字段），不要在业务代码里写裸字符串，便于全局检索与重命名。
- 返回 `null` 表示该院区未配置，业务要按遗留行为决定兜底（多数取默认值）。

## 8. MyBatis / VO / 分页

- mapper XML 放 `<mod>-server-impl/src/main/resources/mapper/*Dao.xml`（共享的放 `<mod>-common-server-impl`）；全局扫描配置 `classpath*:mapper/*Dao.xml`。
- DAO：`@Repository class XDao extends MybatisBaseDao`，在方法里 `this.findList("sqlId", param)` / `findUnique` / `findRowCount` / `call(procName, params)`。
- **没有开 `map-underscore-to-camel-case`** → 列名 ↔ 属性名必须**显式写 `<resultMap>`**（`resultType` 基本只用于标量，如 `java.lang.Integer` / `BigDecimal`）。Oracle 列名大写，注意别名与映射对齐。
- 分页：`PageableRespVo<E>`（`current` / `pageSize` / `total` / `results`）+ `findPageableList(dao, sqlId, params, pageable)`。
- MyBatis-Plus 在依赖里但**业务不用**（不继承 `BaseMapper` / `ServiceImpl`），SQL 全走 `MybatisBaseDao` + 手写 XML。

## 9. iBATIS 2.x → MyBatis 3 改写

| 遗留 iBATIS                          | MyBatis 3                                                   |
| ------------------------------------ | ----------------------------------------------------------- |
| `#param#`                            | `#{param}`                                                  |
| `$literal$`                          | `${literal}`                                                |
| `<isNotEmpty property="x">`          | `<if test="x != null and x != ''">`                         |
| `<dynamic prepend="WHERE">`          | `<where>` / `<if>`                                          |
| `resultClass` / `resultMap` 列名映射 | 显式 `<resultMap>`（无驼峰自动映射）；`resultType` 用于标量 |

**安全**：`${...}` 拼接的表名 / 排序列必须做白名单校验，防注入（遗留 `$...$` 同样风险）。

## 10. 主数据通用约定

字段口径（`defunct_ind` 'Y'/'N' 与默认过滤、审计四字段、`entity_mstr_id`）见 [repos-and-map.md](repos-and-map.md) §主数据通用约定；**审计字段由框架自动填**（`setModified` 语义见 §4）。另一条硬约束：**绝不直接拷贝遗留 GBK 字节**，中文转码或重录（新侧 UTF-8）。

## 11. 认证与会话

- `/his/**` 按序挂 6 个拦截器（注册处 `autoconfig/ApiWebMvcConfigurer`）：限流 → ExtRequest → Session → ExtSession → 日志 → `RequestAuthInterceptor`。前 5 个来自闭源框架 `com.karrytech.framework.require.starter.interceptor.*`；登录会话放 ThreadLocal `com.karrytech.util.session.SessionFactory`。
- **免登录白名单是 `interceptor/RequestAuthInterceptor` 的静态 `IGNORED_PATHS`**（`URIPaths` 只是 AntPath 匹配器）。典型条目：登录/验证码、`/his/app/common/**`、`/his/common/file/**`、`/his/common/parameters`、CA、第三方回调（`/his/**/interface/**`）等。**新增免登录接口必须往白名单加路径**，否则 `RequestAuthInterceptor.preHandle` 抛 `AUTH_EXPIRED` → 401。
- **方法内 `createSession()` 没有共享实现**，各 controller 自己定义一个同名方法，判据统一是 `if (SessionFactory.get() == null)`，构造系统会话（`userMstrId = 0`、`userName = "系统管理员"`、`entityMstrId = 1`）。
  - 用它的场景：**没有登录用户**的入口 —— 内部调用、第三方回调、定时/批处理触发。
  - 有登录用户的普通业务接口**不要**加，避免掩盖真实的会话缺失。
  - 遗留里这类接口通常在方法内自建系统会话，移植时**一并保留**；个别把 `@Transactional` 标在 controller 层，也照旧。

## 12. 会踩的坑

- **模块名 ≠ 业务归属**：`webhis-charge-*` 里没有业务代码；收费在 `webhis-pa-*` / `webhis-common-*`。迁移前先读代码。
- 包名多为 `com.karrytech.webhis.<mod>`，但个别模块（如 emr / record）仍是 `com.karrytech.his.*`；`webhis-common-*` 里还留着 `com.kompakar.ehealth.base.util`。
- 响应形态不统一（裸对象/数组 vs `{code,data}` / `CommonResult.success`），前端按各端点实际形态处理。
- 启动器只依赖各域的 `-api` 与 `-server-impl`；新建域时漏了这一步，接口会 404。
- 构建需 **JDK 8**；必须用仓库根 `settings.xml`（内网 Nexus，闭源框架 jar 只在那里）。
- `application-jdbc.properties` 可能有未解决的 Git 冲突标记，**改库配置前看清实际生效行**。
- macOS 下 Oracle 连内网库要 `startup.sh` 里的 no-socks-proxy `-javaagent`，勿删 `tools/no-socks-proxy-agent.jar`。

## 13. 构建与运行

```sh
./startup.sh dev        # mvn install -pl webhis-starter-api -am + spring-boot:run
./startup.sh build      # clean compile package（跳过测试）后起 jar
./startup.sh start      # 不重编译，直接起已有 jar（可跟 debug）
./startup.sh debug      # 起服务并开 JDWP（调试端口 5005）
./startup.sh stop       # 关闭 9800 端口进程

mvn -pl webhis-<mod>-server-impl -am install -Dmaven.test.skip=true   # 只构建单模块 + 依赖
```

- 端口 9800；Swagger `http://<host>:9800/swagger-ui/index.html`（按域分组）。
- 无真实测试（各 `AppTest` 是桩），一律 `-Dmaven.test.skip=true`；**不要声称测试通过**。验证见 **[backend-verification.md](backend-verification.md)**。

## 14. 参考文档

- `<后端>/AGENTS.md`（构建与运行、新增接口四步、白名单/`createSession`、模块归属）—— 最新最权威。
- `<后端>/docs/<功能>/`（若存在：00 总览 / 01 表结构 / 02 接口 / 03 模型结构 / 04 清理记录）与接口清单类文档，**接口以它为准**。
