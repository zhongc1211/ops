#!/bin/bash
# reports/93/rerun.sh：PR 93 的演练（构造输入，全部在沙箱 HOME 里，用仓库里的脚本副本）。
#   A. orca-agent-launch 启动前检查：claude / pi / codex 各自的指令链里有没有标记句（用例见 FAILURE-MODES.md）
#   B. wake/install.sh --check 的「全局 AGENTS 三机一致」：假 ssh 把沙箱目录当对端
# 不装到线上、不碰真实家目录、不写仓库里的文件。产物：${RERUN_OUT:-$HOME/.orca-state/e2e/pr93-<HEAD 前 12 位>}/results.tsv
# 退出码：全部 PASS 0；有 FAIL 1；一个用例都没有 3。
set -u
cd "$(dirname "$0")/../.." || exit 3
REPO=$(pwd)
HEAD=$(git rev-parse HEAD) || exit 3
OUT=${RERUN_OUT:-$HOME/.orca-state/e2e/pr93-${HEAD:0:12}}
mkdir -p "$OUT/logs" || exit 3
TSV=$OUT/results.tsv
printf 'case\tstatus\tdetail\n' > "$TSV"
tmpbase=${TMPDIR:-/tmp}
SB=$(mktemp -d "${tmpbase%/}/pr93-drill.XXXXXX") || exit 3
trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
MARKER_LINE='- NEVER write unit tests after you write code.'

record() {  # case status detail
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$TSV"
    echo "$2  $1  $3"
}
# check <case> <期望退出码> <实际退出码> <日志> [必须出现的固定字符串 | !不能出现的]...
check() {
    local c=$1 want=$2 rc=$3 log=$4 why="" s
    shift 4
    [ "$rc" = "$want" ] || why="退出码 ${rc}，应为 ${want}"
    for s in "$@"; do
        case "$s" in
            '!'*) ! grep -qF -- "${s#!}" "$log" || why="${why:+${why}；}不应出现「${s#!}」" ;;
            *) grep -qF -- "$s" "$log" || why="${why:+${why}；}缺「${s}」" ;;
        esac
    done
    if [ -z "$why" ]; then record "$c" PASS "rc=${rc}；日志 logs/${c}.log"; else record "$c" FAIL "$why"; fi
}

# ---------- A. 启动前检查 ----------
mkdir -p "$SB/fakebin" "$SB/webhooks"
for a in claude pi codex; do printf '#!/bin/sh\nexit 0\n' > "$SB/fakebin/$a"; done
printf '#!/bin/sh\necho "$@" >> "%s/notify-run.calls"\nexit 0\n' "$SB" > "$SB/fakebin/notify-run"
chmod +x "$SB/fakebin/"*
# 拒绝叫醒发往本机关着的端口，发不出去，不出网
printf 'URL=http://127.0.0.1:9/drill\nKEY=drill-not-a-secret\n' > "$SB/webhooks/drill-bot.env"

newcase() {  # $1=用例名 → 建 $SB/<用例>/home 和 $SB/<用例>/ws，打印用例目录
    mkdir -p "$SB/$1/home" "$SB/$1/ws"
    echo "$SB/$1"
}
launch() {  # case agent home ws dry(1/空) → 打印退出码；输出写 logs/<case>.log
    local log="$OUT/logs/$1.log"
    ( cd "$4" && env -u PI_CODING_AGENT_DIR -u CODEX_HOME -u CLAUDE_CONFIG_DIR -u ORCA_DISPATCH_PID \
        HOME="$3" PATH="$SB/fakebin:$PATH" ORCA_AGENT_LAUNCH_DRY="$5" \
        ORCA_AGENT_LAUNCH_WEBHOOK_DIR="$SB/webhooks" ORCA_AGENT_LAUNCH_NOTIFY_RUN="$SB/fakebin/notify-run" \
        "$REPO/wake/bin/orca-agent-launch" --bot drill-bot --task "PR93 演练 $1" -- "$2" ) >"$log" 2>&1
    echo $?
}
global_ok() {  # $1=home：全局 AGENTS 有标记句，~/.claude/CLAUDE.md 引用它
    mkdir -p "$1/.pi/agent" "$1/.claude"
    printf '# 全局\n\n%s\n' "$MARKER_LINE" > "$1/.pi/agent/AGENTS.md"
    printf '%s\n' '@~/.pi/agent/AGENTS.md' > "$1/.claude/CLAUDE.md"
}

d=$(newcase L1-claude-global-ok); H=$d/home; W=$d/ws
global_ok "$H"
rc=$(launch L1-claude-global-ok claude "$H" "$W" 1)
check L1-claude-global-ok 0 "$rc" "$OUT/logs/L1-claude-global-ok.log" "启动检查：claude 指令链" "标记句在 $H/.pi/agent/AGENTS.md"

d=$(newcase L2-claude-global-no-marker); H=$d/home; W=$d/ws
global_ok "$H"; printf '# 全局（标记句删了）\n' > "$H/.pi/agent/AGENTS.md"
rc=$(launch L2-claude-global-no-marker claude "$H" "$W" 1)
check L2-claude-global-no-marker 2 "$rc" "$OUT/logs/L2-claude-global-no-marker.log" "应当包含标记句的文件：$H/.pi/agent/AGENTS.md"

d=$(newcase L3a-claude-ws-agents-imported); H=$d/home; W=$d/ws
printf '%s\n' "$MARKER_LINE" > "$W/AGENTS.md"; printf '@AGENTS.md\n' > "$W/CLAUDE.md"
rc=$(launch L3a-claude-ws-agents-imported claude "$H" "$W" 1)
check L3a-claude-ws-agents-imported 0 "$rc" "$OUT/logs/L3a-claude-ws-agents-imported.log" "标记句在 $W/AGENTS.md"

d=$(newcase L3b-claude-ws-agents-not-imported); H=$d/home; W=$d/ws
printf '%s\n' "$MARKER_LINE" > "$W/AGENTS.md"; printf '# 本仓库说明（没有引用 AGENTS.md）\n' > "$W/CLAUDE.md"
rc=$(launch L3b-claude-ws-agents-not-imported claude "$H" "$W" 1)
check L3b-claude-ws-agents-not-imported 2 "$rc" "$OUT/logs/L3b-claude-ws-agents-not-imported.log" "应当包含标记句的文件：$H/.pi/agent/AGENTS.md"

# 同一布局换 pi：pi 每级目录读 AGENTS.md（AGENTS.override.md 优先、CLAUDE.md 兜底）
mkdir -p "$SB/L3c-pi-ws-agents"; cp -R "$SB/L3b-claude-ws-agents-not-imported/." "$SB/L3c-pi-ws-agents/"
H=$SB/L3c-pi-ws-agents/home; W=$SB/L3c-pi-ws-agents/ws
rc=$(launch L3c-pi-ws-agents pi "$H" "$W" 1)
check L3c-pi-ws-agents 0 "$rc" "$OUT/logs/L3c-pi-ws-agents.log" "启动检查：pi 指令链" "标记句在 $W/AGENTS.md"

d=$(newcase L4a-import-missing-other-ok); H=$d/home; W=$d/ws
global_ok "$H"; printf '@missing.md\n' > "$W/CLAUDE.md"
rc=$(launch L4a-import-missing-other-ok claude "$H" "$W" 1)
check L4a-import-missing-other-ok 0 "$rc" "$OUT/logs/L4a-import-missing-other-ok.log" "$W/missing.md" "不存在" "标记句在 $H/.pi/agent/AGENTS.md"

d=$(newcase L4b-import-missing-global); H=$d/home; W=$d/ws
global_ok "$H"; rm -f "$H/.pi/agent/AGENTS.md"
rc=$(launch L4b-import-missing-global claude "$H" "$W" 1)
check L4b-import-missing-global 2 "$rc" "$OUT/logs/L4b-import-missing-global.log" "不存在" "应当包含标记句的文件：$H/.pi/agent/AGENTS.md"

d=$(newcase L4c-marker-in-imported-file); H=$d/home; W=$d/ws
global_ok "$H"; printf '# 全局（没有标记句）\n' > "$H/.pi/agent/AGENTS.md"
mkdir -p "$W/docs"; printf '@docs/rules.md\n' > "$W/CLAUDE.md"; printf '%s\n' "$MARKER_LINE" > "$W/docs/rules.md"
rc=$(launch L4c-marker-in-imported-file claude "$H" "$W" 1)
check L4c-marker-in-imported-file 0 "$rc" "$OUT/logs/L4c-marker-in-imported-file.log" "标记句在 $W/docs/rules.md"

d=$(newcase L4d-import-cycle); H=$d/home; W=$d/ws
printf '@b.md\n' > "$W/a.md"; printf '@a.md\n' > "$W/b.md"; printf '@a.md\n' > "$W/CLAUDE.md"
( launch L4d-import-cycle claude "$H" "$W" 1 > "$SB/L4d.rc" ) & lp=$!
( sleep 20; kill "$lp" 2>/dev/null ) & kp=$!
wait "$lp" 2>/dev/null; kill "$kp" 2>/dev/null; wait "$kp" 2>/dev/null
rc=$(cat "$SB/L4d.rc" 2>/dev/null); [ -n "$rc" ] || rc="超时"
check L4d-import-cycle 2 "$rc" "$OUT/logs/L4d-import-cycle.log" "$W/b.md"

d=$(newcase L4e-unreadable); H=$d/home; W=$d/ws
global_ok "$H"; chmod 000 "$H/.pi/agent/AGENTS.md"
rc=$(launch L4e-unreadable claude "$H" "$W" 1)
check L4e-unreadable 2 "$rc" "$OUT/logs/L4e-unreadable.log" "读不了" "$H/.pi/agent/AGENTS.md"

d=$(newcase L4f-empty-chain); H=$d/home; W=$d/ws
rc=$(launch L4f-empty-chain claude "$H" "$W" 1)
check L4f-empty-chain 2 "$rc" "$OUT/logs/L4f-empty-chain.log" "一个文件都没有" "应当包含标记句的文件：$H/.pi/agent/AGENTS.md"

d=$(newcase L4g-codex-global-ok); H=$d/home; W=$d/ws
mkdir -p "$H/.codex"; printf '%s\n' "$MARKER_LINE" > "$H/.codex/AGENTS.md"
rc=$(launch L4g-codex-global-ok codex "$H" "$W" 1)
check L4g-codex-global-ok 0 "$rc" "$OUT/logs/L4g-codex-global-ok.log" "启动检查：codex 指令链" "标记句在 $H/.codex/AGENTS.md"

d=$(newcase L4h-codex-missing); H=$d/home; W=$d/ws
global_ok "$H"
rc=$(launch L4h-codex-missing codex "$H" "$W" 1)
check L4h-codex-missing 2 "$rc" "$OUT/logs/L4h-codex-missing.log" "应当包含标记句的文件：$H/.codex/AGENTS.md"

d=$(newcase L4i-reject-not-dry); H=$d/home; W=$d/ws
rm -f "$SB/notify-run.calls"
rc=$(launch L4i-reject-not-dry claude "$H" "$W" "")
[ -e "$SB/notify-run.calls" ] && echo "假 notify-run 被调用了：$(cat "$SB/notify-run.calls")" >> "$OUT/logs/L4i-reject-not-dry.log"
check L4i-reject-not-dry 2 "$rc" "$OUT/logs/L4i-reject-not-dry.log" "应当包含标记句的文件" "!假 notify-run 被调用了"

# ---------- B. install.sh --check ----------
IH=$SB/install-home
mkdir -p "$IH/.local/bin" "$SB/sshbin" "$SB/peers"
# 已装文件和仓库一致（沙箱里手工拷，不跑装模式），这样整体退出码只由新检查决定
for f in orca-wake orca-wake-hooks notify-run orca-agent-launch agent-stop; do cp "$REPO/wake/bin/$f" "$IH/.local/bin/$f"; done
cp "$REPO/scripts/agent-probe" "$IH/.local/bin/agent-probe"
global_ok "$IH"
cat > "$SB/sshbin/ssh" <<'SH'
#!/bin/bash
# 假 ssh：跳过选项，取主机名；把 $FAKE_SSH_ROOT/<主机> 当对端 HOME 执行命令
while [ $# -gt 0 ]; do case "$1" in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done
host=$1; shift
echo "$host" >> "$FAKE_SSH_ROOT/calls"
if [ -f "$FAKE_SSH_ROOT/$host.down" ]; then echo "ssh: connect to host $host port 22: Connection refused" >&2; exit 255; fi
if [ -f "$FAKE_SSH_ROOT/$host.flaky" ]; then rm -f "$FAKE_SSH_ROOT/$host.flaky"; echo "ssh: connect to host $host port 22: Operation timed out" >&2; exit 255; fi
[ -d "$FAKE_SSH_ROOT/$host" ] || { echo "ssh: Could not resolve hostname $host" >&2; exit 255; }
HOME="$FAKE_SSH_ROOT/$host" exec sh -c "$*"
SH
chmod +x "$SB/sshbin/ssh"
reset_peers() {
    rm -rf "$SB/peers"; mkdir -p "$SB/peers"
    global_ok "$SB/peers/peer-a"; global_ok "$SB/peers/peer-b"
}
icheck() {  # case peers → 打印退出码；输出写 logs/<case>.log
    ( env HOME="$IH" PATH="$SB/sshbin:$PATH" FAKE_SSH_ROOT="$SB/peers" WAKE_CHECK_PEERS="$2" \
        "$REPO/wake/install.sh" --check ) >"$OUT/logs/$1.log" 2>&1
    echo $?
}
calls() { grep -c "^$1\$" "$SB/peers/calls" 2>/dev/null || true; }
sha12() { (shasum -a 256 "$1" 2>/dev/null || sha256sum "$1") | cut -c1-12; }

reset_peers
rc=$(icheck I1-same "peer-a peer-b")
check I1-same 0 "$rc" "$OUT/logs/I1-same.log" "PASS  全局 AGENTS 一致" "!FAIL"

reset_peers; printf '# peer-b 的版本不一样\n%s\n' "$MARKER_LINE" > "$SB/peers/peer-b/.pi/agent/AGENTS.md"
rc=$(icheck I2-differ "peer-a peer-b")
check I2-differ 1 "$rc" "$OUT/logs/I2-differ.log" "FAIL  全局 AGENTS 不一致" \
    "peer-a=$(sha12 "$SB/peers/peer-a/.pi/agent/AGENTS.md")" "peer-b=$(sha12 "$SB/peers/peer-b/.pi/agent/AGENTS.md")" \
    "=$(sha12 "$IH/.pi/agent/AGENTS.md")"

reset_peers; touch "$SB/peers/peer-b.down"
rc=$(icheck I3-unreachable "peer-a peer-b")
echo "假 ssh 连 peer-b 的次数：$(calls peer-b)" >> "$OUT/logs/I3-unreachable.log"
check I3-unreachable 1 "$rc" "$OUT/logs/I3-unreachable.log" "peer-b 无法核对" "假 ssh 连 peer-b 的次数：2"

reset_peers; touch "$SB/peers/peer-b.flaky"
rc=$(icheck I4-flaky "peer-a peer-b")
echo "假 ssh 连 peer-b 的次数：$(calls peer-b)" >> "$OUT/logs/I4-flaky.log"
check I4-flaky 0 "$rc" "$OUT/logs/I4-flaky.log" "PASS  全局 AGENTS 一致" "假 ssh 连 peer-b 的次数：2"

reset_peers; printf '# 没有引用全局 AGENTS\n' > "$SB/peers/peer-b/.claude/CLAUDE.md"
rc=$(icheck I5-claude-no-ref "peer-a peer-b")
check I5-claude-no-ref 1 "$rc" "$OUT/logs/I5-claude-no-ref.log" "FAIL  peer-b 的 ~/.claude/CLAUDE.md 没有引用" "PASS  全局 AGENTS 一致"

reset_peers
rc=$(icheck I6-no-peers "")
echo "假 ssh 被调用的次数：$(grep -c . "$SB/peers/calls" 2>/dev/null || echo 0)" >> "$OUT/logs/I6-no-peers.log"
check I6-no-peers 0 "$rc" "$OUT/logs/I6-no-peers.log" "PASS  全局 AGENTS 一致" "假 ssh 被调用的次数：0"

# ---------- 汇总 ----------
pass=$(awk -F'\t' 'NR>1 && $2=="PASS"' "$TSV" | wc -l | tr -d ' ')
total=$(awk -F'\t' 'NR>1 && ($2=="PASS" || $2=="FAIL")' "$TSV" | wc -l | tr -d ' ')
echo "产物：$OUT"
echo "RERUN pr=93 head=$HEAD pass=$pass total=$total"
[ "$total" -gt 0 ] || exit 3
[ "$pass" = "$total" ] || exit 1
exit 0
