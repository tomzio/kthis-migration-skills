#!/usr/bin/env bash
# 在遗留 KTHIS/eHealth 源码（Java 6 / GBK）里按中文或标识符检索。
#
# 用法:
#   grep-gbk.sh <pattern> [dir]            # 打印命中行（前缀为文件路径:行号）
#   grep-gbk.sh <pattern> [dir] --files    # 只打印命中文件路径
#
# [dir] 省略时依次取：$KTHIS_LEGACY_DIR 环境变量 > 路径配置里的 KTHIS_LEGACY_DIR。
# 路径配置读取顺序：KTHIS_MIGRATION_CONFIG > <项目根>/.agents/paths.env。
# <项目根> 的确定：技能所在仓库根（含 .agents/）> $KTHIS_PROJECT_ROOT > 从当前目录逐级向上找含 .agents/ 或 docs/migration/ 的目录。
# 请先运行 scripts/setup-paths.sh 生成配置（每个开发者路径可能不同）。
#
# 说明: 遗留源码是 GBK，中文无法被 grep/rg 直接命中（rg 本机通常也没装）。
#       这里对每个文件先 iconv 转 UTF-8 再 grep。
# [dir] 建议缩到具体项目/子目录，避免遍历整个大型遗留工作区。
#
# 注意: 不要开 set -e / pipefail —— 循环里 grep 无命中返回 1 是正常情况，
#       开 -e 会让脚本在第一个不匹配的文件处提前退出、什么都不输出。
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 项目根探测：技能所在仓库根 > KTHIS_PROJECT_ROOT > 当前目录逐级向上找 .agents/ 或 docs/migration/
SKILL_REPO_ROOT="$(cd "$SKILL_DIR/../../.." 2>/dev/null && pwd -P || true)"
if [ -n "${SKILL_REPO_ROOT}" ] && [ -d "${SKILL_REPO_ROOT}/.agents" ]; then
  PROJ_ROOT="${SKILL_REPO_ROOT}"
elif [ -n "${KTHIS_PROJECT_ROOT:-}" ] && [ -d "${KTHIS_PROJECT_ROOT}" ]; then
  PROJ_ROOT="$(cd "${KTHIS_PROJECT_ROOT}" && pwd -P)"
else
  PROJ_ROOT=""
  d="$PWD"
  while [ -n "$d" ]; do
    if [ -d "${d}/.agents" ] || [ -d "${d}/docs/migration" ]; then PROJ_ROOT="$d"; break; fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
fi

PATTERN="${1:?用法: grep-gbk.sh <pattern> [dir] [--files]}"
DIR="${2:-}"
MODE="${3:-}"
# 允许省略 [dir] 直接使用 --files：grep-gbk.sh <pattern> --files
if [ "$DIR" = "--files" ]; then MODE="$DIR"; DIR=""; fi

if [ -z "$DIR" ]; then
  if [ -n "${KTHIS_LEGACY_DIR:-}" ]; then
    DIR="$KTHIS_LEGACY_DIR"
  else
    for f in "${KTHIS_MIGRATION_CONFIG:-}" "${PROJ_ROOT}/.agents/paths.env"; do
      [ -n "$f" ] || continue
      [ -f "$f" ] || continue
      # shellcheck disable=SC1090
      . "$f"
      [ -n "${KTHIS_LEGACY_DIR:-}" ] && break
    done
    DIR="${KTHIS_LEGACY_DIR:-}"
  fi
fi

if [ -z "$DIR" ]; then
  echo "未指定检索目录，且未配置 KTHIS_LEGACY_DIR。" >&2
  echo "请先运行: ${SKILL_DIR}/scripts/setup-paths.sh（会按需落位模板并生成 <项目根>/.agents/paths.env）" >&2
  echo "也可设置 KTHIS_LEGACY_DIR / KTHIS_PROJECT_ROOT，或显式传入目录: grep-gbk.sh <pattern> <dir>" >&2
  exit 2
fi

if [ ! -d "$DIR" ]; then
  echo "目录不存在: ${DIR}（路径配置可能过期，重跑 setup-paths.sh）" >&2
  exit 1
fi

find "$DIR" -type f \( -name '*.java' -o -name '*.properties' -o -name '*.xml' -o -name '*.sql' \) -print0 \
  | while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      if [ "$MODE" = "--files" ]; then
        if iconv -f GB18030 -t UTF-8 "$f" 2>/dev/null | grep -q -- "$PATTERN"; then
          echo "$f"
        fi
      else
        iconv -f GB18030 -t UTF-8 "$f" 2>/dev/null \
          | grep -n -- "$PATTERN" \
          | sed "s#^#$f:#"
      fi
    done

exit 0
