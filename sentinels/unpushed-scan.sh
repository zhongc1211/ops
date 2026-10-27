#!/bin/bash
# iMac ops · 24：本机日志；提醒策略仍由 unpushed_scan.py 决定。
# UNPUSHED_STATE_DIR 可隔离状态与日志，参数原样传给扫描器。
B=$(cd "$(dirname "$0")" && pwd)
python3 "$B/unpushed_local.py" imac "$@"
exit 1
