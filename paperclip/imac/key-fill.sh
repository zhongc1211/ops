#!/bin/bash
# 由 Zack 在 iMac 本机终端跑：把 Console API key 存进 Paperclip 的 company secret，
# 再把 agent ops-system 的环境变量 ANTHROPIC_API_KEY 绑到这个 secret。
# key 用 read -s 读（不回显），经管道交给 python（不进命令行参数、不进环境变量、不写文件、不打印）。
# 用法：key-fill.sh          填 key
#       key-fill.sh --check  只打印 有/没有
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/config.sh"
export API_URL COMPANY_NAME AGENT_NAME

if [ "${1:-}" = --check ]; then
    exec "${TIMEOUT}" 60 "${PY}" "${here}/key-fill.py" --check </dev/null
fi

printf '粘贴 Console API key 后回车（屏幕不显示）: '
IFS= read -rs key
printf '\n'
[ -n "${key}" ] || { echo "没输入，退出"; exit 1; }
printf '%s' "${key}" | "${TIMEOUT}" 120 "${PY}" "${here}/key-fill.py" --fill
unset key
