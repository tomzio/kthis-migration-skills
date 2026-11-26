#!/usr/bin/env bash
# 解析、校验并可选保存三仓库路径配置。
#
# 默认只探测并打印，不建目录、不写文件；仅 --write 写入 <项目根>/.agents/paths.env。
# 模板 paths.env.example 可手动复制到 .agents/（模板可入库）。
#
# 用法:
#   setup-paths.sh                  # 探测 / 校验并打印（默认不写）
#   setup-paths.sh --write          # 校验通过后写入 <项目根>/.agents/paths.env
#   setup-paths.sh --detect         # 只探测并打印（同默认）
#   setup-paths.sh --print          # 打印当前生效配置（KEY=VALUE）
#   setup-paths.sh --legacy D --front D --server D [--write]   # 显式指定
#   setup-paths.sh --force --write  # 忽略现有配置，重新探测并覆盖
#
# 项目根：技能仓库根（含 .agents/）> $KTHIS_PROJECT_ROOT > 向上查找 .agents/ 或 docs/migration/ > 当前目录。
# 配置读取：$KTHIS_MIGRATION_CONFIG > <项目根>/.agents/paths.env。
set -u

# 公共：SKILL_DIR 与项目根探测
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib-root.sh"

LEGACY=""; FRONT=""; SERVER=""
DETECT_ONLY=0; PRINT_ONLY=0; FORCE=0; WRITE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --legacy) LEGACY="${2:-}"; shift 2 ;;
    --front)  FRONT="${2:-}";  shift 2 ;;
    --server) SERVER="${2:-}"; shift 2 ;;
    --write)  WRITE=1;        shift ;;
    --detect) DETECT_ONLY=1; shift ;;
    --print)  PRINT_ONLY=1;  shift ;;
    --force)  FORCE=1;       shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "未知参数: $1（用 --help 查看用法）" >&2; exit 2 ;;
  esac
done

# ---- 定位项目根 ----
PROJ_ROOT="$(detect_proj_root)"
if [ -z "$PROJ_ROOT" ]; then
  PROJ_ROOT="$PWD"
  echo "提示：未找到含 .agents/ 的项目根，以当前目录作为项目根：${PROJ_ROOT}" >&2
fi

PROJ_CFG="$PROJ_ROOT/.agents/paths.env"

# ---- 仓库校验 ----
is_legacy() { [ -d "$1/com.kompakar.ehealth.base" ] || [ -d "$1/eHealth" ]; }
is_front()  { [ -f "$1/package.json" ] && [ -d "$1/src/pages" ]; }
is_server() { [ -f "$1/pom.xml" ] && [ -d "$1/webhis-starter-api" ]; }

check_kind() { # $1=kind $2=dir
  case "$1" in
    legacy) is_legacy "$2" ;;
    front)  is_front  "$2" ;;
    server) is_server "$2" ;;
  esac
}

# ---- 读取现有配置（$KTHIS_MIGRATION_CONFIG > 项目根 .agents/paths.env）----
# 只解析三个 KEY=VALUE，不 source（配置不可信）。
if [ "$FORCE" = 0 ]; then
  for f in "${KTHIS_MIGRATION_CONFIG:-}" "$PROJ_CFG"; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    load_paths_config "$f"
    break
  done
  LEGACY="${LEGACY:-${KTHIS_LEGACY_DIR:-}}"
  FRONT="${FRONT:-${WEBHIS_FRONT_DIR:-}}"
  SERVER="${SERVER:-${WEBHIS_SERVER_DIR:-}}"
fi

# ---- 自动探测 ----
candidate_roots() {
  printf '%s\n' \
    "$HOME/workspace/kthis" "$HOME/workspace" "$HOME/projects" "$HOME/dev" "$HOME/code" \
    "/data" "/workspace" "$HOME"
}

# detect_kind <kind>：在候选根里找匹配目录，命中即打印绝对路径
detect_kind() {
  kind="$1"
  case "$kind" in
    legacy) name_expr=( -name eclipse_projects -o -name dev ) ;;
    front)  name_expr=( -name webhis-front ) ;;
    server) name_expr=( -name webhis-server ) ;;
  esac

  for root in $(candidate_roots); do
    [ -d "$root" ] || continue
    # 消解软链：find 不遍历符号链接形式的起始路径
    root="$(cd "$root" && pwd -P)"
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      if check_kind "$kind" "$d"; then (cd "$d" && pwd -P); return 0; fi
    done < <(find "$root" -maxdepth 4 -type d \( "${name_expr[@]}" \) 2>/dev/null)
  done
  return 1
}

[ -z "$LEGACY" ] && LEGACY="$(detect_kind legacy || true)"
[ -z "$FRONT" ]  && FRONT="$(detect_kind front || true)"
[ -z "$SERVER" ] && SERVER="$(detect_kind server || true)"

# 规范化为物理路径（消解软链）
canon() { if [ -n "$1" ] && [ -d "$1" ]; then (cd "$1" && pwd -P); else printf '%s' "$1"; fi; }
LEGACY="$(canon "$LEGACY")"; FRONT="$(canon "$FRONT")"; SERVER="$(canon "$SERVER")"

# ---- 打印模式 ----
if [ "$PRINT_ONLY" = 1 ] || [ "$DETECT_ONLY" = 1 ]; then
  echo "KTHIS_LEGACY_DIR=${LEGACY:-<未找到>}"
  echo "WEBHIS_FRONT_DIR=${FRONT:-<未找到>}"
  echo "WEBHIS_SERVER_DIR=${SERVER:-<未找到>}"
  [ "$DETECT_ONLY" = 1 ] && [ "$PRINT_ONLY" = 0 ] && echo "# --detect：未写入 paths.env" >&2
  exit 0
fi

# ---- 校验 ----
ok=1
for pair in "legacy:$LEGACY" "front:$FRONT" "server:$SERVER"; do
  k="${pair%%:*}"; d="${pair#*:}"
  if [ -z "$d" ]; then
    echo "✗ ${k}: 未找到路径（请用 --${k} 指定）" >&2; ok=0; continue
  fi
  if check_kind "$k" "$d"; then
    echo "✓ ${k}: $d"
  else
    echo "✗ ${k}: $d 不像是目标仓库" >&2; ok=0
  fi
done

if [ "$ok" != 1 ]; then
  cat >&2 <<EOF

未能确定全部路径。请显式指定后重试，例如：
  $0 --legacy <遗留dev路径> --front <webhis-front路径> --server <webhis-server路径>
或直接编辑 ${PROJ_CFG}（模板见技能自带 paths.env.example）。
EOF
  exit 1
fi

# ---- 默认只打印 ----
if [ "$WRITE" = 0 ]; then
  echo "KTHIS_LEGACY_DIR=${LEGACY}"
  echo "WEBHIS_FRONT_DIR=${FRONT}"
  echo "WEBHIS_SERVER_DIR=${SERVER}"
  echo "# 未写入 paths.env；确认无误后加 --write 保存到 ${PROJ_CFG}" >&2
  exit 0
fi

# ---- --write：写入项目根 .agents/paths.env ----
mkdir -p "$PROJ_ROOT/.agents"

# 单引号包裹，防止后续 source 时执行 $() / 反引号或破坏语法。
quote_value() {
  local v="$1" repl="'\\''"
  v="${v//\'/$repl}"
  printf "'%s'" "$v"
}

{
  printf '%s\n' \
    '# 三仓库路径配置（setup-paths.sh --write 生成，可手改）' \
    '# 本机私有，勿提交/分发；模板见技能自带 paths.env.example。'
  printf 'KTHIS_LEGACY_DIR=%s\n' "$(quote_value "$LEGACY")"
  printf 'WEBHIS_FRONT_DIR=%s\n' "$(quote_value "$FRONT")"
  printf 'WEBHIS_SERVER_DIR=%s\n' "$(quote_value "$SERVER")"
} > "$PROJ_CFG"
chmod 600 "$PROJ_CFG" 2>/dev/null || true
echo "已写入 ${PROJ_CFG}"
if command -v git >/dev/null 2>&1 \
   && git -C "$PROJ_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && ! git -C "$PROJ_ROOT" check-ignore -q .agents/paths.env; then
  echo "提示：项目 .gitignore 未忽略 .agents/paths.env，建议加入该条目。" >&2
fi
