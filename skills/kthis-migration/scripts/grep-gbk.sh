#!/usr/bin/env bash
# 在遗留 KTHIS/eHealth（Java 6 / GBK）源码里按中文或标识符检索。
#
# 用法:
#   grep-gbk.sh <pattern> [dir]         # 打印命中行
#   grep-gbk.sh <pattern> [dir] --files # 只打印命中文件
#
# [dir] 省略时取 $KTHIS_LEGACY_DIR；也可读 $KTHIS_MIGRATION_CONFIG 或 <项目根>/.agents/paths.env。
# 未配置时运行 scripts/setup-paths.sh 查看探测结果，确认后加 --write。
# 逐文件 iconv GB18030 → UTF-8 再 grep；Windows 需 Git Bash / WSL。
# [dir] 建议缩到具体项目/子目录，避免遍历整个工作区。
#
# 不要开 set -e / pipefail：grep 无命中返回 1 是正常情况。
set -u

if ! command -v iconv >/dev/null 2>&1; then
  echo "未找到 iconv；macOS / Linux 通常自带，Windows 请使用 Git Bash / WSL 或安装 iconv。" >&2
  exit 2
fi

# 公共：SKILL_DIR 与项目根探测
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib-root.sh"
PROJ_ROOT="$(detect_proj_root)"

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
      load_paths_config "$f"
      [ -n "${KTHIS_LEGACY_DIR:-}" ] && break
    done
    DIR="${KTHIS_LEGACY_DIR:-}"
  fi
fi

if [ -z "$DIR" ]; then
  echo "未指定检索目录，且未配置 KTHIS_LEGACY_DIR。" >&2
  echo "请先运行: ${SKILL_DIR}/scripts/setup-paths.sh 查看探测结果并按提示加 --write 写入 <项目根>/.agents/paths.env" >&2
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
