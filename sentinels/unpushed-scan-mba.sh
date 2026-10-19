#!/bin/bash
# Orca precheck for「ops · 24 未推送扫描」（box、iMac、MBA 各一个；MBA 版：--machine mba，box 上日志名 unpushed-scan-mba-YYYYMMDD.log，每小时）。活全在这里干完，永远 exit 1，不启动模型。
# 跑 unpushed_scan.py 扫本机 Orca 工作区（只读），有发现由它用 notify-run 叫醒项目 bot。
# 日志以 box 的 /workspace/ops/reports/unpushed-scan-YYYYMMDD.log 为准：
#   box 直接写；iMac（和 MBA）先写本机镜像 ~/.orca-state/unpushed-scan/mirror-YYYYMMDD.log，再经 ssh 追加到 box。
#   ssh 不通时这次的行存进 pending.log，下次连上时先补发。
# 参数原样交给 unpushed_scan.py（演练用 --only/--state/--drill）；UNPUSHED_LOG_NAME 可以换日志文件名（演练用）。
B=$(cd "$(dirname "$0")" && pwd)
D=$(TZ=Asia/Singapore date +%Y%m%d)
NAME=${UNPUSHED_LOG_NAME:-unpushed-scan-mba-$D.log}
if [ -d /workspace/ops/reports ]; then
  python3 "$B/unpushed_scan.py" --machine box --log "/workspace/ops/reports/$NAME" "$@" >/dev/null 2>&1
  exit 1
fi
S=$HOME/.orca-state/unpushed-scan; mkdir -p "$S"
python3 "$B/unpushed_scan.py" --machine mba --log "$S/mirror-$D.log" "$@" > "$S/this-run.log" 2>&1
cat "$S/this-run.log" >> "$S/pending.log"
for attempt in 1 2 3; do
  if ssh -o ConnectTimeout=20 -o BatchMode=yes box "cat >> '/workspace/ops/reports/$NAME'" < "$S/pending.log"; then
    : > "$S/pending.log"; break
  fi
  sleep 10
done
[ -s "$S/pending.log" ] && echo "$(TZ=Asia/Singapore date '+%Y-%m-%d %H:%M:%S') [mba] ssh box 失败，日志行留在 $S/pending.log 下次补发" >> "$S/mirror-$D.log"
exit 1
