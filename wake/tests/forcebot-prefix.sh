#!/bin/bash
# PER-105：FORCE_BOT 强制演练给 task 加「[演练 叫醒通路] 」的本地替身检查。不是 E2E：接收端是 mock_webhook.py，
# key 是假的，orca 是假脚本，HOME 是临时目录；stuck-check 用 --send 读临时 pending.json，不扫真 Orca。
#   wake/tests/forcebot-prefix.sh [<代码目录>] [<产物目录>]
# 环境变量：FORCEBOT_BASE=<目录> 对照用的旧代码（默认 git archive e5c61f1），FORCEBOT_PREFILTER=<wake-prefilter 路径>
#   设了就把收到的强制演练 payload 喂给它 check（mode=on），结果写进 prefilter.txt（C，只记录，不算断言）。
#
# 先写的失败方式（这个检查要能抓到的）：
#   F1 STUCK_FORCE_BOT 设了，嫌疑（suspects）发给 ops-system 但 task 没有前缀              → S1
#   F2 直发 cfg=bot:<bot>（停下没送达等）改发 ops-system 但没前缀                           → S2
#   F3 直发 cfg=fallback（自动任务没跑完等）走 ops-system 的 webhook，但 payload 的 bot 还是
#      coding-assistant 或没前缀：PER-88 规则 d 只放行 bot=ops-system，会把它挡掉           → S3
#   F4 cfg=stuck（报了没人验收，发 stuck-webhook.env，不受 FORCE_BOT 影响）被加了前缀       → S4
#   F5 task 已经以「[演练 叫醒通路]」开头，又加一次                                         → S5
#   F6 没设 STUCK_FORCE_BOT 时 payload 和旧代码不一样（同一份 pending）                     → S6
#   F7 heartbeat-watch.sh 强制演练没前缀 / 没设时和旧代码不一样                             → H1、H2
#   F8 unpushed_scan.py 强制演练标题没前缀；--drill 时「【演练】」跑到前缀前面；没设时变了   → U1、U2、U3
#   F10 演练时 ops-system 发不出去，带前缀的直发存进 pending.json，下次正常运行原样发给真 bot
#       （PER-88 合进来后真 bot 那条被规则 d 挡掉）                                         → S7
#   F9 检查读到真配置：HOME、webhook 目录、状态目录全在临时目录，假 env 里的 URL 只到 127.0.0.1
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
CODE=$(cd "${1:-$REPO}" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fbp.XXXXXX")
OUT=${2:-$T/out}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
PORT=$((18800 + RANDOM % 90))
P="[演练 叫醒通路]"
fail=0
check() {  # check <编号> <说明> <python 表达式，rows = $CUR 里收到的请求>
    if python3 - "$CUR" "$3" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
sys.exit(0 if eval(sys.argv[2], {"rows": rows, "P": "[演练 叫醒通路]"}) else 1)
PY
    then echo "PASS $1 $2"; else echo "FAIL $1 $2"; fail=1; fi
}
same() {  # same <编号> <说明> <新> <旧>：两份收到的 body 逐条一样（JSON 键顺序也一样）
    if python3 - "$3" "$4" <<'PY'
import json, sys
b = lambda f: sorted(json.dumps(json.loads(l)["body"], ensure_ascii=False) for l in open(f, encoding="utf-8") if l.strip())
a, o = b(sys.argv[1]), b(sys.argv[2])
sys.exit(0 if a == o and a else 1)
PY
    then echo "PASS $1 $2"; else echo "FAIL $1 $2"; fail=1; fi
}
show() { python3 -c '
import json, sys
for l in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(l); b = r["body"]
    print("  %s bot=%s task=%s" % (r["path"], b.get("bot"), b.get("task")))' "$T/req.jsonl"; }

BASE=${FORCEBOT_BASE:-}
if [ -z "$BASE" ]; then
    BASE=$T/base
    mkdir -p "$BASE"
    git -C "$REPO" archive e5c61f1 | tar -x -C "$BASE"
fi
echo "代码：$CODE"
echo "对照：$BASE"

mkdir -p "$T/home/.config/grokbot/webhooks" "$T/bin" "$T/nrbin"
H=$T/home/.config/grokbot/webhooks
for b in ops-system coding-assistant xinyue; do
    printf 'URL=http://127.0.0.1:%s/hook/%s\nKEY=fake-key\n' "$PORT" "$b" >"$H/$b.env"
done
printf 'URL=http://127.0.0.1:%s/hook/stuck-webhook\nKEY=fake-key\n' "$PORT" >"$T/home/.config/grokbot/stuck-webhook.env"
python3 "$HERE/mock_webhook.py" --port "$PORT" --out "$T/req.jsonl" --key fake-key >"$T/mock.log" 2>&1 &
MP=$!
trap 'kill $MP 2>/dev/null; wait $MP 2>/dev/null; rm -rf "$T"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do nc -z 127.0.0.1 "$PORT" 2>/dev/null && break; sleep 0.3; done
E="env -i PATH=$T/nrbin:/usr/bin:/bin HOME=$T/home LANG=en_US.UTF-8"
round() {  # round <名字>：把这一轮收到的请求存到产物目录，清空接收端文件
    touch "$T/req.jsonl"
    cp "$T/req.jsonl" "$OUT/$1.jsonl"
    : >"$T/req.jsonl"
}

# ---- stuck-check.sh --send ----
pending() {
    python3 - "$1" <<'PY'
import json, sys, time
now = time.time()
pl = lambda bot, task, kind, status="stuck": {"bot": bot, "task": task, "worktree": "iMac:/tmp/fbp-" + kind, "status": status,
                                              "kind": kind, "note": "替身检查：" + kind, "machine": "iMac", "source": "stuck-check"}
sus = lambda i, task: {"id": i, "key": "iMac:/tmp/fbp-" + i, "kind": "agent_idle", "bot": "xinyue", "task": task,
                       "worktree": "iMac:/tmp/fbp-" + i, "marker": now - 3600, "note": "替身检查：agent_idle", "machine": "iMac"}
json.dump({"created": now, "suspects": [sus("S1", "fbp 嫌疑"), sus("S2", "[演练 叫醒通路] fbp 已带前缀")],
           "direct": [{"id": "undelivered:fbp", "cfg": "bot:xinyue", "payload": pl("xinyue", "fbp 停下没送达", "stop_not_delivered")},
                      {"id": "marker:fbp:1", "cfg": "fallback", "payload": pl("coding-assistant", "自动任务没跑完：fbp", "automation_no_ok")},
                      {"id": "reported", "cfg": "stuck", "payload": pl("xinyue", "fbp 报了没人验收", "", "reported_not_accepted")}]},
          open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}
stuck() {  # stuck <代码目录> <名字> [FORCE_BOT]；KEEP=1 时沿用上一轮留下的状态目录
    [ "${KEEP:-}" = 1 ] || { rm -rf "$T/st"; mkdir -p "$T/st"; pending "$T/st/pending.json"; }
    $E STUCK_STATE_DIR="$T/st" STUCK_WEBHOOK_DIR="$H" STUCK_ENV_FILE="$T/home/.config/grokbot/stuck-webhook.env" \
        STUCK_POST_GAP=0 STUCK_BACKOFF=1 STUCK_NO_GATE=1 WAKE_PREFILTER=off ${3:+STUCK_FORCE_BOT=$3} \
        /bin/bash "$1/scripts/stuck-check.sh" --send >"$OUT/$2.out" 2>&1
    echo "stuck-check $2 rc=$?"
    show; round "$2"
}
stuck "$CODE" stuck-force ops-system
CUR=$OUT/stuck-force.jsonl
check S1 "嫌疑改发 ops-system，task 以前缀开头" \
    'any(r["body"]["task"] == P + " fbp 嫌疑" and r["body"]["bot"] == "ops-system" and r["path"] == "/hook/ops-system" for r in rows)'
check S2 "直发 cfg=bot: 改发 ops-system，task 以前缀开头" \
    'any(r["body"]["task"] == P + " fbp 停下没送达" and r["body"]["bot"] == "ops-system" and r["path"] == "/hook/ops-system" for r in rows)'
check S3 "直发 cfg=fallback 走 ops-system webhook，bot=ops-system 且 task 以前缀开头" \
    'any(r["body"]["task"] == P + " 自动任务没跑完：fbp" and r["body"]["bot"] == "ops-system" and r["path"] == "/hook/ops-system" for r in rows)'
check S4 "cfg=stuck 照旧发 stuck-webhook，不加前缀" \
    'any(r["body"]["task"] == "fbp 报了没人验收" and r["path"] == "/hook/stuck-webhook" for r in rows)'
check S5 "已带前缀的只出现一次" \
    'any(r["body"]["task"] == P + " fbp 已带前缀" for r in rows) and all(r["body"]["task"].count(P) <= 1 for r in rows)'
check S0 "收到 5 条，全是 auth_ok，ops-system 那 4 条都有前缀" \
    'len(rows) == 5 and all(r["auth_ok"] for r in rows) and all(r["body"]["task"].startswith(P + " ") for r in rows if r["path"] == "/hook/ops-system")'
stuck "$CODE" stuck-plain
stuck "$BASE" stuck-plain-base
CUR=$OUT/stuck-plain.jsonl
check S6a "没设 FORCE_BOT：5 条，只有原本就带前缀的那条有前缀" \
    'len(rows) == 5 and sum(P in r["body"]["task"] for r in rows) == 1'
same S6 "没设 FORCE_BOT：payload 和旧代码一样" "$OUT/stuck-plain.jsonl" "$OUT/stuck-plain-base.jsonl"
touch "$T/req.jsonl.fail-ops-system"  # 假接收端对 /hook/ops-system 回 503
stuck "$CODE" stuck-force-fail ops-system
rm -f "$T/req.jsonl.fail-ops-system"
cp "$T/st/pending.json" "$OUT/stuck-force-fail.pending.json"
KEEP=1 stuck "$CODE" stuck-after-fail
CUR=$OUT/stuck-after-fail.jsonl
check S7 "演练没发出去的直发，下次正常运行发给原来的 bot，task、bot 都不带演练的改动" \
    'any(r["path"] == "/hook/xinyue" and r["body"]["task"] == "fbp 停下没送达" for r in rows) and any(r["path"] == "/hook/coding-assistant" and r["body"]["task"] == "自动任务没跑完：fbp" and r["body"]["bot"] == "coding-assistant" for r in rows)'

# ---- heartbeat-watch.sh ----
old=$(( $(date +%s) - 3600 ))
cat >"$T/bin/orca-hb" <<EOF
#!/bin/sh
echo '{"ok":true,"result":{"runs":[{"createdAt":${old}000,"precheckResult":{"stdout":"@@HB {\\"ts\\": $old, \\"last_scan\\": $old}"}}]}}'
EOF
chmod +x "$T/bin/orca-hb"
hb() {  # hb <代码目录> <名字> [FORCE_BOT]
    rm -rf "$T/hb"; mkdir -p "$T/hb"
    $E HB_ORCA="$T/bin/orca-hb" HB_STATE_DIR="$T/hb" STUCK_WEBHOOK_DIR="$H" ${3:+STUCK_FORCE_BOT=$3} \
        /bin/bash "$1/scripts/heartbeat-watch.sh" --target "fbp||00000000-0000-0000-0000-000000000105|20" >"$OUT/$2.out" 2>&1
    echo "heartbeat-watch $2 rc=$?"
    show; round "$2"
}
hb "$CODE" hb-force ops-system
CUR=$OUT/hb-force.jsonl
check H1 "heartbeat 强制演练：1 条，发给 ops-system，task 以前缀开头且只一次" \
    'len(rows) == 1 and rows[0]["path"] == "/hook/ops-system" and rows[0]["body"]["bot"] == "ops-system" and rows[0]["body"]["task"].startswith(P + " ") and rows[0]["body"]["task"].count(P) == 1'
hb "$CODE" hb-plain
hb "$BASE" hb-plain-base
same H2 "heartbeat 没设 FORCE_BOT：payload 和旧代码一样" "$OUT/hb-plain.jsonl" "$OUT/hb-plain-base.jsonl"

# ---- unpushed_scan.py（叫醒经真 notify-run，临时 HOME）----
R=$T/repo
git init -q "$R"
git -C "$R" remote add origin https://example.invalid/xinyue.git
GIT_AUTHOR_DATE="@$(( $(date +%s) - 3 * 3600 )) +0800" GIT_COMMITTER_DATE="@$(( $(date +%s) - 3 * 3600 )) +0800" \
    git -C "$R" -c user.name=fbp -c user.email=fbp@example.invalid commit -q --allow-empty -m "fbp 没推送"
cat >"$T/bin/orca-wt" <<EOF
#!/bin/sh
echo '{"ok":true,"result":{"worktrees":[{"hostId":"local","path":"$R","isBare":false}]}}'
EOF
chmod +x "$T/bin/orca-wt"
up() {  # up <代码目录> <名字> <FORCE_BOT 或 -> [--drill]
    rm -f "$T/nrbin/notify-run"; ln -s "$1/wake/bin/notify-run" "$T/nrbin/notify-run"
    local f=$3; [ "$f" = - ] && f=
    $E ORCA="$T/bin/orca-wt" NOTIFY_RUN_TRIES=1 ${f:+UNPUSHED_FORCE_BOT=$f} \
        python3 "$1/sentinels/unpushed_scan.py" --machine fbp --state "$T/up-$2.json" ${4:-} >"$OUT/$2.out" 2>&1
    echo "unpushed_scan $2 rc=$?"
    show; round "$2"
}
WS=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$R")
up "$CODE" up-force ops-system
CUR=$OUT/up-force.jsonl
check U1 "unpushed 强制演练：1 条，发给 ops-system，task 以前缀开头" \
    'len(rows) == 1 and rows[0]["path"] == "/hook/ops-system" and rows[0]["body"]["bot"] == "ops-system" and rows[0]["body"]["task"].startswith(P + " ops · 24 未推送扫描")'
up "$CODE" up-force-drill ops-system --drill
CUR=$OUT/up-force-drill.jsonl
check U2 "unpushed --drill：前缀在最前，「【演练】」跟在后面" \
    'len(rows) == 1 and rows[0]["body"]["task"].startswith(P + " 【演练】ops · 24 未推送扫描") and rows[0]["body"]["task"].count(P) == 1'
up "$CODE" up-plain -
up "$BASE" up-plain-base -
CUR=$OUT/up-plain.jsonl
check U3a "unpushed 没设 FORCE_BOT：1 条发给 xinyue，没有前缀" \
    'len(rows) == 1 and rows[0]["path"] == "/hook/xinyue" and P not in rows[0]["body"]["task"]'
python3 - "$OUT/up-plain.jsonl" "$OUT/up-plain-base.jsonl" <<'PY'
import json, sys  # notify-run 的 payload 带运行时间、pid 一类会变的字段：只比 bot、task、status、note
for f in sys.argv[1:]:
    rows = [json.loads(l)["body"] for l in open(f, encoding="utf-8") if l.strip()]
    json.dump([{k: r.get(k) for k in ("bot", "task", "status", "note")} for r in rows], open(f + ".cmp", "w", encoding="utf-8"),
              ensure_ascii=False)
PY
if cmp -s "$OUT/up-plain.jsonl.cmp" "$OUT/up-plain-base.jsonl.cmp" && [ -s "$OUT/up-plain.jsonl" ]; then
    echo "PASS U3 unpushed 没设 FORCE_BOT：bot、task、status、note 和旧代码一样"
else
    echo "FAIL U3 unpushed 没设 FORCE_BOT：bot、task、status、note 和旧代码一样"; fail=1
fi

# ---- C：喂给 PER-88 的 wake-prefilter（只记录）----
if [ -n "${FORCEBOT_PREFILTER:-}" ]; then
    mkdir -p "$T/pf/state" "$T/pf/config"
    python3 - "$OUT" "$FORCEBOT_PREFILTER" "$T/pf" "$T/home" "$R" <<'PY' | tee "$OUT/prefilter.txt"
import json, os, subprocess, sys
out, pf, d, home, ws = sys.argv[1:]
env = {"PATH": "/usr/bin:/bin", "HOME": home, "WAKE_PREFILTER": "on", "ORCA_WAKE_STATE_DIR": d + "/state",
       "ORCA_WAKE_CONFIG_DIR": d + "/config", "WAKE_PREFILTER_LOG": d + "/prefilter.log", "WAKE_PREFILTER_ORCA": "/usr/bin/false"}
for name, src in (("stuck-force", "stuck-check"), ("hb-force", "stuck-check"), ("up-force", "notify-run"),
                  ("up-force-drill", "notify-run")):
    for l in open(os.path.join(out, name + ".jsonl"), encoding="utf-8"):
        r = json.loads(l)
        if r["path"] != "/hook/ops-system":
            continue
        args = [sys.executable, pf, "check", "--source", src] + (["--pid", "1", "--ws", ws] if src == "notify-run" else [])
        p = subprocess.run(args, input=json.dumps(r["body"], ensure_ascii=False), capture_output=True, text=True, env=env, timeout=20)
        print("%s\t--source %s\trc=%d\t%s\tbot=%s\ttask=%s" % (name, src, p.returncode, p.stdout.strip() or "-",
                                                             r["body"].get("bot"), r["body"].get("task")))
# 反例：带前缀但 bot 还是 coding-assistant（cfg=fallback 那条不改 bot 时就是这样），规则 d 不放行
p = subprocess.run([sys.executable, pf, "check", "--source", "stuck-check"], capture_output=True, text=True, env=env, timeout=20,
                   input=json.dumps({"bot": "coding-assistant", "task": "[演练 叫醒通路] 自动任务没跑完：fbp", "status": "stuck",
                                     "kind": "automation_no_ok"}, ensure_ascii=False))
print("反例 bot=coding-assistant\t--source stuck-check\trc=%d\t%s" % (p.returncode, p.stdout.strip() or "-"))
PY
    cp "$T/pf/prefilter.log" "$OUT/prefilter.log" 2>/dev/null
fi

echo "产物：$OUT"
echo "RESULT $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
