#!/bin/bash
# orca-bot.deepvision.sg 守护（纯脚本，作为 Orca automation「ops · 03 orca-bot 守护」的 precheck 跑，永远 exit 1 => 不启动 agent）
# 连续 2 次不通 => POST 卡住兜底 webhook 叫醒 Coding助手（唤醒会让 box 恢复，box 看门狗/bot 再重启 orca-remote）
# 同一次故障最多每 10 分钟叫一次
# 日志 ~/.orca-state/orca-bot-guard/guard.log。webhook 每次都记 HTTP 码；非 2xx 时带响应体前 160 个字符（去掉 URL/KEY 和长串，
#   压成一行）。10-16 两段 14 次「webhook failed」当时不记码。10-19 演练查到一个原因：/bin/bash 3.2 在 UTF-8 下把 `$code）` 里
#   「）」的第一个字节当成变量名的一部分，body 里留下半个字符，webhook 回 400（Content-Length 对不上）。变量后面紧跟中文时一律写 ${x}。
# URL 和 KEY 只经 stdin 交给 curl，不进命令行参数、日志和输出。
# 测试用环境变量：GUARD_STATE_DIR、GUARD_ENV_FILE、GUARD_PROBE_URL、GUARD_BOT（payload 里的 bot，默认 coding）。
ST=${GUARD_STATE_DIR:-$HOME/.orca-state/orca-bot-guard}; mkdir -p "$ST"; LOG=$ST/guard.log
ENV_FILE=${GUARD_ENV_FILE:-$HOME/.config/grokbot/stuck-webhook.env}
ts(){ TZ=Asia/Singapore date '+%F %T'; }
code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' "${GUARD_PROBE_URL:-https://orca-bot.deepvision.sg/}")
if [ "$code" = 200 ]; then
  [ -f "$ST/fails" ] && echo "$(ts) recovered" >> "$LOG"
  rm -f "$ST/fails"; exit 1
fi
n=$(( $(cat "$ST/fails" 2>/dev/null || echo 0) + 1 )); echo $n > "$ST/fails"
echo "$(ts) down code=$code fails=$n" >> "$LOG"
[ $n -lt 2 ] && exit 1
last=$(cat "$ST/last_wake" 2>/dev/null || echo 0); now=$(date +%s)
[ $((now-last)) -lt 600 ] && exit 1
URL="" KEY=""
# shellcheck disable=SC1090
[ -r "$ENV_FILE" ] && . "$ENV_FILE"
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "$(ts) webhook failed http=no_config（$ENV_FILE 缺 URL 或 KEY）" >> "$LOG"; exit 1
fi
resp=$(mktemp "${TMPDIR:-/tmp}/orca-bot-guard.XXXXXX")
body="{\"bot\":\"${GUARD_BOT:-coding}\",\"task\":\"orca-bot 守护\",\"status\":\"down\",\"note\":\"orca-bot.deepvision.sg 连续 $n 次不通（code=${code}），请在 box 上重启 orca-remote\"}"
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
http=$(printf 'url = "%s"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' \
         "$(esc "$URL")" "$(esc "$KEY")" |
       curl -sS -m 20 -X POST -o "$resp" -w '%{http_code}' --data-binary "$body" -K - 2>/dev/null)
case "$http" in
  2??) echo $now > "$ST/last_wake"; echo "$(ts) woke Coding助手 http=$http" >> "$LOG" ;;
  *)
    # 响应体：去掉 URL/KEY、看着像令牌的长串，压成一行，最多 160 个字符
    snip=$(head -c 400 "$resp" 2>/dev/null | URL="$URL" KEY="$KEY" python3 -c '
import os, re, sys
t = sys.stdin.read()
for s in (os.environ.get("URL"), os.environ.get("KEY")):
    if s:
        t = t.replace(s, "<已隐藏>")
t = re.sub(r"[A-Za-z0-9_\-]{32,}", "<长串已隐藏>", t)
t = " ".join(t.split())
print(t[:160] + ("…" if len(t) > 160 else ""))' 2>/dev/null)
    echo "$(ts) webhook failed http=${http:-无响应}${snip:+ 响应：$snip}" >> "$LOG" ;;
esac
rm -f "$resp"
exit 1
