#!/bin/bash
# B1（automations/heartbeat-1021/）的演练：盯 iMac ops · 01 的跨机看守从 box 挪到 MBA↔iMac。在 iMac 的仓库根目录跑：
#   wake/tests/heartbeat-watch-ssh.sh           跑全部场景，产物写到 reports/heartbeat-mba-imac-1021/（目录里有 .hb-drill 标记才清空重写）
#   wake/tests/heartbeat-watch-ssh.sh --record  从本机 Orca 重录回放数据 wake/tests/hb-replay/fixtures/（只留 @@HB 行），然后退出
#   HB_DRILL_OUT=<目录>                          产物换个目录
#   HB_DRILL_NOTE=<一句话>                       写在产物 README 标题下面（回退测试 heartbeat-watch-ssh-rollback.sh 用）
# 要求：本机是 iMac（Orca 有 environment mba、grok-bot），能 ssh mba，MBA 能 ssh imac。退出码：0 全部 PASS，1 有 FAIL，2 跑不起来。
# 场景编号和要防的失败方式见 automations/heartbeat-1021/FAILURE-MODES.md；结果和期望写进产物目录的 README.md。
# 安全：heartbeat-watch 都用临时 HB_STATE_DIR，除 S12、S13 外都带 --dry-run、用假 webhook 目录（127.0.0.1:9 的假地址），不发叫醒、不读真凭据。
# S12、S13 不带 --dry-run（要看写下的 state.json 和 @@HB）：webhook 目录是空的，PATH 里有只记录调用的假 curl。
# S15 的 lock-held-alert 不看 --dry-run，要真发告警：发给假 webhook 目录（STUCK_FORCE_BOT=ops-system，127.0.0.1:9 的假地址），
# PATH 里的假 curl 只记下请求体、回 200，不连网络。
# lockf 的锁文件和 lock-held-alert 的状态文件都放在临时目录里，不碰 ~/.orca-state/heartbeat-watch/ 下的真文件。
# S14 的 kill、term、crash 核对 pid、ppid、命令名以后，只给演练自己起的 lockf 发 SIGKILL、SIGTERM、SIGSEGV。
# crash 每跑一次，macOS 在那台机器多写一份 lockf 的崩溃报告（iMac 上在 ~/Library/Logs/DiagnosticReports/，
# MBA 上在 /Library/Logs/DiagnosticReports/），演练不删（FAILURE-MODES F36、F37）。
# orca 只用 automations list / show / runs；不往 ~/.orca-state/bin 装文件；MBA 上只用 mktemp -d 建的临时目录，跑完删掉。
# 替身：S1、S3 用回放（假 HB_ORCA，S1 还固定时钟），S5 用假 ssh，S8 用假 orca，S12 用 ssh 替身（远端命令换成 sleep 110），
# S13 用 ssh、orca 替身（A 那轮每次调用先等 30 秒），S14 的 held、nodir、timeout 第一轮用 ssh / orca 替身，
# S15 用假 curl、改短的阈值和演练写的状态文件，这几个不算 E2E。
# S2、S4、S5b、S6、S6b、S7、S9、S10、S14 的 kill、term、crash 是真机器、真 ssh、真 Orca（只读）、真 lockf。
# 内部用法：--mba-side <MBA 上的临时目录> <标记>，由 iMac 这边拷到 MBA 上跑 MBA 的场景。
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
WATCHED=439cd438-cffe-44dd-bd2b-23b07bfa3d61      # iMac ops · 01 卡住工作检查
TARGET="iMac ops · 01 卡住工作检查||${WATCHED}|20"  # defs.json 里 MBA 新任务的目标；environment 空 = HB_ORCA 连到的那台
STANDIN=62d18b16-74ca-4c7f-a670-04197e7652fe      # MBA ops · 09，S6 / S6b 里代替还没建的 MBA 新任务
BOX=94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80
IMAC_WATCH=5c2d0575-dddc-4d5c-8f73-e47b26ea9a11
NOID=00000000-0000-0000-0000-000000000000
FAKEID=11111111-2222-3333-4444-555555555555
NOW=1792584000                                    # S1 的固定时钟：2026-10-21 20:00:00 SGT
MINPATH=/usr/bin:/bin:/usr/sbin:/sbin             # 近似 Orca 预检的最少环境
OLDWRAP=7ac12209ade6b548bdc39bf262f29c72cfb86318  # S12.old 用这个 commit 的 orca-via-ssh（第二轮审查前，ssh 没有 70 秒上限）
CANARY=

rssh() { ssh -o BatchMode=yes -o ConnectTimeout=10 mba "$@"; }

# 真路径的现状：MBA 上这九个都不该有，iMac 上两个锁文件、lock-held-alert 和它的两个状态文件不该有；主检出的 HEAD 前后要一样（只读 rev-parse）。
real_paths() {
    local p
    for p in .orca-state/bin/heartbeat-watch.sh .orca-state/bin/orca-via-ssh .orca-state/bin/lock-held-alert .orca-state/heartbeat-watch \
        .orca-state/heartbeat-watch/mba-hb-watch.lock .orca-state/heartbeat-watch/5c2d0575.lock \
        .orca-state/heartbeat-watch/mba-hb-watch.lock.skips.json .orca-state/heartbeat-watch/5c2d0575.lock.skips.json \
        orca/workspaces/ops/scripts/orca-via-ssh; do
        if [ -e "$HOME/$p" ]; then echo "有 ~/$p"; else echo "没有 ~/$p"; fi
    done
    echo "主检出 HEAD $(git -C "$HOME/orca/workspaces/ops" rev-parse HEAD 2>&1)"
}

# S5：包装该拒绝的都退出 2、不调 ssh。PATH 最前面是只记录参数的假 ssh；最后两条是放行的对照，假 ssh 要记到一次。
s5() {
    local wrap=$1 o=$2
    mkdir -p "$o/bin"
    cat >"$o/bin/ssh" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '[%s]' "$a"; done >>"$FAKE_SSH_LOG"
printf '\n' >>"$FAKE_SSH_LOG"
echo '{"ok": true, "result": {"runs": []}}'
EOF
    chmod +x "$o/bin/ssh"
    s5_one "$wrap" "$o" edit 2 imac automations edit "$NOID" --name hb-drill-rejected
    s5_one "$wrap" "$o" edit-id 2 imac automations edit --id "$NOID" --disabled
    s5_one "$wrap" "$o" run 2 imac automations run --id "$NOID"
    s5_one "$wrap" "$o" create 2 imac automations create --name hb-drill-rejected --disabled
    s5_one "$wrap" "$o" remove 2 imac automations remove --id "$NOID"
    s5_one "$wrap" "$o" show 2 imac automations show --id "$NOID" --json
    s5_one "$wrap" "$o" other-group 2 imac environment list --json
    s5_one "$wrap" "$o" only-automations 2 imac automations
    s5_one "$wrap" "$o" no-args 2 imac
    s5_one "$wrap" "$o" host-unset 2 -unset- automations runs --id "$NOID" --json
    s5_one "$wrap" "$o" host-empty 2 '' automations runs --id "$NOID" --json
    s5_one "$wrap" "$o" host-option 2 '-oProxyCommand=sh -c "echo HBPWN >&2"' automations runs --id "$NOID" --json
    s5_one "$wrap" "$o" allow-runs 0 imac automations runs --id "$NOID" --json
    s5_one "$wrap" "$o" allow-list 0 imac automations list --json
}

# s5_one <包装> <目录> <名字> <期望退出码> <ORCA_SSH_HOST，-unset- 表示不设> <参数...>
s5_one() {
    local wrap=$1 o=$2 name=$3 want=$4 host=$5 hostenv
    shift 5
    hostenv="ORCA_SSH_HOST=$host"
    [ "$host" = -unset- ] && hostenv=HB_DRILL_NOHOST=1
    : >"$o/$name.ssh-calls"
    echo "$want" >"$o/$name.want"
    { printf '%s orca-via-ssh' "$hostenv"; printf ' %s' "$@"; echo; } >"$o/$name.cmd"
    env -i HOME="$HOME" PATH="$o/bin:$MINPATH" LANG=en_US.UTF-8 HB_DRILL_CANARY="$CANARY" FAKE_SSH_LOG="$o/$name.ssh-calls" \
        "$hostenv" "$wrap" "$@" >"$o/$name.out" 2>"$o/$name.err"
    echo $? >"$o/$name.rc"
}

# 照 Orca 起预检：/bin/sh -c，自成一个进程组；到超时先给整个进程组发 SIGTERM，2 秒后发 SIGKILL；stdout、stderr 都关了才算结束。
# 只给它自己起的这个进程组发信号。write_orca_precheck <路径>；用法 python3 <路径> <超时秒数> <前缀> <precheck>，写 <前缀>.out、.err、.orca.json。
write_orca_precheck() {
    cat >"$1" <<'PY'
import json, os, signal, subprocess, sys, time

limit, prefix, cmd = int(sys.argv[1]), sys.argv[2], sys.argv[3]


def killpg(pg, sig):
    try:
        os.killpg(pg, sig)
    except ProcessLookupError:
        pass


start = time.time()
p = subprocess.Popen(["/bin/sh", "-c", cmd], stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
timed_out = False
try:
    out, err = p.communicate(timeout=limit)
    end = time.time()
except subprocess.TimeoutExpired:
    timed_out = True
    killpg(p.pid, signal.SIGTERM)
    kill_at = time.time() + 2
    try:
        out, err = p.communicate(timeout=2)
        end = time.time()
        time.sleep(max(0.0, kill_at - time.time()))
        killpg(p.pid, signal.SIGKILL)
    except subprocess.TimeoutExpired:
        killpg(p.pid, signal.SIGKILL)
        out, err = p.communicate(timeout=10)
        end = time.time()
open(prefix + ".out", "wb").write(out)
open(prefix + ".err", "wb").write(err)
json.dump({"timeoutSeconds": limit, "timedOut": timed_out, "exitCode": None if timed_out else p.returncode,
           "durationS": round(end - start, 1), "start": start, "end": end}, open(prefix + ".orca.json", "w"))
PY
}

# s14_run <mini|inherit> <替身目录> <HB_STATE_DIR> <webhook 目录> <命令...>：替身目录放在 PATH 最前面。
# mini：env -i 最少环境（MBA，近似 Orca 预检）；inherit：本机环境去掉 HB_ORCA 等（iMac，同 S6b）。
s14_run() {
    local mode=$1 stub=$2 st=$3 hooks=$4
    shift 4
    if [ "$mode" = mini ]; then
        env -i HOME="$HOME" PATH="$stub:$MINPATH" LANG=en_US.UTF-8 PYTHONDONTWRITEBYTECODE=1 HB_DRILL_CANARY="$CANARY" \
            HB_STATE_DIR="$st" STUCK_WEBHOOK_DIR="$hooks" "$@"
    else
        env -u STUCK_FORCE_BOT -u HB_ORCA -u ORCA_SSH_HOST -u HB_LOCK_ALERT_MIN PATH="$stub:$PATH" PYTHONDONTWRITEBYTECODE=1 \
            HB_DRILL_CANARY="$CANARY" HB_STATE_DIR="$st" STUCK_WEBHOOK_DIR="$hooks" "$@"
    fi
}

# lockf 起的命令（它的子进程）的 pid；最多等 5 秒，没等到输出空。
lockf_child() {
    local c='' i=0
    while [ -z "$c" ] && [ $i -lt 50 ]; do
        sleep 0.1
        c=$(pgrep -l -P "$1" | awk '{print $1; exit}')
        i=$((i + 1))
    done
    echo "$c"
}

# lockf 开头的崩溃报告有几个：先数 ~/Library/Logs/DiagnosticReports，再数 /Library/Logs/DiagnosticReports（MBA 的写在这里，
# FAILURE-MODES F37），一行两个数，读不了的目录记 ?。S14.crash 前后各数一次，只看文件名
crashes() {
    local d
    for d in "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports; do
        if [ -r "$d" ] && [ -x "$d" ]; then find "$d" -maxdepth 1 -name 'lockf*' | wc -l | tr -d ' '; else echo '?'; fi
    done | paste -s -d ' ' -
}

# S14（FAILURE-MODES.md A31、A33–A35、A52、A54）：lockf 本身，MBA、iMac 各跑一遍，锁文件都在 <工作目录> 下。
# s14 <mini|inherit> <工作目录> <输出目录> <precheck，锁目录写成 @LOCKDIR@> <锁文件名> <替身名，空格隔开> <第二轮的超时>
#     <orca-precheck.py> <webhook 目录>
# 替身：log/ 里的只记录调用（pid、时间、替身名、参数）、退出 1；slow/ 里的记下 pid、时间、替身名后 exec sleep 60。
# 要在主 shell 里调（不放进 $( ) 或后台）：kill、term、crash 那步核对 lockf 的 ppid 是 $$。只 wait 自己起的 pid，不碰后台的 S12。
s14() {
    local mode=$1 d=$2 o=$3 pc=$4 lk=$5 stubs=$6 lim2=$7 op=$8 hooks=$9 s k sig L hp c i pid ppid comm
    mkdir -p "$o" "$d/log" "$d/slow" "$d/none" "$d/held/lock" "$d/timeout/lock"
    for s in $stubs; do
        printf '#!/bin/sh\necho "$$ $(date +%%s) %s $*" >>"%s"\nexit 1\n' "$s" "$d/log.calls" >"$d/log/$s"
        printf '#!/bin/sh\necho "$$ $(date +%%s) %s" >>"%s"\nexec /bin/sleep 60\n' "$s" "$d/slow.calls" >"$d/slow/$s"
        chmod +x "$d/log/$s" "$d/slow/$s"
    done
    # held：lockf … sleep 6 先拿住锁（等到它起的 sleep 出现），再照 defs 原文跑 precheck。nodir：锁文件放在不存在的目录里
    # （漏了 README 第 1 步的 mkdir）。HB_STATE_DIR 都指向不存在的目录：heartbeat-watch 一起来就会建它（第 63 行，读 state 之前）。
    # 跑完把 lock-held-alert 记在锁文件旁边的状态文件（<锁文件>.skips.json）拷出来。
    for k in held nodir; do
        L=$d/held/lock
        [ "$k" = nodir ] && L=$d/nodir/no-such-dir
        hp=''
        if [ "$k" = held ]; then
            /usr/bin/lockf -k -t 0 "$L/$lk" /bin/sleep 6 &
            hp=$!
            c=$(lockf_child "$hp")
            echo "${c:-没等到}" >"$o/held.holder-child"
        fi
        : >"$d/log.calls"
        printf '%s\n' "${pc//@LOCKDIR@/$L} --dry-run" >"$o/$k.cmd"
        s14_run "$mode" "$d/log" "$d/$k/probe" "$hooks" /bin/sh -c "$(cat "$o/$k.cmd")" >"$o/$k.out" 2>"$o/$k.err"
        echo $? >"$o/$k.rc"
        if [ -e "$d/$k/probe" ]; then echo 有; else echo 没有; fi >"$o/$k.probe"
        cp "$d/log.calls" "$o/$k.calls"
        if [ -f "$L/$lk.skips.json" ]; then cp "$L/$lk.skips.json" "$o/$k.skips.json"; fi
        if [ -n "$hp" ]; then
            wait "$hp"
            echo $? >"$o/held.holder-rc"
        fi
    done
    # kill、term、crash：只用 lockf。lockf … sleep 8 拿住锁，探一次；核对 pid、ppid、命令名以后只给这个 lockf 发信号（kill 发 SIGKILL，
    # term 发 SIGTERM，crash 发 SIGSEGV 模拟崩溃），马上再探一次，再看锁文件还在不在（-k 不删它）。
    # 它起的 sleep 不发信号，最多等 15 秒让它自己结束。crash 前后各数一次两个 DiagnosticReports 目录里 lockf 开头的文件。
    for k in kill:KILL term:TERM crash:SEGV; do
        sig=${k#*:}
        k=${k%%:*}
        mkdir -p "$d/$k/lock"
        L=$d/$k/lock/$lk
        if [ "$k" = crash ]; then crashes >"$o/crash.reports-before"; fi
        /usr/bin/lockf -k -t 0 "$L" /bin/sleep 8 &
        hp=$!
        c=$(lockf_child "$hp")
        /usr/bin/lockf -k -t 0 "$L" /usr/bin/true 2>"$o/$k.probe1.err"
        echo $? >"$o/$k.probe1.rc"
        ps -o pid,ppid,rss,etime,comm -p "$hp" | sed 1d >"$o/$k.holder-ps"
        read -r pid ppid _ _ comm <"$o/$k.holder-ps"
        case "${pid:-}:${ppid:-}:${comm:-}" in
            "$hp:$$:"*lockf)
                kill -"$sig" "$hp"
                echo "kill -${sig} ${hp}（pid ${pid}、ppid ${ppid} 是演练的 shell、命令名 ${comm}）" >"$o/$k.sent" ;;
            *) echo "没发：pid、ppid、命令名对不上（${pid:-空} ${ppid:-空} ${comm:-空}，期望 ${hp} $$ lockf）" >"$o/$k.sent" ;;
        esac
        wait "$hp"
        echo $? >"$o/$k.holder-rc"
        /usr/bin/lockf -k -t 0 "$L" /usr/bin/true 2>"$o/$k.probe2.err"
        echo $? >"$o/$k.probe2.rc"
        if [ -f "$L" ]; then echo 有; else echo 没有; fi >"$o/$k.lockfile"
        if [ -n "$c" ]; then ps -o pid,ppid,rss,etime,comm -p "$c" | sed 1d; else echo "没等到它起的 sleep"; fi >"$o/$k.child-after-signal"
        i=0
        while [ -n "$c" ] && ps -o pid,ppid,rss,etime,comm -p "$c" >/dev/null && [ $i -lt 150 ]; do
            sleep 0.1
            i=$((i + 1))
        done
        if [ -n "$c" ] && ps -o pid,ppid,rss,etime,comm -p "$c" >/dev/null; then echo 还在; else echo "没了（发信号以后约 $((i / 10)) 秒）"; fi \
            >"$o/$k.child-end"
        if [ "$k" = crash ]; then crashes >"$o/crash.reports-after"; fi
    done
    # timeout：第一轮照 Orca 的做法起，超时 12 秒，替身换成 slow/ 里的；替身起来 3 秒后探一次锁，前后各记一次时间（判断时和第一轮的
    # 起止时间比，FAILURE-MODES.md C15）。第一轮被杀以后看替身还在不在，紧接着用真的 ssh / orca 起第二轮（none/ 是空目录），
    # 超时取 defs。两轮都加 --dry-run。
    L=$d/timeout/lock
    printf '%s\n' "${pc//@LOCKDIR@/$L} --dry-run" >"$o/timeout.cmd"
    : >"$d/slow.calls"
    s14_run "$mode" "$d/slow" "$d/timeout/state" "$hooks" /usr/bin/python3 -I "$op" 12 "$o/timeout-1" "$(cat "$o/timeout.cmd")" &
    hp=$!
    i=0
    while [ ! -s "$d/slow.calls" ] && [ $i -lt 100 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    sleep 3
    /usr/bin/python3 -I -c 'import time; print("%.3f" % time.time())' >"$o/timeout.probe.t"
    /usr/bin/lockf -k -t 0 "$L/$lk" /usr/bin/true 2>"$o/timeout.probe.err"
    echo $? >"$o/timeout.probe.rc"
    /usr/bin/python3 -I -c 'import time; print("%.3f" % time.time())' >>"$o/timeout.probe.t"
    wait "$hp"
    sleep 1  # 被杀的替身由 launchd 收尸，留 1 秒
    cut -d' ' -f1 "$d/slow.calls" | while read -r pid; do
        ps -o pid,ppid,rss,etime,comm -p "$pid" | sed 1d
    done >"$o/timeout.stub-after"
    cp "$d/slow.calls" "$o/timeout.stub-calls"
    s14_run "$mode" "$d/none" "$d/timeout/state" "$hooks" /usr/bin/python3 -I "$op" "$lim2" "$o/timeout-2" "$(cat "$o/timeout.cmd")"
}

# S15（FAILURE-MODES.md A41–A47、C17–C19）：锁一直被占着。MBA、iMac 各跑一遍，锁文件都在 <工作目录> 下。
# s15 <mini|inherit> <工作目录> <输出目录> <precheck，锁目录写成 @LOCKDIR@> <锁文件名> <超时> <orca-precheck.py>
#     <webhook 目录（里面是 ops-system.env 假配置）>
# 每轮照 Orca 的做法起，加 --dry-run，STUCK_FORCE_BOT=ops-system。PATH 最前面只有假 curl：记下请求体（一行一个）、回 200，不连网络。
# main：外部用 lockf … sleep 32 拿住锁，阈值改成 0.25 分钟，第 1–4 轮在第 1 轮开始后约 0、6、18、24 秒起；sleep 结束以后起第 5、6 轮。
# 45：不设阈值（默认 45 分钟），外部拿住锁，状态文件写成「44 分钟前起跳过 9 轮」「46 分钟前起跳过 9 轮」，各跑一轮。
# bad：外部拿住锁，状态文件是乱码、状态文件的路径是个目录，各跑一轮。
# 每轮之后记下 HB_STATE_DIR 有没有被建出来、假 curl 累计几次、锁文件旁边的状态文件。要在主 shell 里调：只 wait 自己起的 lockf。
s15() {
    local mode=$1 d=$2 o=$3 pc=$4 lk=$5 lim=$6 op=$7 hooks=$8 L cl hp n at
    mkdir -p "$o" "$d/bin" "$d/main/lock" "$d/45/lock" "$d/bad/lock"
    cat >"$d/bin/curl" <<'EOF'
#!/bin/sh
# S15 的假 curl：记下 --data-binary @文件 的请求体；配置从 stdin 读，只看 url 是不是演练的假地址，不记 KEY
body=''
while [ $# -gt 0 ]; do
    [ "$1" = --data-binary ] && body=${2#@}
    shift
done
case $(cat) in *'url = "http://127.0.0.1:9/'*) to=假地址 ;; *) to=别的地址 ;; esac
{ printf '%s ' "$to"; tr -d '\n' <"$body"; echo; } >>"$S15_CURL_LOG"
printf 200
EOF
    chmod +x "$d/bin/curl"
    hostname -s >"$o/host"
    echo "$lk" >"$o/lockname"
    # s15_round <名字> <HB_STATE_DIR> <额外环境变量...>：锁目录是 $L，假 curl 记到 $cl
    s15_round() {
        local n=$1 st=$2
        shift 2
        printf '%s\n' "${pc//@LOCKDIR@/$L} --dry-run" >"$o/$n.cmd"
        s14_run "$mode" "$d/bin" "$st" "$hooks" env S15_CURL_LOG="$cl" STUCK_FORCE_BOT=ops-system "$@" \
            /usr/bin/python3 -I "$op" "$lim" "$o/$n" "$(cat "$o/$n.cmd")"
        if [ -e "$st" ]; then echo 有; else echo 没有; fi >"$o/$n.probe"
        wc -l <"$cl" | tr -d ' ' >"$o/$n.curls"
        if [ -f "$L/$lk.skips.json" ]; then cp "$L/$lk.skips.json" "$o/$n.skips.json"; fi
    }
    L=$d/main/lock
    cl=$o/main.curl-bodies
    : >"$cl"
    /usr/bin/lockf -k -t 0 "$L/$lk" /bin/sleep 32 &
    hp=$!
    lockf_child "$hp" >"$o/main.holder-child"
    /usr/bin/python3 -I -c 'import time; print("%.3f" % time.time())' >"$o/t0"
    for n in 1:0 2:6 3:18 4:24; do
        at=${n#*:}
        n=${n%%:*}
        /usr/bin/python3 -I -c 'import sys, time; time.sleep(max(0.0, float(sys.argv[1]) + float(sys.argv[2]) - time.time()))' \
            "$(cat "$o/t0")" "$at"
        s15_round "r$n" "$d/main/probe" HB_LOCK_ALERT_MIN=0.25
    done
    wait "$hp"
    echo $? >"$o/main.holder-rc"
    /usr/bin/python3 -I -c 'import time; print("%.3f" % time.time())' >"$o/main.holder-end"
    s15_round r5 "$d/main/state" HB_LOCK_ALERT_MIN=0.25
    s15_round r6 "$d/main/state" HB_LOCK_ALERT_MIN=0.25
    L=$d/45/lock
    cl=$o/45.curl-bodies
    : >"$cl"
    /usr/bin/lockf -k -t 0 "$L/$lk" /bin/sleep 8 &
    hp=$!
    lockf_child "$hp" >"$o/45.holder-child"
    for n in 45a:44 45b:46; do
        at=${n#*:}
        n=${n%%:*}
        /usr/bin/python3 -I -c 'import json, sys, time
t = time.time()
json.dump({"first": t - float(sys.argv[2]) * 60, "last": t - 300, "skips": 9}, open(sys.argv[1], "w"))' "$L/$lk.skips.json" "$at"
        cp "$L/$lk.skips.json" "$o/$n.seed.json"
        s15_round "$n" "$d/45/probe"
    done
    wait "$hp"
    echo $? >"$o/45.holder-rc"
    L=$d/bad/lock
    cl=$o/bad.curl-bodies
    : >"$cl"
    /usr/bin/lockf -k -t 0 "$L/$lk" /bin/sleep 8 &
    hp=$!
    lockf_child "$hp" >"$o/bad.holder-child"
    printf '{"first": 不是 JSON {{\n' >"$L/$lk.skips.json"
    cp "$L/$lk.skips.json" "$o/bad-a.seed"
    s15_round bad-a "$d/bad/probe"
    rm -f "$L/$lk.skips.json"
    mkdir "$L/$lk.skips.json"
    s15_round bad-b "$d/bad/probe"
    wait "$hp"
    echo $? >"$o/bad.holder-rc"
}

# ---------- MBA 这边（iMac 拷过来的临时目录 $1 里跑，输出写 $1/out，iMac 再拷回去判断）----------
mba_side() {
    local R=$1 O=$1/out sh pc weird t0
    CANARY=$2
    mkdir -p "$O"
    real_paths >"$O/S10-before.txt"
    run() {  # run <名字> <额外环境变量...> -- <命令...>：最少环境 + 临时状态目录 + 假 webhook 目录
        local n=$1
        local -a e
        e=()
        shift
        while [ "$1" != -- ]; do e+=("$1"); shift; done
        shift
        env -i HOME="$HOME" PATH="$MINPATH" LANG=en_US.UTF-8 PYTHONDONTWRITEBYTECODE=1 HB_DRILL_CANARY="$CANARY" \
            STUCK_WEBHOOK_DIR="$R/hooks" ${e[@]+"${e[@]}"} "$@" >"$O/$n.out" 2>"$O/$n.err"
        echo $? >"$O/$n.rc"
    }
    # S12（FAILURE-MODES.md A18–A20、A39）：ssh 连上了、iMac 那边不回。s12 <名字> <目录名> <超时文件> <precheck>
    # PATH 最前面是 ssh 替身（远端命令换成 sleep 110，别的参数原样 exec 真 ssh，pid 不变）和只记录调用的假 curl。
    # 不带 --dry-run，状态写临时目录，webhook 目录是空的。照 Orca 起预检的做法（F14）跑。
    # 第二次 ssh 起来时、整条跑完时，用 ps 看前面起的 ssh 还在不在（输出空 = 没了）。
    s12() {
        local n=$1 d=$R/$2 tf=$3 cmd=$4 i=0 p1 f
        mkdir -p "$d/bin" "$d/state" "$d/hooks" "$d/lock"
        cat >"$d/bin/ssh" <<'EOF'
#!/bin/bash
echo "$$ $(date +%s)" >>"$S12_SSH_LOG"
printf '[%s]' "$@" >>"$S12_SSH_ARGS"
echo >>"$S12_SSH_ARGS"
set -- "${@:1:$(($# - 1))}" 'sleep 110'
exec /usr/bin/ssh "$@"
EOF
        printf '#!/bin/sh\necho "$*" >>"$S12_CURL_LOG"\nexit 7\n' >"$d/bin/curl"
        chmod +x "$d/bin/ssh" "$d/bin/curl"
        : >"$d/ssh.log"
        : >"$d/ssh.args"
        : >"$d/curl.log"
        printf '%s\n' "$cmd" >"$O/$n.cmd"
        env -i HOME="$HOME" PATH="$d/bin:$MINPATH" LANG=en_US.UTF-8 PYTHONDONTWRITEBYTECODE=1 HB_DRILL_CANARY="$CANARY" \
            S12_SSH_LOG="$d/ssh.log" S12_SSH_ARGS="$d/ssh.args" S12_CURL_LOG="$d/curl.log" \
            HB_STATE_DIR="$d/state" STUCK_WEBHOOK_DIR="$d/hooks" \
            /usr/bin/python3 -I "$R/orca-precheck.py" "$(cat "$tf")" "$O/$n" "$cmd" &
        while [ ! -e "$O/$n.orca.json" ] && [ "$(wc -l <"$d/ssh.log")" -lt 2 ] && [ $i -lt 300 ]; do
            sleep 1
            i=$((i + 1))
        done
        date +%s >"$O/$n.first-check-at"
        p1=$(head -1 "$d/ssh.log" | cut -d' ' -f1)
        if [ -n "$p1" ]; then
            ps -o pid,ppid,rss,etime,comm -p "$p1" | sed 1d >"$O/$n.first-alive-at-second"
        else
            echo "没有起过 ssh" >"$O/$n.first-alive-at-second"
        fi
        wait
        sleep 1  # 父进程先被杀的 ssh 由 launchd 收尸，留 1 秒
        cut -d' ' -f1 "$d/ssh.log" | while read -r p1; do
            ps -o pid,ppid,rss,etime,comm -p "$p1" | sed 1d
        done >"$O/$n.alive-after"
        cp "$d/ssh.log" "$O/$n.ssh-starts"
        cp "$d/ssh.args" "$O/$n.ssh-args"
        cp "$d/curl.log" "$O/$n.curl-calls"
        (cd "$d/state" && find . -type f | sort) >"$O/$n.statefiles"
        for f in state.json heartbeat.json watch.log; do
            if [ -f "$d/state/$f" ]; then cp "$d/state/$f" "$O/$n.$f"; fi
        done
        echo "MBA $n 跑完"
    }
    # S13（FAILURE-MODES.md A30、C15）：两轮同时跑。照 defs 原文（只换两个脚本路径和锁目录，不带 --dry-run）照 Orca 的做法起三轮 A、B、C，
    # 共用状态目录和锁文件。PATH 最前面的 ssh、orca 替身记下每次调用（pid、时间、替身名）再 exec 真的，A 那轮每次先等 30 秒：
    # A 的替身起来 3 秒后起 B，A 结束后起 C。新代码只经 ssh；回退测试里 base 的 MBA precheck 直接调 orca（F30），PATH 里找不到 orca 时
    # heartbeat-watch 用 /Applications/Orca.app/Contents/Resources/bin/orca，orca 替身 exec 的也是它。
    # B 前后各记一次状态目录里每个文件的 sha256。webhook 目录是空的，PATH 里有只记录调用的假 curl。
    # B 之后拷一份锁文件旁边 lock-held-alert 的状态文件（A44），C 之后看它还在不在。
    s13() {
        local d=$R/s13 n hp i=0 sk=$R/s13/lock/mba-hb-watch.lock.skips.json
        mkdir -p "$d/bin" "$d/state" "$d/hooks" "$d/lock"
        cat >"$d/bin/ssh" <<'EOF'
#!/bin/sh
n=${0##*/}
echo "$$ $(date +%s) $n" >>"$S13_LOG"
[ "$S13_DELAY" = 0 ] || sleep "$S13_DELAY"
[ "$n" = ssh ] && exec /usr/bin/ssh "$@"
exec /Applications/Orca.app/Contents/Resources/bin/orca "$@"
EOF
        cp "$d/bin/ssh" "$d/bin/orca"
        printf '#!/bin/sh\necho "$*" >>"$S13_CURL_LOG"\nexit 7\n' >"$d/bin/curl"
        chmod +x "$d/bin/ssh" "$d/bin/orca" "$d/bin/curl"
        for n in A B C; do : >"$d/calls-$n.log"; done
        : >"$d/curl.log"
        cp "$R/s13-precheck.txt" "$O/S13.cmd"
        s13_one A 30 &
        hp=$!
        while [ ! -s "$d/calls-A.log" ] && [ ! -e "$O/S13-A.orca.json" ] && [ $i -lt 200 ]; do
            sleep 0.1
            i=$((i + 1))
        done
        sleep 3
        s13_state >"$O/S13-B.state-before"
        s13_one B 0
        s13_state >"$O/S13-B.state-after"
        if [ -f "$sk" ]; then cp "$sk" "$O/S13-B.skips.json"; fi
        wait "$hp"
        s13_one C 0
        if [ -e "$sk" ]; then echo 有; else echo 没有; fi >"$O/S13-C.skips-after"
        cp "$d/curl.log" "$O/S13.curl-calls"
        (cd "$d/state" && find . -type f | sort) >"$O/S13.statefiles"
        if [ -f "$d/state/state.json" ]; then cp "$d/state/state.json" "$O/S13.state.json"; fi
    }
    s13_one() {  # s13_one <A|B|C> <替身每次调用先等几秒>
        env -i HOME="$HOME" PATH="$R/s13/bin:$MINPATH" LANG=en_US.UTF-8 PYTHONDONTWRITEBYTECODE=1 HB_DRILL_CANARY="$CANARY" \
            S13_LOG="$R/s13/calls-$1.log" S13_DELAY="$2" S13_CURL_LOG="$R/s13/curl.log" \
            HB_STATE_DIR="$R/s13/state" STUCK_WEBHOOK_DIR="$R/s13/hooks" \
            /usr/bin/python3 -I "$R/orca-precheck.py" "$(cat "$R/mba-timeout.txt")" "$O/S13-$1" "$(cat "$R/s13-precheck.txt")"
        cp "$R/s13/calls-$1.log" "$O/S13-$1.calls"
    }
    s13_state() {
        (cd "$R/s13/state" && find . -type f | sort | while IFS= read -r f; do shasum -a 256 "$f"; done)
    }
    write_orca_precheck "$R/orca-precheck.py"
    # S12、S12.old 各要 4 分钟左右：先在后台起，和下面的场景同时跑，S10 之前等它们跑完。
    # S12 照 defs 原文（只换两个脚本路径和锁目录），超时取 defs；S12.old 的包装是 7ac1220 那版，precheck 直接写，
    # 超时取 7ac1220 那版 defs（240，第四轮的方案 1）。
    s12 S12 s12 "$R/mba-timeout.txt" "$(cat "$R/s12-precheck.txt")" &
    s12 S12-old s12-old "$R/s12-old-timeout.txt" \
        "HB_ORCA='$R/orca-via-ssh.7ac1220' ORCA_SSH_HOST=imac '$R/heartbeat-watch.sh' --precheck --target '$TARGET'" &
    # S2：defs.json 里 MBA 新任务的 precheck 原文（只换两个脚本路径和锁目录、加 --dry-run），分别经 /bin/sh 和 /bin/zsh 跑。
    mkdir -p "$R/s2/lock"
    pc=$(cat "$R/s2-precheck.txt")
    for sh in sh zsh; do
        mkdir -p "$R/s2-$sh/state"
        printf '%s\n' "$pc" >"$O/S2-$sh.cmd"
        run "S2-$sh" HB_STATE_DIR="$R/s2-$sh/state" -- "/bin/$sh" -c "$pc"
    done
    echo "MBA S2 跑完"
    # S3：同样跑 --dry-run，HB_ORCA 换成回放，最新心跳 30 分钟前。
    mkdir -p "$R/s3/state"
    run S3 HB_STATE_DIR="$R/s3/state" HB_ORCA="$R/hb-replay/orca" HB_REPLAY_AGE_S=1800 HB_REPLAY_LOG="$O/S3.orca-calls" -- \
        "$R/heartbeat-watch.sh" --precheck --dry-run --target "$TARGET"
    echo "MBA S3 跑完"
    # S4：ORCA_SSH_HOST 指向不存在的主机。S4b：state 里种「50 分钟前起就查不到」。
    mkdir -p "$R/s4/state" "$R/s4b/state"
    t0=$(date +%s)
    run S4 HB_STATE_DIR="$R/s4/state" HB_ORCA="$R/orca-via-ssh" ORCA_SSH_HOST=no-such-host.invalid -- \
        "$R/heartbeat-watch.sh" --precheck --dry-run --target "$TARGET"
    echo $(($(date +%s) - t0)) >"$O/S4.secs"
    run S4-wrapper ORCA_SSH_HOST=no-such-host.invalid -- "$R/orca-via-ssh" automations runs --id "$WATCHED" --json
    python3 -I -c 'import json, sys, time; json.dump({sys.argv[1]: {"fail_since": time.time() - 3000}}, open(sys.argv[2], "w"))' \
        "$WATCHED" "$R/s4b/state/state.json"
    shasum -a 256 "$R/s4b/state/state.json" | cut -d' ' -f1 >"$O/S4b.state-before"
    run S4b HB_STATE_DIR="$R/s4b/state" HB_ORCA="$R/orca-via-ssh" ORCA_SSH_HOST=no-such-host.invalid -- \
        "$R/heartbeat-watch.sh" --precheck --dry-run --target "$TARGET"
    shasum -a 256 "$R/s4b/state/state.json" | cut -d' ' -f1 >"$O/S4b.state-after"
    echo "MBA S4 跑完"
    # S5：包装的拒绝（假 ssh）。S5b：真 ssh 到 iMac，参数里带各种 shell 特殊字符，看 orca 收到的是不是原样。
    s5 "$R/orca-via-ssh" "$O/S5"
    weird=$(cat "$R/weird.txt"; printf x)
    weird=${weird%x}
    run S5b ORCA_SSH_HOST=imac -- "$R/orca-via-ssh" automations list --environment "$weird" --json
    echo "MBA S5 跑完"
    # S7：MBA 上直接用包装读 iMac ops · 01 的运行记录和自动任务列表（原文不留，只留摘要）。
    run S7-runs ORCA_SSH_HOST=imac -- "$R/orca-via-ssh" automations runs --id "$WATCHED" --json
    run S7-list ORCA_SSH_HOST=imac -- "$R/orca-via-ssh" automations list --json
    python3 -I - "$O/S7-runs.out" "$O/S7-list.out" "$WATCHED" >"$O/S7.json" <<'PY'
import json, re, sys, time
runs_p, list_p, wid = sys.argv[1:4]
res = {}
try:
    d = json.load(open(runs_p, encoding="utf-8"))
    runs = (d.get("result") or {}).get("runs") or []
    hbs = [json.loads(m.group(1)) for r in runs
           for m in re.finditer(r"^@@HB (\{.*\})\s*$", (r.get("precheckResult") or {}).get("stdout") or "", re.M)]
    newest = max(hbs, key=lambda h: h["ts"]) if hbs else None
    res.update(runs_ok=d.get("ok"), runs=len(runs), hb_lines=len(hbs), newest_hb=newest,
               newest_hb_age_min=round((time.time() - newest["ts"]) / 60, 1) if newest else None,
               newest_run_status=runs[0].get("status") if runs else None)
except (OSError, ValueError) as e:
    res["runs_error"] = type(e).__name__
try:
    d = json.load(open(list_p, encoding="utf-8"))
    autos = (d.get("result") or {}).get("automations") or []
    a = [x for x in autos if x.get("id") == wid]
    res.update(list_ok=d.get("ok"), list_count=len(autos),
               watched={k: a[0].get(k) for k in ("name", "createdAt", "enabled")} if a else None)
except (OSError, ValueError) as e:
    res["list_error"] = type(e).__name__
print(json.dumps(res, ensure_ascii=False))
PY
    rm -f "$O/S7-runs.out" "$O/S7-list.out"
    echo "MBA S7 跑完"
    s13
    echo "MBA S13 跑完"
    s14 mini "$R/s14" "$O/S14" "$(cat "$R/s14-precheck.txt")" mba-hb-watch.lock "ssh orca" "$(cat "$R/mba-timeout.txt")" \
        "$R/orca-precheck.py" "$R/hooks"
    echo "MBA S14 跑完"
    s15 mini "$R/s15" "$O/S15" "$(cat "$R/s14-precheck.txt")" mba-hb-watch.lock "$(cat "$R/mba-timeout.txt")" \
        "$R/orca-precheck.py" "$R/hooks-s15"
    echo "MBA S15 跑完"
    wait
    # S12、S13 不是 dry-run，状态写在它们自己的临时目录里，不算。
    find "$R" -path '*/state/*' -type f ! -path "$R/s12*" ! -path "$R/s13*" | sed "s|^$R/||" | sort >"$O/S10-statefiles.txt"
    real_paths >"$O/S10-after.txt"
}

if [ "${1:-}" = --mba-side ]; then
    mba_side "$2" "$3"
    exit 0
fi

# ---------- iMac 这边 ----------
case ${1:-} in
    "" | --record) ;;
    *) echo "用法：wake/tests/heartbeat-watch-ssh.sh [--record]" >&2; exit 2 ;;
esac
T=$(mktemp -d -t hb-drill)
trap 'rm -rf "$T"' EXIT

if [ "${1:-}" = --record ]; then
    orca automations runs --id "$WATCHED" --json >"$T/runs.json" && orca automations list --json >"$T/list.json" || {
        echo "录不到：本机 orca automations runs / list 失败" >&2
        exit 2
    }
    python3 -I - "$T/runs.json" "$T/list.json" "$WATCHED" "$here/hb-replay/fixtures" <<'PY'
import datetime, json, os, re, sys
runs_p, list_p, wid, out = sys.argv[1:5]
when = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).strftime("%F %T SGT")
keep = []
for r in json.load(open(runs_p, encoding="utf-8"))["result"]["runs"]:
    pr = r.get("precheckResult")
    if pr:
        hb = [l for l in (pr.get("stdout") or "").splitlines() if re.fullmatch(r"@@HB \{.*\}\s*", l)]
        pr = {"exitCode": pr.get("exitCode"), "timedOut": pr.get("timedOut"), "durationMs": pr.get("durationMs"),
              "stdout": "".join(l + "\n" for l in hb)}
    keep.append({"createdAt": r["createdAt"], "status": r["status"], "precheckResult": pr})
autos = [{k: a[k] for k in ("id", "name", "createdAt")}
         for a in json.load(open(list_p, encoding="utf-8"))["result"]["automations"] if a["id"] == wid]
os.makedirs(out, exist_ok=True)
note = "%s 在 iMac 上录：orca automations %s --json。只留 heartbeat-watch 用到的字段，stdout 只留 @@HB 行。"
json.dump({"_recorded": note % (when, "runs --id " + wid), "ok": True, "result": {"runs": keep}},
          open(os.path.join(out, "runs-439cd438.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
json.dump({"_recorded": note % (when, "list"), "ok": True, "result": {"automations": autos}},
          open(os.path.join(out, "list-imac.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("录好：%d 条运行记录、%d 个自动任务 → %s" % (len(keep), len(autos), out))
PY
    exit $?
fi

OUT=${HB_DRILL_OUT:-$root/reports/heartbeat-mba-imac-1021}
if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT")" ] && [ ! -e "$OUT/.hb-drill" ]; then
    echo "heartbeat-watch-ssh.sh：$OUT 不空、也没有 .hb-drill 标记，不动它；换 HB_DRILL_OUT" >&2
    exit 2
fi
rm -rf "$OUT"
mkdir -p "$OUT/raw"
: >"$OUT/.hb-drill"
: >"$OUT/results.tsv"
CANARY=hbcanary-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
mkdir -p "$T/hooks" "$T/hooks-s15"
printf 'URL=http://127.0.0.1:9/hb-drill\nKEY=hb-drill-dummy-key\n' >"$T/hooks/coding-assistant.env"
# S15 的 lock-held-alert 真发告警：STUCK_FORCE_BOT=ops-system，发给这个假配置，PATH 里的假 curl 接住
printf 'URL=http://127.0.0.1:9/hb-drill-s15\nKEY=hb-drill-dummy-key\n' >"$T/hooks-s15/ops-system.env"
# lock-held-alert 的临时副本，precheck 里的 ~/.orca-state/bin/lock-held-alert 换成它（回退测试的 base 里没有它，现网版 defs 也不引用它）
if [ -f "$root/scripts/lock-held-alert" ]; then cp "$root/scripts/lock-held-alert" "$T/lock-held-alert"; fi

oneline() { printf '%s' "$1" | tr '\t\n' '  '; }
res() {  # res <编号> <PASS|FAIL> <期望> <实际>
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$(oneline "$3")" "$(oneline "$4")" >>"$OUT/results.tsv"
    printf '%-4s %-16s %s\n' "$2" "$1" "$(oneline "$4")"
}
has() { grep -Fq -- "$2" "$1" 2>/dev/null; }
snip() {  # snip <文件> <子串>：第一行含这个子串的，去掉开头的时间戳，最多 240 个字
    python3 -I - "$1" "$2" <<'PY'
import re, sys
try:
    lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    lines = []
for l in lines:
    if sys.argv[2] in l:
        l = re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l)
        print(l[:240] + ("…" if len(l) > 240 else ""))
        break
PY
}
# expect <编号> <期望> <输出文件> <期望退出码> <退出码文件> <子串...>：子串都要有；「!」开头的不能有。实际 = 第一个子串所在行 + 退出码。
# 调用前设 XTRA（接在实际后面的说明）、XFAIL（非空就记 FAIL），用完清空。
XTRA='' XFAIL=''
expect() {
    local id=$1 want=$2 f=$3 wrc=$4 rcf=$5 v=PASS p first='' rc
    shift 5
    rc=$(cat "$rcf" 2>/dev/null || echo 没有)
    [ "$rc" = "$wrc" ] || v=FAIL
    for p in "$@"; do
        case $p in
            '!'*) ! has "$f" "${p#!}" || v=FAIL ;;
            *) has "$f" "$p" || v=FAIL; [ -n "$first" ] || first=$p ;;
        esac
    done
    has "$f" "$CANARY" && v=FAIL
    [ -n "$XFAIL" ] && v=FAIL
    res "$id" "$v" "${want}；退出 ${wrc}" "$(snip "$f" "$first")；退出 ${rc}${XTRA}"
    XTRA='' XFAIL=''
}

{
    echo "时间 $(TZ=Asia/Singapore date '+%F %T SGT')"
    echo "命令 wake/tests/heartbeat-watch-ssh.sh"
    echo "commit $(git -C "$root" rev-parse HEAD)（分支 $(git -C "$root" rev-parse --abbrev-ref HEAD)）"
    echo "代码有没有未提交的改动（scripts automations wake）：$(git -C "$root" status --porcelain -- scripts automations wake | wc -l | tr -d ' ') 个文件"
    echo "base（和 origin/main 的分叉点）$(git -C "$root" merge-base HEAD origin/main)"
    echo "iMac：$(hostname -s)，macOS $(sw_vers -productVersion) $(uname -m)，$(/bin/bash --version | head -1)，$(/usr/bin/python3 --version 2>&1)，perl $(/usr/bin/perl -e 'print $^V')，$(ssh -V 2>&1)，orca $(orca --version 2>&1 | head -1)，shellcheck $(shellcheck --version 2>/dev/null | sed -n 2p | cut -d' ' -f2)"
    echo "MBA：$(rssh 'echo "$(hostname -s)，macOS $(sw_vers -productVersion) $(uname -m)，$(/bin/bash --version | head -1)，$(/usr/bin/python3 --version 2>&1)，perl $(/usr/bin/perl -e "print \$^V")，$(ssh -V 2>&1)，orca $(zsh -lc "orca --version" 2>&1 | head -1)"' 2>&1)"
} >"$OUT/env.txt"
cat "$OUT/env.txt"
BASE=$(git -C "$root" merge-base HEAD origin/main)
IMAC_BEFORE=$(shasum -a 256 "$HOME/.orca-state/bin/heartbeat-watch.sh" 2>&1 | cut -d' ' -f1)
real_paths >"$T/imac-paths-before.txt"

# ---------- S0 静态：三版 heartbeat-watch 只差注释 ----------
V=$T/versions
mkdir -p "$V" "$OUT/raw/S0"
git -C "$root" show "$BASE:scripts/heartbeat-watch.sh" >"$V/base.sh"
cp "$root/scripts/heartbeat-watch.sh" "$V/new.sh"
VERS="base new"
if [ -f "$HOME/.orca-state/bin/heartbeat-watch.sh" ]; then
    cp "$HOME/.orca-state/bin/heartbeat-watch.sh" "$V/installed.sh"
    VERS="base installed new"
fi
chmod +x "$V"/*.sh
for v in $VERS; do
    printf '%s 整个文件      %s\n' "$v" "$(shasum -a 256 <"$V/$v.sh" | cut -d' ' -f1)"
    printf '%s Python 部分   %s\n' "$v" "$(sed -n '/^exec "\$PY" - "\$@" <<.PYEOF.$/,/^PYEOF$/p' "$V/$v.sh" | shasum -a 256 | cut -d' ' -f1)"
    printf '%s 去掉注释行    %s\n' "$v" "$(grep -v '^[[:space:]]*#' "$V/$v.sh" | shasum -a 256 | cut -d' ' -f1)"
done >"$OUT/raw/S0/sha256.txt"
diff "$V/base.sh" "$V/new.sh" >"$OUT/raw/S0/diff-base-new.txt"
[ -f "$V/installed.sh" ] && diff "$V/installed.sh" "$V/new.sh" >"$OUT/raw/S0/diff-installed-new.txt"
v=PASS
[ "$(grep -c '^[0-9]' "$OUT/raw/S0/diff-base-new.txt")" = 1 ] && [ "$(head -1 "$OUT/raw/S0/diff-base-new.txt")" = 13c13 ] || v=FAIL
res S0.diff "$v" "和 base 比只改了第 13 行（一处 13c13）" "$(grep '^[0-9]' "$OUT/raw/S0/diff-base-new.txt" | tr '\n' ' ')"
v=PASS
for k in "Python 部分" "去掉注释行"; do
    [ "$(grep -F "$k" "$OUT/raw/S0/sha256.txt" | awk '{print $NF}' | sort -u | wc -l | tr -d ' ')" = 1 ] || v=FAIL
done
res S0.same "$v" "${VERS} 三版的 Python 部分、去掉 # 注释行后的全文 sha256 都一样" "$(grep -F 'Python 部分' "$OUT/raw/S0/sha256.txt" | awk '{print $1 "=" substr($NF,1,12)}' | tr '\n' ' ')"
v=PASS
[ "$(sed -n 33p "$V/new.sh")" = 'BOT = "coding-assistant"' ] && [ "$(sed -n 33p "$V/base.sh")" = 'BOT = "coding-assistant"' ] || v=FAIL
res S0.bot "$v" '第 33 行仍是 BOT = "coding-assistant"' "$(sed -n 33p "$V/new.sh")"

# ---------- S1 回放：三版对同一份录好的数据输出逐字节一致（替身：假 HB_ORCA + 固定时钟）----------
mkdir -p "$OUT/raw/S1" "$T/s1bin" "$T/s1home"
printf '#!/bin/sh\necho "$*" >>"%s"\nexit 7\n' "$T/curl-calls" >"$T/s1bin/curl"
chmod +x "$T/s1bin/curl"
: >"$T/curl-calls"
# s1 <例子> <回放的环境变量，空格隔开> <种进 state.json 的内容，- 表示不种> <heartbeat-watch 参数...>
s1() {
    local c=$1 spec=$2 seed=$3 v s kv e
    shift 3
    echo "$spec" >"$OUT/raw/S1/$c.vars"
    { printf 'heartbeat-watch.sh'; printf ' "%s"' "$@"; echo; } >"$OUT/raw/S1/$c.cmd"
    [ "$seed" = - ] || echo "$seed" >"$OUT/raw/S1/$c.seed.json"
    for v in $VERS; do
        s=$T/s1/$c-$v/state
        mkdir -p "$s"
        [ "$seed" = - ] || echo "$seed" >"$s/state.json"
        e=()
        for kv in $spec; do e+=("$kv"); done
        env -i HOME="$T/s1home" PATH="$T/s1bin:$MINPATH" LANG=en_US.UTF-8 PYTHONPATH="$here/hb-replay/clock" \
            PYTHONDONTWRITEBYTECODE=1 HB_FAKE_NOW="$NOW" HB_ORCA="$here/hb-replay/orca" HB_REPLAY_LOG="$OUT/raw/S1/$c.$v.orca-calls" \
            HB_STATE_DIR="$s" STUCK_WEBHOOK_DIR="$T/hooks" ${e[@]+"${e[@]}"} \
            /bin/bash "$V/$v.sh" "$@" >"$OUT/raw/S1/$c.$v.out" 2>"$OUT/raw/S1/$c.$v.err"
        echo $? >"$OUT/raw/S1/$c.$v.rc"
    done
}
# s1_check <例子> <期望> <期望退出码> <子串...>：先比三版的 stdout、stderr、退出码，再看本分支这版的输出。
s1_check() {
    local c=$1 want=$2 wrc=$3 x k same=三版一致 f=$OUT/raw/S1/$1.new
    shift 3
    for x in $VERS; do
        [ "$x" = new ] && continue
        for k in out err rc; do
            cmp -s "$OUT/raw/S1/$c.$x.$k" "$f.$k" || same="和 ${x} 不一致（${k}）"
        done
    done
    cat "$f.out" "$f.err" >"$T/s1-$c.all"
    XTRA="；${same}"
    [ "$same" = 三版一致 ] || XFAIL=1
    expect "S1.$c" "${want}；三版一致" "$T/s1-$c.all" "$wrc" "$f.rc" "$@"
}
W=$WATCHED
s1 c01 "HB_REPLAY_AGE_S=120" - --precheck --dry-run --target "$TARGET"
s1 c02 "HB_REPLAY_AGE_S=1800" - --precheck --dry-run --target "$TARGET"
s1 c03 "HB_REPLAY_AGE_S=60 HB_REPLAY_MODE=scan-stale HB_REPLAY_SCAN_AGE_S=2400" - --precheck --dry-run --target "$TARGET"
s1 c04 "HB_REPLAY_MODE=nohb" - --precheck --dry-run --target "$TARGET"
s1 c05 "HB_REPLAY_AGE_S=120" "{\"$W\": {\"last_hb\": $((NOW - 3600)), \"alerted\": $((NOW - 3000)), \"why\": \"演练种的：60 分钟没有新心跳\"}}" \
    --precheck --dry-run --target "$TARGET"
s1 c06 "HB_REPLAY_MODE=unreachable" - --precheck --dry-run --target "$TARGET"
s1 c07 "HB_REPLAY_MODE=unreachable" "{\"$W\": {\"fail_since\": $((NOW - 3000))}}" --precheck --dry-run --target "$TARGET"
s1 c08 "HB_REPLAY_MODE=garbage" - --precheck --dry-run --target "$TARGET"
s1 c09 "HB_REPLAY_MODE=new HB_REPLAY_CREATED_AGE_S=300" - --precheck --dry-run --target "$TARGET"
s1 c10 "HB_REPLAY_AGE_S=1800" "{\"$W\": {\"last_hb\": $((NOW - 2400)), \"alerted\": $((NOW - 600)), \"why\": \"演练种的：已经报过\"}}" \
    --precheck --dry-run --target "$TARGET"
s1 c11 "" - --precheck --dry-run --target "坏的目标|没有 id"
s1 c12 "HB_REPLAY_MODE=error" - --precheck --dry-run --target "$TARGET"
s1 c13 "HB_REPLAY_AGE_S_94e4b0bc=60 HB_REPLAY_AGE_S_62d18b16=1800" - --precheck --dry-run \
    --target "box ops · 29 卡住检查心跳|grok-bot|${BOX}|20" --target "MBA ops · 29 心跳互查|mba|${STANDIN}|20"
s1 c14 "HB_REPLAY_AGE_S=120" - --dry-run --target "$TARGET"
ST='"kind": "heartbeat_stale"'
TO="dry-run，将 POST 给 coding-assistant："
s1_check c01 "正常：心跳 2 分钟前，不发" 1 "iMac ops · 01 卡住工作检查：正常（最新心跳" "!将 POST 给"
s1_check c02 "心跳过期 30 分钟：报 heartbeat_stale 给 coding-assistant" 1 "：中断：最新心跳在" "已 30 分钟没有新的（阈值 20 分钟）" "$TO" "$ST" '"bot": "coding-assistant"'
s1_check c03 "心跳还在、扫描 40 分钟没跑完：报 heartbeat_stale" 1 "：中断：心跳还在" "已 40 分钟没跑完" "$TO" "$ST"
s1_check c04 "运行记录里没有 @@HB：报 heartbeat_stale" 1 "次运行记录里没有心跳行（@@HB）" "$TO" "$ST"
s1_check c05 "之前报过中断、现在心跳正常：报一次 heartbeat_recovered" 1 "已恢复，报过一次" "：正常（最新心跳" "$TO" '"kind": "heartbeat_recovered"'
s1_check c06 "连不上（ssh 退出 255、stdout 空）：记「查不到」，45 分钟内不报" 1 "：运行记录查不到（JSONDecodeError），已连续 0 分钟" "!将 POST 给" "!脚本出错"
s1_check c07 "50 分钟前起就查不到：报 heartbeat_stale「连不上 本机 的 Orca」" 1 "：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（JSONDecodeError）" "$TO" "$ST"
s1_check c08 "输出不是 JSON：记「查不到」，不报" 1 "：运行记录查不到（JSONDecodeError），已连续 0 分钟" "!将 POST 给" "!脚本出错"
s1_check c09 "新建 5 分钟、还没有运行记录：不判断" 1 "：自动任务建好 5 分钟（不到 20 分钟），还没有心跳，这次不判断" "!将 POST 给"
s1_check c10 "还在中断、已经报过：不重复报" 1 "：还在中断（" "起已报过，不重复报）" "!将 POST 给"
s1_check c11 "目标写错：用法错误" 2 "用法：heartbeat-watch.sh" "!将 POST 给"
s1_check c12 "orca 回 ok:false：记「查不到」，不报" 1 '：运行记录查不到（{"code": "automation_not_found"' "!将 POST 给" "!脚本出错"
s1_check c13 "两个目标（5c2d0575 并行版的样子）：box 正常、MBA 那条过期只报 MBA" 1 "MBA ops · 29 心跳互查：中断：最新心跳在" "box ops · 29 卡住检查心跳：正常（最新心跳" "$TO" "检查任务没在跑：MBA ops · 29 心跳互查" "!检查任务没在跑：box"
s1_check c14 "不带 --precheck、正常：退出 0" 0 "：正常（最新心跳" "!将 POST 给"
v=PASS
[ -s "$T/curl-calls" ] && v=FAIL
res S1.curl "$v" "S1 全部 --dry-run：PATH 里的假 curl 一次都没被调用" "假 curl 被调用 $(wc -l <"$T/curl-calls" | tr -d ' ') 次"

# ---------- S5 包装拒绝（iMac 这边；MBA 那边在 MBA 上跑同一套）----------
s5 "$root/scripts/orca-via-ssh" "$T/s5-imac"
mkdir -p "$OUT/raw/S5-imac"
# s5_judge <目录> <机器>
s5_judge() {
    local o=$1 m=$2 n want rc calls v bad='' ok=0 total=0
    for f in "$o"/*.want; do
        n=$(basename "$f" .want)
        want=$(cat "$f")
        rc=$(cat "$o/$n.rc")
        calls=$(wc -l <"$o/$n.ssh-calls" | tr -d ' ')
        total=$((total + 1))
        v=ok
        [ "$rc" = "$want" ] || v=bad
        case $n in
            allow-*) [ "$calls" = 1 ] && grep -q '^\[-o\]\[BatchMode=yes\]\[-o\]\[ConnectTimeout=10\]\[-o\]\[ServerAliveInterval=15\]\[-o\]\[ServerAliveCountMax=2\]\[imac\]\[zsh -lc ' "$o/$n.ssh-calls" || v=bad ;;
            *) [ "$calls" = 0 ] || v=bad ;;
        esac
        if grep -rqF -- "$CANARY" "$o/$n.out" "$o/$n.err"; then v=bad; fi
        if [ $v = ok ]; then ok=$((ok + 1)); else bad="$bad $n(退出 ${rc}，ssh ${calls} 次)"; fi
    done
    v=PASS
    [ "$ok" = "$total" ] && [ "$total" = 14 ] || v=FAIL
    res "S5.${m}" "$v" "${m}：edit / run / create / remove / show、别的命令组、参数不全、ORCA_SSH_HOST 没设 / 空 / 以 - 开头，共 12 条都退出 2、假 ssh 0 次；放行的 runs、list 两条对照假 ssh 各记到 1 次，参数开头是 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 imac zsh -lc；输出里没有标记环境变量" \
        "${ok}/${total} 条符合${bad:+；不符：}${bad}；edit 那条：$(head -1 "$o/edit.err")"
}
s5_judge "$T/s5-imac" iMac
cp "$T/s5-imac"/*.cmd "$T/s5-imac"/*.rc "$T/s5-imac"/*.err "$T/s5-imac"/*.ssh-calls "$OUT/raw/S5-imac/"

# ---------- S9 现网配置和 defs.json 对得上（只读 show / list）----------
mkdir -p "$OUT/raw/S9"
python3 -I - "$root/automations/heartbeat-1021/defs.json" "$OUT/raw/S9" "$OUT/results.tsv" "$IMAC_WATCH" "$BOX" "$WATCHED" "$STANDIN" <<'PY'
import json, os, subprocess, sys, time
defs = json.load(open(sys.argv[1], encoding="utf-8"))
out, tsv, imac_watch, box, watched, standin = sys.argv[2:8]


def orca(*a):
    """只读的 orca 调用，连不上（box 的隧道常断几分钟）时最多 3 次、间隔 8 秒。"""
    err = None
    for n in range(3):
        if n:
            time.sleep(8)
        p = subprocess.run(["orca", *a, "--json"], capture_output=True, text=True, timeout=90)
        try:
            d = json.loads(p.stdout)
        except ValueError:
            err = "输出不是 JSON（退出 %s）" % p.returncode
            continue
        if d.get("ok"):
            return d["result"], n + 1, None
        err = json.dumps(d.get("error"), ensure_ascii=False)
    return None, 3, err


def pick(a):
    return {k: a.get(k) for k in ("id", "name", "enabled", "rrule", "timezone", "missedRunGraceMinutes", "precheck")}


def res(cid, ok, want, got):
    line = "%s\t%s\t%s\t%s" % (cid, "PASS" if ok else "FAIL", want, got)
    open(tsv, "a", encoding="utf-8").write(line.replace("\n", " ") + "\n")
    print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", cid, got))


shown = {}
for key, args in (("5c2d0575", ["--id", imac_watch]), ("94e4b0bc", ["--id", box, "--environment", "grok-bot"]),
                  ("439cd438", ["--id", watched])):
    r, tries, err = orca("automations", "show", *args)
    shown[key] = pick(r["automation"]) if r else None
    json.dump({"command": "orca automations show %s --json" % " ".join(args), "tries": tries, "error": err,
               "automation": shown[key]}, open(os.path.join(out, key + ".json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
before = next(e for e in defs["edit"] if e["stage"] == "parallel")["before"]
a = shown["5c2d0575"]
res("S9.5c2d0575", bool(a) and a["enabled"] and a["name"] == before["name"] and a["precheck"]["command"] == before["precheck"]
    and a["precheck"]["timeoutSeconds"] == before["precheckTimeout"],
    "iMac 5c2d0575 现网的名字、precheck、超时和 defs.json 的 before 一样（回滚就还原成这个），启用中",
    ("名字「%s」、超时 %s、启用 %s、precheck %s defs" % (a["name"], a["precheck"]["timeoutSeconds"], a["enabled"],
     "等于" if a["precheck"]["command"] == before["precheck"] else "不等于")) if a else "读不到")
b, bx = shown["94e4b0bc"], defs["box"]
res("S9.94e4b0bc", bool(b) and b["enabled"] == bx["enabled"] and b["name"] == bx["name"] and b["precheck"]["command"] == bx["precheck"]
    and b["precheck"]["timeoutSeconds"] == bx["precheckTimeout"] and b["rrule"] == "*/5 * * * *" and b["missedRunGraceMinutes"] == 720,
    "box 94e4b0bc（经 grok-bot）现网的名字、precheck、超时 240 和 defs.json 一样，启用中；每 5 分钟、grace 720（MBA 新任务照抄）",
    ("名字「%s」、rrule %s、超时 %s、grace %s、启用 %s、precheck %s defs" % (b["name"], b["rrule"], b["precheck"]["timeoutSeconds"],
     b["missedRunGraceMinutes"], b["enabled"], "等于" if b["precheck"]["command"] == bx["precheck"] else "不等于")) if b
    else "读不到：%s" % json.load(open(os.path.join(out, "94e4b0bc.json"), encoding="utf-8"))["error"])
c, wd = shown["439cd438"], defs["watched"]
res("S9.439cd438", bool(c) and c["enabled"] and c["name"] == wd["name"] and c["precheck"]["timeoutSeconds"] == wd["precheckTimeout"],
    "iMac ops · 01 439cd438 启用中，名字和 precheck 超时（600）和 defs.json 一样",
    ("名字「%s」、超时 %s、启用 %s、rrule %s" % (c["name"], c["precheck"]["timeoutSeconds"], c["enabled"], c["rrule"])) if c else "读不到")
r, tries, err = orca("automations", "list", "--environment", "mba")
autos = r["automations"] if r else []
new_name = defs["create"][0]["name"]
same = [x["id"] for x in autos if x["name"] == new_name]
st = [x["name"] for x in autos if x["id"] == standin]
json.dump({"command": "orca automations list --environment mba --json", "tries": tries, "error": err,
           "automations": [{k: x.get(k) for k in ("id", "name", "enabled")} for x in autos]},
          open(os.path.join(out, "mba-list.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
res("S9.mba", bool(r) and not same and bool(st),
    "MBA 上还没有「%s」（本 PR 没建任务）；S6 用的 ops · 09 %s 在" % (new_name, standin[:8]),
    ("%d 个自动任务，同名的 %d 个，ops · 09：%s" % (len(autos), len(same), st[0] if st else "没有")) if r else "读不到：%s" % err)
open(os.path.join(out, "live-5c2d0575-precheck.txt"), "w", encoding="utf-8").write(a["precheck"]["command"] if a else "")
PY

# ---------- S8 register.sh 只打印（替身：PATH 里只记录调用的假 orca）----------
mkdir -p "$OUT/raw/S8" "$T/s8bin"
printf '#!/bin/sh\necho "$*" >>"%s"\nexit 0\n' "$T/s8-orca-calls" >"$T/s8bin/orca"
chmod +x "$T/s8bin/orca"
: >"$T/s8-orca-calls"
s8() {  # s8 <名字> <期望退出码> <register.sh 参数...>
    local n=$1 want=$2
    shift 2
    echo "register.sh $*" >"$OUT/raw/S8/$n.cmd"
    PATH="$T/s8bin:$PATH" /bin/bash "$root/automations/heartbeat-1021/register.sh" "$@" >"$OUT/raw/S8/$n.out" 2>"$OUT/raw/S8/$n.err"
    echo $? >"$OUT/raw/S8/$n.rc"
    grep '^orca automations' "$OUT/raw/S8/$n.out" >"$T/s8-$n.cmdline"
}
s8 mba 0 mba
s8 imac 0 imac
s8 imac-parallel 0 imac --stage parallel --mba-id "$FAKEID"
s8 imac-final 0 imac --stage final --mba-id "$FAKEID"
s8 imac-rollback 0 imac --stage rollback
s8 bad-id 2 imac --mba-id 1234
s8 mba-stage 2 mba --stage final
s8 box 2 box
s8 stage-novalue 2 imac --stage
s8 unknown-flag 2 imac --force
PC_MBA="'HB_ORCA=\$HOME/.orca-state/bin/orca-via-ssh ORCA_SSH_HOST=imac \$HOME/.orca-state/bin/lock-held-alert /usr/bin/lockf -k -t 0 \$HOME/.orca-state/heartbeat-watch/mba-hb-watch.lock \$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target \"iMac ops · 01 卡住工作检查||${WATCHED}|20\"'"
TB="--target \"box ops · 29 卡住检查心跳|grok-bot|${BOX}|20\""
TM="--target \"MBA ops · 29 心跳互查|mba|${FAKEID}|20\""
expect S8.mba "mba：create 带 --disabled、--fresh-session、每 5 分钟、超时 330、grace 720，precheck 是 defs 原文（外面套 lockf，锁文件 mba-hb-watch.lock；lockf 前面是 ~/.orca-state/bin/lock-held-alert）" "$T/s8-mba.cmdline" 0 "$OUT/raw/S8/mba.rc" \
    "orca automations create --name 'ops · 29 心跳互查 MBA（盯 iMac ops · 01）'" "--trigger '*/5 * * * *'" "--precheck $PC_MBA" \
    "--precheck-timeout 330" "--missed-run-grace-minutes 720" "--fresh-session" "--disabled"
cat "$OUT/raw/S8/imac.out" >"$T/s8-imac.all"
expect S8.imac-noid "imac 没给 --mba-id：命令里是占位，并提示不能照抄" "$T/s8-imac.all" 0 "$OUT/raw/S8/imac.rc" "没给 --mba-id" "|mba|<MBA 新任务 id>|20"
expect S8.parallel "parallel：外面套 lockf（锁文件 5c2d0575.lock）、lockf 前面是 ~/.orca-state/bin/lock-held-alert，保留 box 目标在前、加 MBA 目标，不改名，超时 600（两个目标最坏 572 秒）" "$T/s8-imac-parallel.cmdline" 0 "$OUT/raw/S8/imac-parallel.rc" \
    "orca automations edit ${IMAC_WATCH} --precheck '\$HOME/.orca-state/bin/lock-held-alert /usr/bin/lockf -k -t 0 \$HOME/.orca-state/heartbeat-watch/5c2d0575.lock \$HOME/.orca-state/bin/heartbeat-watch.sh --precheck ${TB} ${TM}' --precheck-timeout 600" "!--name" "!<MBA 新任务 id>"
expect S8.final "final：只剩 MBA 目标，改名「盯 MBA ops · 29」，超时 300（一个目标最坏 286 秒），没套 lockf 和 lock-held-alert" "$T/s8-imac-final.cmdline" 0 "$OUT/raw/S8/imac-final.rc" \
    "orca automations edit ${IMAC_WATCH} --name 'ops · 29 心跳互查（盯 MBA ops · 29）' --precheck '\$HOME/.orca-state/bin/heartbeat-watch.sh --precheck ${TM}' --precheck-timeout 300" "!box ops · 29 卡住检查心跳" "!lockf" "!lock-held-alert"
LIVE=$(cat "$OUT/raw/S9/live-5c2d0575-precheck.txt" 2>/dev/null)
expect S8.rollback "rollback：还原成现网 5c2d0575 的名字和 precheck（S9 读到的原文），没套 lockf 和 lock-held-alert" "$T/s8-imac-rollback.cmdline" 0 "$OUT/raw/S8/imac-rollback.rc" \
    "orca automations edit ${IMAC_WATCH} --name 'ops · 29 心跳互查（盯 box ops · 29）' --precheck '${LIVE:-S9 没读到}' --precheck-timeout 240" "!lockf" "!lock-held-alert"
v=PASS
bad=''
for n in bad-id mba-stage box stage-novalue unknown-flag; do
    [ "$(cat "$OUT/raw/S8/$n.rc")" = 2 ] || { v=FAIL; bad="$bad $n"; }
done
[ -s "$T/s8-orca-calls" ] && v=FAIL
res S8.refuse "$v" "参数错（id 不完整、mba 带 --stage、机器名不对、--stage 没值、不认识的参数）都退出 2；整个 S8 假 orca 0 次调用（dry-run 不调 orca）" \
    "退出码不是 2 的：${bad:-没有}；假 orca 被调用 $(wc -l <"$T/s8-orca-calls" | tr -d ' ') 次；--apply 没跑（任务书禁止）"

# ---------- S6 iMac 经 environment mba 读 MBA 的一条现有任务；S6b 照 defs 原文跑 5c2d0575 的并行版、最终版 ----------
mkdir -p "$OUT/raw/S6" "$OUT/raw/S6b" "$T/s6/state"
TGT6="MBA ops · 09 内存与 CPU 负载清理|mba|${STANDIN}|20"
echo "heartbeat-watch.sh --dry-run --target \"$TGT6\"" >"$OUT/raw/S6/run.cmd"
env -u STUCK_FORCE_BOT -u HB_ORCA -u ORCA_SSH_HOST HB_STATE_DIR="$T/s6/state" STUCK_WEBHOOK_DIR="$T/hooks" PYTHONDONTWRITEBYTECODE=1 \
    /bin/bash "$V/new.sh" --dry-run --target "$TGT6" >"$OUT/raw/S6/run.out" 2>"$OUT/raw/S6/run.err"
echo $? >"$OUT/raw/S6/run.rc"
cat "$OUT/raw/S6/run.out" "$OUT/raw/S6/run.err" >"$T/s6.all"
expect S6 "iMac 经 environment mba 读到 MBA ops · 09 的运行记录：不是「查不到」，有运行记录和最新一次运行时间（它不打 @@HB，所以结论是没有心跳行）" \
    "$T/s6.all" 0 "$OUT/raw/S6/run.rc" "MBA ops · 09 内存与 CPU 负载清理：中断：最近 " "次运行记录里没有心跳行（@@HB），最新一次运行在 " "!运行记录查不到" "!最新一次运行在 从没有" "!最近 0 次"
# before-base：现网 5c2d0575 的 precheck（defs 里 before 的原文）用 base 版跑，紧接着并行版，给 S6b.box 当同一时刻的 base 对照。
# 锁目录换成临时目录（并行版套了 lockf），lock-held-alert 换成临时副本。
for stage in parallel before-base final; do
    mkdir -p "$T/s6b-$stage/state" "$T/s6b-$stage/lock"
    sv=$V/new.sh
    [ "$stage" = before-base ] && sv=$V/base.sh
    python3 -I - "$root/automations/heartbeat-1021/defs.json" "$stage" "$sv" "$STANDIN" "$T/s6b-$stage/lock/" "$T/lock-held-alert" \
        >"$OUT/raw/S6b/$stage.cmd" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if sys.argv[2] == "before-base":
    p = next(x for x in d["edit"] if x["stage"] == "parallel")["before"]["precheck"]
else:
    p = next(x for x in d["edit"] if x["stage"] == sys.argv[2])["set"]["precheck"]
    assert p.count("<MBA 新任务 id>") <= 1  # 回退测试的现网版 defs 没有 MBA 目标
old, lockdir, guard = "$HOME/.orca-state/bin/heartbeat-watch.sh", "$HOME/.orca-state/heartbeat-watch/", "$HOME/.orca-state/bin/lock-held-alert"
assert p.count(old) == 1 and p.count(lockdir) <= 1 and p.count(guard) <= 1  # 回退测试的现网版 defs 没有 lockf 和 lock-held-alert
p = p.replace(old, sys.argv[3]).replace(guard, sys.argv[6]).replace(lockdir, sys.argv[5]).replace("<MBA 新任务 id>", sys.argv[4])
assert ".orca-state" not in p  # 演练不碰真锁
print(p + " --dry-run")
PY
    env -u STUCK_FORCE_BOT -u HB_ORCA -u ORCA_SSH_HOST HB_STATE_DIR="$T/s6b-$stage/state" STUCK_WEBHOOK_DIR="$T/hooks" PYTHONDONTWRITEBYTECODE=1 \
        /bin/sh -c "$(cat "$OUT/raw/S6b/$stage.cmd")" >"$OUT/raw/S6b/$stage.out" 2>"$OUT/raw/S6b/$stage.err"
    echo $? >"$OUT/raw/S6b/$stage.rc"
    cat "$OUT/raw/S6b/$stage.out" "$OUT/raw/S6b/$stage.err" >"$T/s6b-$stage.all"
done
# 对照：现网 5c2d0575 最近几次对 box 的结论（grok-bot 隧道常断几分钟，S6b.box 没过时看这里）。
python3 -I - "$IMAC_WATCH" >"$OUT/raw/S6b/live-5c2d0575-box.txt" <<'PY'
import datetime, json, subprocess, sys
p = subprocess.run(["orca", "automations", "runs", "--id", sys.argv[1], "--json"], capture_output=True, text=True, timeout=90)
try:
    runs = json.loads(p.stdout)["result"]["runs"]
except (ValueError, KeyError, TypeError):
    print("读不到（退出 %s）" % p.returncode)
    sys.exit(0)
for r in runs[:4]:
    box = [l for l in ((r.get("precheckResult") or {}).get("stdout") or "").splitlines() if "box ops · 29" in l]
    when = datetime.datetime.fromtimestamp(r["createdAt"] / 1000, datetime.timezone(datetime.timedelta(hours=8)))
    print(when.strftime("%H:%M"), (box[0][24:] if box else "（没有 box 那行，%s）" % r.get("status"))[:120])
PY
order=$(grep -n -e 'box ops · 29 卡住检查心跳：' -e 'MBA ops · 29 心跳互查：' "$T/s6b-parallel.all" | head -2 | cut -d' ' -f4 | cut -c1-3 | tr -d '\n')
XTRA="；box 那行：$(snip "$T/s6b-parallel.all" "box ops · 29 卡住检查心跳：")"
[ "$order" = boxMBA ] || { XFAIL=1; XTRA="${XTRA}；顺序不对（${order}）"; }
expect S6b.parallel "5c2d0575 并行版 precheck（defs 原文，MBA 新任务 id 用 ops · 09 代替，锁目录换成临时目录，lock-held-alert 换成临时副本）：box 目标在前、出一行结论，MBA 目标读到运行记录，没有脚本出错；锁空着、没有状态文件，lock-held-alert 什么都不打" \
    "$T/s6b-parallel.all" 1 "$OUT/raw/S6b/parallel.rc" "MBA ops · 29 心跳互查：中断：最近 " "box ops · 29 卡住检查心跳：" \
    "!MBA ops · 29 心跳互查：运行记录查不到" "!最近 0 次" "!脚本出错" "!lock-held-alert："
XTRA=''
has "$T/s6b-parallel.all" "box ops · 29 卡住检查心跳：正常（最新心跳" || XTRA="；本次 box 那行：$(snip "$T/s6b-parallel.all" "box ops · 29 卡住检查心跳：")"
XTRA="${XTRA}；紧接着用 base 版跑现网 precheck（raw/S6b/before-base.*）：$(snip "$T/s6b-before-base.all" "box ops · 29 卡住检查心跳：")"
XTRA="${XTRA}；现网 5c2d0575 最近几次对 box 的结论：$(tr '\n' ' ' <"$OUT/raw/S6b/live-5c2d0575-box.txt")"
expect S6b.box "并行版里的 box 目标正常。要 iMac 到 box 的 grok-bot 隧道当时是通的；没过时对照同一时刻 base 版跑现网 precheck 的结论和现网 5c2d0575 的运行记录（都在实际一栏）" \
    "$T/s6b-parallel.all" 1 "$OUT/raw/S6b/parallel.rc" "box ops · 29 卡住检查心跳：正常（最新心跳"
expect S6b.final "5c2d0575 最终版 precheck：只查 MBA 目标，读到运行记录" \
    "$T/s6b-final.all" 1 "$OUT/raw/S6b/final.rc" "MBA ops · 29 心跳互查：中断：最近 " "!box ops · 29" "!运行记录查不到" "!最近 0 次"

# S14 的判断（FAILURE-MODES.md A31–A35、A52、A54、C15、C20），MBA、iMac 共用。s14_judge <输出目录> <机器> <第二轮第一个目标的结论行开头>
s14_judge() {
    python3 -I - "$1" "$2" "$3" "$OUT/results.tsv" "$CANARY" <<'PY'
import json, os, re, sys
d, m, first, tsv, canary = sys.argv[1:6]


def rd(name):
    try:
        return open(os.path.join(d, name), encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def orca(name):
    try:
        return json.loads(rd(name + ".orca.json"))
    except ValueError:
        return {}


def res(cid, ok, want, got):
    got = got.replace("\t", " ").replace("\n", " ")
    open(tsv, "a", encoding="utf-8").write("%s\t%s\t%s\t%s\n" % (cid, "PASS" if ok else "FAIL", want, got))
    print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", cid, got))


def head(s, n=160):
    s = " ⏎ ".join(l for l in s.strip().splitlines() if l.strip())
    return (s[:n] + "…" if len(s) > n else s) or "空"


def names(text):  # 替身记下的每行：pid 时间 替身名 …
    n = [l.split()[2] for l in text.splitlines() if len(l.split()) >= 3]
    return "（%s）" % "、".join("%s %d 次" % (s, n.count(s)) for s in sorted(set(n))) if n else ""


def skips(name):  # lock-held-alert 记在锁文件旁边的状态文件（演练拷出来的那份）
    try:
        v = json.loads(rd(name))
    except ValueError:
        return None
    return v if isinstance(v, dict) else None


stub = "ssh 和 orca" if m == "MBA" else "orca 和 orca-ide"
for k, code, word, how in (("held", "75", "already locked", "锁先被 lockf … sleep 6 拿住"),
                           ("nodir", "73", "cannot open", "锁文件放在不存在的目录里（漏了 README 第 1 步的 mkdir）")):
    out, err, rc, probe = rd(k + ".out"), rd(k + ".err"), rd(k + ".rc").strip(), rd(k + ".probe").strip()
    calls = len(rd(k + ".calls").splitlines())
    lines, st = [l for l in out.splitlines() if l.strip()], skips(k + ".skips.json")
    if k == "held":  # A30、A44：stdout 只有 lock-held-alert 的一行；状态文件记 1 次、没有报过
        out_ok = (len(lines) == 1 and "lock-held-alert：" in lines[0] and "已连续跳过 1 轮" in lines[0] and "@@HB" not in out
                  and bool(st) and st.get("skips") == 1 and "alerted" not in st)
        swant = "stdout 只有 lock-held-alert 的一行「…已连续跳过 1 轮…」、没有 @@HB，锁文件旁边的状态文件记 1 次、没有报过"
    else:  # A35、A54：73 不计数，stdout 空，没有状态文件
        out_ok = not out and st is None and not os.path.exists(os.path.join(d, k + ".skips.json"))
        swant = "stdout 空，没有状态文件（lock-held-alert 不计 73）"
    ok = rc == code and out_ok and word in err and probe == "没有" and calls == 0 and canary not in out + err
    extra = "；持锁的 lockf 起的 sleep：%s，lockf 退出 %s" % (rd("held.holder-child").strip(), rd("held.holder-rc").strip()) if k == "held" else ""
    res("S14.%s.%s" % (m, k), ok,
        "%s 上照 defs 原文跑 precheck（锁文件换到临时目录，lock-held-alert 换成临时副本，加 --dry-run，HB_STATE_DIR 指向不存在的目录，"
        "PATH 最前面是记录调用的 %s 替身），%s：退出 %s，stderr 有 %s，%s；那个目录没被建出来（heartbeat-watch 没起）；替身 0 次" % (
            m, stub, how, code, word, swant),
        "退出 %s，stdout %d 字节，stderr：%s；目录%s；替身 %d 次%s%s；stdout：%s；状态文件：%s" % (
            rc, len(out.encode()), head(err), probe or "?", calls, names(rd(k + ".calls")), extra, head(out),
            json.dumps(st, sort_keys=True) if st else "没有"))
# A52、C20：持锁的 lockf 被 SIGKILL、SIGTERM、SIGSEGV（模拟崩溃）以后锁马上放开，-k 留下的锁文件不挡下一次
for k, sig, code in (("kill", "KILL", "137"), ("term", "TERM", "143"), ("crash", "SEGV", "139")):
    p1, p2, hrc = rd(k + ".probe1.rc").strip(), rd(k + ".probe2.rc").strip(), rd(k + ".holder-rc").strip()
    sent, child, end = rd(k + ".sent").strip(), rd(k + ".child-after-signal").split(), rd(k + ".child-end").strip()
    lf = rd(k + ".lockfile").strip()
    ok = (p1 == "75" and sent.startswith("kill -%s " % sig) and hrc == code and p2 == "0" and lf == "有"
          and len(child) >= 2 and child[1] == "1" and end.startswith("没了"))
    crash = ("；lockf 开头的崩溃报告（~/Library/Logs/DiagnosticReports、/Library/Logs/DiagnosticReports）：发信号前 %s，之后 %s" % (
        "、".join((rd("crash.reports-before").split() + ["?", "?"])[:2]),
        "、".join((rd("crash.reports-after").split() + ["?", "?"])[:2]))) if k == "crash" else ""
    res("S14.%s.%s" % (m, k), ok,
        "%s 上只用 lockf：lockf -k -t 0 <锁> sleep 8 拿住锁，探一次退出 75；核对 pid、ppid、命令名以后只给这个 lockf 发 SIG%s%s，"
        "它退出 %s；马上再探一次退出 0；锁文件还在（-k）；它起的 sleep ppid 1，之后自己结束%s" % (
            m, sig, "（模拟崩溃）" if k == "crash" else "", code, "；前后各数一次两个 DiagnosticReports 目录里 lockf 开头的文件，只记不判" if k == "crash" else ""),
        "第一次探退出 %s（%s）；%s；它退出 %s；第二次探退出 %s；锁文件%s；发信号以后它起的 sleep：%s；%s%s" % (
            p1, head(rd(k + ".probe1.err"), 80), sent, hrc, p2, lf or "?", " ".join(child) or "没有", end, crash))
o1, o2 = orca("timeout-1"), orca("timeout-2")
prc, perr = rd("timeout.probe.rc").strip(), rd("timeout.probe.err")
stubs, after = len(rd("timeout.stub-calls").splitlines()), rd("timeout.stub-after").strip()
try:
    t0, t1 = (float(x) for x in rd("timeout.probe.t").split())
except ValueError:
    t0 = t1 = None
# 探锁要落在第一轮跑的期间（FAILURE-MODES.md C15）
during = t0 is not None and bool(o1) and o1["start"] < t0 and t1 < o1["end"]
when = ("没记下探锁的时间" if t0 is None else "没有第一轮的预检结果" if not o1 else
        "探锁在第一轮开始后 %.1f–%.1f 秒（第一轮%s）" % (t0 - o1["start"], t1 - o1["start"], "还在跑" if during else "不在跑"))
out2, err2 = rd("timeout-2.out"), rd("timeout-2.err")
line2 = next((re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l) for l in out2.splitlines() if first in l),
             "（没有「%s」那行）" % first)
ok = (prc == "75" and "already locked" in perr and during and stubs >= 1
      and o1.get("timedOut") is True and 12 <= (o1.get("durationS") or 0) <= 27 and not after
      and o2.get("timedOut") is False and o2.get("exitCode") == 1 and "already locked" not in err2 and first in out2
      and canary not in out2 + err2 + rd("timeout-1.out") + rd("timeout-1.err"))
res("S14.%s.timeout" % m, ok,
    "%s 上第一轮照 Orca 的做法起，超时 12 秒，加 --dry-run，%s 替身换成 sleep 60：替身起来 3 秒后、第一轮还在跑的时候探锁，退出 75；"
    "第一轮到 12 秒被杀（timedOut，用时 12–27 秒），替身的进程没了；紧接着第二轮用真的 ssh / orca、超时取 defs（%s 秒），"
    "加 --dry-run：没超时，退出 1，没有 already locked，有「%s」那行" % (m, stub, o2.get("timeoutSeconds"), first),
    "探锁退出 %s（%s），%s；第一轮%s，用时 %s 秒；替身起了 %d 次%s，被杀以后%s；第二轮%s，用时 %s 秒，退出 %s，stderr %s；%s" % (
        prc, head(perr, 80), when, "超时被杀" if o1.get("timedOut") else "没超时（退出 %s）" % o1.get("exitCode"),
        o1.get("durationS"), stubs, names(rd("timeout.stub-calls")), "都没了" if not after else "还在：" + head(after, 80),
        "超时被杀" if o2.get("timedOut") else "没超时", o2.get("durationS"), o2.get("exitCode"),
        "有 already locked" if "already locked" in err2 else "没有 already locked", line2[:160]))
PY
}

# S15 的判断（FAILURE-MODES.md A41–A47、C17–C19），MBA、iMac 共用。
# s15_judge <输出目录> <机器> <第 5 轮第一个目标「正常」那行的开头> <告警里要有的目标名...>
s15_judge() {
    python3 -I - "$OUT/results.tsv" "$CANARY" "$@" <<'PY'
import json, os, re, sys
tsv, canary, d, m, okline = sys.argv[1:6]
targets = sys.argv[6:]


def rd(name):
    try:
        return open(os.path.join(d, name), encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def js(name):
    try:
        v = json.loads(rd(name))
    except ValueError:
        return None
    return v if isinstance(v, dict) else None


def num(name):
    try:
        return float(rd(name).strip())
    except ValueError:
        return None


def res(cid, ok, want, got):
    got = got.replace("\t", " ").replace("\n", " ")
    open(tsv, "a", encoding="utf-8").write("%s\t%s\t%s\t%s\n" % (cid, "PASS" if ok else "FAIL", want, got))
    print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", cid, got))


def rnd(n):
    """一轮：预检结果、stdout 不空的行、lock-held-alert 的行、HB_STATE_DIR 有没有被建、到这轮为止假 curl 几次、这轮之后的状态文件"""
    o = js(n + ".orca.json") or {}
    out, err = rd(n + ".out"), rd(n + ".err")
    lines = [re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l) for l in out.splitlines() if l.strip()]
    c = rd(n + ".curls").strip()
    return {"o": o, "rc": "没有结果" if not o else "超时" if o.get("timedOut") else o.get("exitCode"), "out": out, "err": err,
            "lines": lines, "guard": [l for l in lines if l.startswith("lock-held-alert：")], "probe": rd(n + ".probe").strip(),
            "curls": int(c) if c.isdigit() else -1, "st": js(n + ".skips.json"),
            "has_st": os.path.exists(os.path.join(d, n + ".skips.json"))}


def bodies(name):  # 假 curl 记下的：每行「假地址 请求体」
    b = []
    for l in rd(name).splitlines():
        to, _, body = l.partition(" ")
        try:
            b.append((to, json.loads(body)))
        except ValueError:
            b.append((to, {}))
    return b


def skipped(x, n):  # 跳过的一轮：退出 75，stderr 有 already locked，stdout 只有 lock-held-alert 的一行「已连续跳过 n 轮」，HB_STATE_DIR 没建
    return (x["rc"] == 75 and "already locked" in x["err"] and len(x["lines"]) == 1 and len(x["guard"]) == 1
            and "已连续跳过 %d 轮" % n in x["guard"][0] and "@@HB" not in x["out"] and x["probe"] == "没有")


def brief(x):  # 一轮的 stdout：lock-held-alert 的行去掉括号里的时间和锁文件，没有就是第一行
    if x["guard"]:
        return re.sub(r"（从 [^）]*）|（锁文件 [^）]*）", "", x["guard"][0].replace("lock-held-alert：", ""))[:150]
    return (x["lines"][0][:80] + "…") if x["lines"] else "空"


def body(b):
    return "kind %s、status %s、source %s、bot %s、发到%s" % (
        b[1].get("kind"), b[1].get("status"), b[1].get("source"), b[1].get("bot"), b[0]) if b else "没有"


canary_ok = all(canary not in rd(f) for f in os.listdir(d) if os.path.isfile(os.path.join(d, f))) if os.path.isdir(d) else False
host, lk = rd("host").strip(), rd("lockname").strip()
R = {n: rnd(n) for n in ("r1", "r2", "r3", "r4", "r5", "r6", "45a", "45b", "bad-a", "bad-b")}

# 主线（A41–A44、A46）：外部拿住锁，阈值 0.25 分钟
r = [R["r%d" % i] for i in range(1, 7)]
main = bodies("main.curl-bodies")
t0, hend = num("t0"), num("main.holder-end")
offs = [x["o"]["start"] - t0 if t0 is not None and "start" in x["o"] else None for x in r]
timing = (all(f is not None and t <= f <= t + 2 for t, f in zip((0, 6, 18, 24), offs)) and hend is not None
          and r[3]["o"].get("end", hend) < hend <= r[4]["o"].get("start", 0))
note = (main[0][1].get("note") or "") if main else ""
alert_ok = (len(main) >= 1 and main[0][0] == "假地址" and main[0][1].get("kind") == "heartbeat_stale"
            and main[0][1].get("status") == "stuck" and main[0][1].get("source") == "lock-held-alert"
            and main[0][1].get("bot") == "ops-system" and bool(host) and host in note and bool(lk) and lk in note
            and all(t in note for t in targets))
recov_ok = (len(main) == 2 and main[1][0] == "假地址" and main[1][1].get("kind") == "heartbeat_recovered"
            and main[1][1].get("status") == "recovered" and main[1][1].get("source") == "lock-held-alert"
            and main[1][1].get("bot") == "ops-system")
r5g = r[4]["guard"][0] if r[4]["guard"] else ""
ok = (all(skipped(r[i], i + 1) for i in range(4)) and timing
      and "才报" in r[0]["guard"][0] and "才报" in r[1]["guard"][0]
      and "报警：POST heartbeat_stale → ops-system → 200" in r[2]["guard"][0] and bool(r[2]["st"]) and "alerted" in r[2]["st"]
      and "已报过，不重复报" in r[3]["guard"][0]
      and r[4]["rc"] == 1 and "already locked" not in r[4]["err"] and okline in r[4]["out"] and len(r[4]["guard"]) == 1
      and "锁拿到了，之前连续跳过 4 轮" in r5g and "已报恢复：POST heartbeat_recovered → ops-system → 200" in r5g
      and not r[4]["has_st"]
      and r[5]["rc"] == 1 and not r[5]["guard"]
      and [x["curls"] for x in r] == [0, 0, 1, 1, 2, 2] and alert_ok and recov_ok and canary_ok)
nskip = sum(x["rc"] == 75 for x in r[:4])
ok_line5 = next((l for l in r[4]["lines"] if okline in l), "（没有「%s」那行）" % okline)
res("S15.%s" % m, ok,
    "%s 上照 defs 原文跑 precheck（锁文件换到临时目录，lock-held-alert 换成临时副本，加 --dry-run，STUCK_FORCE_BOT=ops-system，"
    "HB_LOCK_ALERT_MIN=0.25），外部 lockf … sleep 32 拿住锁，照 Orca 的做法在第 1 轮开始后约 0、6、18、24 秒起 4 轮：都退出 75，"
    "stderr 有 already locked，stdout 只有 lock-held-alert 的一行「已连续跳过 N 轮」（N 是 1–4），HB_STATE_DIR 没被建出来；"
    "第 1、2 轮假 curl 0 次；第 3 轮假 curl 1 次，kind heartbeat_stale、status stuck、source lock-held-alert、bot ops-system，"
    "note 里有主机名、锁文件名和目标名（%s），状态文件记了报过的时间；第 4 轮写「已报过」，假 curl 还是 1 次；"
    "sleep 结束以后第 5 轮（真的 ssh / orca）退出 1，没有 already locked，有「%s」，stdout 有「锁拿到了，之前连续跳过 4 轮」"
    "和已报恢复，假 curl 2 次，第 2 次 kind heartbeat_recovered、status recovered，状态文件没了；第 6 轮退出 1，"
    "lock-held-alert 什么都不打，假 curl 还是 2 次" % (m, "、".join("「%s」" % t for t in targets), okline),
    "第 1–4 轮退出 %s（跳过 %d 轮），开始于第 1 轮后 %s 秒，第 1 轮后状态目录%s；第 1–4 轮 stdout：%s；"
    "第 3 轮后状态文件%s；第 1 条告警：%s，note 里%s主机名「%s」、%s锁文件名、目标名%s；持锁的 sleep 在第 1 轮后 %s 秒结束（lockf 退出 %s）；"
    "第 5 轮：退出 %s，%s，%s；lock-held-alert：%s；第 2 条：%s；第 5 轮后状态文件%s；"
    "第 6 轮：退出 %s，lock-held-alert 的行 %d 行；假 curl 每轮之后累计 %s，共 %d 次" % (
        "、".join(str(x["rc"]) for x in r[:4]), nskip, "、".join("?" if f is None else "%.1f" % f for f in offs[:4]),
        r[0]["probe"] or "?", " / ".join("%d「%s」" % (i + 1, brief(x)) for i, x in enumerate(r[:4])),
        "记了报过的时间" if r[2]["st"] and "alerted" in r[2]["st"] else "没记报过（%s）" % json.dumps(r[2]["st"]),
        body(main[0] if main else None), "有" if host and host in note else "没有", host or "?",
        "有" if lk and lk in note else "没有", "都有" if all(t in note for t in targets) else "缺了",
        "?" if hend is None or t0 is None else "%.1f" % (hend - t0), rd("main.holder-rc").strip() or "?",
        r[4]["rc"], "有 already locked" if "already locked" in r[4]["err"] else "没有 already locked", ok_line5[:100],
        brief(r[4]) if r[4]["guard"] else "没有它的行", body(main[1] if len(main) >= 2 else None),
        "还在" if r[4]["has_st"] else "没了", r[5]["rc"], len(r[5]["guard"]),
        "、".join(str(x["curls"]) for x in r), len(main)))

# 45（A45、C17）：不设阈值，状态文件是演练写的
a, b = R["45a"], R["45b"]
b45 = bodies("45.curl-bodies")
seeds = [js(n + ".seed.json") or {} for n in ("45a", "45b")]
ok = (skipped(a, 10) and "到 45 分钟才报" in a["guard"][0] and a["curls"] == 0
      and skipped(b, 10) and "到了 45 分钟，报警：POST heartbeat_stale → ops-system → 200" in b["guard"][0] and b["curls"] == 1
      and len(b45) == 1 and b45[0][1].get("kind") == "heartbeat_stale" and b45[0][1].get("status") == "stuck"
      and b45[0][1].get("bot") == "ops-system" and bool(b["st"]) and "alerted" in b["st"] and canary_ok)
res("S15.%s.45" % m, ok,
    "%s 上不设 HB_LOCK_ALERT_MIN（默认 45 分钟），外部拿住锁：状态文件写成「44 分钟前起、已跳过 9 轮」跑一轮，退出 75，「已连续跳过 10 轮」，"
    "假 curl 0 次；再写成「46 分钟前起、已跳过 9 轮」跑一轮，退出 75，假 curl 1 次，kind heartbeat_stale、status stuck、bot ops-system，"
    "状态文件记了报过的时间" % m,
    "44 分钟：退出 %s，stdout：%s，假 curl %d 次；46 分钟：退出 %s，stdout：%s，假 curl %d 次（%s），之后状态文件%s；"
    "演练写的状态文件：%s / %s" % (
        a["rc"], brief(a), a["curls"], b["rc"], brief(b), b["curls"], body(b45[0] if b45 else None),
        "记了报过的时间" if b["st"] and "alerted" in b["st"] else "没记报过",
        json.dumps(seeds[0], sort_keys=True), json.dumps(seeds[1], sort_keys=True)))

# bad（A47）：状态文件坏了，退出码照旧
a, b = R["bad-a"], R["bad-b"]
nbad = len(bodies("bad.curl-bodies"))
ok = (skipped(a, 1) and bool(a["st"]) and a["st"].get("skips") == 1 and "lock-held-alert：出错" not in a["err"]
      and b["rc"] == 75 and "already locked" in b["err"] and "lock-held-alert：出错（退出码照旧 75）" in b["err"]
      and b["probe"] == "没有" and nbad == 0 and canary_ok)
errline = next((re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l) for l in b["err"].splitlines() if "lock-held-alert：" in l),
               "（stderr 没有 lock-held-alert 的行）")
res("S15.%s.bad" % m, ok,
    "%s 上外部拿住锁：状态文件内容是乱码时当成没有记录，这一轮算第 1 次跳过，退出 75，状态文件换成记 1 次；状态文件的路径是个目录、写不进去时，"
    "退出还是 75，stderr 有 lock-held-alert 的报错；假 curl 0 次" % m,
    "乱码：退出 %s，stdout：%s，之后状态文件 %s；目录：退出 %s，stdout：%s，stderr：%s；假 curl %d 次" % (
        a["rc"], brief(a), json.dumps(a["st"], sort_keys=True) if a["st"] else "没有", b["rc"], brief(b), errline[:200], nbad))
PY
}

# ---------- S14、S15 iMac：lockf 实测、锁一直被占着（MBA 那边在 MBA 上跑同一套）。照 defs 里 5c2d0575 并行版的 precheck，
# 锁目录换成临时目录，lock-held-alert 换成临时副本 ----------
write_orca_precheck "$T/orca-precheck.py"
python3 -I - "$root/automations/heartbeat-1021/defs.json" "$V/new.sh" "$STANDIN" "$T/s14-imac" "$T/lock-held-alert" <<'PY'
import json, sys
e = next(x for x in json.load(open(sys.argv[1], encoding="utf-8"))["edit"] if x["stage"] == "parallel")
p, old, lockdir = e["set"]["precheck"], "$HOME/.orca-state/bin/heartbeat-watch.sh", "$HOME/.orca-state/heartbeat-watch/"
guard = "$HOME/.orca-state/bin/lock-held-alert"
# 回退测试的现网版 defs 没有 lockf 和 lock-held-alert
assert p.count(old) == 1 and p.count(lockdir) <= 1 and p.count(guard) <= 1 and p.count("<MBA 新任务 id>") <= 1
p = p.replace(old, sys.argv[2]).replace(guard, sys.argv[5]).replace(lockdir, "@LOCKDIR@/").replace("<MBA 新任务 id>", sys.argv[3])
assert ".orca-state" not in p  # 演练不碰真锁、不用装好的 lock-held-alert
open(sys.argv[4] + "-precheck.txt", "w", encoding="utf-8").write(p)
open(sys.argv[4] + "-timeout.txt", "w").write("%d\n" % e["set"]["precheckTimeout"])
PY
if [ -s "$T/s14-imac-precheck.txt" ]; then
    s14 inherit "$T/s14" "$OUT/raw/S14-imac" "$(cat "$T/s14-imac-precheck.txt")" 5c2d0575.lock "orca orca-ide" \
        "$(cat "$T/s14-imac-timeout.txt")" "$T/orca-precheck.py" "$T/hooks"
    s15 inherit "$T/s15" "$OUT/raw/S15-imac" "$(cat "$T/s14-imac-precheck.txt")" 5c2d0575.lock "$(cat "$T/s14-imac-timeout.txt")" \
        "$T/orca-precheck.py" "$T/hooks-s15"
fi
s14_judge "$OUT/raw/S14-imac" iMac "box ops · 29 卡住检查心跳："
s15_judge "$OUT/raw/S15-imac" iMac "box ops · 29 卡住检查心跳：正常（最新心跳" "box ops · 29 卡住检查心跳" "MBA ops · 29 心跳互查"

# ---------- MBA 这边：S2、S3、S4、S4b、S5、S5b、S7、S12、S13、S14、S15、S10 ----------
WEIRD="hb'drill \"q\" \$(echo HBX) \`echo HBY\` ; echo HBZ && echo HBW * \\ \$HOME 中文 · |
第二行"
M=$OUT/raw/mba
mkdir -p "$M" "$T/bundle/hooks" "$T/bundle/hooks-s15" "$T/bundle/hb-replay"
R=$(rssh 'mktemp -d -t hb-drill' 2>"$T/mktemp.err")
case $R in
    /*/hb-drill.*) case $R in *[!A-Za-z0-9/._-]*) R= ;; esac ;;
    *) R= ;;
esac
if [ -z "$R" ]; then
    res S2 FAIL "MBA 上建临时目录" "ssh mba 失败：$(head -2 "$T/mktemp.err" | tr '\n' ' ')；MBA 的场景都没跑"
else
    echo "MBA 临时目录 $R" >"$M/tmpdir.txt"
    cp "$root/scripts/heartbeat-watch.sh" "$root/scripts/orca-via-ssh" "$T/bundle/"
    if [ -f "$T/lock-held-alert" ]; then cp "$T/lock-held-alert" "$T/bundle/"; fi
    git -C "$root" show "$OLDWRAP:scripts/orca-via-ssh" >"$T/bundle/orca-via-ssh.7ac1220"
    chmod +x "$T/bundle/orca-via-ssh.7ac1220"
    cp "$here/heartbeat-watch-ssh.sh" "$T/bundle/drill.sh"
    cp -R "$here/hb-replay/." "$T/bundle/hb-replay/"
    cp "$T/hooks/coding-assistant.env" "$T/bundle/hooks/"
    cp "$T/hooks-s15/ops-system.env" "$T/bundle/hooks-s15/"
    printf '%s' "$WEIRD" >"$T/bundle/weird.txt"
    # 照 defs 里 MBA 新任务的 precheck 拼：三个脚本路径换成临时副本，锁目录换成各场景自己的临时目录（S14、S15 写成 @LOCKDIR@，
    # 在 s14、s15 里换）。S2 加 --dry-run；S12、S13 不加。超时取 defs 的 precheckTimeout；S12.old 的超时取 7ac1220 那版 defs
    # （第四轮的方案 1：钉在 240）。
    git -C "$root" show "$OLDWRAP:automations/heartbeat-1021/defs.json" >"$T/defs-7ac1220.json"
    python3 -I - "$root/automations/heartbeat-1021/defs.json" "$R" "$T/bundle" "$T/defs-7ac1220.json" <<'PY'
import json, sys


def mba(f):
    return next(x for x in json.load(open(f, encoding="utf-8"))["create"] if x["machine"] == "mba")


c = mba(sys.argv[1])
p, r, b = c["precheck"], sys.argv[2], sys.argv[3]
lockdir = "$HOME/.orca-state/heartbeat-watch/"
# 包装路径、lock-held-alert、锁目录最多一处：回退测试（heartbeat-watch-ssh-rollback.sh）的现网版 defs 不经包装、没有 lockf 和 lock-held-alert
assert p.count("$HOME/.orca-state/bin/heartbeat-watch.sh") == 1 and p.count("$HOME/.orca-state/bin/orca-via-ssh") <= 1
assert p.count(lockdir) <= 1 and p.count("$HOME/.orca-state/bin/lock-held-alert") <= 1
for old, new in (("$HOME/.orca-state/bin/orca-via-ssh", r + "/orca-via-ssh"),
                 ("$HOME/.orca-state/bin/lock-held-alert", r + "/lock-held-alert"),
                 ("$HOME/.orca-state/bin/heartbeat-watch.sh", r + "/heartbeat-watch.sh")):
    p = p.replace(old, new)
for name, lock, tail in (("s2", r + "/s2/lock/", " --dry-run"), ("s12", r + "/s12/lock/", ""), ("s13", r + "/s13/lock/", ""),
                         ("s14", "@LOCKDIR@/", "")):
    q = p.replace(lockdir, lock)
    assert ".orca-state" not in q  # 演练不碰真锁
    open("%s/%s-precheck.txt" % (b, name), "w", encoding="utf-8").write(q + tail + "\n")
open(b + "/mba-timeout.txt", "w").write("%d\n" % c["precheckTimeout"])
open(b + "/s12-old-timeout.txt", "w").write("%d\n" % mba(sys.argv[4])["precheckTimeout"])
PY
    COPYFILE_DISABLE=1 tar -C "$T/bundle" -cf - . | rssh "tar -C '$R' -xf -"
    rssh "/bin/bash '$R/drill.sh' --mba-side '$R' '$CANARY'" >"$M/mba-side.log" 2>&1
    echo "MBA 那边退出 $?" >>"$M/mba-side.log"
    rssh "COPYFILE_DISABLE=1 tar -C '$R/out' -cf - ." | tar -C "$M" -xf -
    rssh "rm -rf '$R'; test -e '$R' && echo 还在 || echo 删掉了" >"$M/tmpdir-cleanup.txt" 2>&1
fi

if [ -n "$R" ]; then
    for sh in sh zsh; do
        cat "$M/S2-$sh.out" "$M/S2-$sh.err" >"$T/S2-$sh.all" 2>/dev/null
        expect "S2.$sh" "MBA 上经 /bin/${sh} 跑 defs 原文（env -i 最少环境，只换三个脚本路径和锁目录，加 --dry-run）：经 ssh 读 iMac ops · 01，结果正常；锁空着、没有状态文件，lock-held-alert 什么都不打" \
            "$T/S2-$sh.all" 1 "$M/S2-$sh.rc" "iMac ops · 01 卡住工作检查：正常（最新心跳" "!运行记录查不到" "!脚本出错" "!将 POST 给" "!lock-held-alert："
    done
    cat "$M/S3.out" "$M/S3.err" >"$T/S3.all" 2>/dev/null
    expect S3 "MBA 上回放 30 分钟前的心跳：出 heartbeat_stale 待发内容，收件人 coding-assistant（STUCK_FORCE_BOT 没设）" \
        "$T/S3.all" 1 "$M/S3.rc" "$TO" "：中断：最新心跳在" "已 30 分钟没有新的" "$ST" '"bot": "coding-assistant"' '"machine": "本机"'
    cat "$M/S4.out" "$M/S4.err" >"$T/S4.all" 2>/dev/null
    XTRA="；用时 $(cat "$M/S4.secs" 2>/dev/null) 秒"
    expect S4 "ORCA_SSH_HOST=no-such-host.invalid：记「运行记录查不到」、不报、不算脚本出错，--precheck 退出 1" \
        "$T/S4.all" 1 "$M/S4.rc" "iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟" "!脚本出错" "!将 POST 给"
    v=PASS
    [ "$(cat "$M/S4-wrapper.rc" 2>/dev/null)" = 255 ] && [ ! -s "$M/S4-wrapper.out" ] || v=FAIL
    res S4.wrapper "$v" "包装连不上时退出 255（ssh 的）、stdout 空" "退出 $(cat "$M/S4-wrapper.rc" 2>/dev/null)，stdout $(wc -c <"$M/S4-wrapper.out" | tr -d ' ') 字节，stderr：$(head -1 "$M/S4-wrapper.err")"
    cat "$M/S4b.out" "$M/S4b.err" >"$T/S4b.all" 2>/dev/null
    XTRA="；state.json 没被改"
    cmp -s "$M/S4b.state-before" "$M/S4b.state-after" || { XTRA="；state.json 被改了"; XFAIL=1; }
    expect S4b "state 里记着 50 分钟前起查不到：报 heartbeat_stale「连不上 本机 的 Orca」给 coding-assistant；dry-run 不改 state" \
        "$T/S4b.all" 1 "$M/S4b.rc" "：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（JSONDecodeError）" "$TO" "$ST"
    s5_judge "$M/S5" MBA
    python3 -I - "$M/S5b.out" "$T/bundle/weird.txt" "$M/S5b.rc" "$CANARY" "$OUT/results.tsv" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
weird = open(sys.argv[2], encoding="utf-8").read()
rc = open(sys.argv[3]).read().strip()
try:
    d = json.loads(raw)
except ValueError:
    d = None
msg = ((d.get("error") or {}).get("message") or "") if isinstance(d, dict) else ""
ok = isinstance(d, dict) and d.get("ok") is False and weird in msg and sys.argv[4] not in raw and rc != "255"
got = "stdout %s；ok=%s；orca 收到的值%s原样；error.message：%s；退出 %s" % (
    "是一个 JSON" if d is not None else "不是 JSON", d.get("ok") if isinstance(d, dict) else "-",
    "是" if weird in msg else "不是", msg.replace("\n", "⏎")[:200], rc)
want = ("MBA 经包装真 ssh 到 iMac：--environment 的值带单双引号、$(…)、反引号、;、&&、*、反斜杠、$HOME 变量、中文、换行，"
        "orca 的报错里原样带回（没被展开或执行），stdout 只有一个 JSON")
open(sys.argv[5], "a", encoding="utf-8").write("S5b\t%s\t%s\t%s\n" % ("PASS" if ok else "FAIL", want, got))
print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", "S5b", got))
PY
    python3 -I - "$M/S7.json" "$M/S7-runs.rc" "$M/S7-list.rc" "$OUT/results.tsv" <<'PY'
import json, sys
try:
    s = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    s = {}
rc1, rc2 = open(sys.argv[2]).read().strip(), open(sys.argv[3]).read().strip()
hb = s.get("newest_hb") or {}
ok = (rc1 == "0" and rc2 == "0" and s.get("runs_ok") is True and (s.get("runs") or 0) >= 1 and (s.get("hb_lines") or 0) >= 1
      and s.get("list_ok") is True and bool(s.get("watched")) and bool((s.get("watched") or {}).get("createdAt")))
got = "runs 退出 %s、%s 条运行记录、%s 行 @@HB，最新心跳 %s 分钟前（rc %s）；list 退出 %s、%s 个自动任务，439cd438「%s」createdAt %s" % (
    rc1, s.get("runs"), s.get("hb_lines"), s.get("newest_hb_age_min"), hb.get("rc"), rc2, s.get("list_count"),
    (s.get("watched") or {}).get("name"), (s.get("watched") or {}).get("createdAt"))
want = "MBA 上直接跑 orca-via-ssh automations runs / list：ok，读到 ops · 01 的运行记录和 @@HB，list 里有 439cd438 和 createdAt"
open(sys.argv[4], "a", encoding="utf-8").write("S7\t%s\t%s\t%s\n" % ("PASS" if ok else "FAIL", want, got))
print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", "S7", got))
PY
    # S12、S12.old 的判断（FAILURE-MODES.md A18、A19、A39）
    python3 -I - "$M" "$OUT/results.tsv" "$CANARY" "$WATCHED" "$T/bundle/mba-timeout.txt" "$T/bundle/s12-old-timeout.txt" <<'PY'
import json, os, re, sys
m, tsv, canary, wid = sys.argv[1:5]
limit, oldlimit = open(sys.argv[5]).read().strip(), open(sys.argv[6]).read().strip()


def rd(name):
    try:
        return open(os.path.join(m, name), encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def gone(s):
    return "已经没了" if not s.strip() else "还在：" + " / ".join(s.strip().splitlines())


for n, cid in (("S12", "S12"), ("S12-old", "S12.old")):
    try:
        o = json.loads(rd(n + ".orca.json"))
    except ValueError:
        o = {}
    out = rd(n + ".out")
    allout = out + rd(n + ".err")
    t = [int(l.split()[1]) for l in rd(n + ".ssh-starts").splitlines() if len(l.split()) == 2]
    gaps = [b - a for a, b in zip(t, t[1:])]
    first, after, checked = rd(n + ".first-alive-at-second"), rd(n + ".alive-after"), rd(n + ".first-check-at").strip()
    hbs = re.findall(r"^@@HB (\{.*\})\s*$", out, re.M)
    hb = json.loads(hbs[-1]) if hbs else None
    files = rd(n + ".statefiles").split()
    common = "ssh 起了 %d 次%s；%s；跑完时%s" % (
        len(t), "，相邻开始隔 " + "、".join("%d" % g for g in gaps) + " 秒" if gaps else "",
        "第二次起来后 %s 秒查，第一次的 ssh %s" % (int(checked) - t[1], gone(first)) if len(t) >= 2 and checked.isdigit()
        else "没有第二次 ssh", "都没了" if not after.strip() else gone(after))
    if n == "S12":
        try:
            fs = (json.loads(rd("S12.state.json")).get(wid) or {}).get("fail_since")
        except (ValueError, AttributeError):
            fs = None
        fs_ok = isinstance(fs, (int, float)) and o.get("start", 0) <= fs <= o.get("end", 0)
        curl = rd("S12.curl-calls").strip()
        line = next((re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l) for l in out.splitlines() if not l.startswith("@@HB")),
                    "（stdout 没有日志行）")
        ok = (o.get("timedOut") is False and o.get("exitCode") == 1
              and "iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟" in out
              and hb is not None and hb.get("rc") == 0 and fs_ok
              and len(t) == 3 and all(75 <= g <= 85 for g in gaps) and not first.strip() and not after.strip()
              and not curl and "POST" not in allout and "webhook 配置" not in allout and "lock-held-alert：" not in allout
              and canary not in allout)
        got = "%s，用时 %s 秒，退出 %s；%s；@@HB %s；state.json 的 fail_since %s；%s；假 curl %d 次" % (
            ("超时被杀" if o.get("timedOut") else "没超时") if o else "没有预检结果", o.get("durationS"), o.get("exitCode"),
            line[:240], "rc %s" % hb.get("rc") if hb else "没有",
            ("在运行期间（开始后 %.1f 秒）" % (fs - o["start"]) if fs_ok else "不在运行期间（%s）" % fs) if fs is not None else "没有",
            common, len(curl.splitlines()))
        want = ("MBA 上照 defs 原文跑 precheck（只换三个脚本路径和锁目录，不带 --dry-run），ssh 替身让 iMac 那边不回（sleep 110），"
                "照 Orca 的做法起、超时 %s 秒：没超时、自己结束、退出 1；有「运行记录查不到（JSONDecodeError），已连续 0 分钟」；"
                "@@HB rc 0；state.json 的 fail_since 在这次运行期间；ssh 3 次，相邻开始隔 75–85 秒；第二次起来时第一次的 ssh 已经没了，"
                "跑完都没了；假 curl 0 次，输出里没有 POST 和 webhook 配置；锁空着、没有状态文件，lock-held-alert 什么都不打" % limit)
    else:
        lim = o.get("timeoutSeconds")
        ok = (o.get("timedOut") is True and o.get("exitCode") is None and lim == 240 and str(lim) == oldlimit
              and lim <= (o.get("durationS") or 0) <= lim + 15 and not hbs and not files
              and len(t) >= 2 and all(95 <= g <= 105 for g in gaps) and not first.strip() and not after.strip()
              and canary not in allout)
        got = "超时 %s 秒，%s，用时 %s 秒；@@HB %s；状态目录里%s；%s" % (
            lim, ("超时被杀（timedOut）" if o.get("timedOut") else "没超时，退出 %s" % o.get("exitCode")) if o else "没有预检结果",
            o.get("durationS"), "有" if hbs else "没有", "：" + "、".join(files) if files else "什么都没有", common)
        want = ("同样的设置，包装换成 7ac1220 那版（ssh 没有上限），precheck 直接写（没有 lockf），超时取 7ac1220 那版 defs（%s 秒，要是 240）："
                "到超时被杀（timedOut，用时在超时到超时加 15 秒之间）；"
                "没有 @@HB；状态目录里什么都没写；相邻两次 ssh 开始隔 95–105 秒；第二次起来时第一次的 ssh 已经没了"
                "（heartbeat-watch 的 90 秒超时杀的就是 ssh），跑完都没了" % oldlimit)
    got = got.replace("\t", " ").replace("\n", " ")
    open(tsv, "a", encoding="utf-8").write("%s\t%s\t%s\t%s\n" % (cid, "PASS" if ok else "FAIL", want, got))
    print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", cid, got))
PY
    # S13 的判断（FAILURE-MODES.md A30、A32、A37、A44、A46、C15）
    python3 -I - "$M" "$OUT/results.tsv" "$CANARY" <<'PY'
import json, os, re, sys
m, tsv, canary = sys.argv[1:4]
OK_LINE = "iMac ops · 01 卡住工作检查：正常（最新心跳"
GUARD = "lock-held-alert："


def rd(name):
    try:
        return open(os.path.join(m, name), encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


r = {}
for n in "ABC":
    try:
        o = json.loads(rd("S13-%s.orca.json" % n))
    except ValueError:
        o = {}
    out = rd("S13-%s.out" % n)
    hbs = re.findall(r"^@@HB (\{.*\})\s*$", out, re.M)
    calls = [l.split()[2] for l in rd("S13-%s.calls" % n).splitlines() if len(l.split()) >= 3]  # pid 时间 替身名
    r[n] = {"o": o, "out": out, "err": rd("S13-%s.err" % n), "hb": json.loads(hbs[-1]) if hbs else None,
            "ssh": calls.count("ssh"), "orca": calls.count("orca")}
a, b, c = r["A"], r["B"], r["C"]


def normal(x):
    return (x["o"].get("timedOut") is False and x["o"].get("exitCode") == 1 and OK_LINE in x["out"]
            and x["hb"] is not None and x["hb"].get("rc") == 0)


def line(x):
    l = next((l for l in x["out"].splitlines() if l.strip() and not l.startswith("@@HB")), "（stdout 没有日志行）")
    return re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l)[:120]


def since(x, k1, y, k2):
    try:
        return "%.1f" % (x["o"][k1] - y["o"][k2])
    except (KeyError, TypeError):
        return "?"


def desc(x):
    return "%s，用时 %s 秒，退出 %s，%s，@@HB %s，ssh %d 次、orca %d 次" % (
        ("超时被杀" if x["o"].get("timedOut") else "没超时") if x["o"] else "没有预检结果", x["o"].get("durationS"),
        x["o"].get("exitCode"), line(x), "rc %s" % x["hb"].get("rc") if x["hb"] else "没有", x["ssh"], x["orca"])


def guard(x):  # lock-held-alert 打的行，去掉开头的时间戳
    return [re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l) for l in x["out"].splitlines() if GUARD in l]


try:
    bst = json.loads(rd("S13-B.skips.json"))
except ValueError:
    bst = None
bst = bst if isinstance(bst, dict) else None
ao, bo, co = a["o"], b["o"], c["o"]
inside = bool(ao and bo) and ao["start"] < bo["start"] and bo["end"] < ao["end"]
after = bool(ao and co) and co["start"] >= ao["end"]
same = rd("S13-B.state-before") == rd("S13-B.state-after")
curl = rd("S13.curl-calls").strip()
alltext = "".join(x["out"] + x["err"] for x in (a, b, c))
blines = [l for l in b["out"].splitlines() if l.strip()]
cg = guard(c)
c_after = rd("S13-C.skips-after").strip()
# A44、A46：B 的 stdout 只有 lock-held-alert 的一行，状态文件记 1 次、没有报过；A 不打它的行；C 打「之前连续跳过 1 轮」，之后状态文件没了
gok = (len(blines) == 1 and len(guard(b)) == 1 and "已连续跳过 1 轮" in blines[0] and "@@HB" not in b["out"]
       and bool(bst) and bst.get("skips") == 1 and "alerted" not in bst
       and not guard(a) and len(cg) == 1 and "锁拿到了，之前连续跳过 1 轮" in cg[0] and c_after == "没有")
ok = (normal(a) and inside and bo.get("timedOut") is False and bo.get("exitCode") == 75
      and bo.get("durationS") is not None and bo["durationS"] <= 3
      and "already locked" in b["err"] and b["ssh"] == 0 and b["orca"] == 0 and same
      and after and normal(c) and gok and not curl and "POST" not in alltext and "webhook 配置" not in alltext
      and canary not in alltext)
got = "A：%s；B：A 开始后 %s 秒开始、A 结束前 %s 秒结束（%s），%s，用时 %s 秒，退出 %s，stdout %d 字节，stderr：%s，" \
      "ssh %d 次、orca %d 次，状态目录前后%s；C：A 结束后 %s 秒开始，%s；假 curl %d 次；状态文件：%s；" \
      "lock-held-alert：A 的 stdout 里%s它的行；B 的 stdout：%s；B 之后锁文件旁边的状态文件：%s；C：%s；C 之后状态文件%s" % (
          desc(a), since(b, "start", a, "start"), since(a, "end", b, "end"), "在 A 跑的期间" if inside else "不在 A 跑的期间",
          ("超时被杀" if bo.get("timedOut") else "没超时") if bo else "没有预检结果", bo.get("durationS"), bo.get("exitCode"),
          len(b["out"].encode()), (b["err"].strip().splitlines() or ["空"])[0][:120], b["ssh"], b["orca"],
          "一样" if same else "不一样",
          since(c, "start", a, "end"), desc(c), len(curl.splitlines()), " ".join(rd("S13.statefiles").split()) or "没有",
          "有" if guard(a) else "没有", (re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", blines[0]) if blines else "空")[:200],
          json.dumps(bst, sort_keys=True) if bst else "没有", (cg[0] if cg else "没有它的行")[:200], c_after or "?")
want = ("MBA 上照 defs 原文跑 MBA 新任务的 precheck（只换三个脚本路径和锁目录，不带 --dry-run），照 Orca 的做法起三轮，"
        "共用状态目录和锁文件；ssh、orca 替身记下每次调用再 exec 真的，A 那轮每次先等 30 秒，A 的替身起来 3 秒后起 B，A 结束后起 C："
        "A 退出 1、正常、@@HB rc 0，lock-held-alert 什么都不打；B 在 A 跑的期间开始和结束，3 秒内退出 75，stdout 只有 lock-held-alert 的一行"
        "「…已连续跳过 1 轮…」、没有 @@HB，stderr 有 already locked，ssh、orca 都是 0 次，B 前后状态目录一样，锁文件旁边的状态文件记 1 次、没有报过；"
        "C 在 A 结束以后开始，退出 1、正常、@@HB rc 0，stdout 有「锁拿到了，之前连续跳过 1 轮」，C 之后状态文件没了；"
        "假 curl 0 次，输出里没有 POST 和 webhook 配置")
got = got.replace("\t", " ").replace("\n", " ")
open(tsv, "a", encoding="utf-8").write("S13\t%s\t%s\t%s\n" % ("PASS" if ok else "FAIL", want, got))
print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", "S13", got))
PY
    s14_judge "$M/S14" MBA "iMac ops · 01 卡住工作检查："
    s15_judge "$M/S15" MBA "iMac ops · 01 卡住工作检查：正常（最新心跳" "iMac ops · 01 卡住工作检查"
    v=PASS
    cmp -s "$M/S10-before.txt" "$M/S10-after.txt" || v=FAIL
    [ "$(grep -c '^没有 ' "$M/S10-after.txt")" = 9 ] || v=FAIL
    [ "$(cat "$M/S10-statefiles.txt")" = s4b/state/state.json ] || v=FAIL
    grep -q '^删掉了' "$M/tmpdir-cleanup.txt" || v=FAIL
    res S10.MBA "$v" "MBA 演练前后：~/.orca-state/bin/ 下的 heartbeat-watch.sh、orca-via-ssh、lock-held-alert，~/.orca-state/heartbeat-watch 和它下面的 mba-hb-watch.lock、5c2d0575.lock 和两个锁旁边的状态文件（.skips.json），主检出的 scripts/orca-via-ssh 都没有，主检出 HEAD 不变；临时状态目录里只有 S4b 种的 state.json（S12、S13 不是 dry-run，它们的状态目录不算）；临时目录删掉了" \
        "$(tr '\n' ' ' <"$M/S10-after.txt")；状态文件：$(tr '\n' ' ' <"$M/S10-statefiles.txt")；临时目录$(cat "$M/tmpdir-cleanup.txt")"
fi

# ---------- S10 iMac：已装的 heartbeat-watch 没动；临时状态目录里 dry-run 没写东西 ----------
real_paths >"$T/imac-paths-after.txt"
IMAC_AFTER=$(shasum -a 256 "$HOME/.orca-state/bin/heartbeat-watch.sh" 2>&1 | cut -d' ' -f1)
(cd "$T" && find . -path '*/state/*' -type f | sort) >"$OUT/raw/S10-imac-statefiles.txt"
v=PASS
[ "$IMAC_BEFORE" = "$IMAC_AFTER" ] || v=FAIL
cmp -s "$T/imac-paths-before.txt" "$T/imac-paths-after.txt" || v=FAIL
for p in orca/workspaces/ops/scripts/orca-via-ssh .orca-state/bin/lock-held-alert .orca-state/heartbeat-watch/mba-hb-watch.lock \
    .orca-state/heartbeat-watch/5c2d0575.lock .orca-state/heartbeat-watch/mba-hb-watch.lock.skips.json \
    .orca-state/heartbeat-watch/5c2d0575.lock.skips.json; do
    grep -qFx "没有 ~/$p" "$T/imac-paths-after.txt" || v=FAIL
done
for c in c05 c07 c10; do
    for x in $VERS; do
        cmp -s "$OUT/raw/S1/$c.seed.json" "$T/s1/$c-$x/state/state.json" || v=FAIL
    done
done
[ "$(grep -vc -e '/s1/c05-' -e '/s1/c07-' -e '/s1/c10-' "$OUT/raw/S10-imac-statefiles.txt")" = 0 ] || v=FAIL
res S10.iMac "$v" "iMac 演练前后：~/.orca-state/bin/heartbeat-watch.sh 的 sha256 不变，没有 ~/.orca-state/bin/lock-held-alert，主检出没有 scripts/orca-via-ssh、HEAD 不变，~/.orca-state/heartbeat-watch/ 下没有 mba-hb-watch.lock、5c2d0575.lock 和它们旁边的状态文件（.skips.json；演练的锁和状态文件都在临时目录）；所有临时状态目录里只有种进去的 state.json，内容没变（dry-run 不写 state.json、watch.log、heartbeat.json）" \
    "已装版 ${IMAC_BEFORE:0:16} → ${IMAC_AFTER:0:16}；$(tr '\n' ' ' <"$T/imac-paths-after.txt")；状态文件 $(wc -l <"$OUT/raw/S10-imac-statefiles.txt" | tr -d ' ') 个"

# ---------- S11 静态：bash 3.2 语法、UTF-8 lint、shellcheck、包装最后一步是 perl 加 70 秒上限再 exec ssh ----------
mkdir -p "$OUT/raw/S11"
SH_FILES="scripts/orca-via-ssh scripts/lock-held-alert automations/heartbeat-1021/register.sh wake/tests/heartbeat-watch-ssh.sh wake/tests/hb-replay/orca"
v=PASS
for f in $SH_FILES; do
    /bin/bash -n "$root/$f" >>"$OUT/raw/S11/bash-n.txt" 2>&1 || v=FAIL
done
(cd "$root" && wake/tests/lint-bash32-utf8.sh $SH_FILES) >"$OUT/raw/S11/lint-bash32-utf8.txt" 2>&1 || v=FAIL
if command -v shellcheck >/dev/null; then
    (cd "$root" && shellcheck -S warning $SH_FILES) >"$OUT/raw/S11/shellcheck.txt" 2>&1 || v=FAIL
else
    echo "没装 shellcheck，没跑" >"$OUT/raw/S11/shellcheck.txt"
fi
for f in wake/tests/hb-replay/replay.py wake/tests/hb-replay/clock/sitecustomize.py; do
    python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$root/$f" >>"$OUT/raw/S11/python-ast.txt" 2>&1 || v=FAIL
done
# lock-held-alert 里 exec "$PY" - "$@" <<'PYEOF' 和 PYEOF 之间的 Python
sed -n '/^exec "\$PY" - "\$@" <<.PYEOF.$/,/^PYEOF$/p' "$root/scripts/lock-held-alert" 2>/dev/null | sed '1d;$d' >"$T/lock-held-alert.py"
python3 -I -c 'import ast, sys; s = open(sys.argv[1], encoding="utf-8").read(); assert s.strip(); ast.parse(s)' "$T/lock-held-alert.py" \
    >>"$OUT/raw/S11/python-ast.txt" 2>&1 || v=FAIL
L1=$(grep -v '^[[:space:]]*$' "$root/scripts/orca-via-ssh" 2>/dev/null | tail -2 | sed -n 1p)
L2=$(grep -v '^[[:space:]]*$' "$root/scripts/orca-via-ssh" 2>/dev/null | tail -1)
case $L1 in "exec /usr/bin/perl -e 'alarm shift; exec { \$ARGV[0] } @ARGV"*"' 70 \\") ;; *) v=FAIL ;; esac
case $L2 in "    ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 "*) ;; *) v=FAIL ;; esac
res S11 "$v" "5 个 shell 文件 /bin/bash 3.2 -n、lint-bash32-utf8、shellcheck -S warning 都过；2 个 Python 文件和 lock-held-alert 里的 Python 能解析；orca-via-ssh 最后一步是 exec /usr/bin/perl -e 'alarm shift; exec …' 70 ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2（每次 ssh 最多 70 秒；heartbeat-watch 超时杀的也是 ssh 本身）" \
    "bash -n $(wc -c <"$OUT/raw/S11/bash-n.txt" | tr -d ' ') 字节输出；lint $(wc -l <"$OUT/raw/S11/lint-bash32-utf8.txt" | tr -d ' ') 行；shellcheck $(wc -l <"$OUT/raw/S11/shellcheck.txt" | tr -d ' ') 行；最后一步：${L1:0:60}… ${L2:0:100}…"

# ---------- 报告 ----------
python3 -I - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(out, "results.tsv"), encoding="utf-8") if l.strip()]
npass, nfail = sum(r[1] == "PASS" for r in rows), sum(r[1] != "PASS" for r in rows)
env = open(os.path.join(out, "env.txt"), encoding="utf-8").read().strip().splitlines()
cell = lambda s: s.replace("|", "\\|").replace("`", "'")
scen = [
    ("S0", "三版 heartbeat-watch（base、iMac 已装、本分支）去掉注释后一致，第 33 行收件人不变", "iMac", "静态对比"),
    ("S1", "14 个回放例子 × 三版：输出和退出码逐字节一致，且符合期望", "iMac", "替身：假 HB_ORCA 回放录好的数据 + 固定时钟"),
    ("S2", "MBA 上照 defs 原文跑 precheck（/bin/sh、/bin/zsh 各一次）读真的 iMac ops · 01", "MBA → ssh iMac", "真"),
    ("S3", "MBA 上 --dry-run，目标换成心跳过期的回放数据", "MBA", "替身：假 HB_ORCA"),
    ("S4 / S4b", "ORCA_SSH_HOST 指向不存在的主机", "MBA", "真 ssh（主机名解析失败）"),
    ("S5", "orca-via-ssh 拒绝 edit 等子命令和坏的主机名", "iMac、MBA", "替身：假 ssh"),
    ("S5b", "orca-via-ssh 的参数转义", "MBA → ssh iMac", "真（orca 只读的 list，报错里带回参数）"),
    ("S6", "iMac 经 environment mba 读 MBA 一条现有任务（ops · 09）", "iMac → mba", "真"),
    ("S6b", "iMac 照 defs 原文跑 5c2d0575 的并行版、最终版 precheck；紧接着用 base 版跑现网 precheck 当对照", "iMac → grok-bot、mba", "真（MBA 新任务还没建，用 ops · 09 代替）"),
    ("S7", "MBA 上直接用 orca-via-ssh 读 iMac 的 runs、list", "MBA → ssh iMac", "真"),
    ("S8", "register.sh 只打印命令，不调用 orca", "iMac", "替身：假 orca"),
    ("S9", "现网配置和 defs.json 对得上（只读 show / list）", "iMac → grok-bot、mba", "真（只读）"),
    ("S10", "真路径没动：没装文件、主检出没动、dry-run 不写状态、没建真的锁文件", "iMac、MBA", "真"),
    ("S11", "静态检查", "iMac", "—"),
    ("S12", "ssh 连上了、iMac 那边不回：照 defs 原文跑 MBA 的 precheck，看超时以前有没有写下 fail_since 和 @@HB；"
     "S12.old 换成 7ac1220 的包装（ssh 没有上限）、超时钉在 7ac1220 那版 defs 的 240 秒对照", "MBA → ssh iMac",
     "替身：ssh 替身把远端命令换成 sleep 110；ssh 客户端、包装、heartbeat-watch 和 iMac 是真的。预检进程照 Orca 的做法起，不是 Orca 起的"),
    ("S13", "两轮同时跑：照 defs 原文跑 MBA 新任务的 precheck（套着 lock-held-alert 和 lockf），A 还在跑时起 B，A 结束后起 C，"
     "三轮共用状态目录和锁文件",
     "MBA → ssh iMac",
     "替身：ssh、orca 替身记下每次调用，A 那轮每次调用先等 30 秒再 exec 真的；lock-held-alert、lockf、包装、heartbeat-watch、"
     "ssh 客户端和 iMac 是真的。三轮都是演练脚本照 Orca 的做法起的，不是 Orca 起的"),
    ("S14", "lockf 实测：拿不到锁时（held）、锁目录不存在时（nodir）、持锁的 lockf 被 SIGKILL、SIGTERM、SIGSEGV 以后（kill、term、crash）、"
     "一轮被超时杀掉以后（timeout）",
     "MBA、iMac 各一遍",
     "kill、term、crash 只用 lockf 和 sleep，是真的（crash 是从外面发 SIGSEGV 模拟的）；held、nodir 用记录调用的 ssh / orca 替身；"
     "timeout 第一轮用 sleep 60 的替身、超时 12 秒，第二轮是真的"),
    ("S15", "锁一直被占着：外部 lockf 拿住锁，precheck 每轮跳过，到阈值时 lock-held-alert 报警一次，锁放开后报恢复；"
     "默认阈值 45 分钟（.45）；状态文件坏了（.bad）",
     "MBA、iMac 各一遍",
     "替身：假 curl（记下请求体、回 200）、阈值改成 0.25 分钟、.45 的状态文件是演练写的；lock-held-alert、lockf、heartbeat-watch 是真的，"
     "第 5、6 轮读真的 iMac ops · 01 / box、MBA。预检进程是演练脚本照 Orca 的做法起的"),
]
L = ["# heartbeat-watch 跨机看守挪到 MBA↔iMac：演练结果", "",
     "B1（ops 审计）。代码和上线步骤见 [`automations/heartbeat-1021/`](../../automations/heartbeat-1021/README.md)，"
     "失败方式清单见 [`FAILURE-MODES.md`](../../automations/heartbeat-1021/FAILURE-MODES.md)。这个文件由演练脚本生成。", ""] + \
    (["> " + os.environ["HB_DRILL_NOTE"], ""] if os.environ.get("HB_DRILL_NOTE") else []) + [
     "**结果：%d 项 PASS，%d 项 FAIL。**" % (npass, nfail), "", "## 怎么重跑", "",
     "在 iMac 的仓库根目录：", "", "```bash", "wake/tests/heartbeat-watch-ssh.sh", "```", "",
     "要求本机 Orca 有 environment `mba`、`grok-bot`，能 `ssh mba`，MBA 能 `ssh imac`。整个目录会被重写"
     "（有 `.hb-drill` 标记才清空）。回放数据要重录时先跑 `wake/tests/heartbeat-watch-ssh.sh --record`。", "",
     "heartbeat-watch 都用临时 `HB_STATE_DIR`；除 S12、S13 外都带 `--dry-run`、用假 webhook 目录（`127.0.0.1:9` 的假地址），不发叫醒、不读真凭据。"
     "S12、S13 不带 `--dry-run`（要看写下的 state.json 和 `@@HB`）：webhook 目录是空的，PATH 里放了只记录调用的假 curl。"
     "S12 第一次查不到时 heartbeat-watch 走 `continue`，到不了发告警那步；S13 读的是真的 ops · 01，正常时不发告警，"
     "万一判中断，没有 webhook 配置、curl 也是假的，发不出去。"
     "lockf 的锁文件、lock-held-alert 的状态文件都放在临时目录里，没碰 `~/.orca-state/heartbeat-watch/` 下的真文件（S10 核对）；"
     "precheck 里的 `~/.orca-state/bin/lock-held-alert` 换成了仓库里 `scripts/lock-held-alert` 的临时副本。"
     "lock-held-alert 不看 `--dry-run`：S15 里它真发告警，发给假 webhook 配置（`STUCK_FORCE_BOT=ops-system`，`127.0.0.1:9` 的假地址），"
     "PATH 里的假 curl 记下请求体、回 200，不连网络；别的场景到不了它发告警的那一步（没到 45 分钟）。"
     "S12.old、S14 的 timeout 第一轮到超时时，演练脚本照 Orca 的做法给它自己起的预检进程组发 SIGTERM、2 秒后 SIGKILL；"
     "S14 的 kill、term、crash 核对 pid、ppid（演练的 shell）、命令名（lockf）以后，只给演练自己起的 lockf 发 SIGKILL、SIGTERM、SIGSEGV，"
     "它起的 sleep 不发信号、等它自己结束。没有给演练以外的进程发过信号。"
     "crash 让 macOS 给 lockf 写一份崩溃报告 `lockf-<日期>-<时间>.ips`，每台每跑一次多一份：iMac 上在 `~/Library/Logs/DiagnosticReports/`，"
     "MBA 上在 `/Library/Logs/DiagnosticReports/`；两台「共享 Mac 分析」都关着，报告只留在本机；演练不删它（FAILURE-MODES F36、F37）。"
     "orca 只用 `automations list / show / runs`；不往 `~/.orca-state/bin/` 装文件；MBA 上只用 `mktemp -d` 的临时目录，跑完删掉。", "",
     "## 这次运行", ""] + ["- " + cell(l) for l in env] + ["", "## 场景", "",
     "| 编号 | 场景 | 在哪跑 | 真机还是替身 |", "|---|---|---|---|"] + \
    ["| %s | %s | %s | %s |" % s for s in scen] + [
     "", "S1、S3、S5、S8、S12、S13、S15 和 S14 的 held、nodir、timeout 用了测试替身，不算 E2E。S2 是从 iMac `ssh mba` 起的进程，不是 Orca 在 MBA 上跑的预检；"
     "Orca 预检环境里能不能连 ssh，要到上线卡 ② 第一次真实运行才算证实。", "",
     "## 期望和实际", "", "| 编号 | 期望 | 实际 | 结果 |", "|---|---|---|---|"] + \
    ["| %s | %s | %s | %s |" % (r[0], cell(r[2]), cell(r[3]), "PASS" if r[1] == "PASS" else "**%s**" % r[1]) for r in rows] + [
     "", "## 没跑的", "",
     "- `register.sh --apply`：任务书禁止。主机名检查、备份文件检查和真正调用 orca 的部分都没演练过。",
     "- 任何 `orca automations create / edit / run`：任务书禁止。MBA 新任务还没建，S6、S6b 用 MBA ops · 09 代替它。",
     "- wake-tla（`wake/tla/check.sh`）：没跑。两台都没有 Java 17 和 tla2tools（iMac 只有 Java 8，MBA 没有 Java）；check.sh 用 `free`、"
     "`/proc/loadavg`，只能在 Linux 上跑；`SOURCES.sha256` 里 stuck-check.sh、heartbeat-watch.sh 两项和现在的代码对不上，要先更新模型；"
     "模型里还是 box 盯 iMac，没有 lockf。见 FAILURE-MODES F29。",
     "- Orca 把预检退出 75 记成 `skipped_precheck`：没在真机上验证。要让 Orca 真跑一轮带锁的预检，就得建任务或者改现网任务，任务书禁止；"
     "orca CLI 也没有不建任务就能试预检的命令。依据是两台 Orca 的代码和现有运行记录（退出 1、2、255 和超时都记成 `skipped_precheck`），"
     "见 FAILURE-MODES F25。卡 ② 启用以后可以手动验证一次（README 卡 ②）。",
     "- Orca 自己让两轮预检重叠：没在真机上看到，只读了两台 Orca 的代码（F28）。S13 的三轮是演练脚本起的。",
     "- iMac 上真的 orca 卡住时什么样：没演练。S12 的「iMac 那边不回」是 ssh 替身把远端命令换成 `sleep 110`；"
     "真 orca 可能自己 60 秒超时、先回一个报错，那样不用等 70 秒上限。",
     "- Orca 自己起这条预检：要到上线卡 ② 才有。S12、S13、S14 的 timeout 的预检进程是演练脚本照 Orca 的做法起的"
     "（`/bin/sh -c`、新进程组、到时先 TERM 后 KILL）。",
     "- ssh 连接半路断了（ServerAlive 起作用）：没演练。",
     "- MBA 那条的少见情况：还没见过心跳、心跳又过期，而且 runs 前两次各卡满 70 秒，再加一次 list，最坏 296 秒，加起动约 4 秒，在 330 秒的超时以内。没演练。",
     "- lock-held-alert 真等 45 分钟：没跑。S15 主线把阈值改成 0.25 分钟；默认的 45 分钟由 S15 的 .45 看，状态文件是演练写的（FAILURE-MODES C17）。",
     "- lock-held-alert 的告警发不出去（没有 webhook 配置、POST 失败）、「已恢复」发不出去：没演练，S15 只走了发成功的路（假 curl 回 200，A51）。",
     "- 两个 lock-held-alert 同时写状态文件：没演练（A50）。",
     "- 收件方（Coding助手）怎么处理 `source` 是 `lock-held-alert` 的 `heartbeat_stale`、`heartbeat_recovered`：没验证，告警只发给了假 curl（C18）。",
     "- lockf 自己真的段错误：没有。S14 的 crash 是从外面给 lockf 发 SIGSEGV 模拟的（C20）。",
     "", "## 文件", "",
     "- `results.tsv`：每项一行（编号、结果、期望、实际），`README.md` 由它生成。",
     "- `env.txt`：时间、commit、两台机器的系统和工具版本。",
     "- `raw/S0/`：三版的 sha256 和 diff。`raw/S1/`：每个例子的参数（`.cmd`）、回放设置（`.vars`，不用 `.env`：仓库的 .gitignore 不收 `*.env`）、种的状态（`.seed.json`），"
     "三版各自的 stdout、stderr、退出码和假 orca 收到的调用。",
     "- `raw/S5-imac/`：iMac 上包装每条用例的命令、退出码、stderr、假 ssh 收到的参数。",
     "- `raw/S6/`、`raw/S6b/`：iMac 上的命令和原始输出。`raw/S8/`：register.sh 每次的参数和输出。`raw/S9/`：只读 show / list 摘下来的字段。",
     "- `raw/mba/`：MBA 那边的原始输出（S2、S3、S4、S4b、S5、S5b、S7 摘要、S10、S12、S13、S14、S15）。S7 只留摘要，不留运行记录原文。",
     "- `raw/mba/S13.cmd`、`raw/mba/S13-A.*`、`S13-B.*`、`S13-C.*`：precheck；三轮各自的 stdout、stderr、预检结果（`.orca.json`）、"
     "ssh、orca 替身记下的调用（`.calls`：pid、时间、替身名）；`S13-B.state-before`、`S13-B.state-after`：B 前后状态目录里每个文件的 sha256；"
     "`S13-B.skips.json`：B 之后锁文件旁边 lock-held-alert 的状态文件；`S13-C.skips-after`：C 之后它还在不在；"
     "`S13.curl-calls`、`S13.statefiles`、`S13.state.json`：假 curl 的调用、三轮跑完后状态目录里的文件和 state.json。",
     "- `raw/mba/S14/`、`raw/S14-imac/`：S14 每一步的 precheck（`.cmd`）、退出码、stdout、stderr、替身的调用（`.calls`、`timeout.stub-calls`：pid、时间、替身名）、"
     "HB_STATE_DIR 指向的目录有没有被建出来（`.probe`）、held 之后锁文件旁边的状态文件（`held.skips.json`）；"
     "kill、term、crash 每项的进程检查（`<项>.holder-ps`、`<项>.child-after-signal`，是 `ps -o pid,ppid,rss,etime,comm` 的输出）、"
     "发出的信号（`<项>.sent`）、两次探锁的结果（`<项>.probe1.*`、`<项>.probe2.*`）、lockf 的退出码（`<项>.holder-rc`）、锁文件还在不在（`<项>.lockfile`）、"
     "它起的 sleep 什么时候没的（`<项>.child-end`）；crash 前后 lockf 开头的崩溃报告数（`crash.reports-before`、`crash.reports-after`，"
     "两个数依次是 `~/Library/Logs/DiagnosticReports/`、`/Library/Logs/DiagnosticReports/` 里的，读不了的目录记 `?`；"
     "after 是等它起的 sleep 结束以后数的，报告写得更晚时会数漏，所以只记不判，F36、F37）；"
     "timeout 探锁的结果和探锁前后的时间（`timeout.probe.*`）、两轮的预检结果（`timeout-1.*`、`timeout-2.*`）。",
     "- `raw/mba/S15/`、`raw/S15-imac/`：每一轮（主线 `r1`–`r6`，`45a`、`45b`，`bad-a`、`bad-b`）的 precheck（`.cmd`）、stdout、stderr、"
     "预检结果（`.orca.json`）、HB_STATE_DIR 有没有被建出来（`.probe`）、到这轮为止假 curl 几次（`.curls`）、这轮之后锁文件旁边的状态文件（`.skips.json`，没有就是没了）；"
     "假 curl 记下的请求体（`main.curl-bodies`、`45.curl-bodies`、`bad.curl-bodies`，每行「假地址 请求体」）；演练写的状态文件（`45a.seed.json`、`45b.seed.json`、`bad-a.seed`）；"
     "第 1 轮开始的时间（`t0`）、持锁的 sleep 的 pid 和它结束的时间、lockf 的退出码（`main.holder-*`、`45.holder-*`、`bad.holder-*`）；主机名（`host`）、锁文件名（`lockname`）。",
     "- `raw/mba/S12.*`、`raw/mba/S12-old.*`：precheck（`.cmd`）、stdout、stderr、预检结果（`.orca.json`：超时、是否超时、退出码、用时、起止时间）、"
     "每次 ssh 的 pid 和开始时间（`.ssh-starts`）、ssh 收到的参数（`.ssh-args`）、进程检查（`.first-alive-at-second`、`.alive-after`，"
     "是 `ps -o pid,ppid,rss,etime,comm` 的输出，空 = 进程已经没了）、假 curl 的调用（`.curl-calls`）、状态目录里的文件和内容。",
     "- `raw/S11/`：静态检查的输出。", "- `SHA256SUMS`：除它自己以外所有文件的 sha256（`shasum -a 256 -c SHA256SUMS` 校验）。"]
open(os.path.join(out, "README.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
print("\n%d 项 PASS，%d 项 FAIL" % (npass, nfail))
PY
(cd "$OUT" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r f; do shasum -a 256 "$f"; done >SHA256SUMS)
echo "产物：$OUT"
awk -F'\t' '$2 != "PASS" { bad = 1 } END { exit bad }' "$OUT/results.tsv"
