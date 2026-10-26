#!/usr/bin/env bash
# 解析、校验并（可选）生成三仓库路径配置。
#
# 每个开发者的仓库路径可能不同，配置写在本机私有文件（默认 <项目根>/.agents/paths.env）。
#
# 用法:
#   scripts/setup-paths.sh                 # 校验现有配置；缺失/失效则自动探测并写出
#   scripts/setup-paths.sh --detect        # 只探测并打印结果，不写文件
#   scripts/setup-paths.sh --print         # 打印当前生效配置（KEY=VALUE 形式）
#   scripts/setup-paths.sh --legacy D --front D --server D   # 显式指定并写入
#   scripts/setup-paths.sh --out <file>    # 指定写出位置（默认 <项目根>/.agents/paths.env）
#   scripts/setup-paths.sh --force         # 即使配置已存在也重新探测覆盖
#
# 项目根定位（技能单独安装也适用）：技能所在仓库根（../../..，含 .agents/ 时）
#   > 环境变量 KTHIS_PROJECT_ROOT > 当前目录逐级向上（找含 .agents/ 或 docs/migration/ 的目录）> 当前目录。
# 项目根缺 .agents/ 时自动创建，并把技能自带 paths.env.example 落位为
#   <项目根>/.agents/paths.env.example（已存在则不覆盖；建议提交到仓库）。
#
# 配置读取顺序：$KTHIS_MIGRATION_CONFIG / --out > <项目根>/.agents/paths.env（唯一配置文件）
set -u

# 公共：SKILL_DIR 与项目根探测
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib-root.sh"

LEGACY=""; FRONT=""; SERVER=""
DETECT_ONLY=0; PRINT_ONLY=0; FORCE=0; OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --legacy) LEGACY="${2:-}"; shift 2 ;;
    --front)  FRONT="${2:-}";  shift 2 ;;
    --server) SERVER="${2:-}"; shift 2 ;;
    --out)    OUT="${2:-}";    shift 2 ;;
    --detect) DETECT_ONLY=1; shift ;;
    --print)  PRINT_ONLY=1;  shift ;;
    --force)  FORCE=1;       shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "未知参数: $1（用 --help 查看用法）" >&2; exit 2 ;;
  esac
done

# ---- 定位项目根（技能单独安装时也能工作）----
PROJ_ROOT="$(detect_proj_root)"
if [ -z "$PROJ_ROOT" ]; then
  PROJ_ROOT="$PWD"
  echo "提示：未找到含 .agents/ 的项目根，以当前目录作为项目根：${PROJ_ROOT}" >&2
fi

# ---- 自愈：项目根缺 .agents/ 时创建，并把技能自带的模板落位（已存在则不覆盖）----
mkdir -p "$PROJ_ROOT/.agents"
if [ -f "$SKILL_DIR/paths.env.example" ] && [ ! -f "$PROJ_ROOT/.agents/paths.env.example" ]; then
  cp "$SKILL_DIR/paths.env.example" "$PROJ_ROOT/.agents/paths.env.example"
  echo "已在 ${PROJ_ROOT}/.agents/ 放置模板 paths.env.example（建议提交到仓库）" >&2
fi
PROJ_CFG="$PROJ_ROOT/.agents/paths.env"

# ---- 写出位置（--out / $KTHIS_MIGRATION_CONFIG 优先，其次项目根 .agents/paths.env）----
if [ -z "$OUT" ]; then
  if [ -n "${KTHIS_MIGRATION_CONFIG:-}" ]; then
    OUT="$KTHIS_MIGRATION_CONFIG"
  else
    OUT="$PROJ_CFG"
  fi
fi

# ---- 校验器：判断某个目录是不是目标仓库 ----
is_legacy() { [ -d "$1/com.kompakar.ehealth.base" ] || [ -f "$1/eHealth/WebContent/WEB-INF/jdbc.properties" ]; }
is_front()  { [ -f "$1/package.json" ] && [ -d "$1/src/pages" ]; }
is_server() { [ -f "$1/pom.xml" ] && [ -d "$1/webhis-starter-api" ]; }

check_kind() { # $1=kind $2=dir
  case "$1" in
    legacy) is_legacy "$2" ;;
    front)  is_front  "$2" ;;
    server) is_server "$2" ;;
  esac
}

# ---- 读取现有配置（OUT > 项目 .agents/paths.env）----
# 只解析三个 KEY=VALUE，绝不 source 用户配置，避免配置里的命令被执行。
if [ "$FORCE" = 0 ]; then
  for f in "$OUT" "$PROJ_CFG"; do
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

# detect_kind <kind>：在候选根目录里找匹配目录，命中即打印其绝对路径
detect_kind() {
  kind="$1"
  case "$kind" in
    legacy) name_expr=( -name eclipse_projects -o -name dev ) ;;
    front)  name_expr=( -name webhis-front ) ;;
    server) name_expr=( -name webhis-server ) ;;
  esac

  for root in $(candidate_roots); do
    [ -d "$root" ] || continue
    # 消解软链：find 不会遍历符号链接形式的起始路径（如 ~/workspace → 实际数据盘）
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

# 统一规范化为物理路径（消解软链，如 ~/workspace 指向备份盘/挂载点时取其真实路径）
canon() { if [ -n "$1" ] && [ -d "$1" ]; then (cd "$1" && pwd -P); else printf '%s' "$1"; fi; }
LEGACY="$(canon "$LEGACY")"; FRONT="$(canon "$FRONT")"; SERVER="$(canon "$SERVER")"

# ---- 打印模式 ----
if [ "$PRINT_ONLY" = 1 ] || [ "$DETECT_ONLY" = 1 ]; then
  echo "KTHIS_LEGACY_DIR=${LEGACY:-<未找到>}"
  echo "WEBHIS_FRONT_DIR=${FRONT:-<未找到>}"
  echo "WEBHIS_SERVER_DIR=${SERVER:-<未找到>}"
  [ "$DETECT_ONLY" = 1 ] && [ "$PRINT_ONLY" = 0 ] && echo "# --detect：未写入文件" >&2
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
或直接编辑 ${OUT}（模板见 .agents/paths.env.example）。
EOF
  exit 1
fi

# ---- 写出 ----
mkdir -p "$(dirname "$OUT")"

# 路径用 shell 单引号包裹，避免 $()、反引号、空格、引号等被后续 source 执行 / 破坏语法。
quote_value() {
  local v="$1" repl="'\\''"
  v="${v//\'/$repl}"
  printf "'%s'" "$v"
}

{
  printf '%s\n' \
    '# 三仓库路径配置（由 scripts/setup-paths.sh 生成，可按需手改）' \
    '# 本文件为本机私有配置，勿提交/分发（已 gitignore）。模板见 .agents/paths.env.example。'
  printf 'KTHIS_LEGACY_DIR=%s\n' "$(quote_value "$LEGACY")"
  printf 'WEBHIS_FRONT_DIR=%s\n' "$(quote_value "$FRONT")"
  printf 'WEBHIS_SERVER_DIR=%s\n' "$(quote_value "$SERVER")"
} > "$OUT"
chmod 600 "$OUT" 2>/dev/null || true
echo "已写入 ${OUT}"
