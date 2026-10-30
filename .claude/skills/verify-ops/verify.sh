#!/bin/bash
# verify-ops：在沙箱 HOME 里驱动 ops 仓库的真实脚本（叫醒链路、起 agent 的门、卡住检查、各种 --check、夜审收尾门），
# 只有外部边界（webhook 接收端、Orca CLI、Linear、agent-probe 的进程表、夜审的存储机）换成本机替身。说明见同目录 SKILL.md。
#
#   bash .claude/skills/verify-ops/verify.sh doctor            起一个沙箱、跑只读体检、清掉沙箱；不健康退出 2
#   bash .claude/skills/verify-ops/verify.sh run [feature...]  起沙箱 → 体检 → 跑 feature（不写就全跑）→ 写证据 → 清理
#   bash .claude/skills/verify-ops/verify.sh launch            只起沙箱，打印沙箱目录（手动驱动用，用完必须 cleanup）
#   bash .claude/skills/verify-ops/verify.sh cleanup <沙箱>    杀 pidfile 里本次起的进程、删沙箱；不删运行目录
#   bash .claude/skills/verify-ops/verify.sh list              列出 feature 名
#
# feature：wake-chain agent-launch-gate stuck-check drift-checks night-review-gate wake-tla
# 退出码：0 没有失败（最后一行 VERIFY-OPS PASS（skipped N））；1 有失败（VERIFY-OPS FAIL（skipped N））；2 体检不过或用法错；3 一个用例都没跑（VERIFY-OPS EMPTY（0 个用例，skipped N））。
# 运行目录：${VERIFY_OPS_ARCHIVE:-$HOME/ops-archive/verify-ops}/<UTC 时间>/（summary.json、report.md、features/、webhook/），
#   清理时保留。仓库里不写任何运行产物。
# VERIFY_OPS_SUT=<目录>：换一份 ops 树当被测代码（故意改坏的副本就这样跑）；不设 = 本次 checkout。
# 兼容 macOS 自带的 /bin/bash 3.2：不用关联数组、mapfile、${var,,}；全角标点前的变量都加花括号。
set -u

SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SKILL_DIR/../../.." && pwd)
VO="$SKILL_DIR/helpers/vo.py"
# 运行目录里的掩码：真实 HOME → ~，主机名和用户名 → <host>（notify-run 的 payload 带 machine=主机名）
export VO_REAL_HOME="$HOME" VO_MASK_WORDS="${VO_MASK_WORDS:-$(hostname):$(hostname -s):$(id -un)}"
REAL_HOME=$HOME
SUT=${VERIFY_OPS_SUT:-$REPO}
SUT=$(cd "$SUT" && pwd) || { echo "verify-ops: VERIFY_OPS_SUT 不存在" >&2; exit 2; }
ARCHIVE=${VERIFY_OPS_ARCHIVE:-$REAL_HOME/ops-archive/verify-ops}
ALL_FEATURES="wake-chain agent-launch-gate stuck-check drift-checks night-review-gate wake-tla"
FAKE_KEY=e2e-fake   # migration-1020 的假端点只认这个 KEY（记 auth_ok）；不是任何真实凭据
unset ORCA_DISPATCH_PID ORCA_DISPATCH_BOT ORCA_TASK_ID ORCA_DISPATCH_ISSUE ORCA_DISPATCH_TS ORCA_PANE_KEY STUCK_FORCE_BOT
# 这两个会改 orca-agent-launch 和 install.sh --check 看的文件和机器
unset PI_CODING_AGENT_DIR WAKE_CHECK_PEERS
# 沙箱 HOME 自带 .claude；外面设的 CLAUDE_CONFIG_DIR 会让 pin-claude-plugins.sh 直接拒绝（Ubuntu 的 Orca 终端里就设了）
unset CLAUDE_CONFIG_DIR

say() { printf '%s\n' "$*"; }

# ---------- Launch ----------
# agents_fixture <沙箱>：orca-agent-launch 要指令链里有标记句，install.sh --check 要三台 ~/.pi/agent/AGENTS.md 一致。
# 沙箱 HOME 和三个假对端都拷被测仓库的 AGENTS.md（标记句不在这里再写一份）；假 ssh 把 $SB/peers/<机器> 当对端的 HOME。
agents_fixture() {
    local sb=$1 h
    for h in "$sb/home" "$sb/peers/imac" "$sb/peers/mba" "$sb/peers/box"; do
        mkdir -p "$h/.pi/agent" "$h/.claude"
        cp "$SUT/AGENTS.md" "$h/.pi/agent/AGENTS.md"
        echo '@~/.pi/agent/AGENTS.md' >"$h/.claude/CLAUDE.md"
    done
    cat >"$sb/bin/ssh" <<'EOF'
#!/bin/sh
# 假 ssh：只答 install.sh --check 的 agents-probe，别的命令一律连不上
for a in "$@"; do peer=$cmd; cmd=$a; done
case "$cmd" in *agents-probe*) [ -d "$VO_SANDBOX/peers/$peer" ] && HOME="$VO_SANDBOX/peers/$peer" exec sh -c "$cmd" ;; esac
echo "verify-ops 假 ssh：不答 ${peer}" >&2
exit 255
EOF
}

# launch：建沙箱，起两个假 webhook，写假 env 文件。沙箱目录打印到 stdout 最后一行。
launch() {
    local sb p1 p2 i
    sb=$(mktemp -d "${TMPDIR:-/tmp}/verify-ops.XXXXXX") || return 2
    mkdir -p "$sb/home/.config/grokbot/webhooks" "$sb/bin" "$sb/mock"
    : >"$sb/pids"
    # 假端点 A：复用 automations/migration-1020/e2e/mock_webhook.py（每个 POST 回 200，记一行；stopfile 出现就自己退出）
    python3 -I "$SUT/automations/migration-1020/e2e/mock_webhook.py" "$sb/mock/a.jsonl" "$sb/mock/a.port" 3600 "$sb/mock/a.stop" \
        >/dev/null 2>"$sb/mock/a.err" &
    echo "$! mock-a" >>"$sb/pids"
    # 假端点 B：复用 wake/tests/mock_webhook.py（有 <out>.fail-<路径末段> 文件时回 503，用来测非 2xx）
    p2=$(python3 -I "$VO" freeport)
    python3 -I "$SUT/wake/tests/mock_webhook.py" --port "$p2" --out "$sb/mock/b.jsonl" --key "$FAKE_KEY" \
        >/dev/null 2>"$sb/mock/b.err" &
    echo "$! mock-b" >>"$sb/pids"
    echo "$p2" >"$sb/mock/b.port"
    for i in $(seq 1 50); do [ -s "$sb/mock/a.port" ] && break; sleep 0.1; done
    p1=$(cat "$sb/mock/a.port" 2>/dev/null)
    [ -n "$p1" ] || { echo "verify-ops: 假端点 A 没起来：$(cat "$sb/mock/a.err")" >&2; return 2; }
    for i in $(seq 1 50); do curl -s -o /dev/null -X POST -d '{}' "http://localhost:$p2/ready" && break; sleep 0.1; done
    : >"$sb/mock/b.jsonl"
    local w="$sb/home/.config/grokbot/webhooks"
    for b in verify-bot coding-assistant ops-system; do
        printf 'URL=http://localhost:%s/hook/%s\nKEY=%s\n' "$p1" "$b" "$FAKE_KEY" >"$w/$b.env"
    done
    printf 'URL=http://localhost:%s/hook/verify-down\nKEY=%s\n' "$p2" "$FAKE_KEY" >"$w/verify-down.env"
    touch "$sb/mock/b.jsonl.fail-verify-down"
    # 假 agent：orca-agent-launch 只认 claude / pi / codex；用 pi（notify-run 不对 pi 做「起没起来」检查）
    printf '#!/bin/sh\necho "verify-ops 假 pi：$*"\nexit 0\n' >"$sb/bin/pi"
    printf '#!/bin/sh\nexec python3 -I "%s" orca "$@"\n' "$VO" >"$sb/bin/orca"
    printf '#!/bin/sh\nexec python3 -I "%s" linear "$@"\n' "$VO" >"$sb/bin/fake-linear-ok"
    cp "$sb/bin/orca" "$sb/bin/orca-ide"   # stuck-check 先找 orca-ide
    agents_fixture "$sb"
    chmod +x "$sb/bin/"*
    # stuck-check 用 python 跑 STUCK_PROBE，所以假 agent-probe 是个 python 文件
    printf 'import runpy, sys\nsys.argv = ["vo.py", "probe"]\nrunpy.run_path("%s", run_name="__main__")\n' "$VO" >"$sb/bin/agent-probe.py"
    cat >"$sb/env.sh" <<EOF
export HOME="$sb/home"
export PATH="$sb/bin:$SUT/wake/bin:$SUT/wake/tests/fake-orca:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NOTIFY_RUN_LOG="$sb/home/.orca-state/notify-run/notify-run.log"
export ORCA_WAKE_STATE_DIR="$sb/home/.local/state/orca-wake" ORCA_WAKE_CONFIG_DIR="$sb/home/.config/orca-wake"
export VO_SANDBOX="$sb" VO_SUT="$SUT" VO_PORT_A="$p1" VO_PORT_B="$p2"
EOF
    echo "$sb"
}

# ---------- Cleanup ----------
cleanup() {
    local sb=$1 pid label
    case "$sb" in "${TMPDIR:-/tmp}"/verify-ops.*|/tmp/verify-ops.*|/private/tmp/verify-ops.*) ;; *)
        echo "verify-ops: 不是 verify-ops 的沙箱，不动：$sb" >&2; return 2 ;; esac
    [ -d "$sb" ] || return 0
    touch "$sb/mock/a.stop" 2>/dev/null
    if [ -f "$sb/pids" ]; then
        while read -r pid label; do
            [ -n "$pid" ] || continue
            kill "$pid" 2>/dev/null
        done <"$sb/pids"
        sleep 0.5
        while read -r pid label; do
            [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        done <"$sb/pids"
    fi
    rm -rf "$sb"
}

# ---------- Doctor ----------
# port_owner <端口>：打印监听这个端口的 pid。macOS 用 lsof；Linux 没装 lsof 时用 ss。两样都没有返回 3。
port_owner() {
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1
    elif command -v ss >/dev/null 2>&1; then
        ss -ltnp "sport = :$1" 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1
    else
        return 3
    fi
}

# doctor_in <沙箱>：只读。0 = 值得驱动；2 = 不健康（HOME 不是沙箱、端口不归我们、被测脚本不是这份）。
doctor_in() {
    local sb=$1 bad=0 pid label port owner f rc
    ( . "$sb/env.sh"
      [ "$HOME" = "$sb/home" ] && [ "$HOME" != "$REAL_HOME" ] ) \
        && say "ok   HOME 是沙箱（\$TMPDIR 下的 verify-ops.*/home），不是真 HOME" \
        || { say "BAD  HOME 不是沙箱"; bad=1; }
    for f in a b; do
        port=$(cat "$sb/mock/$f.port" 2>/dev/null)
        pid=$(awk -v l="mock-$f" '$2 == l {print $1}' "$sb/pids")
        owner=$(port_owner "${port:-0}"); rc=$?
        if [ "$rc" = 3 ] && [ -n "$port" ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            say "warn 缺 lsof 和 ss，无法确认端口归属：假端点 $f 端口 ${port}，pidfile 里的进程 ${pid} 还活着（不算端口冲突）"
        elif [ -n "$port" ] && [ -n "$pid" ] && [ "$owner" = "$pid" ]; then
            say "ok   假端点 $f 端口 ${port} 由本次起的进程 ${pid} 监听"
        else
            say "BAD  假端点 $f 端口 ${port:-?} 的监听进程 ${owner:-无} 不是 pidfile 里的 ${pid:-?}"; bad=1
        fi
    done
    for f in notify-run orca-agent-launch orca-wake; do
        got=$( . "$sb/env.sh"; command -v "$f" )
        if [ "$got" = "$SUT/wake/bin/$f" ]; then say "ok   $f 解析到被测目录的 wake/bin/（不是 ~/.local/bin 那份）"
        else say "BAD  $f 解析到 ${got:-无}，不是被测目录"; bad=1; fi
    done
    ( . "$sb/env.sh"; [ "$(command -v pi)" = "$sb/bin/pi" ] ) && say "ok   pi 是沙箱里的假 agent" || { say "BAD  pi 不是假 agent"; bad=1; }
    ( . "$sb/env.sh"; [ "$(command -v ssh)" = "$sb/bin/ssh" ] ) && say "ok   ssh 是沙箱里的假 ssh，连不到真机器" || { say "BAD  ssh 不是假 ssh"; bad=1; }
    if [ "$SUT" = "$REPO" ]; then say "ok   被测代码 = 本次 checkout（$(git -C "$REPO" rev-parse --short=12 HEAD)，dirty=$(dirty)）"
    else say "note 被测代码 = VERIFY_OPS_SUT 指定的副本（不是 checkout；结果不能当 PR 的证据）"; fi
    say "info bash：${BASH_VERSION}（/bin/bash：$(/bin/bash -c 'echo $BASH_VERSION')）"
    if java -version >/dev/null 2>&1 && [ -r "${TLA_JAR:-$REAL_HOME/.local/opt/tla/tla2tools.jar}" ]; then
        say "info Java 和 tla2tools.jar 都在：wake-tla 会跑"
    else
        say "info 缺 Java 或 tla2tools.jar：wake-tla 记 skipped（不算通过），其余照跑"
    fi
    return $(( bad * 2 ))
}

dirty() { [ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] && echo false || echo true; }

# ---------- 记录用例 ----------
FEAT="" RUN="" SB=""
ok()   { printf '%s\tpass\t%s\t%s\n' "$FEAT" "$1" "${2:-}" >>"$RUN/cases.tsv"; say "ok   $1"; }
bad()  { printf '%s\tfail\t%s\t%s\n' "$FEAT" "$1" "${2:-}" >>"$RUN/cases.tsv"; say "FAIL $1${2:+（$2）}"; }
skip() { printf '%s\tskipped\t%s\t%s\n' "$FEAT" "$1" "${2:-}" >>"$RUN/cases.tsv"; say "SKIP $1${2:+（$2）}"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "得到 ${2}，期望 ${3}"; fi; }  # expect <名字> <实际> <期望>
cnt() { python3 -I "$VO" count "$@"; }
A() { echo "$SB/mock/a.jsonl"; }
B() { echo "$SB/mock/b.jsonl"; }
nrlog() { cat "$SB/home/.orca-state/notify-run/notify-run.log" 2>/dev/null; }

# ---------- feature：wake-chain ----------
f_wake_chain() {
    local NR="$SUT/wake/bin/notify-run" rc p t0
    "$NR" --bot verify-bot --task wc-done --no-tty -- true; rc=$?
    expect "true：退出码 0 原样传出" "$rc" 0
    expect "true：假端点恰好收到 1 条（bot=verify-bot status=done exit_code=0）" \
        "$(cnt "$(A)" task=wc-done bot=verify-bot status=done exit_code=0 source=notify-run auth_ok=true)/$(cnt "$(A)" task=wc-done)" "1/1"
    expect "true：notify-run.log 记 http=200 第 1 次" "$(nrlog | grep -c 'bot=verify-bot.*status=done.*http=200	try=1')" 1

    "$NR" --bot verify-bot --task wc-failed --no-tty -- sh -c 'echo verify-ops-out; exit 7'; rc=$?
    expect "exit 7：退出码 7 原样传出" "$rc" 7
    expect "exit 7：假端点恰好收到 1 条 status=failed exit_code=7" \
        "$(cnt "$(A)" task=wc-failed status=failed exit_code=7)/$(cnt "$(A)" task=wc-failed)" "1/1"
    expect "exit 7：log_tail 带命令输出" "$(grep -c '"task": "wc-failed".*verify-ops-out' "$(A)")" 1

    "$NR" --bot verify-bot --task wc-false --no-tty -- false; rc=$?
    expect "false：退出码 1，status=failed" "$rc/$(cnt "$(A)" task=wc-false status=failed exit_code=1)" "1/1"

    "$NR" --bot verify-bot --task wc-killed --no-tty -- sleep 30 &
    p=$!; echo "$p notify-run-killed" >>"$SB/pids"
    sleep 1; kill -TERM "$p"; wait "$p"; rc=$?
    expect "被 TERM：退出码 143" "$rc" 143
    expect "被 TERM：假端点恰好收到 1 条 status=killed exit_code=143" \
        "$(cnt "$(A)" task=wc-killed status=killed exit_code=143)/$(cnt "$(A)" task=wc-killed)" "1/1"

    # 非 2xx：假端点 B 对 /hook/verify-down 回 503。NOTIFY_RUN_TRIES=2，两次之间 notify-run 睡 20 秒。
    t0=$(date +%s)
    NOTIFY_RUN_TRIES=2 "$NR" --bot verify-down --task wc-503 --no-tty -- true 2>"$SB/wc-503.err"; rc=$?
    cat "$SB/wc-503.err"
    expect "503：发送失败不改变命令退出码（0）" "$rc" 0
    expect "假端点回 503 时不应记成已发送：按 NOTIFY_RUN_TRIES=2 重试，假端点收到 2 次" \
        "$(cnt "$(B)" task=wc-503 answered=503)" 2
    expect "503：notify-run.log 两行 http=503（第 1、2 次），没有任何一行记成 2xx" \
        "$(nrlog | grep 'bot=verify-down' | grep -c 'http=503')/$(nrlog | grep 'bot=verify-down' | grep -c 'http=2')" "2/0"
    expect "503：两次之间等了约 20 秒（notify-run 的重试间隔）" "$([ $(( $(date +%s) - t0 )) -ge 19 ] && echo yes)" yes
}

# ---------- feature：agent-launch-gate ----------
f_agent_launch_gate() {
    local OAL="$SUT/wake/bin/orca-agent-launch" rc n0 log="$SB/linear.log"
    export ORCA_AGENT_LAUNCH_NOTIFY_RUN="$SUT/wake/bin/notify-run"
    # 在空目录里起：checkout 的 AGENTS.md 有标记句，cwd 在仓库里就测不到沙箱 HOME 这一路
    mkdir -p "$SB/ws"; cd "$SB/ws" || return 1
    rej() {  # rej <名字> <期望退出码> <参数...>：拒绝，且拒绝原因叫醒了一次（发给 bot 或 coding-assistant）
        local name=$1 want=$2 before; shift 2
        before=$(cnt "$(A)" kind=agent_not_started source=orca-agent-launch)
        "$OAL" "$@" 2>>"$SB/oal.err"; rc=$?
        expect "${name}：退出码 $want" "$rc" "$want"
        expect "${name}：拒绝原因叫醒 1 次（kind=agent_not_started）" \
            "$(( $(cnt "$(A)" kind=agent_not_started source=orca-agent-launch) - before ))" 1
    }
    rej "没带 --bot" 2 --task gate-nobot -- pi
    rej "没带 --task" 2 --bot verify-bot -- pi
    rej "bot 没有 webhook 配置" 2 --bot verify-nobody --task gate-nohook -- pi
    expect "bot 没有 webhook 配置：拒绝改发 coding-assistant" "$(cnt "$(A)" task=gate-nohook bot=coding-assistant)" 1
    rej "经 bash -c 转一层" 2 --bot verify-bot --task gate-bash -- bash -c pi
    rej "经 env 转一层" 2 --bot verify-bot --task gate-env -- env pi
    rej "经 nohup 转一层" 2 --bot verify-bot --task gate-nohup -- nohup pi
    # 代码里带 --issue 没带 --eta 是退出码 2（brief 写的是 3，以代码为准，见 features/agent-launch-gate.md）
    rej "带 --issue 没带 --eta" 2 --bot verify-bot --task gate-noeta --issue PER-1 -- pi
    # Linear 写不进：用 wake/tests/fake-orca/orca（它的 linear issue 回空卡片 → 「Linear 里找不到」）
    printf '{"iMac": {}}\n' >"$SB/empty-orca.json"
    FAKE_ORCA_FIXTURE="$SB/empty-orca.json" FAKE_ORCA_LOG="$SB/fake-orca-oal.log" \
        ORCA_AGENT_LAUNCH_ORCA="$SUT/wake/tests/fake-orca/orca" \
        rej "Linear 写不进去" 3 --bot verify-bot --task gate-linear-fail --issue PER-1 --eta 2026-11-01 -- pi
    expect "Linear 写不进去：没起 agent（没有 notify-run 的叫醒）" "$(cnt "$(A)" task=gate-linear-fail source=notify-run)" 0
    # 合法：无 --issue
    n0=$(cnt "$(A)" source=notify-run)
    "$OAL" --bot verify-bot --task gate-ok -- pi 2>>"$SB/oal.err"; rc=$?
    expect "合法参数：进入 notify-run --tty，假 agent 退出码 0 传出" "$rc" 0
    expect "合法参数：假 agent 退出后叫醒恰好 1 次（notify-run，done）" \
        "$(cnt "$(A)" task=gate-ok source=notify-run status=done bot=verify-bot)/$(cnt "$(A)" task=gate-ok)" "1/1"
    expect "合法参数：tty 模式（log_tail 是终端直通说明）" "$(grep '"task": "gate-ok"' "$(A)" | grep -c '终端直通模式')" 1
    # 合法：带 --issue --eta，Linear 写入用沙箱里的假 Linear
    VO_LINEAR_LOG="$log" ORCA_AGENT_LAUNCH_ORCA="$SB/bin/fake-linear-ok" \
        "$OAL" --bot verify-bot --task gate-issue-ok --issue PER-9 --eta "2026-11-02 10:00" -- pi 2>>"$SB/oal.err"; rc=$?
    expect "带 --issue --eta：退出码 0，叫醒 1 次" "$rc/$(cnt "$(A)" task=gate-issue-ok source=notify-run issue=PER-9)" "0/1"
    expect "带 --issue --eta：写了 due=2026-11-02" "$(grep -c '"due-date", "set", "PER-9", "--to", "2026-11-02"' "$log")" 1
    expect "带 --issue --eta：描述补了「负责 bot：verify-bot」" "$(grep '"save-issue"' "$log" | grep -c '负责 bot：verify-bot')" 1
    # 启动前检查：上面放行的 3 次都靠沙箱全局 AGENTS；改成没有标记句、再删掉，都要拒绝
    expect "启动前检查：放行的 3 次标记句都在沙箱 ~/.pi/agent/AGENTS.md" \
        "$(grep -c '启动检查：pi 指令链 1 个文件，标记句在 .*/\.pi/agent/AGENTS\.md$' "$SB/oal.err")" 3
    local g="$HOME/.pi/agent/AGENTS.md"
    printf '# 沙箱：没有标记句\n' >"$g"
    rej "指令链文件没有标记句" 2 --bot verify-bot --task gate-no-marker -- pi
    expect "指令链文件没有标记句：报「都没有标记句」，没起 agent" \
        "$(grep -c '拒绝：启动检查：pi 指令链 1 个文件都没有标记句' "$SB/oal.err")/$(cnt "$(A)" task=gate-no-marker source=notify-run)" "1/0"
    rm -f "$g"
    rej "指令链一个文件都没有" 2 --bot verify-bot --task gate-no-chain -- pi
    expect "指令链一个文件都没有：报「一个文件都没有」，没起 agent" \
        "$(grep -c '拒绝：启动检查：pi 指令链里一个文件都没有' "$SB/oal.err")/$(cnt "$(A)" task=gate-no-chain source=notify-run)" "1/0"
    cp "$SUT/AGENTS.md" "$g"   # 后面的 feature 共用这个沙箱 HOME
    unset ORCA_AGENT_LAUNCH_NOTIFY_RUN
    cat "$SB/oal.err"
}

# ---------- feature：stuck-check ----------
f_stuck_check() {
    local SC="$SUT/scripts/stuck-check.sh" st="$SB/stuck-state" p1 p2 rc
    mkdir -p "$st" "$SB/stuck-runs"
    sleep 600 & p1=$!; echo "$p1 agent-idle-standin" >>"$SB/pids"
    sleep 600 & p2=$!; echo "$p2 agent-silent-standin" >>"$SB/pids"
    python3 -I "$VO" stuck-fixture "$SB" "$p1" "$p2"
    sc() {  # 一次「不带参数」的检查：查一遍并直接发（不经复核）
        env STUCK_STATE_DIR="$st" STUCK_RUNS_DIR="$SB/stuck-runs" STUCK_WEBHOOK_DIR="$HOME/.config/grokbot/webhooks" \
            STUCK_ENV_FILE="$HOME/.config/grokbot/webhooks/coding-assistant.env" STUCK_PROBE="$SB/bin/agent-probe.py" \
            VO_PROBE_JSON="$SB/probe.json" VO_FAKE_ORCA_PY="$SUT/wake/tests/fake_orca.py" \
            FAKE_ORCA_FIXTURE="$SB/orca.json" FAKE_ORCA_LOG="$SB/fake-orca-stuck.log" \
            STUCK_ORCA_WAKE="$SUT/wake/bin/orca-wake" STUCK_MBA_ENV= STUCK_BOX_RETRY_WAIT=0 STUCK_POST_GAP=0 STUCK_BACKOFF=1 \
            STUCK_PRECHECK_TIMEOUT_S=300 "$SC" "$@"
    }
    sc >"$SB/stuck-1.out" 2>&1; rc=$?; cat "$SB/stuck-1.out"
    expect "第 1 次检查退出码 0" "$rc" 0
    expect "agent_gone：恰好 1 条（verify-gone）" "$(cnt "$(A)" kind=agent_gone task=verify-gone worktree=iMac:/fake/ws/verify-gone)/$(cnt "$(A)" kind=agent_gone)" "1/1"
    expect "agent_idle：恰好 1 条（verify-idle，orca-wake 回 no_state_for_pid 后按老办法报）" \
        "$(cnt "$(A)" kind=agent_idle task=verify-idle worktree=iMac:/fake/ws/verify-idle)/$(cnt "$(A)" kind=agent_idle)" "1/1"
    expect "agent_silent：恰好 1 条（verify-silent）" "$(cnt "$(A)" kind=agent_silent task=verify-silent worktree=iMac:/fake/ws/verify-silent)/$(cnt "$(A)" kind=agent_silent)" "1/1"
    expect "三条都来自 stuck-check、status=stuck" "$(cnt "$(A)" source=stuck-check status=stuck)" 3
    sc >"$SB/stuck-2.out" 2>&1; rc=$?; cat "$SB/stuck-2.out"
    expect "第 2 次检查（同一工作区没新活动）：不再报，仍是 3 条" "$rc/$(cnt "$(A)" source=stuck-check status=stuck)" "0/3"
    expect "两次检查都打了心跳 @@HB" "$(cat "$SB/stuck-1.out" "$SB/stuck-2.out" | grep -c '^@@HB {')" 2
    # 心跳过期：heartbeat-watch.sh + wake/tests/hb-replay 的回放 orca（最新心跳 30 分钟前）
    local HW="$SUT/scripts/heartbeat-watch.sh" tgt="ops01-卡住检查||439cd438-cffe-44dd-bd2b-23b07bfa3d61|20"
    hw() { env HB_STATE_DIR="$SB/hb-state" STUCK_WEBHOOK_DIR="$HOME/.config/grokbot/webhooks" HB_ORCA="$SUT/wake/tests/hb-replay/orca" \
        HB_REPLAY_LOG="$SB/hb-replay.log" "$@"; }
    hw HB_REPLAY_AGE_S=1800 "$HW" --target "$tgt" >"$SB/hb-1.out" 2>&1; rc=$?; cat "$SB/hb-1.out"
    expect "心跳 30 分钟前（阈值 20）：heartbeat-watch 退出码 0，ops-system 收到 1 条 heartbeat_stale" \
        "$rc/$(cnt "$(A)" kind=heartbeat_stale bot=ops-system)" "0/1"
    hw HB_REPLAY_AGE_S=1800 "$HW" --target "$tgt" >"$SB/hb-2.out" 2>&1; cat "$SB/hb-2.out"
    expect "同一次中断再查：不重复报" "$(cnt "$(A)" kind=heartbeat_stale)" 1
    hw HB_REPLAY_AGE_S=120 "$HW" --target "$tgt" >"$SB/hb-3.out" 2>&1; cat "$SB/hb-3.out"
    expect "心跳恢复（2 分钟前）：报 1 条 heartbeat_recovered" "$(cnt "$(A)" kind=heartbeat_recovered)" 1
}

# ---------- feature：drift-checks ----------
f_drift_checks() {
    local rc out h n=4 sha
    # 1. wake/install.sh --check：先在沙箱 HOME 装一遍，再让对端的全局 AGENTS 不一致，最后改坏一个已装文件
    "$SUT/wake/install.sh" >"$SB/install.out" 2>&1 || cat "$SB/install.out"
    "$SUT/wake/install.sh" --check >"$SB/d1.out" 2>&1; rc=$?; cat "$SB/d1.out"
    # 台数写死：默认对端 imac mba box 去掉本机再加上本机，本机是这三台之一时 3 台，否则 4 台。对端被悄悄少探一台时这条要挂
    case "$(hostname | cut -d. -f1 | tr '[:upper:]' '[:lower:]')" in imac|mba|box|grok-bot-vm-*) n=3 ;; esac
    sha=$( (shasum -a 256 "$HOME/.pi/agent/AGENTS.md" 2>/dev/null || sha256sum "$HOME/.pi/agent/AGENTS.md") | cut -c1-12)
    expect "install.sh --check 干净：退出码 0，${n} 台全局 AGENTS 一致" \
        "$rc/$(grep -cE "^PASS  全局 AGENTS 一致（${n} 台：[^ ]+=${sha}( [^ ]+=${sha}){$((n - 1))}）$" "$SB/d1.out")" "0/1"
    for h in imac mba box; do echo "# verify-ops drift" >>"$SB/peers/$h/.pi/agent/AGENTS.md"; done
    "$SUT/wake/install.sh" --check >"$SB/d1b.out" 2>&1; rc=$?; cat "$SB/d1b.out"
    expect "install.sh --check 对端全局 AGENTS 不一致：退出码 1，报不一致" "$rc/$(grep -c '^FAIL  全局 AGENTS 不一致：' "$SB/d1b.out")" "1/1"
    for h in imac mba box; do cp "$HOME/.pi/agent/AGENTS.md" "$SB/peers/$h/.pi/agent/AGENTS.md"; done
    echo "# verify-ops drift" >>"$HOME/.local/bin/notify-run"
    "$SUT/wake/install.sh" --check >"$SB/d2.out" 2>&1; rc=$?; cat "$SB/d2.out"
    expect "install.sh --check 漂移：退出码 1，指出 notify-run「不同」，全局 AGENTS 仍一致" \
        "$rc/$(grep -c '^不同  .*/\.local/bin/notify-run$' "$SB/d2.out")/$(grep -c '^PASS  全局 AGENTS 一致（' "$SB/d2.out")" "1/1/1"

    # 2. scripts/sync-bot-rules --check：沙箱里克隆一份仓库，targets.tsv 加一行指向沙箱目录，ref=HEAD，不 fetch
    local R="$SB/repo-clone" T="$SB/bot-rules-target"
    git clone -q --local --no-hardlinks "$SUT" "$R" 2>/dev/null || git clone -q "$SUT" "$R"
    mkdir -p "$T"
    printf 'verify\t*\tdocs/bot-rules/dev-bot-rules/\t%s\n' "$T" >>"$R/docs/bot-rules/targets.tsv"
    git -C "$R" -c user.name=verify-ops -c user.email=verify-ops@invalid commit -qam "verify-ops sandbox target"
    SBR() { "$SUT/scripts/sync-bot-rules" --repo "$R" --ref HEAD --no-fetch --machine verify "$@"; }
    SBR --apply >"$SB/d3a.out" 2>&1
    SBR --check >"$SB/d3.out" 2>&1; rc=$?; cat "$SB/d3.out"
    expect "sync-bot-rules --check 干净：退出码 0，至少 1 行 same" "$rc/$([ "$(grep -c '| same$' "$SB/d3.out")" -ge 1 ] && echo y)" "0/y"
    out=$(cd "$T" && find . -type f | sed 's#^\./##' | head -1)
    echo "# verify-ops drift" >>"$T/$out"
    echo extra >"$T/verify-extra.md"
    SBR --check >"$SB/d4.out" 2>&1; rc=$?; cat "$SB/d4.out"
    expect "sync-bot-rules --check 漂移：退出码 1，指出 ${out} drift 和 verify-extra.md extra" \
        "$rc/$(grep -c "/$out | .* | drift$" "$SB/d4.out")/$(grep -c 'verify-extra.md | .* | extra$' "$SB/d4.out")" "1/1/1"

    # 3. make-prompts.py --check：对被测目录只读跑一次（干净），再对沙箱副本改一个已提交的 prompt
    python3 -I "$SUT/automations/migration-1020/make-prompts.py" --check >"$SB/d5.out" 2>&1; rc=$?; cat "$SB/d5.out"
    expect "make-prompts.py --check 干净：退出码 0" "$rc" 0
    cp -R "$SUT/automations/migration-1020" "$SB/mp"
    out=$(cd "$SB/mp" && find prompts -name '*.prompt.md' | sort | head -1)
    echo "verify-ops drift" >>"$SB/mp/$out"
    python3 -I "$SB/mp/make-prompts.py" --check >"$SB/d6.out" 2>&1; rc=$?; cat "$SB/d6.out"
    expect "make-prompts.py --check 漂移：退出码 1，指出 ${out}" "$rc/$(grep -c "$out differs" "$SB/d6.out")" "1/1"

    # 4. bootstrap/claude-plugins/pin-claude-plugins.sh --check --home 沙箱
    # 预检：两个插件仓库在本机、且含钉的 commit，否则离线做不出干净状态，记 skipped（见 features/drift-checks.md Gotchas）
    local P="$HOME/.claude/pinned-marketplaces" PIN="$SUT/bootstrap/claude-plugins/pin-claude-plugins.sh" src n v sha miss="" ok_src=1
    for n in cursor-plugins=PSTACK_SHA compound-engineering-plugin=CE_SHA; do
        v=${n#*=}; n=${n%=*}; src="$REAL_HOME/.claude/pinned-marketplaces/$n"
        sha=$(sed -n "s/^${v}=\([0-9a-f]\{40\}\).*/\1/p" "$PIN")
        if [ -z "$sha" ]; then
            bad "pin-claude-plugins：读不到钉的 commit" "$PIN 里没有 ${v}"
            return
        elif [ ! -d "$src/.git" ]; then miss="$miss 没有 ${n}"
        elif ! git -C "$src" cat-file -e "$sha^{commit}" 2>/dev/null; then miss="$miss ${n} 缺 $(printf %.12s "$sha")"
        fi
    done
    if [ -n "$miss" ]; then
        skip "pin-claude-plugins --check" "缺前置条件：~/.claude/pinned-marketplaces/${miss}"
        return
    fi
    mkdir -p "$P" "$HOME/.claude/plugins"
    for n in cursor-plugins compound-engineering-plugin; do
        git clone -q --shared "$REAL_HOME/.claude/pinned-marketplaces/$n" "$P/$n" 2>/dev/null || ok_src=0
    done
    if [ "$ok_src" = 0 ]; then
        bad "pin-claude-plugins：预检过了但 git clone --shared 失败"
        return
    fi
    # installed_plugins.json 是 `claude plugin install` 写的（外部 CLI 边界）：按钉的版本写进沙箱，安装脚本就不去调 claude
    python3 -I - "$SUT/bootstrap/claude-plugins/pin-claude-plugins.sh" "$P" "$HOME/.claude/plugins/installed_plugins.json" <<'PY'
import json, re, subprocess, sys
src, P, out = sys.argv[1:4]
s = open(src, encoding="utf-8").read()
ps, ce = re.search(r"^PSTACK_SHA=(\w+)", s, re.M).group(1), re.search(r"^CE_SHA=(\w+)", s, re.M).group(1)
pins = [("cursor-plugins", ps, "harness/pstack/claude-code/plugin.json", "pstack@cursor-plugins"),
        ("compound-engineering-plugin", ce, ".claude-plugin/plugin.json", "compound-engineering@compound-engineering-plugin")]
d = {"version": 2, "plugins": {}}
for name, sha, man, pid in pins:
    ver = json.loads(subprocess.run(["git", "-C", "%s/%s" % (P, name), "show", "%s:%s" % (sha, man)],
                                    capture_output=True, check=True).stdout)["version"]
    d["plugins"][pid] = [{"scope": "user", "version": ver, "gitCommitSha": sha}]
json.dump(d, open(out, "w"), indent=2)
PY
    bash "$SUT/bootstrap/claude-plugins/pin-claude-plugins.sh" --home "$HOME" >"$SB/d7a.out" 2>&1
    bash "$SUT/bootstrap/claude-plugins/pin-claude-plugins.sh" --check --home "$HOME" >"$SB/d7.out" 2>&1; rc=$?; cat "$SB/d7.out"
    expect "pin-claude-plugins --check 干净：退出码 0（全部一致。）" "$rc/$(grep -c '^全部一致。' "$SB/d7.out")" "0/1"
    python3 -I - "$HOME/.claude/settings.json" <<'PY'
import json, sys
f = sys.argv[1]; d = json.load(open(f))
d["permissions"]["deny"] = [r for r in d["permissions"]["deny"] if r != "Skill(pstack:tdd)"]
json.dump(d, open(f, "w"), indent=2)
PY
    bash "$SUT/bootstrap/claude-plugins/pin-claude-plugins.sh" --check --home "$HOME" >"$SB/d8.out" 2>&1; rc=$?; cat "$SB/d8.out"
    expect "pin-claude-plugins --check 漂移：退出码 1，指出 deny Skill(pstack:tdd) 不符" \
        "$rc/$(grep -c '^不符  settings.json deny Skill(pstack:tdd)$' "$SB/d8.out")" "1/1"
}

# ---------- feature：night-review-gate ----------
f_night_review_gate() {
    local G="$SUT/scripts/night-review-gate.sh" rc
    mkdir -p "$SB/nr-dir"
    nr() { env NR_STATE="$SB/nr-state" NR_DIR="$SB/nr-dir" NR_STORE_HOST=local NR_STORE_DIR="$SB/nr-store" \
        HEAVY_LOCK_DIR="$SB/heavy.lock" "$G" "$@"; }
    lock() {  # 像夜审 precheck 一样先拿锁，finish 必须把它放掉
        HEAVY_LOCK_DIR="$SB/heavy.lock" bash "$SUT/scripts/heavy-lock.sh" acquire night-review-xinyue >/dev/null
        expect "$1：finish 之前 heavy-lock 被占着" "$([ -d "$SB/heavy.lock" ] && echo held || echo free)" held
    }
    printf '# 心月夜审 2026-10-28\n\n状态：完成\n' >"$SB/nr-dir/2026-10-28-xinyue.md"
    echo '{}' >"$SB/nr-dir/2026-10-28-xinyue-ledger.jsonl"
    lock "有「状态：完成」"
    nr finish xinyue 2026-10-28 mba ok; rc=$?
    expect "有「状态：完成」：finish 之后 heavy-lock 已释放" "$([ -e "$SB/heavy.lock" ] && echo held || echo free)" free
    expect "摘要有「状态：完成」：finish 退出码 0" "$rc" 0
    expect "有「状态：完成」：摘要和 ledger 拷进存储目录后读回到了" \
        "$(grep -c '^状态：完成' "$SB/nr-store/2026-10-28-xinyue.md" 2>/dev/null)/$([ -f "$SB/nr-store/2026-10-28-xinyue-ledger.jsonl" ] && echo y)" "1/y"
    expect "有「状态：完成」：状态文件记 state=done" "$(tail -1 "$SB/nr-state/xinyue/2026-10-28.status" | grep -c 'state=done machine=mba reason=ok files=2')" 1
    printf '# 心月夜审 2026-10-27\n\n状态：进行中\n' >"$SB/nr-dir/2026-10-27-xinyue.md"
    lock "没有「状态：完成」"
    nr finish xinyue 2026-10-27 mba ok; rc=$?
    expect "摘要没有「状态：完成」：finish 退出码 3" "$rc" 3
    expect "没有「状态：完成」：没拷进存储，状态记 failed detail=no_done_line" \
        "$([ -e "$SB/nr-store/2026-10-27-xinyue.md" ] && echo copied || echo none)/$(tail -1 "$SB/nr-state/xinyue/2026-10-27.status" | grep -c 'state=failed.*detail=no_done_line')" "none/1"
    expect "没有「状态：完成」：finish 之后 heavy-lock 也已释放" "$([ -e "$SB/heavy.lock" ] && echo held || echo free)" free
}

# ---------- feature：wake-tla（调用 wake-tla-verify，不复制） ----------
f_wake_tla() {
    local java=${TLA_JAVA:-$REAL_HOME/.local/opt/jdk-17.0.12+7-jre/bin/java} jar=${TLA_JAR:-$REAL_HOME/.local/opt/tla/tla2tools.jar} rc
    if [ ! -x "$java" ] || [ ! -r "$jar" ]; then
        skip "wake/tla/check.sh w0 h0" "缺 TLA 工具：$( [ -x "$java" ] || echo "Java 17（TLA_JAVA）" ) $( [ -r "$jar" ] || echo "tla2tools.jar（TLA_JAR）" )不在，装法见 wake/tla/README.md「安装」"
        return 0
    fi
    TLA_JAVA="$java" TLA_JAR="$jar" "$SUT/wake/tla/check.sh" --out "$SB/tla-out" w0 h0; rc=$?
    case "$rc" in
        0) ok "wake/tla/check.sh w0 h0 与期望表一致" ;;
        2) skip "wake/tla/check.sh w0 h0" "check.sh 报环境问题（退出码 2，见上面原文）" ;;
        *) bad "wake/tla/check.sh w0 h0 与期望表不一致" "退出码 $rc" ;;
    esac
    cp "$SB/tla-out/summary.tsv" "$RUN/features/wake-tla.summary.tsv" 2>/dev/null || true
}

# ---------- run ----------
run_features() {
    local sel="" f fn rc ts
    if [ $# -eq 0 ]; then sel=$ALL_FEATURES; else
        for f in "$@"; do case " $ALL_FEATURES " in *" $f "*) sel="$sel $f" ;; *) say "verify-ops: 没有这个 feature：${f}（verify.sh list 看名字）；一个用例都不跑"; say "VERIFY-OPS EMPTY（0 个用例，skipped 0）"; exit 3 ;; esac; done
    fi
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    RUN="$ARCHIVE/$ts"
    mkdir -p "$RUN/features" "$RUN/webhook" || exit 2
    : >"$RUN/cases.tsv"; : >"$RUN/features.tsv"
    local g0 g1 guard_ok=true
    g0=$(python3 -I "$VO" guard "$REAL_HOME/.config/grokbot/webhooks" "$REAL_HOME/.orca-state/notify-run/notify-run.log")
    SB=$(launch | tail -1)
    [ -d "$SB" ] || { echo "verify-ops: 沙箱没建起来" >&2; exit 2; }
    trap 'cleanup "$SB"' EXIT
    trap 'exit 130' INT TERM
    say "== doctor"
    if ! doctor_in "$SB" | tee "$RUN/doctor.txt"; then :; fi
    if grep -q '^BAD' "$RUN/doctor.txt"; then say "verify-ops: 体检不过，不驱动（见上）"; exit 2; fi
    for f in $sel; do
        FEAT=$f
        fn=f_$(echo "$f" | tr - _)
        say "== $f"
        ( . "$SB/env.sh"; set +e; "$fn" ) >"$SB/feat-$f.log" 2>&1
        rc=$?
        cat "$SB/feat-$f.log"
        python3 -I "$VO" mask "$SB/feat-$f.log" "$RUN/features/$f.log"
        printf '%s\t%s\t%s\n' "$f" "bash .claude/skills/verify-ops/verify.sh run $f" "$rc" >>"$RUN/features.tsv"
    done
    for f in a b; do [ -f "$SB/mock/$f.jsonl" ] && python3 -I "$VO" mask "$SB/mock/$f.jsonl" "$RUN/webhook/requests-$f.jsonl"; done
    [ -f "$SB/home/.orca-state/notify-run/notify-run.log" ] && python3 -I "$VO" mask "$SB/home/.orca-state/notify-run/notify-run.log" "$RUN/webhook/notify-run.log"
    cleanup "$SB"; trap - EXIT
    local left
    left=$(ps ax -o pid=,command= | grep -F "$SB" | grep -v grep | wc -l | tr -d ' ')
    g1=$(python3 -I "$VO" guard "$REAL_HOME/.config/grokbot/webhooks" "$REAL_HOME/.orca-state/notify-run/notify-run.log")
    python3 -I - "$g0" "$g1" <<'PY' || guard_ok=false
import json, sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
sys.exit(0 if a["webhooks"] == b["webhooks"] and a["notify_run_log_verify_lines"] == b["notify_run_log_verify_lines"] == 0 else 1)
PY
    python3 -I - "$RUN/meta.json" "$g0" "$g1" "$guard_ok" "$ts" "$SUT" "$REPO" "$(dirty)" "$BASH_VERSION" "$left" "$([ -d "$SB" ] && echo no || echo yes)" <<'PY'
import json, platform, subprocess, sys
out, g0, g1, guard_ok, ts, sut, repo, dirty, bashv, left, removed = sys.argv[1:12]
sha = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
if platform.system() == "Darwin":
    machine = "macOS %s %s" % (subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip(), platform.machine())
else:
    machine = "%s %s" % (platform.system(), platform.machine())
    try:
        rel = dict(l.rstrip("\n").split("=", 1) for l in open("/etc/os-release", encoding="utf-8") if "=" in l)
        if rel.get("PRETTY_NAME"):
            machine = "%s %s %s" % (platform.system(), rel["PRETTY_NAME"].strip('"'), platform.machine())
    except OSError:
        pass
json.dump({
    "run_dir": ts, "sha": sha, "dirty": dirty == "true", "sut_kind": "checkout" if sut == repo else "VERIFY_OPS_SUT 副本",
    "machine": machine, "bash": bashv,
    "guard_before": json.loads(g0), "guard_after": json.loads(g1), "guard_ok": guard_ok == "true",
    "sandbox_removed": removed == "yes", "processes_left": int(left),
    "skipped_by_policy": [
        {"what": "sentinels/prod-watch.sh", "why": "读生产部署 id，碰生产，要 Zack 卡"},
        {"what": "scripts/ws-cleanup.sh 非 dry-run", "why": "真删工作区，要 Zack 卡"},
        {"what": "live Orca / Linear / EverOS 写入", "why": "真实外部系统，要 Zack 卡"},
        {"what": "真实 webhook（真 bot）", "why": "会真的叫醒 bot，要 Zack 卡"}],
    "stand_ins": [
        "webhook 接收端 → automations/migration-1020/e2e/mock_webhook.py（回 200）和 wake/tests/mock_webhook.py（回 503），只监听本机回环",
        "Orca CLI → wake/tests/fake_orca.py（夹具由 helpers/vo.py stuck-fixture 生成），terminal wait 的 tui-idle 由 vo.py orca 回答",
        "Linear 写入 → vo.py linear（成功路径）和 wake/tests/fake-orca/orca（写不进路径）",
        "agent-probe 的进程表 → vo.py probe（两个本次起的 sleep 进程当 agent）",
        "heartbeat-watch 读的运行记录 → wake/tests/hb-replay/orca 回放",
        "夜审存储机（ssh 到 box）→ NR_STORE_HOST=local + 沙箱目录",
        "claude plugin install 写的 installed_plugins.json → 沙箱里按钉的版本预写；插件仓库从本机 ~/.claude/pinned-marketplaces 本地克隆",
        "全局规矩文件 → 沙箱 HOME 和假对端的 ~/.pi/agent/AGENTS.md 拷被测仓库的 AGENTS.md，~/.claude/CLAUDE.md 是一行 @ 引用",
        "ssh 到对端（install.sh --check 读全局 AGENTS）→ 沙箱里的假 ssh，对端是 $SB/peers/<机器>/",
        "agent（claude/pi/codex）→ 沙箱里的假 pi 脚本"],
}, open(out, "w"), indent=1, ensure_ascii=False)
PY
    local res skipped
    res=$(python3 -I "$VO" summary "$RUN")
    skipped=$(echo "$res" | cut -d' ' -f4)
    say "== 运行目录：$RUN"
    say "   summary.json：${res}；沙箱已删=$([ -d "$SB" ] && echo 否 || echo 是)，残留进程 ${left}，真实 HOME 守卫 ${guard_ok}"
    case "$res" in
        *PASS) say "VERIFY-OPS PASS（skipped ${skipped}）"; exit 0 ;;
        *EMPTY) say "VERIFY-OPS EMPTY（0 个用例，skipped ${skipped}）"; exit 3 ;;
        *) say "VERIFY-OPS FAIL（skipped ${skipped}）"; exit 1 ;;
    esac
}

case "${1:-}" in
    doctor)
        if [ -n "${2:-}" ]; then doctor_in "$2"; exit $?; fi
        SB=$(launch | tail -1); [ -d "$SB" ] || exit 2
        doctor_in "$SB"; rc=$?
        cleanup "$SB"
        exit $rc ;;
    launch) launch ;;
    cleanup) [ -n "${2:-}" ] || { echo "用法：verify.sh cleanup <沙箱>" >&2; exit 2; }; cleanup "$2" ;;
    list) for f in $ALL_FEATURES; do echo "$f"; done ;;
    run) shift; run_features "$@" ;;
    *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
