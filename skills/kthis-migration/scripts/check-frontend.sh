#!/usr/bin/env bash
# 迁移前端「落地前体检」：把可机检的规则一次跑完。
# 规则唯一来源见 .agents/rules/*；判定与用法见
# .agents/skills/kthis-migration/references/frontend-porting.md §10。
#
# 用法：bash .agents/skills/kthis-migration/scripts/check-frontend.sh <目录或文件> [更多…]
# 退出码：0 = 无 ERROR（可能有 WARN）；1 = 有 ERROR；2 = 用法错误 / 无匹配文件。

set -u

if [ "$#" -eq 0 ]; then
  echo "用法：bash .agents/skills/kthis-migration/scripts/check-frontend.sh <目录或文件> [更多…]" >&2
  echo "示例：bash .agents/skills/kthis-migration/scripts/check-frontend.sh src/pages/<mod>/<页面目录>" >&2
  exit 2
fi

FILES=$(find "$@" -type f \
  \( -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' -o -name '*.less' -o -name '*.css' \) \
  2>/dev/null | sort -u)
if [ -z "${FILES}" ]; then
  echo "未找到可检查的文件：$*" >&2
  exit 2
fi

ERR=0
WARN=0
FILE_COUNT=$(printf '%s\n' "${FILES}" | wc -l | tr -d ' ')

# 在所有目标文件里按正则找（输出 file:line:内容）
# $1=内容正则 $2=可选：文件名（路径）过滤正则（如 '[Dd]ialog|[Ss]lip'）
hits() {
  local list="${FILES}"
  if [ -n "${2:-}" ]; then
    list="$(printf '%s\n' "${FILES}" | grep -E -- "$2" || true)"
    [ -z "${list}" ] && return 0
  fi
  printf '%s\n' "${list}" | tr '\n' '\0' | xargs -0 grep -nE -- "$1" 2>/dev/null
}

check_error() { # $1=规则名 $2=出处 $3=正则
  local found
  found=$(hits "$3")
  if [ -n "${found}" ]; then
    ERR=$((ERR + 1))
    printf '✗ ERROR  %s（出处：%s）\n' "$1" "$2"
    printf '%s\n' "${found}" | sed 's/^/      /'
  else
    printf '✓        %s\n' "$1"
  fi
}

check_warn() { # $1=提示名 $2=出处 $3=正则 $4=可选：文件名（路径）过滤正则
  local found
  found=$(hits "$3" "${4:-}")
  if [ -n "${found}" ]; then
    WARN=$((WARN + 1))
    printf '! WARN   %s（出处：%s）\n' "$1" "$2"
    printf '%s\n' "${found}" | sed 's/^/      /'
  fi
}

check_warn_filtered() { # $1=提示名 $2=出处 $3=命中正则 $4=排除正则
  local found
  found=$(hits "$3" | grep -vE -- "$4")
  if [ -n "${found}" ]; then
    WARN=$((WARN + 1))
    printf '! WARN   %s（出处：%s）\n' "$1" "$2"
    printf '%s\n' "${found}" | sed 's/^/      /'
  fi
}

check_error_filtered() { # $1=规则名 $2=出处 $3=命中正则 $4=文件名(路径)过滤正则
  local found
  found=$(hits "$3" "$4")
  if [ -n "${found}" ]; then
    ERR=$((ERR + 1))
    printf '✗ ERROR  %s（出处：%s）\n' "$1" "$2"
    printf '%s\n' "${found}" | sed 's/^/      /'
  else
    printf '✓        %s\n' "$1"
  fi
}

check_error_pair() { # $1=规则名 $2=出处 $3=命中正则A $4=同文件必须同时命中正则B $5=文件名(路径)过滤正则
  local list found f
  list="$(printf '%s\n' "${FILES}" | grep -E -- "$5" || true)"
  found=""
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    if grep -qE -- "$3" "${f}" 2>/dev/null && grep -qE -- "$4" "${f}" 2>/dev/null; then
      found="${found}${f}:$(grep -nE -- "$3" "${f}" | head -1 | sed 's/^/ /')
"
    fi
  done <<< "${list}"
  if [ -n "${found}" ]; then
    ERR=$((ERR + 1))
    printf '✗ ERROR  %s（出处：%s）\n' "$1" "$2"
    printf '%s' "${found}" | sed 's/^/      /'
  else
    printf '✓        %s\n' "$1"
  fi
}

check_error_missing() { # $1=规则名 $2=出处 $3=文件内命中正则A $4=文件内必须存在的正则B $5=文件名(路径)过滤正则
  local list found f
  list="$(printf '%s\n' "${FILES}" | grep -E -- "$5" || true)"
  found=""
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    if grep -qE -- "$3" "${f}" 2>/dev/null && ! grep -qE -- "$4" "${f}" 2>/dev/null; then
      found="${found}${f}:$(grep -nE -- "$3" "${f}" | head -1 | sed 's/^/ /')
"
    fi
  done <<< "${list}"
  if [ -n "${found}" ]; then
    ERR=$((ERR + 1))
    printf '✗ ERROR  %s（出处：%s）\n' "$1" "$2"
    printf '%s' "${found}" | sed 's/^/      /'
  else
    printf '✓        %s\n' "$1"
  fi
}

# 过滤：只在去掉 minmax(...) 后仍含 1fr 的行上输出（bash 3.2 不支持 case 直接写在 $() 里，故独立成函数）
_tp_bare_1fr() {
  while IFS= read -r line; do
    tp_v="${line#*templateColumns=\"}"
    tp_v="${tp_v%%\"*}"
    if printf '%s' "${tp_v}" | sed -E 's/minmax\([^)]*\)//g' | grep -q '1fr'; then
      printf '%s\n' "${line}"
    fi
  done
}

check_error_templateColumns() { # templateColumns 的值里去掉所有 minmax(...) 后仍含 1fr → 裸 1fr
  local found
  found=$(hits 'templateColumns="[^"]*"' | _tp_bare_1fr)
  if [ -n "${found}" ]; then
    ERR=$((ERR + 1))
    printf '✗ ERROR  %s（出处：%s）\n' "templateColumns 不裸用 1fr（用 minmax(0,1fr)）" "docs/migration/00-前端布局规范.md §3.4"
    printf '%s\n' "${found}" | sed 's/^/      /'
  else
    printf '✓        %s\n' "templateColumns 不裸用 1fr（用 minmax(0,1fr)）"
  fi
}

echo "体检目标：$*（${FILE_COUNT} 个文件）"
echo
echo "== ERROR（必须清零）=="
check_error "禁止导入 moment / lodash / @brickio/ui（lodash-es / dayjs 是允许的替代）" \
  ".agents/rules/FrontNormalize.md" \
  "^[[:space:]]*import[^;]*['\"](moment|lodash|lodash/|@brickio/ui)['\"/]"
check_error "样式禁止 !important" ".agents/rules/pageStyleRule.md「4. 样式作用域」" '!important'
check_error "样式禁用 nth-child / nth-of-type" ".agents/rules/pageStyleRule.md「4. 样式作用域」" 'nth-(child|of-type)'
check_error "禁止 scroll={{ x: 'max-content' }}（rc-table 会退化为 table-layout: auto）" \
  ".agents/rules/tableRule.md" "x:[[:space:]]*'max-content'"
check_error "标识列不渲染 ×（'N' 应渲染空）" ".agents/rules/tableRule.md「标识（布尔）列只标『是』」" "'×'"
check_error "无 console.log" "AGENTS.md" 'console\.log\('
check_error_templateColumns
check_error "横向滚动 scroll={{ x }} 必须用数值（字符串会让 rc-table 退化为 table-layout: auto）" \
  ".agents/rules/tableRule.md" \
  "scroll=\{\{[[:space:]]*x:[[:space:]]*'"
check_error "列表 key 不能用 index（用 \${id}_\${index}）" \
  ".agents/rules/tableRule.md" \
  'key=\{[[:space:]]*index[[:space:]]*\}|key=\{[[:space:]]*.{0,80}\+[[:space:]]*index'
check_error "effect 的 context 必须挂在第一个参数（写第二个参数会运行时抛错、lint/tsc 发现不了）" \
  ".agents/rules/page-norm.md" \
  '\*[A-Za-z0-9_]+\([^,]*,[[:space:]]*\{[^}]*context'
check_error_filtered "页面主体不得内嵌弹窗（表单 / 明细一律用 app/openComponentPopup 打开，禁止在页面里渲染 <Modal / <Drawer / <…Dialog）" \
  ".agents/rules/page-norm.md「1. 主页面」" \
  '<[A-Za-z]*(Modal|Drawer|Dialog)[ \t/>]' \
  '[Pp]age\.(jsx|tsx)$'
check_error_pair "页面主体不得内嵌新增 / 编辑 / 明细维护表单（Page 里同现表单元素与「保存 / 提交」按钮；表单必须走弹窗 / 侧滑）" \
  ".agents/rules/page-norm.md「1. 主页面」" \
  '<GridFormAntd|<Field[[:space:]/>]|<Form[[:space:]/>]|GridFormItem' \
  '保存|提交' \
  '[Pp]age\.(jsx|tsx)$'
check_error_filtered "标识（布尔）列 'Y' 应渲染 <Icon type=\"yes-green\" /> 图标，不要用 '√' 字符替代" \
  ".agents/rules/tableRule.md「标识（布尔）列只标『是』」" \
  "'√'" \
  '[Pp]age\.(jsx|tsx)$'
check_error_filtered "多列表单禁止给 GridFormAntd 设 gap：水平间距由 label padding 统一提供（组内 8px / 组间 16px 已默认成立），再加 gap=\"0 16px\" 会把组间拉到 32px" \
  ".agents/rules/componentUseRule.md「表单控件」" \
  'gap=' \
  '[Dd]ialog\.(jsx|tsx)$'
check_error_filtered "表单弹窗的复位按钮文案统一「重置」（i18n.reset），不要用「清除」（遗留「清除」= 清空查询条件并清空结果，语义不同）" \
  ".agents/rules/page-norm.md「2. 对话框」" \
  'i18n\.clear|>清除<|"clear": *"清除"' \
  '[Dd]ialog'

echo
echo "== WARN（逐条人工确认）=="
check_warn "弹窗内出现 <Switch：表单勾选应改用 Checkbox" \
  ".agents/rules/componentUseRule.md" '<Switch' '[Dd]ialog|[Ss]lip'
check_warn "页面主体出现表单提交 onFinish：确认只是查询条件表单（新增 / 编辑 / 明细维护表单必须在弹窗 / 侧滑里）" \
  ".agents/rules/page-norm.md「1. 主页面」" 'onFinish=' '[Pp]age\.(jsx|tsx)$'
check_warn_filtered "vid 命名不合 ^[a-z]+_（应为 模块_文件名_xxx）" \
  ".agents/rules/tableRule.md" 'vid="[^"]*"' 'vid="[a-z]+_'
check_warn "出现 FieldGroup：确认未与 Field 混用同一表单（底边距 24px vs 0）" \
  ".agents/rules/componentUseRule.md" '<FieldGroup'
check_warn_filtered "TableBox 同行未见 title：确认保留了列表区名称（不传会兜底「数据列表」）" \
  ".agents/rules/page-norm.md" '<TableBox' 'title='
check_warn "内联硬编码宽高（应走 less / 组件 props）" \
  ".agents/rules/pageStyleRule.md" \
  'style=\{\{[^}]*(width|height)[[:space:]]*:'
check_warn "样式硬编码 width/height px（逐条确认是否必要）" \
  ".agents/rules/pageStyleRule.md" \
  '(^|[[:space:]])width:[[:space:]]*[0-9]+px|(^|[[:space:]])height:[[:space:]]*[0-9]+px'
check_warn "Divider 同行带 className/style：确认是否必要、能否复用默认样式 / 全局工具类" \
  ".agents/rules/pageStyleRule.md「6. 复用优先与最小化自定义样式（强制）」" \
  '<Divider[^>]*(className|style)='
check_warn_filtered "i18n 用于字符串位置未取 .props.text：确认 placeholder / rules.message / new Error 等不显示 [object Object]" \
  ".agents/rules/componentUseRule.md「校验与联动」" \
  'placeholder=\{[[:space:]]*i18n\.|new Error\(i18n\.|message:[[:space:]]*i18n\.' \
  '\.props\.text'
check_warn "主页面使用了 rowSelection：确认不是主从表维护、设置页；此类页面主列表应点击行选中，不传 rowSelection" \
  ".agents/rules/tableRule.md「行交互与展示」" \
  'rowSelection=\{' \
  '[Pp]age\.(jsx|tsx)$'

echo
if [ "${ERR}" -eq 0 ]; then
  echo "结果：ERROR 0，WARN ${WARN} → 把命令与结果贴进 _进度台账.md 当轮次行"
  exit 0
fi
echo "结果：ERROR ${ERR}，WARN ${WARN} → 先清零 ERROR 再提交" >&2
exit 1
