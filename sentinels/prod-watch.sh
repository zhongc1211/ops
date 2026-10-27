#!/bin/bash
# iMac ops · 23：全程本机；预检永远 exit 1，不启动模型。
# 人工初始化：prod-watch.sh --init-baseline（看日志确认成功）。
# 人工需精确退出码时用 python3 prod_ledger.py run。
B=${PROD_WATCH_BIN:-$(cd "$(dirname "$0")" && pwd)}
python3 "$B/prod_ledger.py" run "$@"
exit 1
