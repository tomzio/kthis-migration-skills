#!/usr/bin/env bash
# lib.sh —— 迁移文档脚本的公共路径与函数。被 audit-docs.sh / scaffold-docs.sh /
#           new-volume.sh / rename-screenshots.sh source；单独运行无意义。
#
# 提供：SCRIPT_DIR / SKILL_DIR / REPO_ROOT / TEMPLATES / DATE，
#       以及 detect_mig_dir / sed_inplace / subst / tpl_of。
# 调用方负责 before 设 `set -u`（本文件不做进程级设置）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${SKILL_DIR}/../../.." && pwd -P)"
TEMPLATES="${SKILL_DIR}/templates"
DATE="$(date +%Y-%m-%d)"

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

# ---- sed 就地替换：macOS 用 BSD sed（-i ''），Linux 用 GNU sed（-i）----
sed_inplace() { if sed --version >/dev/null 2>&1; then sed -i "${1}" "${2}"; else sed -i '' "${1}" "${2}"; fi; }

# ---- 替换占位符：subst <file> <key> <value> ----
subst() {
  local f="${1}" k="${2}" v="${3}" esc
  esc="$(printf '%s' "${v}" | sed -e 's/[\\&|]/\\&/g')"
  sed_inplace "s|${k}|${esc}|g" "${f}"
}

# ---- 册类型（模板名）-> 模板文件名 ----
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
