#!/bin/bash
# 叫醒前预过滤的真进程演练（PER-88）。真 notify-run / orca-wake / stuck-check / wake-prefilter / agent-stop，
# 真 Claude Code（haiku，一句话会话，经 notify-run --tty 起在独立的 tmux 服务器里），真 kill、真退出码。
# webhook 全部发到本机假接收端 wake/tests/mock_webhook.py（127.0.0.1，假 key）；不发真叫醒、不读真 webhook 配置：
# notify-run 和 stuck-check 用临时 HOME，orca-wake 的状态 / 配置 / webhook 目录都指临时目录；
# Claude 自己用真 HOME（登录），只加载 --settings 给的 hook（--setting-sources local，不加载用户的 hook）。
#
#   wake/tests/prefilter-drill.sh <产物目录> [用例...]
#       WAKE_DRILL_CODE=<目录>  被测代码（里面有 wake/bin、scripts），默认本仓库；回退测试指向 main 的导出
#       WAKE_DRILL_MODE=on|shadow|off  预过滤开关（默认 on）
#   用例名见下面的 CASES；不写就全跑。结果：<产物目录>/results.tsv、mock.jsonl、prefilter.log、各用例日志。
#
# 只在两次线上卡住检查扫描之间跑（每 15 分钟一次）。跑完关掉 tmux 服务器、假接收端，删掉演练工作区。
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
shift
CODE=$(cd "${WAKE_DRILL_CODE:-$REPO}" && pwd)
MODE=${WAKE_DRILL_MODE:-on}
# filter = 按预过滤开着判（该挡的挡）；send = 该挡的也都发出来（回退测试、shadow、off）
EXPECT=${WAKE_DRILL_EXPECT:-$([ "$MODE" = on ] && echo filter || echo send)}
BIN="$CODE/wake/bin"
REAL_HOME=$HOME
PORT=${WAKE_DRILL_PORT:-18821}
TMP=$(mktemp -d /tmp/pf-drill.XXXXXX)
FAKE="$TMP/home"
WS="$REPO/.pf-drill-$$"         # 在信任过的 ops 目录下，Claude 不弹信任对话框；带 pid，两份演练可以同时跑
SOCK="pf-drill-$$"
BOT=drill-bot
MOCK_OUT="$OUT/mock.jsonl"
RES="$OUT/results.tsv"
PFLOG="$TMP/state/prefilter.log"
CASES_ALL="r1a1 a2 r10 b1 b2 b3 r9 c1 r3 r3b d1 r8 d2 d3 r2 r5 r6 r7 f1 r4 e1 e2 r11 s1 s2"
CASES=${*:-$CASES_ALL}

mkdir -p "$FAKE/.config/grokbot/webhooks" "$TMP/state" "$TMP/config" "$TMP/stops" "$TMP/stuck" "$WS" "$TMP/cbin"
# claude 和 orca 要用真 HOME（登录、连 Orca）：同名小脚本只把 HOME 改回来再 exec（pid 不变，notify-run 照样认得出 claude）
for c in claude orca; do
    printf '#!/bin/sh\nHOME=%q; export HOME\nexec %q "$@"\n' "$REAL_HOME" "$(command -v "$c")" >"$TMP/cbin/$c"
    chmod +x "$TMP/cbin/$c"
done
for b in "$BOT" coding-assistant ops-system xinyue; do
    printf 'URL=http://127.0.0.1:%s/hook/%s\nKEY=drill-key\n' "$PORT" "$b" >"$FAKE/.config/grokbot/webhooks/$b.env"
done
cp "$FAKE/.config/grokbot/webhooks/coding-assistant.env" "$FAKE/.config/grokbot/stuck-webhook.env"
printf '%s\ncoding-assistant\nops-system\nxinyue\n' "$BOT" >"$TMP/config/enabled-bots"
cat >"$TMP/settings.json" <<EOF
{"hooks": {
$(for ev in UserPromptSubmit Stop StopFailure PermissionRequest Notification; do
    printf '"%s": [{"matcher": "%s", "hooks": [{"type": "command", "timeout": 10, "async": true, "command": "[ -z \\"${ORCA_DISPATCH_BOT:-}\\" ] || WAKE_AGENT_PID=$PPID %s claude-hook"}]}]%s\n' \
        "$ev" "$([ "$ev" = Notification ] && echo 'idle_prompt|permission_prompt' || echo '*')" "$BIN/orca-wake" \
        "$([ "$ev" = Notification ] || echo ,)"
done)
}}
EOF
: >"$MOCK_OUT"
printf 'case\tinput\texpect\tmock\tprefilter_log\tresult\n' >"$RES"
{
    echo "code: $CODE ($(git -C "$CODE" rev-parse HEAD 2>/dev/null || cat "$CODE/.drill-commit" 2>/dev/null))"
    echo "mode: $MODE  expect: $EXPECT  tmp: $TMP  start: $(date '+%F %T %z')"
    echo "claude: $(claude --version 2>/dev/null)  python3: $(python3 --version 2>&1)  host: $(hostname -s)"
} >"$OUT/env.txt"

# 每个进程都从干净的环境起（不带这个会话的 ORCA_* / CLAUDE*），只给演练要的变量
# /usr/bin 在前：python3 用 macOS 自带的 3.9
base_env=(env -i PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$REAL_HOME/.local/bin"
    HOME="$FAKE" USER="$USER" LOGNAME="${LOGNAME:-$USER}" TERM=xterm-256color LANG=en_US.UTF-8 TMPDIR="${TMPDIR:-/tmp}"
    ORCA_WAKE_STATE_DIR="$TMP/state" ORCA_WAKE_CONFIG_DIR="$TMP/config"
    ORCA_WAKE_WEBHOOK_DIRS="$FAKE/.config/grokbot/webhooks" ORCA_WAKE_RETRY_DELAYS=1,1 ORCA_WAKE_SETTLE_S=3
    NOTIFY_RUN_LOG="$TMP/notify-run.log" NOTIFY_RUN_START_MIN=0 AGENT_STOP_DIR="$TMP/stops"
    WAKE_PREFILTER="$MODE" WAKE_PREFILTER_BIN="$BIN/wake-prefilter" WAKE_PREFILTER_ORCA="$TMP/cbin/orca")
CLAUDE=("$TMP/cbin/claude" --model haiku --setting-sources local --settings "$TMP/settings.json"
    --strict-mcp-config)

python3 "$REPO/wake/tests/mock_webhook.py" --port "$PORT" --out "$MOCK_OUT" --key drill-key &
mock=$!
cleanup() {
    tmux -L "$SOCK" kill-server 2>/dev/null
    kill "$mock" 2>/dev/null
    wait "$mock" 2>/dev/null
    [ -z "${E1_WT:-}" ] || git -C "$REPO" worktree remove --force "$E1_WT" 2>/dev/null
    cp "$PFLOG" "$OUT/prefilter.log" 2>/dev/null
    cp "$TMP/notify-run.log" "$OUT/notify-run.log" 2>/dev/null
    cp "$TMP/state/wake.log" "$OUT/wake.log" 2>/dev/null
    cp "$TMP/stuck/stuck-check.log" "$OUT/stuck-check.log" 2>/dev/null
    rm -rf "$WS" "$TMP"
}
trap cleanup EXIT
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" -X POST -d '{}' && break; sleep 0.1; done
: >"$MOCK_OUT"

say() { echo "$(date +%T) $*" | tee -a "$OUT/drill.log"; }
# count <task> [status]：假接收端收到的条数
count() {
    python3 - "$MOCK_OUT" "$1" "${2:-}" <<'EOF'
import json, sys
n = 0
for line in open(sys.argv[1]):
    b = json.loads(line)["body"]
    if b.get("task") == sys.argv[2] and (not sys.argv[3] or b.get("status") == sys.argv[3]):
        n += 1
print(n)
EOF
}
# summary <task>：「done×1 idle×0」这种
summary() {
    python3 - "$MOCK_OUT" "$1" <<'EOF'
import collections, json, sys
c = collections.Counter(json.loads(l)["body"].get("status") for l in open(sys.argv[1])
                        if json.loads(l)["body"].get("task") == sys.argv[2])
print(" ".join("%s×%d" % kv for kv in sorted(c.items())) or "0 条")
EOF
}
pflines() { grep -F "	$1	" "$PFLOG" 2>/dev/null | awk -F'\t' '{printf "%s%s:%s", (NR>1?" | ":""), $3, $4}'; }
pfcount() { local n; n=$(grep -cF "	$1	" "$PFLOG" 2>/dev/null); echo "${n:-0}"; }
waitfor() {  # waitfor <秒> <命令...>
    local t=$1; shift
    for _ in $(seq 1 $((t * 2))); do "$@" && return 0; sleep 0.5; done
    return 1
}
has() { [ "$(count "$1" "$2")" -ge "${3:-1}" ]; }
settled() { [ -z "$(ls "$TMP/state/inflight" 2>/dev/null)" ]; }
stopped() {  # orca-wake 的会话状态里这件活的回合已经结束（Stop）
    python3 - "$TMP/state/sessions" "pfdrill $1" <<'EOF'
import glob, json, os, sys
for f in glob.glob(os.path.join(sys.argv[1], "*.json")):
    d = json.load(open(f))
    if d.get("task") == sys.argv[2] and int(d.get("turn") or 0) >= 1 and (d.get("stop") or {}).get("turn") == d.get("turn"):
        sys.exit(0)
sys.exit(1)
EOF
}
stopped2() {  # 第 2 回合结束
    python3 - "$TMP/state/sessions" "pfdrill $1" <<'EOF'
import glob, json, os, sys
for f in glob.glob(os.path.join(sys.argv[1], "*.json")):
    d = json.load(open(f))
    if d.get("task") == sys.argv[2] and int(d.get("turn") or 0) >= 2 and (d.get("stop") or {}).get("turn") == d.get("turn"):
        sys.exit(0)
sys.exit(1)
EOF
}
row() {  # row <case> <input> <expect> <task> <ok 0|1>
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(summary "$4")" "$(pflines "$4")" \
        "$([ "$5" = 1 ] && echo 符合 || echo 不符合)" >>"$RES"
    say "$1 $([ "$5" = 1 ] && echo 符合 || echo 不符合)：$(summary "$4")；prefilter.log：$(pflines "$4")"
}
# tty <名字> <工作区> <task> <命令...>：在独立 tmux 会话里经 notify-run --tty 起命令
tty() {
    local name=$1 dir=$2 task=$3; shift 3
    mkdir -p "$dir"
    tmux -L "$SOCK" new-session -d -s "$name" -x 160 -y 45 -c "$dir" \
        "$(printf '%q ' exec "${base_env[@]}" "${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}" notify-run --bot "$BOT" --task "$task" --tty -- "$@") 2>>$(printf '%q' "$OUT/$name.stderr")"
}
nrpid() { tmux -L "$SOCK" display-message -p -t "$1" '#{pane_pid}' 2>/dev/null; }
alive() { tmux -L "$SOCK" has-session -t "$1" 2>/dev/null && kill -0 "$(nrpid "$1")" 2>/dev/null; }
gone() { ! alive "$1"; }
keys() { tmux -L "$SOCK" send-keys -t "$1" "$2"; sleep 0.3; tmux -L "$SOCK" send-keys -t "$1" Enter; }
screen() { tmux -L "$SOCK" capture-pane -p -t "$1" >"$OUT/$1.screen.txt" 2>/dev/null; }
child_of() { pgrep -P "$1" | head -1; }
finish_session() {  # 关掉还在的会话（演练收尾，不算用例）
    tmux -L "$SOCK" kill-session -t "$1" 2>/dev/null
    waitfor 30 settled
}
OKP="Reply with exactly one word: OK"
EXTRA_ENV=()

run_case() {
    local c=$1 t="pfdrill $1"
    case "$c" in
    r1a1)  # 首次 done 照发（r1）；之后同一回合的 idle 挡（a1：done→idle）
        # 交互 claude，回合结束（Stop，idle 要等 8 秒 settle）后马上 /exit：done 先送达，idle 后到
        EXTRA_ENV=(ORCA_WAKE_SETTLE_S=30)
        tty r1a1 "$WS/r1a1" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions "$OKP"
        EXTRA_ENV=()
        waitfor 120 stopped r1a1; keys r1a1 /exit
        waitfor 60 gone r1a1; sleep 32; waitfor 30 settled
        row r1 "交互 claude 一句话，回合结束后马上 /exit" "done 照发" "$t" "$([ "$(count "$t" done)" = 1 ] && echo 1 || echo 0)"
        if [ "$EXPECT" = filter ]; then ok=$([ "$(count "$t" idle)" = 0 ] && grep -qF "	$t	" "$PFLOG" && echo 1 || echo 0)
        else ok=$([ "$(count "$t" idle)" = 1 ] && echo 1 || echo 0); fi
        row a1 "同一会话 done 先到（Stop 的 idle 等 30 秒 settle），idle 后到" "idle 挡（a，覆盖）" "$t" "$ok" ;;
    a2)  # idle 先送达，然后 /exit：done 挡
        tty a2 "$WS/a2" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions "$OKP"
        waitfor 120 has "$t" idle; screen a2; keys a2 /exit
        waitfor 60 gone a2; waitfor 30 settled
        row a2 "交互 claude，回合结束 idle 送达后 /exit" "done 挡（a，覆盖）" "$t" \
            "$(want "$t" idle 1 done 0)" ;;
    r10)  # idle:1 送达 → 第 2 回合留了后台 shell（Stop 时有后台任务，按设计不发 idle）→ /exit：done 照发
        tty r10 "$WS/r10" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions "$OKP"
        waitfor 120 has "$t" idle
        keys r10 "Use the Bash tool with run_in_background=true to run: sleep 300 . Do not wait for it; then reply with exactly one word: OK"
        waitfor 120 stopped2 r10; sleep 2; keys r10 /exit
        # 有后台 shell 时 /exit 会先问要不要退出：截屏留证，再回车确认
        waitfor 8 gone r10 || { screen r10; tmux -L "$SOCK" send-keys -t r10 Enter; }
        waitfor 60 gone r10; waitfor 30 settled
        row r10 "idle:1 送达后第 2 回合起后台 shell（Stop 有后台任务，不发 idle），再 /exit" "done 照发（中间有新回合）" "$t" \
            "$(want_send "$t" idle 1 done 1)" ;;
    b1)  # 本地替身检查：done 已送达（r10 的账本，第 2 回合）后，旧回合 idle:1 的 payload 直接喂 wake-prefilter
        local sid u
        u=$(ls "$TMP/state/prefilter/units/" 2>/dev/null | head -1)
        sid=$(python3 -c "import json,glob,sys
for f in glob.glob('$TMP/state/prefilter/units/*.json'):
    d=json.load(open(f))
    if d.get('task')=='pfdrill r10' and d.get('status')=='done': print(d['session_id'], d['turn'])" | head -1)
        if [ -z "$sid" ]; then
            printf 'b1\t本地替身检查：没有 r10 的 done 账本\t-\t-\t-\t没跑\n' >>"$RES"; say "b1 没跑：没有 r10 的 done 账本"; return
        fi
        set -- $sid
        printf '{"bot":"%s","task":"pfdrill r10","status":"idle","agent":"claude","session_id":"%s","seq":"%s","dedup_key":"claude:%s:idle:%s","worktree":"%s","source":"wake-hook"}' \
            "$BOT" "$1" "$(( ${2%%.*} - 1 ))" "$1" "$(( ${2%%.*} - 1 ))" "$WS/r10" >"$TMP/b1.json"
        "${base_env[@]}" "$BIN/wake-prefilter" check --source orca-wake <"$TMP/b1.json" >"$TMP/b1.out"; rc=$?
        printf 'b1\t本地替身检查：r10 的 done（第 %s 回合）已送达后，构造旧回合 idle:%s 交给 wake-prefilter\t%s\t-\t退出码 %s：%s\t%s\n' \
            "$2" "$(( ${2%%.*} - 1 ))" "$([ "$EXPECT" = filter ] && echo '退出码 3（b，覆盖）' || echo '退出码 0')" "$rc" "$(tr "\t" " " <"$TMP/b1.out")" \
            "$( { [ "$EXPECT" = filter ] && [ $rc = 3 ]; } || { [ "$EXPECT" != filter ] && [ $rc = 0 ]; } && echo 符合 || echo 不符合)" >>"$RES"
        say "b1 rc=$rc $(cat "$TMP/b1.out")" ;;
    b2)  # 同一件活（同工作区、bot、task）另一个 notify-run 的 done 已送达，之后这个被 HUP：killed 挡
        tty b2p "$WS/b2" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions "$OKP"
        waitfor 120 has "$t" idle; sleep 1
        tty b2q "$WS/b2" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions -p "$OKP"
        waitfor 120 gone b2q; waitfor 60 has "$t" done; sleep 10; waitfor 30 settled
        kill -HUP "$(nrpid b2p)"; waitfor 60 gone b2p; waitfor 30 settled
        row b2 "同工作区同 task 两个 claude：第二个 -p 的 done 送达后，第一个的 notify-run 收到 HUP（没有 agent-stop 标记）" \
            "killed 挡（b，覆盖）；done 照发一条" "$t" "$(want "$t" done 1 killed 0)" ;;
    b3 | r9)  # Sleep 工作区：idle / done 挡（b3）；failed 照发（r9）
        if [ -z "${SLEEP_WS:-}" ]; then
            printf '%s\tSleep 工作区\t-\t-\t-\t没跑（没给 WAKE_DRILL_SLEEP_WS）\n' "$c" >>"$RES"; say "$c 没跑"; return
        fi
        [ ! -x "$BIN/wake-prefilter" ] || "${base_env[@]}" "$BIN/wake-prefilter" _refresh worktrees 2>/dev/null
        if [ "$c" = b3 ]; then
            tty b3 "$SLEEP_WS" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions -p "$OKP"
            waitfor 120 gone b3; sleep 6; waitfor 30 settled
            row b3 "Orca 工作区状态 sleep 里 claude -p 一句话（-p 不跑异步 Stop hook，只有 done）" "done 挡（b）" "$t" "$(want "$t" done 0)"
        else
            tty r9 "$SLEEP_WS" "$t" "${CLAUDE[@]}" --model no-such-model-pf -p "$OKP"
            waitfor 120 gone r9; waitfor 30 settled
            row r9 "同一个 sleep 工作区，claude 用不存在的模型，退出非 0" "failed 照发" "$t" "$(want_send "$t" failed 1)"
        fi ;;
    c1 | r3)  # agent-stop --mark-only 后真 kill -HUP notify-run：killed 挡（c1）；没有标记的照发（r3）
        tty "$c" "$WS/$c" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions "$OKP"
        waitfor 120 has "$t" idle; sleep 1
        local nr; nr=$(nrpid "$c")
        if [ "$c" = c1 ]; then
            "${base_env[@]}" "$BIN/agent-stop" --mark-only --by drill --reason "PER-88 演练 c1：派活方自己关" "$(child_of "$nr")" \
                >>"$OUT/c1.agent-stop.txt" 2>&1
        fi
        kill -HUP "$nr"; waitfor 60 gone "$c"; waitfor 30 settled
        if [ "$c" = c1 ]; then
            row c1 "idle 送达后 agent-stop --mark-only，再 kill -HUP notify-run（同关终端）" "killed 挡（c）" "$t" "$(want "$t" idle 1 killed 0)"
        else
            row r3 "idle 送达后直接 kill -HUP notify-run，没有标记" "killed 照发" "$t" "$(want_send "$t" idle 1 killed 1)"
        fi ;;
    r3b)  # agent 崩溃：kill -9 claude
        tty r3b "$WS/r3b" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions "$OKP"
        waitfor 120 has "$t" idle; sleep 1
        kill -9 "$(child_of "$(nrpid r3b)")"; waitfor 60 gone r3b; waitfor 30 settled
        row r3b "idle 送达后 kill -9 claude（崩溃）" "failed 137 照发" "$t" "$(want_send "$t" idle 1 failed 1)" ;;
    d2)  # 内置放行：bot ops-system + task「[演练 叫醒通路]…」，开关 on 也照发，prefilter.log 记一行放行
        local BOT=ops-system dt="[演练 叫醒通路] pfdrill d2" ok=0
        tty d2 "$WS/d2" "$dt" "${CLAUDE[@]}" --dangerously-skip-permissions -p "$OKP"
        waitfor 120 gone d2; sleep 6; waitfor 30 settled
        if [ "$(count "$dt" done)" = 1 ] && [ "$(count "$dt")" = 1 ]; then
            if [ -x "$BIN/wake-prefilter" ] && [ "$MODE" != off ]; then
                [ "$(pfcount "$dt")" = 1 ] && grep -F "	$dt	" "$PFLOG" | grep -qF '放行：' && ok=1
            else ok=1; fi
        fi
        row d2 "bot ops-system，task「${dt}」，claude -p 一句话" "done 照发；prefilter.log 一行放行" "$dt" "$ok" ;;
    d3)  # 放行只认 ops-system + [演练 叫醒通路]：别的 bot 或别的 [演练 照旧挡
        local dx="[演练 叫醒通路] pfdrill d3" dy="[演练 pfdrill d3] 别的演练"
        BOT=xinyue tty d3x "$WS/d3x" "$dx" "${CLAUDE[@]}" --dangerously-skip-permissions -p "$OKP"
        BOT=ops-system tty d3y "$WS/d3y" "$dy" "${CLAUDE[@]}" --dangerously-skip-permissions -p "$OKP"
        waitfor 120 gone d3x; waitfor 120 gone d3y; sleep 6; waitfor 30 settled
        row d3 "bot xinyue，task「${dx}」，claude -p 一句话" "done 挡（d）" "$dx" "$(want "$dx" done 0)"
        row d3 "bot ops-system，task「${dy}」，claude -p 一句话" "done 挡（d）" "$dy" "$(want "$dy" done 0)" ;;
    d1 | r8)  # 「[演练」task：不在白名单挡（d1）；在白名单照发（r8）
        local dt="[演练 pfdrill $c] 预过滤"
        if [ "$c" = r8 ]; then printf '# 演练白名单\npfdrill r8\n' >"$TMP/config/prefilter-drill-allow"; fi
        tty "$c" "$WS/$c" "$dt" "${CLAUDE[@]}" --dangerously-skip-permissions -p "$OKP"
        waitfor 120 gone "$c"; sleep 6; waitfor 30 settled
        rm -f "$TMP/config/prefilter-drill-allow"
        if [ "$c" = d1 ]; then
            row d1 "task「${dt}」，claude -p 一句话（只有 done），白名单里没有" "done 挡（d）" "$dt" "$(want "$dt" done 0)"
        else
            row r8 "task「${dt}」，prefilter-drill-allow 有一行 pfdrill r8" "done 照发" "$dt" "$(want_send "$dt" done 1)"
        fi ;;
    r2)  # 非 0 退出
        tty r2 "$WS/r2" "$t" "${CLAUDE[@]}" --model no-such-model-pf -p "$OKP"
        waitfor 120 gone r2; waitfor 30 settled
        row r2 "claude 用不存在的模型，退出非 0" "failed 照发" "$t" "$(want_send "$t" failed 1)" ;;
    r5)  # 等审批：默认权限模式让它跑一条命令
        tty r5 "$WS/r5" "$t" "${CLAUDE[@]}" --permission-mode default "Use the Bash tool to run exactly: echo hi > pf-r5.txt"
        waitfor 120 has "$t" needs_input; screen r5; finish_session r5
        row r5 "交互 claude（默认权限模式）要用 Bash 写文件，弹审批框" "needs_input 照发" "$t" "$(want_send "$t" needs_input 1)" ;;
    r6)  # error、blocked：Pi 扩展调用的同一条 orca-wake send（agent 用 sleep 代替 Pi）
        tty r6 "$WS/r6" "$t" sleep 120
        sleep 1
        local nr pid; nr=$(nrpid r6); pid=$(child_of "$nr")
        for s in error blocked; do
            echo "drill $s" | "${base_env[@]}" ORCA_DISPATCH_BOT="$BOT" ORCA_TASK_ID="$t" ORCA_DISPATCH_PID="$nr" \
                "$BIN/orca-wake" send --agent pi --status "$s" --session "pf-drill-r6" --seq "s-$s" --agent-pid "$pid" --cwd "$WS/r6"
        done
        waitfor 30 has "$t" blocked; waitfor 30 settled; finish_session r6
        row r6 "orca-wake send --agent pi --status error / blocked（Pi 扩展调的命令；agent 是 notify-run 下的 sleep，不是真 Pi）" \
            "error、blocked 都照发" "$t" "$(want_send "$t" error 1 blocked 1)" ;;
    r7)  # agent 没起来：不信任的目录，claude 停在信任对话框
        EXTRA_ENV=(NOTIFY_RUN_START_MIN=0.25)
        tty r7 "$TMP/untrusted-r7" "$t" "${CLAUDE[@]}" "$OKP"
        EXTRA_ENV=()
        waitfor 90 has "$t" stuck; screen r7; finish_session r7
        row r7 "没信任过的目录里起交互 claude（停在信任对话框），NOTIFY_RUN_START_MIN=0.25" "stuck / agent_not_started 照发" "$t" \
            "$(want_send "$t" stuck 1)" ;;
    f1)  # 嵌套 notify-run：agent 回合中途自己跑一条 notify-run，done 挡；外层回合结束的 idle 照发
        local it="pfdrill f1 inner"
        tty f1 "$WS/f1" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions \
            "Run this exact shell command in the foreground and wait for it: HOME=$FAKE $BIN/notify-run --bot $BOT --task '$it' -- sleep 2 ; then reply with exactly one word: OK"
        waitfor 180 has "$t" idle; sleep 2; screen f1; finish_session f1
        local ok=0
        if [ "$EXPECT" = filter ]; then [ "$(count "$it")" = 0 ] && [ "$(pfcount "$it")" -ge 1 ] && [ "$(count "$t" idle)" = 1 ] && ok=1
        else [ "$(count "$it" done)" = 1 ] && ok=1; fi
        printf 'f1\t外层交互 claude 回合中途跑 notify-run -- sleep 2（嵌套）\t内层 done 挡（f）；外层 idle 照发\t内层 %s；外层 %s\t%s\t%s\n' \
            "$(summary "$it")" "$(summary "$t")" "$(pflines "$it")" "$([ $ok = 1 ] && echo 符合 || echo 不符合)" >>"$RES"
        say "f1 inner $(summary "$it") outer $(summary "$t") pf $(pflines "$it")" ;;
    r4 | e1 | e2)  # stuck-check --send：真 stuck-check、真 post；pending 是写进临时状态目录的
        stuck_case "$c" ;;
    r11)  # 预过滤自己坏了：崩溃（exit 1）、超时（sleep 10）都照发；这里的 prefilter 是替身脚本
        printf '#!/bin/sh\nexit 1\n' >"$TMP/pf-crash"; printf '#!/bin/sh\nsleep 10\nexit 3\n' >"$TMP/pf-hang"
        chmod +x "$TMP/pf-crash" "$TMP/pf-hang"
        for k in crash hang; do
            local s0; s0=$(date +%s)
            "${base_env[@]}" WAKE_PREFILTER=on WAKE_PREFILTER_BIN="$TMP/pf-$k" \
                "$BIN/notify-run" --bot "$BOT" --task "$t $k" --no-tty -- true >>"$OUT/r11.txt" 2>&1
            echo "$k: notify-run 用时 $(( $(date +%s) - s0 )) 秒" >>"$OUT/r11.txt"
        done
        printf 'r11\t替身 prefilter：exit 1 / sleep 10 后 exit 3；notify-run --no-tty -- true\t都照发（超时 3 秒）\tcrash %s；hang %s\t-\t%s\n' \
            "$(summary "$t crash")" "$(summary "$t hang")" \
            "$([ "$(count "$t crash" done)" = 1 ] && [ "$(count "$t hang" done)" = 1 ] && echo 符合 || echo 不符合)" >>"$RES"
        say "r11 $(cat "$OUT/r11.txt" | tr '\n' ' ')" ;;
    s1)  # off：不调用 wake-prefilter（间谍脚本没被调），payload 和 main 一样（另一边由回退测试跑同一条）
        printf '#!/bin/sh\necho called >>%s\nexit 3\n' "$TMP/spy.calls" >"$TMP/spy"; chmod +x "$TMP/spy"
        (cd "$WS" && "${base_env[@]}" WAKE_PREFILTER=off WAKE_PREFILTER_BIN="$TMP/spy" \
            "$BIN/notify-run" --bot "$BOT" --task "$t" --no-tty -- printf 'fixed output\n' >/dev/null 2>&1)
        python3 - "$MOCK_OUT" "$t" >"$OUT/s1.payload.json" <<'EOF'
import json, sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["body"].get("task") == sys.argv[2]:
        print(json.dumps(r["body"], ensure_ascii=False, sort_keys=True))
EOF
        printf 's1\tWAKE_PREFILTER=off，WAKE_PREFILTER_BIN 指向会记录调用的脚本；notify-run --no-tty -- printf\t照发，间谍脚本没被调\t%s；间谍调用 %s 次\t-\t%s\n' \
            "$(summary "$t")" "$(cat "$TMP/spy.calls" 2>/dev/null | wc -l | tr -d ' ')" \
            "$([ "$(count "$t" done)" = 1 ] && [ ! -e "$TMP/spy.calls" ] && echo 符合 || echo 不符合)" >>"$RES" ;;
    s2)  # shadow：会挡的照发，prefilter.log 记「shadow 会挡」（输入同 a2）
        EXTRA_ENV=(WAKE_PREFILTER=shadow)
        tty s2 "$WS/s2" "$t" "${CLAUDE[@]}" --dangerously-skip-permissions "$OKP"
        EXTRA_ENV=()
        waitfor 120 has "$t" idle; sleep 1; keys s2 /exit
        waitfor 60 gone s2; waitfor 30 settled
        local ok=0
        if [ "$(count "$t" done)" = 1 ] && [ "$(count "$t" idle)" = 1 ]; then
            if [ "$EXPECT" = filter ]; then grep -F "	$t	" "$PFLOG" | grep -qF 'shadow 会挡' && ok=1; else ok=1; fi
        fi
        row s2 "WAKE_PREFILTER=shadow，同 a2 的输入" "done、idle 都照发；prefilter.log 记 shadow 会挡" "$t" "$ok" ;;
    *) say "不认识的用例 $c" ;;
    esac
}

# want <task> <status> <n> ...：开关 on 时按给的条数判；不是 on（shadow / off / 回退测试）时该挡的也应该发出来，
# 所以只要求每个 status 至少 1 条（给的 n 是 0 的也算 1）
want() {
    local t=$1; shift
    while [ $# -ge 2 ]; do
        local got; got=$(count "$t" "$1")
        if [ "$EXPECT" = filter ]; then [ "$got" = "$2" ] || { echo 0; return; }
        else [ "$got" -ge 1 ] || { echo 0; return; }; fi
        shift 2
    done
    echo 1
}
want_send() {  # 必须照发的：不管开关，条数都按给的判，且 prefilter.log 没有这件活
    local t=$1; shift
    [ "$(pfcount "$t")" = 0 ] || { echo 0; return; }
    while [ $# -ge 2 ]; do [ "$(count "$t" "$1")" = "$2" ] || { echo 0; return; }; shift 2; done
    echo 1
}

stuck_case() {
    local c=$1 t="pfdrill $1" wt pending
    case "$c" in
    r4)
        pending=$(python3 -c "
import json,time
s=lambda k,i:{'id':i,'key':'iMac:$WS/r4:'+k,'kind':k,'bot':'$BOT','task':'$t','worktree':'iMac:$WS/r4','marker':time.time()-3600,
    'note':'演练：'+k,'machine':'iMac'}
print(json.dumps({'created':time.time(),'suspects':[s('agent_idle','S1'),s('agent_silent','S2')],'direct':[]},ensure_ascii=False))") ;;
    e1)
        # 一个真实的、经 merge 合进 origin/main 的提交（main 第一个 merge 提交的第二个父提交），干净的 detached 工作区
        local m; m=$(git -C "$REPO" rev-list --merges --first-parent -n 1 origin/main)
        E1_WT="$TMP/e1-wt"; git -C "$REPO" worktree add --detach "$E1_WT" "$m^2" >/dev/null 2>&1
        wt="iMac:$E1_WT"
        pending=$(direct "$t" "$wt" "") ;;
    e2)
        # 工作区路径里不能带别的编号（PER-88 的工作区路径就带），不然编号不唯一、不查 Linear
        wt="iMac:$TMP/e2"; mkdir -p "$TMP/e2"
        pending=$(direct "$t" "$wt" "${WAKE_DRILL_E2_ISSUE:-}") ;;
    esac
    printf '%s' "$pending" >"$TMP/stuck/pending.json"
    stuck() {
        "${base_env[@]}" STUCK_STATE_DIR="$TMP/stuck" STUCK_WEBHOOK_DIR="$FAKE/.config/grokbot/webhooks" \
            STUCK_ENV_FILE="$FAKE/.config/grokbot/stuck-webhook.env" STUCK_POST_GAP=0 STUCK_BACKOFF=1 \
            STUCK_PREFILTER="$BIN/wake-prefilter" STUCK_ORCA_WAKE="$BIN/orca-wake" STUCK_NO_GATE=1 \
            "$CODE/scripts/stuck-check.sh" --send >>"$OUT/$c.stuck.txt" 2>&1
    }
    stuck
    case "$c" in
    r4) row r4 "stuck-check --send，pending 里 agent_idle、agent_silent 两条嫌疑" "两条都照发" "$t" "$(want_send "$t" stuck 2)" ;;
    e1) row e1 "stuck-check --send，stop_not_delivered，工作区干净、HEAD 经 merge 合进 origin/main" "挡（e）" "$t" "$(want "$t" stuck 0)" ;;
    e2)
        local first; first=$(summary "$t")
        # 第一次 Linear 缓存是冷的：照发并在后台刷新；等刷新完再发一次同样的
        waitfor 90 test -e "$TMP/state/prefilter/cache/linear-${WAKE_DRILL_E2_ISSUE:-X}.json"
        printf '%s' "$(direct "$t" "$wt" "${WAKE_DRILL_E2_ISSUE:-}")" >"$TMP/stuck/pending.json"
        stuck
        local n; n=$(count "$t" stuck)
        printf 'e2\tstuck-check --send，stop_not_delivered，issue %s（Linear 评论里有 [Zack答-…merge…]）发两次\t第一次缓存冷照发，刷新后第二次挡（e）\t第一次后 %s；两次后 %s\t%s\t%s\n' \
            "${WAKE_DRILL_E2_ISSUE:-?}" "$first" "$(summary "$t")" "$(pflines "$t")" \
            "$( { [ "$EXPECT" = filter ] && [ "$n" = 1 ]; } || { [ "$EXPECT" != filter ] && [ "$n" = 2 ]; } && echo 符合 || echo 不符合)" >>"$RES"
        say "e2 $(summary "$t") $(pflines "$t")" ;;
    esac
}
direct() {  # direct <task> <worktree> <issue>：一条 stop_not_delivered 直发
    python3 -c "
import json,sys,time
t,wt,iss=sys.argv[1:4]
p={'bot':'$BOT','task':t,'worktree':wt,'status':'stuck','kind':'stop_not_delivered','issue':iss,
   'note':'演练：最后一次停下没送达','machine':'iMac','source':'stuck-check'}
print(json.dumps({'created':time.time(),'suspects':[],'direct':[{'id':'undelivered:'+wt,'cfg':'bot:$BOT','payload':p}]},ensure_ascii=False))" "$1" "$2" "$3"
}

SLEEP_WS=${WAKE_DRILL_SLEEP_WS:-}
say "开始：$CODE mode=$MODE 用例：$CASES"
for c in $CASES; do
    say "== $c"
    run_case "$c"
done
say "结束"
cat "$RES"
