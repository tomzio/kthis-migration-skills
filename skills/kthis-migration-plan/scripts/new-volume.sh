#!/usr/bin/env bash
# new-volume.sh —— 在已有的 docs/migration/<NN-模块>/ 中插入一册，并自动重排册号、重写导航与引用。
#
# 场景：多轮协作中新增/发现一个页签或弹窗，需要在既有册序中间插入。
#
# 用法：
#   new-volume.sh --module-dir docs/migration/<NN>-<模块名> --title "<册名>" --type tab [--at 05]
#
#   --module-dir  模块目录（必填）
#   --title       册名（不含册号，必填）
#   --type        册类型：main|shell|tab|dialog|aux|data|plan|matrix（必填）
#   --at          插入为第几册（两位/一位数字，如 5）；省略则追加到末尾
#   --dry-run     只打印将做的改动
#
# 会重命名后续册文件（git 跟踪的用 git mv）、重写册间导航、并全局替换 `NN-册名.md` 引用。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
TEMPLATES="${SKILL_DIR}/templates"
REPO_ROOT="$(cd "${SKILL_DIR}/../../.." && pwd -P)"
DATE="$(date +%Y-%m-%d)"

MOD_DIR=""; TITLE=""; TYPE=""; AT=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --module-dir) MOD_DIR="${2:-}"; shift 2 ;;
    --title)      TITLE="${2:-}"; shift 2 ;;
    --type)       TYPE="${2:-}"; shift 2 ;;
    --at)         AT="${2:-}"; shift 2 ;;
    --dry-run)    DRY=1; shift ;;
    -h|--help)    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
[ -z "${MOD_DIR}" ] && { echo "错误：--module-dir 必填" >&2; exit 2; }
[ -z "${TITLE}" ]   && { echo "错误：--title 必填" >&2; exit 2; }
[ -z "${TYPE}" ]    && { echo "错误：--type 必填" >&2; exit 2; }
[ -d "${MOD_DIR}" ] || { echo "错误：目录不存在 ${MOD_DIR}" >&2; exit 2; }
tpl_of() {
  case "${1}" in
    overview) echo "00-总览与通用约定.md.tpl" ;;
    main)     echo "01-主页面.md.tpl" ;;
    shell)    echo "02-编辑弹窗外壳.md.tpl" ;;
    tab)      echo "03-页签.md.tpl" ;;
    dialog)   echo "04-独立弹窗.md.tpl" ;;
    aux)      echo "05-辅助弹窗与码表.md.tpl" ;;
    data)     echo "06-数据流程与接口.md.tpl" ;;
    plan)     echo "07-迁移实施计划.md.tpl" ;;
    matrix)   echo "08-共享分区与复用矩阵.md.tpl" ;;
  esac
}
TPL="$(tpl_of "${TYPE}")"
[ -n "${TPL}" ] && [ -f "${TEMPLATES}/${TPL}" ] || { echo "错误：未知册类型 '${TYPE}' 或无模板" >&2; exit 2; }

MOD_DIR="$(cd "${MOD_DIR}" && pwd -P)"
MOD_BASE="$(basename "${MOD_DIR}")"
MIG_DIR="$(dirname "${MOD_DIR}")"
MOD_NO="${MOD_BASE%%-*}"; MOD_NAME="${MOD_BASE#*-}"

sed_inplace() { if sed --version >/dev/null 2>&1; then sed -i "${1}" "${2}"; else sed -i '' "${1}" "${2}"; fi; }
subst() { local f="${1}" k="${2}" v="${3}" esc; esc="$(printf '%s' "${v}" | sed -e 's/[\\&|]/\\&/g')"; sed_inplace "s|${k}|${esc}|g" "${f}"; }
git_tracked() { git -C "${MOD_DIR}" ls-files --error-unmatch "${1}" >/dev/null 2>&1; }
do_rename() { local from="${1}" to="${2}"; if [ "${DRY}" = 1 ]; then echo "  mv ${from} -> ${to}"; return; fi
  if git_tracked "${from}"; then git -C "${MOD_DIR}" mv "${from}" "${to}"; else mv "${MOD_DIR}/${from}" "${MOD_DIR}/${to}"; fi; }

# 现有册（按册号排序）
OLD_FILES=(); OLD_TITLES=()
while IFS= read -r f; do
  [ -z "${f}" ] && continue
  name="${f:3}"; name="${name%.md}"
  OLD_FILES+=("${f}"); OLD_TITLES+=("${name}")
done <<< "$(cd "${MOD_DIR}" && ls -1 *.md 2>/dev/null | grep -vE '^(_|README)' | sort)"

N="${#OLD_FILES[@]}"
# 插入位置
if [ -z "${AT}" ]; then IDX="${N}"; else IDX=$((10#${AT})); fi
if [ "${IDX}" -lt 0 ] || [ "${IDX}" -gt "${N}" ]; then echo "错误：--at ${AT} 超出范围 0..${N}" >&2; exit 2; fi

# 组装新序列
NEW_TITLES=()
k=0
while [ "${k}" -lt "${N}" ]; do
  [ "${k}" = "${IDX}" ] && NEW_TITLES+=("${TITLE}")
  NEW_TITLES+=("${OLD_TITLES[$k]}")
  k=$((k+1))
done
[ "${IDX}" = "${N}" ] && NEW_TITLES+=("${TITLE}")
NEW_TOTAL=$((N+1))

echo "模块：${MOD_BASE}；插入《${TITLE}》为第 $(printf '%02d' "${IDX}") 册（共 ${NEW_TOTAL} 册，原 ${N} 册）"

# ---- 1) 重命名（从后往前，避免冲突）----
k=$((NEW_TOTAL-1))
while [ "${k}" -ge 0 ]; do
  newf="$(printf '%02d' "${k}")-${NEW_TITLES[$k]}.md"
  oldf=""
  # 在旧序列里找同名册
  j=0
  while [ "${j}" -lt "${N}" ]; do
    if [ "${OLD_TITLES[$j]}" = "${NEW_TITLES[$k]}" ]; then oldf="${OLD_FILES[$j]}"; break; fi
    j=$((j+1))
  done
  if [ -n "${oldf}" ] && [ "${oldf}" != "${newf}" ]; then do_rename "${oldf}" "${newf}"; fi
  k=$((k-1))
done

# ---- 2) 全局替换引用 NN-册名.md（旧->新，按册名锚定，不冲突）----
if [ "${DRY}" = 0 ]; then
  k=0
  while [ "${k}" -lt "${N}" ]; do
    newf=""; j=0
    while [ "${j}" -lt "${NEW_TOTAL}" ]; do
      [ "${NEW_TITLES[$j]}" = "${OLD_TITLES[$k]}" ] && newf="$(printf '%02d' "${j}")-${NEW_TITLES[$j]}.md" && break
      j=$((j+1))
    done
    if [ -n "${newf}" ] && [ "${newf}" != "${OLD_FILES[$k]}" ]; then
      oldesc="$(printf '%s' "${OLD_FILES[$k]}" | sed -e 's/[\\&|]/\\&/g')"
      newesc="$(printf '%s' "${newf}" | sed -e 's/[\\&|]/\\&/g')"
      grep -rlF -- "${OLD_FILES[$k]}" "${MOD_DIR}" --include='*.md' 2>/dev/null | while IFS= read -r f; do
        sed_inplace "s|${oldesc}|${newesc}|g" "${f}"
      done
      grep -rlF -- "${MOD_BASE}/${OLD_FILES[$k]}" "${MIG_DIR}" --include='*.md' 2>/dev/null | while IFS= read -r f; do
        sed_inplace "s|${MOD_BASE}/${oldesc}|${MOD_BASE}/${newesc}|g" "${f}"
      done
    fi
    k=$((k+1))
  done
fi

# ---- 3) 生成新册文件 ----
NEWFILE="$(printf '%02d' "${IDX}")-${TITLE}.md"
if [ "${DRY}" = 1 ]; then
  echo "  新建 ${NEWFILE}（模板 ${TPL}）"
else
  cp "${TEMPLATES}/${TPL}" "${MOD_DIR}/${NEWFILE}"
  # 册类型推断（按册名关键字），用于解析 {{REF_*}} 交叉引用
  infer_type() {
    case "${1}" in
      *总览*)     echo overview ;;
      *主页面*)   echo main ;;
      *弹窗外壳*) echo shell ;;
      *页签*)     echo tab ;;
      *数据流程*) echo data ;;
      *实施计划*) echo plan ;;
      *复用矩阵*) echo matrix ;;
      *辅助弹窗*) echo aux ;;
      *)          echo dialog ;;
    esac
  }
  ref_of() {
    local want="${1}" j=0
    while [ "${j}" -lt "${NEW_TOTAL}" ]; do
      if [ "$(infer_type "${NEW_TITLES[$j]}")" = "${want}" ]; then
        printf '%s' "$(printf '%02d' "${j}")-${NEW_TITLES[$j]}.md"; return
      fi
      j=$((j+1))
    done
    printf '%s' "（无）"
  }
  for kv in "{{VOL_NO}}=$(printf '%02d' "${IDX}")" "{{VOL_TITLE}}=${TITLE}" "{{MODULE_NO}}=${MOD_NO}" \
            "{{MODULE_NAME}}=${MOD_NAME}" "{{DATE}}=${DATE}" "{{LEGACY_UI}}=（待补）"; do
    subst "${MOD_DIR}/${NEWFILE}" "${kv%%=*}" "${kv#*=}"
  done
  subst "${MOD_DIR}/${NEWFILE}" '{{REF_OVERVIEW}}' "$(ref_of overview)"
  subst "${MOD_DIR}/${NEWFILE}" '{{REF_MAIN}}' "$(ref_of main)"
  subst "${MOD_DIR}/${NEWFILE}" '{{REF_DATA}}' "$(ref_of data)"
  subst "${MOD_DIR}/${NEWFILE}" '{{REF_PLAN}}' "$(ref_of plan)"
  subst "${MOD_DIR}/${NEWFILE}" '{{REF_MATRIX}}' "$(ref_of matrix)"
fi

# ---- 4) 重建导航 ----
k=0
while [ "${k}" -lt "${NEW_TOTAL}" ]; do
  f="$(printf '%02d' "${k}")-${NEW_TITLES[$k]}.md"
  nav="返回索引：[README](../README.md)"
  if [ "${k}" -gt 0 ]; then nav="${nav} ｜ 上一册：[$(printf '%02d' $((k-1)))-${NEW_TITLES[$((k-1))]}](./$(printf '%02d' $((k-1)))-${NEW_TITLES[$((k-1))]}.md)"; else nav="${nav} ｜ 上一册：—"; fi
  if [ "${k}" -lt $((NEW_TOTAL-1)) ]; then nav="${nav} ｜ 下一册：[$(printf '%02d' $((k+1)))-${NEW_TITLES[$((k+1))]}](./$(printf '%02d' $((k+1)))-${NEW_TITLES[$((k+1))]}.md)"; else nav="${nav} ｜ 下一册：—"; fi
  if [ "${DRY}" = 1 ]; then echo "  导航 ${f}"; else
    # 用 python 之外的稳妥做法：先删旧导航行，再在 H1 后插入
    tmp="$(mktemp)"; awk -v nav="${nav}" 'NR==1{print; print ""; print "> " nav; next} /^> .*返回索引/{next} {print}' "${MOD_DIR}/${f}" > "${tmp}" && mv "${tmp}" "${MOD_DIR}/${f}"
  fi
  k=$((k+1))
done

echo "完成。请同步更新 README 索引表的「册」号与行，并跑 ${SCRIPT_DIR}/audit-docs.sh"
