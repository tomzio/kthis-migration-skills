#!/usr/bin/env bash
# scaffold-docs.sh —— 为某个功能模块生成 docs/migration/<NN-模块>/ 迁移文档骨架。
#
# 只做「机械搭建」：创建目录、按册类型套模板生成空骨架、写入册间导航（返回索引/上一册/下一册）、
# 生成进度台账。**内容由 AI 按模板与遗留源码逐册填充**（见 SKILL.md「多轮协作流程」）。
#
# 用法：
#   scaffold-docs.sh --no <NN> --name <模块名> --code <模块代号> \
#     [--legacy-ui <遗留入口>] \
#     [--root docs/migration] [--force] \
#     --volume "<主页面>:main" --volume "<弹窗外壳>:shell" --volume "<页签>:tab" ...
#
# 册类型（template 名）：
#   overview 总览与通用约定 | main 主页面 | shell 编辑弹窗外壳 | tab 页签
#   dialog 独立弹窗 | aux 辅助弹窗与码表 | data 数据流程与接口 | plan 迁移实施计划 | matrix 共享分区与复用矩阵
#   类型 overview 会自动补在最前（若未指定）。
#
# 另：--global-layout 可生成跨模块的 docs/migration/00-前端布局规范.md（仅第一次需要）。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${SKILL_DIR}/../../.." && pwd -P)"
TEMPLATES="${SKILL_DIR}/templates"
DATE="$(date +%Y-%m-%d)"

MOD_NO=""; MOD_NAME=""; MOD_CODE=""; LEGACY_UI="（待补）"
MIG_DIR=""; FORCE=0; GLOBAL_LAYOUT=0
declare -a VOLS=()

usage() {
  sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no)            MOD_NO="${2:-}"; shift 2 ;;
    --name)          MOD_NAME="${2:-}"; shift 2 ;;
    --code)          MOD_CODE="${2:-}"; shift 2 ;;
    --legacy-ui)     LEGACY_UI="${2:-}"; shift 2 ;;
    --root)          MIG_DIR="${2:-}"; shift 2 ;;
    --volume)        VOLS+=("${2:-}"); shift 2 ;;
    --force)         FORCE=1; shift ;;
    --global-layout) GLOBAL_LAYOUT=1; shift ;;
    -h|--help)       usage ;;
    *) echo "未知参数：$1" >&2; usage ;;
  esac
done

if [ -z "${MOD_NO}" ] || [ -z "${MOD_NAME}" ] || [ -z "${MOD_CODE}" ]; then
  echo "错误：必须提供 --no / --name / --code。" >&2; echo >&2; usage
fi

case "${MOD_NO}" in
  [0-9][0-9]) ;;
  *) if [ "${#MOD_NO}" = 1 ]; then MOD_NO="0${MOD_NO}"; else
       echo "错误：--no 应为 1~2 位数字（如 02）。" >&2; exit 1; fi ;;
esac

[ -z "${MIG_DIR}" ] && MIG_DIR="${REPO_ROOT}/docs/migration"
MIG_DIR="$(cd "${MIG_DIR}" 2>/dev/null && pwd -P || echo "${MIG_DIR}")"
MODULE_DIR="${MIG_DIR}/${MOD_NO}-${MOD_NAME}"

# ---- 工具函数 ----
sed_inplace() { # file  (使用外部 sed_expr 变量)
  if sed --version >/dev/null 2>&1; then sed -i "${1}" "${2}"; else sed -i '' "${1}" "${2}"; fi
}
subst() { # file key value
  local f="${1}" k="${2}" v="${3}" esc
  esc="$(printf '%s' "${v}" | sed -e 's/[\\&|]/\\&/g')"
  sed_inplace "s|${k}|${esc}|g" "${f}"
}

# ---- 组装册列表 ----
# 确保有 overview 且在最前
HAS_OVERVIEW=0
for v in "${VOLS[@]:-}"; do
  [ "${v##*:}" = "overview" ] && HAS_OVERVIEW=1
done
if [ "${HAS_OVERVIEW}" = 0 ]; then
  VOLS=("总览与通用约定:overview" "${VOLS[@]:-}")
fi

TOTAL=${#VOLS[@]}
if [ "${TOTAL}" = 0 ]; then echo "错误：至少需要一个 --volume。" >&2; exit 1; fi

VALID_TYPES="overview main shell tab dialog aux data plan matrix"
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
declare -a V_NO=() V_TITLE=() V_TYPE=() V_FILE=()
i=0
for v in "${VOLS[@]}"; do
  title="${v%:*}"; type="${v##*:}"
  ok=0
  for t in ${VALID_TYPES}; do [ "${type}" = "${t}" ] && ok=1; done
  if [ "${ok}" = 0 ]; then echo "错误：未知册类型 '${type}'（${v}）。" >&2; exit 1; fi
  [ -n "$(tpl_of "${type}")" ] && [ -f "${TEMPLATES}/$(tpl_of "${type}")" ] || { echo "错误：缺少模板 $(tpl_of "${type}")" >&2; exit 1; }
  n="$(printf '%02d' "${i}")"
  V_NO+=("${n}"); V_TITLE+=("${title}"); V_TYPE+=("${type}"); V_FILE+=("${n}-${title}.md")
  i=$((i+1))
done

# 供 REF_* 使用：类型 -> 文件名
ref_of() { local want="${1}" j=0; while [ "${j}" -lt "${TOTAL}" ]; do if [ "${V_TYPE[$j]}" = "${want}" ]; then printf '%s' "${V_FILE[$j]}"; return; fi; j=$((j+1)); done; printf '%s' "（无）"; }
REF_OVERVIEW="$(ref_of overview)"; REF_MAIN="$(ref_of main)"
REF_DATA="$(ref_of data)"; REF_PLAN="$(ref_of plan)"; REF_MATRIX="$(ref_of matrix)"

# 提示缺失的常用册
for t in data plan; do
  [ "$(ref_of "${t}")" = "（无）" ] && echo "提示：未规划 '${t}' 类型册（通常应有）。" >&2
done

# ---- 创建目录 ----
mkdir -p "${MODULE_DIR}"
echo "模块目录：${MODULE_DIR}"

# ---- 生成各册 ----
j=0
while [ "${j}" -lt "${TOTAL}" ]; do
  tpl="$(tpl_of "${V_TYPE[$j]}")"; out="${MODULE_DIR}/${V_FILE[$j]}"
  if [ -f "${out}" ] && [ "${FORCE}" = 0 ]; then
    echo "  跳过（已存在）：${V_FILE[$j]}"
  else
    cp "${TEMPLATES}/${tpl}" "${out}"
    # 导航行
    nav="返回索引：[README](../README.md)"
    if [ "${j}" -gt 0 ]; then nav="${nav} ｜ 上一册：[${V_FILE[$((j-1))]%.md}](./${V_FILE[$((j-1))]})"; else nav="${nav} ｜ 上一册：—"; fi
    if [ "${j}" -lt $((TOTAL-1)) ]; then nav="${nav} ｜ 下一册：[${V_FILE[$((j+1))]%.md}](./${V_FILE[$((j+1))]})"; else nav="${nav} ｜ 下一册：—"; fi
    subst "${out}" '{{NAV}}' "${nav}"
    subst "${out}" '{{VOL_NO}}' "${V_NO[$j]}"
    subst "${out}" '{{VOL_TITLE}}' "${V_TITLE[$j]}"
    subst "${out}" '{{MODULE_NO}}' "${MOD_NO}"
    subst "${out}" '{{MODULE_NAME}}' "${MOD_NAME}"
    subst "${out}" '{{MODULE_CODE}}' "${MOD_CODE}"
    subst "${out}" '{{LEGACY_UI}}' "${LEGACY_UI}"
    subst "${out}" '{{DATE}}' "${DATE}"
    subst "${out}" '{{REF_OVERVIEW}}' "${REF_OVERVIEW}"
    subst "${out}" '{{REF_MAIN}}' "${REF_MAIN}"
    subst "${out}" '{{REF_DATA}}' "${REF_DATA}"
    subst "${out}" '{{REF_PLAN}}' "${REF_PLAN}"
    subst "${out}" '{{REF_MATRIX}}' "${REF_MATRIX}"
    echo "  生成：${V_FILE[$j]}  [${V_TYPE[$j]}]"
  fi
  j=$((j+1))
done

# ---- 进度台账 ----
LEDGER="${MODULE_DIR}/_进度台账.md"
if [ ! -f "${LEDGER}" ]; then
  cp "${TEMPLATES}/_进度台账.md.tpl" "${LEDGER}"
  for kv in "{{MODULE_NO}}=${MOD_NO}" "{{MODULE_NAME}}=${MOD_NAME}" "{{MODULE_CODE}}=${MOD_CODE}" "{{LEGACY_UI}}=${LEGACY_UI}" "{{DATE}}=${DATE}"; do
    subst "${LEDGER}" "${kv%%=*}" "${kv#*=}"
  done
  echo "  生成：_进度台账.md"
fi

# ---- 全局索引 README.md ----
IDX="${MIG_DIR}/README.md"
if [ ! -f "${IDX}" ]; then
  cp "${TEMPLATES}/README.md.tpl" "${IDX}"
  for kv in "{{MODULE_NO}}=${MOD_NO}" "{{MODULE_NAME}}=${MOD_NAME}" "{{MODULE_CODE}}=${MOD_CODE}" "{{LEGACY_UI}}=${LEGACY_UI}" "{{DATE}}=${DATE}" "{{VOL_NO}}=<册号>" "{{VOL_TITLE}}=<册名>" "{{VOL_FILE}}=<文件>"; do
    subst "${IDX}" "${kv%%=*}" "${kv#*=}"
  done
  echo "  生成：README.md（全局索引，请按模块分节补全）"
else
  echo "  已存在：README.md（请在本模块分节下补充索引行）"
fi

# ---- 跨模块布局规范 ----
if [ "${GLOBAL_LAYOUT}" = 1 ]; then
  GL="${MIG_DIR}/00-前端布局规范.md"
  if [ ! -f "${GL}" ] || [ "${FORCE}" = 1 ]; then
    cp "${TEMPLATES}/00-前端布局规范.md.tpl" "${GL}"
    subst "${GL}" '{{DATE}}' "${DATE}"
    echo "  生成：00-前端布局规范.md"
  else
    echo "  跳过（已存在）：00-前端布局规范.md"
  fi
fi

cat <<EOF

完成。下一步（见 SKILL.md 多轮协作流程）：
  1. 编辑 ${MODULE_DIR}/_进度台账.md，把册规划交给用户确认（第 1 轮）。
  2. 完善 ${MIG_DIR}/README.md 的模块分节与索引行（首次运行会按模板自动生成）。
  3. 逐册填充内容；每册完成后跑：${SCRIPT_DIR}/audit-docs.sh
EOF
