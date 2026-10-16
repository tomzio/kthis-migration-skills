#!/usr/bin/env bash
# audit-docs.sh —— 体检 docs/migration 迁移文档：册号连续性、导航链、链接、截图、占位符、篇幅预算、跨册重复。
#
# 用法：
#   audit-docs.sh [--docs-dir <docs/migration 目录>] [--module <02-模块目录名>] [--strict] [--max-lines <N>] [--dup-strict]
#
#   --docs-dir   迁移文档根目录（默认按下方探测顺序确定；--root 为同义参数）
#   --module     只审计指定模块目录（省略则审计全部 <NN-模块>/）
#   --strict     把「警告」也视为失败（退出码 1）
#   --max-lines  单册行数预算上限，默认 450（超出 → 警告，提示拆分或精简）
#   --dup-strict 把「跨册重复」也判定为警告（默认仅提示，不影响退出码）
#
#   「一册一个家」：同一句解释性内容（≥90 字节）出现在 2 册以上 → 默认仅提示，
#   加 --dup-strict 升级为警告；只保留一个家、其余改为链接。
#   导航行 / 表格 / 标题 / 注释不参与重复检测。
#
# 默认目录探测顺序：--docs-dir / --root > $KTHIS_PROJECT_ROOT（含 docs 或 .agents）>
#   当前目录逐级向上（含 .agents/ 或 docs/migration/）> 技能所在仓库根（../../..）。
# 技能不在仓库内（单独安装）时默认目录可能不存在，请用 --docs-dir 显式指定迁移文档根目录。
#
# 退出码：0 通过；1 有错误（或 --strict 下有警告）。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${SKILL_DIR}/../../.." && pwd -P)"

# ---- 迁移文档根目录探测（技能单独安装时也能工作）----
# 顺序：$KTHIS_PROJECT_ROOT（含 docs 或 .agents）> 当前目录逐级向上（含 .agents/
#   或 docs/migration/）> 技能所在仓库根（存量约定）。
detect_mig_dir() {
  local d root
  if [ -n "${KTHIS_PROJECT_ROOT:-}" ] && [ -d "${KTHIS_PROJECT_ROOT}" ] \
     && { [ -d "${KTHIS_PROJECT_ROOT}/docs" ] || [ -d "${KTHIS_PROJECT_ROOT}/.agents" ]; }; then
    root="$(cd "${KTHIS_PROJECT_ROOT}" && pwd -P)"; printf '%s/docs/migration' "${root}"; return 0
  fi
  d="${PWD}"
  while [ -n "${d}" ]; do
    if [ -d "${d}/.agents" ] || [ -d "${d}/docs/migration" ]; then
      root="$(cd "${d}" && pwd -P)"; printf '%s/docs/migration' "${root}"; return 0
    fi
    [ "${d}" = "/" ] && break
    d="$(dirname "${d}")"
  done
  printf '%s/docs/migration' "${REPO_ROOT}"
}

DOCS_DIR=""; ONLY_MODULE=""; STRICT=0; MAX_LINES=450; DUP_STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --docs-dir) DOCS_DIR="${2:-}"; shift 2 ;;
    --root)     DOCS_DIR="${2:-}"; shift 2 ;;
    --module)   ONLY_MODULE="${2:-}"; shift 2 ;;
    --max-lines) MAX_LINES="${2:-450}"; shift 2 ;;
    --dup-strict) DUP_STRICT=1; shift ;;
    --strict)   STRICT=1; shift ;;
    -h|--help)  sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
[ -z "${DOCS_DIR}" ] && DOCS_DIR="$(detect_mig_dir)"
if [ ! -d "${DOCS_DIR}" ]; then
  echo "错误：未找到迁移文档目录 ${DOCS_DIR}" >&2
  echo "      技能单独安装（不在仓库内）时，请用 --docs-dir <你的迁移文档根目录>（或 --root）显式指定，例如：" >&2
  echo "      $0 --docs-dir <项目根>/docs/migration" >&2
  exit 2
fi
DOCS_DIR="$(cd "${DOCS_DIR}" && pwd -P)"

ERRORS=0; WARNS=0
err()  { echo "  [错误] $*"; ERRORS=$((ERRORS+1)); }
warn() { echo "  [警告] $*"; WARNS=$((WARNS+1)); }

IMG_NAME_RE='^[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)+\.(png|jpg|jpeg)$'

audit_module() {
  local dir="${1}" mod; mod="$(basename "${dir}")"
  echo "== 模块 ${mod} =="
  local files="" f
  for f in "${dir}"/*.md; do
    [ -e "${f}" ] || continue
    f="$(basename "${f}")"
    case "${f}" in _*|README*) continue ;; esac
    files="${files}${f}"$'\n'
  done
  files="$(printf '%s' "${files}" | sort | sed '/^$/d')"
  if [ -z "${files}" ]; then warn "无分册文件"; return; fi

  # 1) 册号连续性 + 命名
  local expect=0 n
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    n="${f:0:2}"
    if ! printf '%s' "${f}" | grep -qE '^[0-9]{2}-.+\.md$'; then
      warn "命名不规范（应为 NN-名称.md）：${f}"
    elif [ "${n}" != "$(printf '%02d' "${expect}")" ]; then
      err "册号不连续：期望 $(printf '%02d' "${expect}")，实际 ${n}（${f}）"
    fi
    expect=$((expect+1))
  done <<< "${files}"

  # 2) 每册必要元素
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    local p="${dir}/${f}" h2
    head -1 "${p}" | grep -qE '^# ' || err "${f}: 缺少 H1 标题"
    grep -q '返回索引' "${p}" || warn "${f}: 缺少导航行（返回索引/上一册/下一册）"
    h2="$(grep -cE '^## ' "${p}")"
    [ "${h2}" -ge 2 ] || warn "${f}: 章节过少（仅 ${h2} 个 ## 标题）"
    if grep -qE '\{\{(NAV|VOL_NO|VOL_TITLE|MODULE_NO|MODULE_NAME|MODULE_CODE|LEGACY_UI|DATE|REF_[A-Z_]+)\}\}|\{\{[一-龥]+\}\}' "${p}"; then
      warn "${f}: 残留模板占位符 {{...}}"
    fi
  done <<< "${files}"

  # 3) 导航链一致性
  local prev="" up
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    local p="${dir}/${f}"
    up="$(grep -oE '上一册：\[[^]]*\]\(\./[^)]*\)' "${p}" | head -1 | sed -E 's|.*\(\./(.*)\)|\1|')"
    if [ -n "${prev}" ]; then
      [ "${up}" = "${prev}" ] || err "${f}: 上一册导航应为 ${prev}，实际 ${up:-（无）}"
    fi
    prev="${f}"
  done <<< "${files}"

  # 4) 相对链接可达性
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    local p="${dir}/${f}" links l
    links="$(grep -oE '\]\([^)]+\)' "${p}" 2>/dev/null | sed -e 's/^](//' -e 's/)$//' | grep -vE '^(https?:|mailto:|#)' || true)"
    while IFS= read -r l; do
      [ -z "${l}" ] && continue
      l="${l%%#*}"
      [ -z "${l}" ] && continue
      case "${l}" in /*) continue ;; esac
      [ -e "${dir}/${l}" ] || warn "${f}: 链接失效 → ${l}"
    done <<< "${links}"
  done <<< "${files}"

  # 5) TODO 统计
  local todos; todos="$(grep -rho '<!-- TODO' "${dir}" 2>/dev/null | wc -l | tr -d ' ')"
  [ "${todos}" -gt 0 ] && echo "  [信息] 未完成 TODO 标记 ${todos} 处"

  # 6) 单册篇幅预算（一册讲透一件事，过长考虑拆分/精简）
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    local p="${dir}/${f}" ln
    ln="$(wc -l < "${p}" | tr -d ' ')"
    if [ "${ln}" -gt "${MAX_LINES}" ]; then
      warn "${f}: 篇幅 ${ln} 行，超过预算 ${MAX_LINES} 行（考虑拆分或精简）"
    elif [ "${ln}" -lt 10 ]; then
      warn "${f}: 篇幅仅 ${ln} 行，疑似空壳"
    fi
  done <<< "${files}"
}

# 跨册重复检测：同一句解释性内容出现在多册 → 「一册一个家」违规。
# 规则可自洽（短规则允许各自重述），此处只针对 ≥90 字节的解释性整句。
audit_duplicates() {
  echo "== 跨册重复（一册一个家）=="
  local mods=("$@") rows dup tmp
  [ "${#mods[@]}" -eq 0 ] && { echo "  [信息] 无模块"; return; }
  tmp="$(mktemp)"
  local d f bn
  for d in "${mods[@]}"; do
    bn="$(basename "${d}")"
    for f in "${d}"/*.md; do
      [ -e "${f}" ] || continue
      case "$(basename "${f}")" in _*|README*) continue ;; esac
      awk -v F="${bn}/$(basename "${f}")" '
        length($0) >= 90 &&
        $0 !~ /返回索引/ && $0 !~ /^[[:space:]]*\|/ &&
        $0 !~ /^#/ && $0 !~ /^[[:space:]]*<!--/ {
          gsub(/^[[:space:]]*[>*-]+[[:space:]]*/,"");
          gsub(/[[:space:]]+$/,""); gsub(/[[:space:]]+/," ");
          print F"\t"$0
        }' "${f}" | grep -vE '\]\(|[─│└┌┐┘├┤┬┴┼▶▼⟨⟩⧉]' || true
    done
  done > "${tmp}"

  # 同一句文本命中 ≥2 个不同册 → 重复
  rows="$(sort -u "${tmp}" | awk -F'\t' '{files[$2]=files[$2]" " $1; n[$2]++}
      END { for (t in n) if (n[t] >= 2) printf "%s\t%s\n", n[t], t }' | sort -rn | head -10)"
  rm -f "${tmp}"
  dup=0
  if [ -n "${rows}" ]; then
    while IFS=$'\t' read -r cnt text; do
      [ -z "${text}" ] && continue
      dup=$((dup+1))
      if [ "${DUP_STRICT}" = 1 ]; then
        warn "重复句（${cnt} 册）：${text:0:60}…（只保留一处，其余改链接）"
      else
        echo "  [信息] 重复句（${cnt} 册）：${text:0:60}…（建议只保留一处，其余改链接）"
      fi
    done <<< "${rows}"
  fi
  [ "${dup}" -eq 0 ] && echo "  [信息] 未发现跨册重复长句"
}

audit_images() {
  echo "== 截图 =="
  local dirs=() d
  [ -d "${DOCS_DIR}/images" ] && dirs+=("${DOCS_DIR}/images")
  for d in "${DOCS_DIR}"/*/images; do
    [ -d "${d}" ] && dirs+=("${d}")
  done
  if [ "${#dirs[@]}" -eq 0 ]; then echo "  [信息] 无 images/ 目录"; return; fi

  local total=0 bad=0 img base imgdir
  for imgdir in "${dirs[@]}"; do
    for img in "${imgdir}"/*; do
      [ -e "${img}" ] || continue
      base="$(basename "${img}")"
      case "${base}" in .*) continue ;; esac
      total=$((total+1))
      if ! printf '%s' "${base}" | grep -qE "${IMG_NAME_RE}"; then
        warn "命名不规范（应为 <NN>-<模块>-<英文名>.png）：${base}"; bad=$((bad+1))
      fi
      if ! grep -rqF --include='*.md' -- "${base}" "${DOCS_DIR}" 2>/dev/null; then
        warn "未被任何文档引用：${base}"
      fi
    done
  done
  echo "  [信息] 截图 ${total} 张，命名不合规 ${bad} 张"

  local ref rel found
  for ref in $(grep -rhoE 'images/[A-Za-z0-9._-]+\.(png|jpg|jpeg)' "${DOCS_DIR}" --include='*.md' 2>/dev/null | sort -u); do
    rel="${ref#images/}"
    found=0
    for imgdir in "${dirs[@]}"; do
      [ -f "${imgdir}/${rel}" ] && { found=1; break; }
    done
    [ "${found}" = 1 ] || warn "文档引用了不存在的图片：${ref}"
  done
}

echo "体检目录：${DOCS_DIR}"
MODULE_DIRS=()
if [ -n "${ONLY_MODULE}" ]; then
  MODULE_DIRS=("${DOCS_DIR}/${ONLY_MODULE}")
else
  for d in "${DOCS_DIR}"/*/; do
    [ -e "${d}" ] || continue
    case "$(basename "${d}")" in
      [0-9][0-9]-*) MODULE_DIRS+=("${d}") ;;
    esac
  done
fi
if [ "${#MODULE_DIRS[@]}" -gt 0 ]; then
  for d in "${MODULE_DIRS[@]}"; do audit_module "${d}"; done
  audit_duplicates "${MODULE_DIRS[@]}"
else
  echo "  [信息] 未发现 <NN-模块>/ 目录"
fi
audit_images

echo "----------------------------------------"
echo "合计：错误 ${ERRORS}，警告 ${WARNS}"
if [ "${ERRORS}" -gt 0 ] || { [ "${STRICT}" = 1 ] && [ "${WARNS}" -gt 0 ]; }; then
  echo "结果：不通过"; exit 1
fi
echo "结果：通过"
