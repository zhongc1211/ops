#!/bin/bash
# S12 ② 第 4 步：建 company、agent、routine、触发器（实现在 provision.py）。
# 用法（在 iMac 上，服务已经由 LaunchAgent 起好）：provision.sh  只打印；provision.sh --apply  照做
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/config.sh"
export API_URL COMPANY_NAME AGENT_NAME AGENT_MODEL AGENT_BUDGET_CENTS AGENT_CWD AGENT_SETTINGS \
    ROUTINE_OPS_TITLE ROUTINE_TEST_TITLE SECRETS_DIR
umask 077
exec "${TIMEOUT}" 600 "${PY}" "${here}/provision.py" "$@"
