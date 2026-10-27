#!/bin/bash
# 卡住检查扫描时长防护（PER-82）的离线演练：假 orca（wake/tests/fake-orca，PATH 前置）+ 临时 STATE 目录 +
# 本地 mock webhook（127.0.0.1），不碰真 Orca、真 bot、~/.orca-state。用了假 orca，属于测试替身，不算 E2E；
# 真实环境的证据另跑（对状态副本用真 orca 只读 --scan，见 PR）。
# Orca 的 precheck 超时由本脚本模拟：到 STUCK_PRECHECK_TIMEOUT_S 秒杀掉整个进程组，和 Orca 一样。
#
#   wake/tests/stuck-check-scan-guard.sh                         测 scripts/stuck-check.sh
#   STUCK_CHECK_SH=<别的版本> wake/tests/stuck-check-scan-guard.sh  回退测试：换成 main 上的版本，应当挂
#   ARTIFACT_DIR=<目录>                                            日志、状态、webhook 记录留在这里（默认临时目录，跑完打印路径）
#
# A 慢工作区：一个工作区的 worktree show 和 box 的 worktree ps 卡 60 秒（单项超时 3 秒，precheck 超时 40 秒）。
#   要求：慢的被跳过并记日志，别的工作区照常报嫌疑 / 断了照常发，整轮在时限内 rc 0，last_scan 前进，时长写进 state。
# B 扫描慢：每个调用慢 0.8 秒，15 个工作区（precheck 超时 20 秒，时限 16 秒）。
#   要求：停在时限、标 truncated、rc 0 没被杀；发一次 scan_slow 给 ops-system；第二次仍慢不重复发，且先做上次没做完的；
#   变快后发一次 scan_slow_recovered，再跑一次不再发。
set -u
here=$(cd "$(dirname "$0")" && pwd)
SC=${STUCK_CHECK_SH:-$here/../../scripts/stuck-check.sh}
PORT=${PORT:-18797}
tmp=$(mktemp -d)
ART=${ARTIFACT_DIR:-$tmp/artifacts}
mkdir -p "$ART" "$tmp/home" "$tmp/hooks" "$tmp/runs"
REQ="$ART/webhook-requests.jsonl"
: >"$REQ"
printf 'URL=http://127.0.0.1:%s/hook/coding-assistant\nKEY=scan-guard-test-key\n' "$PORT" >"$tmp/hooks/coding-assistant.env"
printf 'URL=http://127.0.0.1:%s/hook/ops-system\nKEY=scan-guard-test-key\n' "$PORT" >"$tmp/hooks/ops-system.env"
python3 "$here/mock_webhook.py" --port "$PORT" --out "$REQ" --key scan-guard-test-key &
mock=$!
cleanup() { kill "$mock" 2>/dev/null; wait 2>/dev/null; rm -rf "$tmp/home"; }
trap cleanup EXIT
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/ready" -X POST -d '{}' && break; sleep 0.1; done
: >"$REQ"

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "ok   $1" | tee -a "$ART/summary.txt"; }
bad() { fail=$((fail + 1)); echo "FAIL $1" | tee -a "$ART/summary.txt"; }
check() { if [ "$2" = 0 ]; then ok "$1"; else bad "$1"; fi; }  # check <名字> <0=通过>

# fixture <文件> <普通工作区数> <是否带慢工作区和断了的工作区 0/1>
fixture() {
    python3 - "$1" "$2" "$3" <<'EOF'
import json, sys, time
out, n, extra = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "1"
old = int((time.time() - 7200) * 1000)
ws, terms = [], []
def add(name, live=True):
    p = "/fake/ws/" + name
    ws.append({"path": p, "workspaceKind": "git", "workspaceStatus": "in-progress", "displayName": name,
               "repo": "demo", "repoId": "r1", "branch": name, "lastActivityAt": old, "lastOutputAt": old,
               "liveTerminalCount": 1 if live else 0, "agents": []})
    if live:
        terms.append({"handle": "term-" + name, "worktreePath": p, "connected": True, "lastOutputAt": old,
                      "tabId": "tab-" + name, "leafId": "l1"})
for i in range(n):
    add("ok-gone-%02d" % i)
slow = []
if extra:
    add("slow-gone")
    add("broken-ws", live=False)
    slow = [{"match": "iMac worktree show --worktree path:/fake/ws/slow-gone", "sleep": 60},
            {"match": "box worktree ps", "sleep": 60}]
json.dump({"iMac": {"worktrees": ws, "terminals": terms}, "box": {"worktrees": [], "terminals": []}, "slow": slow},
          open(out, "w"), indent=1)
EOF
}

# scan <名字> <状态目录> [环境变量...]：像 Orca 的 precheck 一样跑一次 --scan，到 STUCK_PRECHECK_TIMEOUT_S 秒杀掉整个进程组。
# 打印 rc 和耗时到 $ART/<名字>.meta
scan() {
    local name=$1 st=$2; shift 2
    env -i PATH="$here/fake-orca:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" HOME="$tmp/home" LANG=en_US.UTF-8 \
        STUCK_STATE_DIR="$st" STUCK_RUNS_DIR="$tmp/runs" STUCK_WEBHOOK_DIR="$tmp/hooks" STUCK_ENV_FILE="$tmp/hooks/coding-assistant.env" \
        STUCK_PROBE="$here/fake_agent_probe.py" STUCK_ORCA_WAKE=/usr/bin/false STUCK_MBA_ENV= STUCK_BOX_RETRY_WAIT=0 \
        STUCK_POST_GAP=0 STUCK_BACKOFF=1 STUCK_GONE_MIN=10 FAKE_ORCA_LOG="$ART/$name.orca-calls.log" \
        ORCA_WAKE_STATE_DIR="$tmp/home/none" NOTIFY_RUN_LOG="$tmp/home/none.log" "$@" \
        python3 - "$SC" "$ART/$name.out" "$ART/$name.meta" <<'EOF'
import os, signal, subprocess, sys, time
lim = float(os.environ.get("STUCK_PRECHECK_TIMEOUT_S") or 300)
t0 = time.time()
with open(sys.argv[2], "w") as out:
    p = subprocess.Popen([sys.argv[1], "--scan"], stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        rc = p.wait(timeout=lim)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        rc = "killed"
open(sys.argv[3], "w").write("rc=%s wall=%.1f limit=%.0f\n" % (rc, time.time() - t0, lim))
EOF
    echo "-- $name: $(cat "$ART/$name.meta")"
}
rc_of() { sed -n 's/^rc=\([^ ]*\).*/\1/p' "$ART/$1.meta"; }
kinds() {  # kinds <kind> [path]: mock 收到几条这个 kind
    python3 - "$REQ" "$1" "${2:-}" <<'EOF'
import json, sys
n = 0
for ln in open(sys.argv[1]):
    r = json.loads(ln)
    if r["body"].get("kind") == sys.argv[2] and (not sys.argv[3] or r["path"].endswith(sys.argv[3])):
        n += 1
print(n)
EOF
}
pyq() { python3 -c "$1" "${@:2}"; }  # pyq <python> <参数...>：退出码 0 = 通过

echo "被测脚本：${SC}（sha256 $(shasum -a 256 "$SC" | cut -c1-16)）" | tee "$ART/summary.txt"

# ---------- A：慢工作区 ----------
A="$tmp/state-a"
mkdir -p "$A"
fixture "$tmp/fx-a.json" 3 1
seed=$(( $(date +%s) - 3600 ))
printf '{"last": %s, "done": %s}\n' "$seed" "$seed" >"$A/gate.json"
scan A "$A" FAKE_ORCA_FIXTURE="$tmp/fx-a.json" STUCK_PRECHECK_TIMEOUT_S=40 STUCK_ORCA_CALL_TIMEOUT_S=3 STUCK_BOX_ENV=box
mkdir -p "$ART/state-a" && cp "$A"/* "$ART/state-a/" 2>/dev/null
m=$(cat "$ART/A.meta")
[ "$(rc_of A)" = 0 ]; check "A1 整轮在 precheck 超时内跑完、rc 0（${m}）" $?
grep -q '跳过 iMac:path:/fake/ws/slow-gone | 原因：orca worktree show' "$ART/A.out"; check "A2 慢工作区被跳过并记日志" $?
grep -q '跳过 box:（整台） | 原因：orca worktree ps' "$ART/A.out"; check "A3 box 的 worktree ps 超时，整台跳过并记日志" $?
pyq 'import json,sys; s=json.load(open(sys.argv[1]))["suspects"]; ks={x["key"] for x in s}
sys.exit(0 if {"iMac:/fake/ws/ok-gone-%02d" % i for i in range(3)} <= ks and "iMac:/fake/ws/slow-gone" not in ks
         and all(x["kind"] == "agent_gone" for x in s) else 1)' "$A/pending.json"
check "A4 其他工作区照常报嫌疑（3 个 agent_gone），慢的不在里面" $?
[ "$(kinds ws_broken coding-assistant)" = 1 ]; check "A5 断了的工作区照常直发（mock 收到 1 条 ws_broken）" $?
pyq 'import json,sys; g=json.load(open(sys.argv[1])); h=json.load(open(sys.argv[2])); sys.exit(0 if g["done"] > int(sys.argv[3]) and h["last_scan"] == g["done"] and h.get("last_duration_s") else 1)' \
    "$A/gate.json" "$A/heartbeat.json" "$seed"
check "A6 last_scan 前进（gate.done 和心跳），心跳带 last_duration_s" $?
pyq 'import json,sys; e=json.load(open(sys.argv[1]))[-1]; n={p["name"] for p in e["phases"]}
sys.exit(0 if e["end"] and e["duration_s"] < 40 and {"一类 iMac", "一类 box", "发送"} <= n and e["skipped_calls"] else 1)' "$A/scan-history.json"
check "A7 scan-history.json 记了时长、各阶段耗时和跳过的调用" $?
[ "$(kinds scan_slow)" = 0 ]; check "A8 时长低于 60% 不发 scan_slow" $?

# ---------- B：扫描慢 ----------
B="$tmp/state-b"
mkdir -p "$B"
fixture "$tmp/fx-b.json" 15 0
slowenv="FAKE_ORCA_FIXTURE=$tmp/fx-b.json STUCK_PRECHECK_TIMEOUT_S=20 STUCK_ORCA_CALL_TIMEOUT_S=3 STUCK_NO_GATE=1"
# shellcheck disable=SC2086
scan B1 "$B" $slowenv FAKE_ORCA_DELAY=0.8
mkdir -p "$ART/state-b1" && cp "$B"/* "$ART/state-b1/" 2>/dev/null
m=$(cat "$ART/B1.meta")
case "$(rc_of B1)" in 0|1) true ;; *) false ;; esac
check "B1 每个调用都慢时停在时限、正常退出（rc 0/1 按有没有嫌疑），没被 precheck 超时杀掉（${m}）" $?
pyq 'import json,sys; e=json.load(open(sys.argv[1]))[-1]; sys.exit(0 if e["truncated"] and e["end"] and e["duration_s"] > 12 else 1)' "$B/scan-history.json"
check "B2 这次扫描标 truncated，时长 > 60%（12 秒）写进 state" $?
[ "$(kinds scan_slow ops-system)" = 1 ]; check "B3 发了 1 条 scan_slow 给 ops-system" $?
pyq 'import json,sys
for ln in open(sys.argv[1]):
    b = json.loads(ln)["body"]
    if b.get("kind") == "scan_slow":
        sys.exit(0 if b["duration_s"] > b["threshold_s"] == 12 and b["phases"].get("一类 iMac") and b["truncated"] else 1)
sys.exit(1)' "$REQ"
check "B4 scan_slow 带时长、阈值、各阶段耗时、truncated" $?
# shellcheck disable=SC2086
scan B2 "$B" $slowenv FAKE_ORCA_DELAY=0.8
[ "$(kinds scan_slow ops-system)" = 1 ] && grep -q '已报过' "$ART/B2.out"; check "B5 一小时内又慢，不重复发 scan_slow（去重）" $?
pyq 'import json,sys; e=json.load(open(sys.argv[1]))[-1]; sys.exit(0 if e["plan"][:2] == ["二类 iMac", "一类 iMac"] else 1)' "$B/scan-history.json"
check "B6 第二次先做上次没做完的（二类排最前面，然后一类 iMac）" $?
# shellcheck disable=SC2086
scan B3 "$B" $slowenv FAKE_ORCA_DELAY=0
m=$(cat "$ART/B3.meta")
case "$(rc_of B3)" in 0|1) true ;; *) false ;; esac; check "B3' 变快后整轮跑完，正常退出（${m}）" $?
pyq 'import json,sys; e=json.load(open(sys.argv[1]))[-1]; sys.exit(0 if not e["truncated"] and e["end"] else 1)' "$B/scan-history.json"
check "B3'' 变快后这次扫描没有 truncated" $?
[ "$(kinds scan_slow_recovered ops-system)" = 1 ]; check "B7 变快后发 1 条 scan_slow_recovered" $?
# shellcheck disable=SC2086
scan B4 "$B" $slowenv FAKE_ORCA_DELAY=0
[ "$(kinds scan_slow_recovered ops-system)" = 1 ] && [ "$(kinds scan_slow ops-system)" = 1 ]; check "B8 恢复后再跑一次，不再发" $?
mkdir -p "$ART/state-b" && cp "$B"/* "$ART/state-b/" 2>/dev/null
echo "通过 ${pass}，失败 ${fail}；产物：${ART}" | tee -a "$ART/summary.txt"
[ "$fail" = 0 ]
