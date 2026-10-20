#!/bin/bash
# 卡住检查主目录 pane 的路由回归用例（PER-78 #45 审查 P2）：假 orca（wake/tests/fake-orca，PATH 前置）+ 假 agent-probe
# + 临时映射 / 状态目录 + 本地 mock webhook（127.0.0.1），不碰真 Orca、真 bot、~/.orca-state。用了替身，不算 E2E。
#
#   wake/tests/stuck-check-main-pane-route.sh                          测 scripts/stuck-check.sh
#   STUCK_CHECK_SH=<别的版本> wake/tests/stuck-check-main-pane-route.sh  回退对照：换成修之前的版本，应当挂
#   ARTIFACT_DIR=<目录>                                                 日志、状态、webhook 记录留在这里
#
# 场景：ops 主目录里一个 agent 终端（paneKey tab-main:l1），Orca 记的 prompt 以「PER-12 」开头，映射里 PER-12 归 vllm-omni。
#   agent 进程已经不在（probe 能读 paneKey，但这个 pane 里没有 agent），2 小时没动 → 报 agent_gone。
# 失败方式（先写下来）：
#   M1 主目录 pane 的合成显示名「ops 主目录 · PER-12 …」被当成「<bot> · <编号>」，告警发给 PER-12 的 bot（vllm-omni）
#   M2 告警发给了别人或者没发（应发给 ops 主目录的 bot：ops-system）
#   M3 发出去的不是这个 pane 的 agent_gone
set -u
here=$(cd "$(dirname "$0")" && pwd)
SC=${STUCK_CHECK_SH:-$here/../../scripts/stuck-check.sh}
PORT=${PORT:-18803}
tmp=$(mktemp -d)
ART=${ARTIFACT_DIR:-$tmp/artifacts}
mkdir -p "$ART" "$tmp/home" "$tmp/hooks" "$tmp/runs" "$tmp/state"
REQ="$ART/webhook-requests.jsonl"
: >"$REQ"
for b in ops-system vllm-omni coding-assistant; do
    printf 'URL=http://127.0.0.1:%s/hook/%s\nKEY=main-pane-test-key\n' "$PORT" "$b" >"$tmp/hooks/$b.env"
done
python3 "$here/mock_webhook.py" --port "$PORT" --out "$REQ" --key main-pane-test-key &
mock=$!
cleanup() { kill "$mock" 2>/dev/null; wait 2>/dev/null; rm -rf "$tmp/home"; }
trap cleanup EXIT
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/ready" -X POST -d '{}' && break; sleep 0.1; done
: >"$REQ"

# 映射：ops 仓库 → ops-system；PER-12 → vllm-omni 开发（BOT_SLUG → vllm-omni）
cat >"$tmp/mapping.md" <<'EOF'
| Bot | 工作区 | 仓库 | Linear |
|---|---|---|---|
| ops-system | ops 主目录（显示名 main） | ops | — |
| vllm-omni 开发 | vllm · PER-12 某任务 | vllm-omni | PER-12 |
EOF
# 假 agent-probe：别的 pane 里有一个包着 notify-run 的 agent（证明这台能读 paneKey），tab-main:l1 里没有 agent
cat >"$tmp/probe.py" <<'EOF'
#!/usr/bin/env python3
import base64, gzip, json, time
doc = {"ts": time.time(), "stops": [], "wake": {"sessions": [], "nr": []}, "procs": [
    {"pid": 4321, "ppid": 4320, "kind": "agent", "name": "claude", "pane": "tab-other:l1", "cwd": "/elsewhere",
     "notify_anc": True, "agent_anc_cwds": [], "in_orca": True, "etime_s": 600, "stat": "S", "dispatch_bot": "ops-system"}]}
print("@@PROBE-BEGIN")
print(base64.b64encode(gzip.compress(json.dumps(doc).encode())).decode())
print("@@PROBE-END")
EOF
chmod +x "$tmp/probe.py"
python3 - "$tmp/fx.json" <<'EOF'
import json, sys, time
old = int((time.time() - 7200) * 1000)
main = "/fake/ops"
w = {"path": main, "workspaceKind": "git", "workspaceStatus": "in-progress", "displayName": "main", "repo": "ops",
     "repoId": "r-ops", "branch": "main", "isMainWorktree": True, "lastActivityAt": old, "lastOutputAt": old,
     "liveTerminalCount": 1,
     "agents": [{"paneKey": "tab-main:l1", "state": "done", "updatedAt": old, "stateStartedAt": old,
                 "prompt": "PER-12 修一下调度开销的回归，跑完 E2E 报告给我"}]}
t = {"handle": "term-main", "worktreePath": main, "connected": True, "lastOutputAt": old, "tabId": "tab-main",
     "leafId": "l1", "agentIdentity": "claude", "title": "claude"}
json.dump({"iMac": {"worktrees": [w], "terminals": [t]}}, open(sys.argv[1], "w"), indent=1)
EOF

env -i PATH="$here/fake-orca:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" HOME="$tmp/home" LANG=en_US.UTF-8 \
    STUCK_STATE_DIR="$tmp/state" STUCK_RUNS_DIR="$tmp/runs" STUCK_WEBHOOK_DIR="$tmp/hooks" \
    STUCK_ENV_FILE="$tmp/hooks/coding-assistant.env" STUCK_MAPPING="$tmp/mapping.md" STUCK_PROBE="$tmp/probe.py" \
    STUCK_ORCA_WAKE=/usr/bin/false STUCK_BOX_ENV= STUCK_MBA_ENV= STUCK_POST_GAP=0 STUCK_BACKOFF=1 STUCK_GONE_MIN=10 \
    FAKE_ORCA_FIXTURE="$tmp/fx.json" FAKE_ORCA_LOG="$ART/orca-calls.log" \
    ORCA_WAKE_STATE_DIR="$tmp/home/none" NOTIFY_RUN_LOG="$tmp/home/none.log" \
    bash "$SC" >"$ART/run.out" 2>&1
echo "rc=$?" >>"$ART/run.out"
cp "$tmp/state/stuck-check.log" "$ART/stuck-check.log" 2>/dev/null

echo "被测脚本：${SC}（sha256 $(shasum -a 256 "$SC" | cut -c1-16)）" | tee "$ART/summary.txt"
python3 - "$REQ" <<'EOF' | tee -a "$ART/summary.txt"
import json, sys
rs = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
gone = [(r["path"].rsplit("/", 1)[-1], r["body"].get("task"), r["body"].get("worktree")) for r in rs
        if r["body"].get("kind") == "agent_gone"]
print("收到的 agent_gone：%s" % gone)
ok = len(gone) == 1 and gone[0][0] == "ops-system" and gone[0][2].endswith("/fake/ops#tab-main:l1")
print("%s M1 主目录 prompt 以 PER-12 开头：agent_gone 发给 ops-system，不发给 PER-12 的 vllm-omni" % ("PASS" if ok else "FAIL"))
sys.exit(0 if ok else 1)
EOF
exit ${PIPESTATUS[0]}
