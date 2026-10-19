#!/usr/bin/env bash
# rename-screenshots.sh —— 遗留截图按「页面功能」改名，并同步更新文档引用。
#
# 规范命名：<功能序号>-<目标模块代号>-<界面英文名>.<png|jpg|jpeg>
#   例：<NN>-<模块代号>-<英文名>-tab.png / <NN>-<模块代号>-add-<英文名>-tab.png / <NN>-<模块代号>-<英文名>-dialog.png
#
# 说明：本脚本只做「机械改名 + 改引用」。「识别截图内容、确定功能英文名」需要先由模型
#       用 read 打开图片看清楚是哪个页面/页签/弹窗，再把结论当作 old=new 传进来。
#
# 用法：
#   rename-screenshots.sh --audit <images-dir> [docs-dir]
#       审计：列出不符合命名规范的图片、文档中失效的图片引用、未被任何文档引用的图片。
#   rename-screenshots.sh <images-dir> <docs-dir> <old>=<new> [<old>=<new> ...]
#       改名：把 images-dir 下的 <old> 重命名为 <new>（新名须符合规范），
#             并把 docs-dir 下所有文档里对 <old> 的引用替换为 <new>。
#       选项：--dry-run 只打印将要执行的操作，不落盘。
#
# 注意：set -u 即可，勿加 set -e / pipefail（会让遍历循环提前退出、输出为空）。

set -u

# 公共路径与函数（sed_inplace 等）
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

NAME_RE='^[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)+\.(png|jpg|jpeg)$'
DRY_RUN=0

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------- 参数解析 ----------
mode=""
if [ "${1:-}" = "--audit" ]; then
  mode="audit"; shift
elif [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -eq 0 ]; then
  usage; exit 0
else
  mode="rename"
fi

args=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    *) args+=("$a") ;;
  esac
done

# ---------- 工具函数 ----------
is_git_repo() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# 转义 sed 正则元字符
sed_esc() { printf '%s' "$1" | sed 's/[][\\.*^$()+?{}|/]/\\&/g'; }

# 收集 docs-dir 下所有被引用的图片文件名（去重）；
# 字符集故意放宽到非 ASCII，以便审计尚未改名的中文截图。
collect_refs() {
  local docs="$1"
  [ -d "$docs" ] || return 0
  grep -rhoE "images/[^][\"'()<>\`[:space:]]+\.(png|jpg|jpeg)" "$docs" 2>/dev/null \
    | sed 's#^images/##' | sort -u
}

do_audit() {
  local images="$1" docs="${2:-}"
  [ -d "$images" ] || { echo "✗ images 目录不存在：$images" >&2; exit 1; }

  echo "== 命名规范审计（${images}）=="
  local bad=0 n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    if ! [[ "$(basename "$f")" =~ $NAME_RE ]]; then
      echo "  ✗ 非规范命名: $(basename "$f")"
      bad=$((bad + 1))
    fi
  done < <(find "$images" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | sort)
  echo "  共 $n 张，其中 $bad 张不合规。"

  if [ -n "$docs" ] && [ -d "$docs" ]; then
    echo "== 引用审计（${docs}）=="
    local broken=0
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      if [ ! -f "$images/$ref" ]; then
        echo "  ✗ 引用不存在: $ref"
        broken=$((broken + 1))
      fi
    done < <(collect_refs "$docs")
    echo "  失效引用 $broken 处。"

    echo "== 未被引用图片 =="
    local unref=0
    while IFS= read -r img; do
      [ -n "$img" ] || continue
      if ! grep -rqF -- "$img" "$docs" 2>/dev/null; then
        echo "  ! 未被引用: $img"
        unref=$((unref + 1))
      fi
    done < <(find "$images" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec basename {} \; | sort)
    echo "  未引用 $unref 张。"
  fi

  [ "$bad" -eq 0 ] && echo "✓ 命名全部合规。" || echo "→ 先识别图片内容，再用本脚本改名。"
}

do_rename() {
  local images="$1" docs="$2"; shift 2
  [ -d "$images" ] || { echo "✗ images 目录不存在：$images" >&2; exit 1; }
  [ $# -gt 0 ] || { echo "✗ 未提供 old=new 映射。" >&2; usage; exit 1; }

  local pair old new src dst changed=0
  for pair in "$@"; do
    old="${pair%%=*}"; new="${pair##*=}"
    if [ -z "$old" ] || [ -z "$new" ] || [ "$old" = "$new" ]; then
      echo "✗ 非法映射：$pair" >&2; exit 1
    fi
    if ! [[ "$new" =~ $NAME_RE ]]; then
      echo "✗ 新名不符合规范（<功能序号>-<模块代号>-<界面英文名>.png）：$new" >&2; exit 1
    fi
    src="$images/$old"; dst="$images/$new"
    [ -f "$src" ] || { echo "✗ 不存在：$src" >&2; exit 1; }
    [ -e "$dst" ] && { echo "✗ 目标已存在，拒绝覆盖：$dst" >&2; exit 1; }

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "would rename: $old -> $new"
    else
      if is_git_repo "$images" && git -C "$images" ls-files --error-unmatch "$old" >/dev/null 2>&1; then
        git -C "$images" mv "$old" "$new" || { echo "✗ git mv 失败：$old" >&2; exit 1; }
      else
        mv "$src" "$dst" || { echo "✗ mv 失败：$old" >&2; exit 1; }
      fi
      echo "✓ renamed: $old -> $new"
    fi

    # 同步文档引用（含 images/ 与 ../images/ 两种写法，按 basename 全局替换）
    if [ -d "$docs" ]; then
      local esc_old files
      esc_old="$(sed_esc "$old")"
      while IFS= read -r files; do
        [ -n "$files" ] || continue
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "  would update ref in: $files"
        else
          sed_inplace "s/${esc_old}/${new}/g" "$files"
          echo "  ref updated: $files"
        fi
        changed=$((changed + 1))
      done < <(grep -rlE "$esc_old" "$docs" 2>/dev/null)
    fi
  done

  echo "完成（更新引用 $changed 处）。建议再跑一次 --audit 复核。"
}

# ---------- 分发 ----------
if [ "$mode" = "audit" ]; then
  [ $# -ge 1 ] || { usage; exit 1; }
  do_audit "${args[@]}"
else
  [ "${#args[@]}" -ge 3 ] || { usage; exit 1; }
  do_rename "${args[@]}"
fi
