#!/usr/bin/env bash
# lib-root.sh —— kthis-migration 脚本公共：SKILL_DIR 与项目根探测。
# 被 setup-paths.sh / grep-gbk.sh source；单独运行无意义。

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 项目根探测：技能所在仓库根（含 .agents/）> $KTHIS_PROJECT_ROOT >
#   当前目录逐级向上（含 .agents/ 或 docs/migration/）。未找到时输出空串。
detect_proj_root() {
  local d r
  r="$(cd "${SKILL_DIR}/../../.." 2>/dev/null && pwd -P || true)"
  if [ -n "$r" ] && [ -d "$r/.agents" ]; then printf '%s' "$r"; return 0; fi
  if [ -n "${KTHIS_PROJECT_ROOT:-}" ] && [ -d "${KTHIS_PROJECT_ROOT}" ]; then
    (cd "${KTHIS_PROJECT_ROOT}" && pwd -P); return 0
  fi
  d="$PWD"
  while [ -n "$d" ]; do
    if [ -d "$d/.agents" ] || [ -d "$d/docs/migration" ]; then printf '%s' "$d"; return 0; fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
  printf ''
}
