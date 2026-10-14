# 遗留侧盘点与 GBK 检索

> 写文档前，先把功能在遗留系统里**端到端跑通/读通**，再落笔。本文件只给**通用方法**；具体仓库路径、模块代号、入口类名由使用者在每轮对话中提供。

## 1. 遗留仓库（路径由使用者提供）

- 路径：优先读**项目根** `.agents/paths.env` 的 `KTHIS_LEGACY_DIR`（每个开发者不同；缺失时运行 `kthis-migration` 技能的 `scripts/setup-paths.sh`，或直接询问使用者），**不要假设固定绝对路径**。典型为 **SVN** 管理、大量扁平 Eclipse 工程、Java 6 源码、**GBK** 编码。
- 若该仓库自带 `AGENTS.md`，**先读它**（通常只含项目简介与架构速览；没有也不影响）。⚠️ 遗留侧**不一定**有迁移清单或原始分析文档；若另有 `docs/migration/` 之类的原始材料，只作**参考线索**，**以源码为准**。
- 数据库连接串：遗留 Web 工程的 `WEB-INF/jdbc.properties`（只读对照表结构）。

## 2. 端到端追踪链

```text
界面入口（Editor / Page / plugin.xml extensions）
  → ui.<mod>.<layer>/*.java（SWT 视图：Editor/Page/CTabItem/ContextMenu）
    → 事件监听 → action / I*Service 调用
      → server.<mod>.<layer> impl
        → dao/ibatis/maps/*.xml
          → 数据库表 / 视图
```

要点：

- **入口定位**：按界面标题 / 菜单文案 / Editor ID 找 `plugin.xml` 的 `extensions`，再进对应 `ui.<mod>.*`。
- **界面文案**（标签、按钮、页签名）：`.../ui.<mod>.<layer>/i18n/messages.properties`（GBK）。
- **页签**：SWT 里常是 `CTabItem` / `CTabFolder`；**每个页签的字段与事件分别统计**，对应到独立册。
- **新增 vs 编辑**：同一 Editor 常用不同入口/参数区分，注意新增态显示的页签/字段可能与编辑态不同。
- **码表 / 系统参数**：值来自码表表或系统参数表，写文档时记录**码表编码**而非中文值。

## 3. GBK 检索

遗留源码是 GBK，`rg`/`grep` 直接搜中文搜不到。做法：`iconv -f GB18030 -t UTF-8` 后再搜。

```sh
find <目录> -name '*.java' -print0 | while IFS= read -r -d '' f; do
  iconv -f GB18030 -t UTF-8 "$f" 2>/dev/null | grep -n "<关键字>" && echo "  ↑ $f"
done
```

> 注意：不要用 `set -e`/pipefail 包住上面的循环（首个不匹配即中断）。UTF-8 文件用 `iconv -f GB18030` 会失败——这是正常的，遗留源文件才是 GB18030。若本机已有现成的 GBK 检索脚本/工具（如某些技能自带的 `grep-gbk.sh`），可直接用，避免重复造轮子；没有就用上面的等价写法。

## 4. 记录来源（可复核）

写册时对关键行为标注来源，例如：

```text
> 来源：<遗留>/.../ui.<mod>.<layer>/src/.../<XxxPage>.java（<页签/弹窗名>）
> 文案：.../i18n/messages.properties（<界面标签>）
```

不必贴代码；给**路径 + 位置描述**即可，供复核与后续开发。

## 5. 常见坑

- 中文乱码：**不要**把 GBK 字节直接写进 UTF-8 文档，需转码或重录。
- 屏幕截图不完整（弹窗只截了一部分）→ 以源码为准。
- 表结构：逻辑删除字段 / 审计字段 / 多院区字段是**通用约定**，别当业务字段重复写。
- **不要照搬旧模块编码**：新旧模块编号常不一致，**先确认新侧目标模块**再落笔。
