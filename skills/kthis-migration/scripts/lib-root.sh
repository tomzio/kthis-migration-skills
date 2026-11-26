#!/usr/bin/env bash
# kthis-migration 脚本公共：SKILL_DIR、项目根探测、安全读取 paths.env。
# 由 setup-paths.sh / grep-gbk.sh source。

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# 项目根：技能目录向上找 .agents/ > $KTHIS_PROJECT_ROOT > 当前目录向上找 .agents/ 或 docs/migration/；
#   未找到时输出空串。
detect_proj_root() {
  local d
  d="$SKILL_DIR"
  while [ -n "$d" ]; do
    if [ -d "$d/.agents" ]; then printf '%s' "$d"; return 0; fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
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

# 安全读取 paths.env：只识别三个 KEY，不 source（配置可能不可信）；支持 export 与单/双引号。
load_paths_config() { # $1=file
  local file="$1" line key val
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
      export[[:space:]]*) line="${line#export}"; line="${line#"${line%%[![:space:]]*}"}" ;;
    esac
    case "$line" in
      KTHIS_LEGACY_DIR=*|WEBHIS_FRONT_DIR=*|WEBHIS_SERVER_DIR=*)
        key="${line%%=*}"
        val="${line#*=}"
        case "$val" in
          \'*\') val="${val#\'}"; val="${val%\'}"; val="${val//\'\\\'\'/\'}" ;;
          \"*\") val="${val#\"}"; val="${val%\"}" ;;
        esac
        case "$key" in
          KTHIS_LEGACY_DIR) KTHIS_LEGACY_DIR="$val" ;;
          WEBHIS_FRONT_DIR) WEBHIS_FRONT_DIR="$val" ;;
          WEBHIS_SERVER_DIR) WEBHIS_SERVER_DIR="$val" ;;
        esac
        ;;
    esac
  done < "$file"
  return 0
}
