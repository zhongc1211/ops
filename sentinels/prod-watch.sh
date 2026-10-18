#!/bin/bash
# Orca precheck for「ops · 23 生产版本哨兵」（iMac，每 15 分钟）。活全在这里干完，永远 exit 1，不启动模型。
# 1) prod_fetch.py 用 iMac 上已有的只读令牌（orca-cf-usage-readonly）查 5 个生产 Worker 当前在线的 deployment。
# 2) 结果经 ssh 交给 box 上的 prod_ledger.py apply：和 box 的台账 /workspace/ops/reports/prod-ledger.md（以它为准）比，
#    有变化就追加「未报」行并叫醒 Coding助手；日志写 box 的 reports/prod-watch-YYYYMMDD.log。
# 3) box 打印的日志行同时存在本机镜像 ~/.orca-state/prod-watch/mirror-YYYYMMDD.log。
# box 连不上时：结果和错误只记镜像；连续 4 次（约 1 小时）连不上才从 iMac 叫醒 Coding助手，6 小时内最多一次。
# 演练：PROD_WATCH_DRILL=1 PROD_LEDGER=<过期的台账副本> prod-watch.sh（不碰真台账，日志进 reports/drills/）。
# ssh 走 everos-ingest 那把 iMac→box 的钥匙（~/.ssh/config 里的 Host box）。
B=${PROD_WATCH_BIN:-$HOME/.orca-state/bin/sentinels}
S=$HOME/.orca-state/prod-watch; mkdir -p "$S"
D=$(TZ=Asia/Singapore date +%Y%m%d); M="$S/mirror-$D.log"
NR=$(command -v notify-run || echo "$HOME/.local/bin/notify-run")
ts() { TZ=Asia/Singapore date '+%Y-%m-%d %H:%M:%S'; }

python3 "$B/prod_fetch.py" > "$S/last.json" 2> "$S/last.err"; frc=$?
args="apply --fetch-rc $frc"
[ -n "${PROD_LEDGER:-}" ] && args="$args --ledger '$PROD_LEDGER'"
[ "${PROD_WATCH_DRILL:-}" = 1 ] && args="$args --drill"

SSH_OPTS=(-o ConnectTimeout=20 -o BatchMode=yes)
ok=0
for attempt in 1 2 3; do
  ssh "${SSH_OPTS[@]}" box "python3 /workspace/ops/sentinels/prod_ledger.py $args" < "$S/last.json" >> "$M" 2>&1
  rc=$?
  [ $rc -ne 255 ] && { ok=1; break; }
  sleep 10
done

f="$S/box-fail"
if [ $ok = 1 ]; then
  echo 0 > "$f"
  [ $rc -ne 0 ] && echo "$(ts) box 上 prod_ledger.py exit $rc（fetch rc=$frc）" >> "$M"
else
  n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); echo $n > "$f"
  echo "$(ts) ssh box 3 次都失败（连续第 $n 次），这次没比对台账；fetch rc=$frc，结果在 $S/last.json" >> "$M"
  last=$(cat "$S/box-fail-alerted" 2>/dev/null || echo 0); now=$(date +%s)
  if [ $n -ge 4 ] && [ $((now - last)) -ge 21600 ]; then
    timeout 180 "$NR" --bot coding-assistant --no-tty --task "ops · 23 生产版本哨兵：iMac 连续 $n 次 ssh 不到 box" -- \
      sh -c "echo 'iMac 上的生产版本哨兵连续 $n 次连不上 box，台账没在更新。镜像日志 $M'" >/dev/null 2>&1
    echo "$now" > "$S/box-fail-alerted"
  fi
fi
exit 1
