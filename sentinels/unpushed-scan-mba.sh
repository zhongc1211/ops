#!/bin/bash
# MBA ops · 24：本机日志；安装时保留此文件名，precheck 相应改名。
# UNPUSHED_STATE_DIR 可隔离状态与日志，参数原样传给扫描器。
B=$(cd "$(dirname "$0")" && pwd)
python3 "$B/unpushed_local.py" mba "$@"
exit 1
