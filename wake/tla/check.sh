#!/bin/bash
# wake/tla/check.sh [--out DIR] [名字前缀...]
# 跑叫醒系统的 TLA+ 模型检查（PER-67），把每次 TLC 的结果和下面表里的「期望」对照。
#   不带名字：全部跑；带前缀（如 w15 h0）：只跑名字以它开头的。
#   每个检查的 TLC 原文写到 DIR/<名字>.out（默认 wake/tla/out，已在 .gitignore），汇总写 DIR/summary.tsv。
# 期望：pass = TLC 跑完没发现错误；violated = TLC 报性质被违反（现有代码的发现，或故意改坏的变体）。
# 退出码：0 全部和期望一致；1 有不一致（结果变了：先读 README「结果变了怎么办」），或被建模的代码和 SOURCES.sha256 对不上（这时不跑 TLC）；2 环境问题（没装 Java/TLA+、资源不够）。
# 资源：每次 -workers 2、-Xmx1500m、timeout 1200 秒；开跑前可用内存 < 2G 或 load > 8 就等 5 分钟（最多等 3 次）。
# 工具（装在用户目录，见 README「安装」）：TLA_JAVA、TLA_JAR 可改路径。
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
JAVA=${TLA_JAVA:-$HOME/.local/opt/jdk-17.0.12+7-jre/bin/java}
JAR=${TLA_JAR:-$HOME/.local/opt/tla/tla2tools.jar}
JAR_SHA=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88   # tla2tools.jar v1.7.4
out=$here/out
if [ "${1:-}" = --out ]; then out=$2; shift 2; fi
want=("$@")

# 名字 模块 期望 说明
RUNS=(
  "w01_p2_nr          MC pass     P2 notify-run：非 2xx 不记成功"
  "w02_p2_nr_mutant   MC violated P2 改坏：notify-run 把任何 http 当成功"
  "w03_p2_ow          MC pass     P2 orca-wake：非 2xx 不写 sent/woken"
  "w04_p2_ow_mutant   MC violated P2 改坏：orca-wake 把任何 HTTP 回答当成功"
  "w05_p2_sc_post     MC pass     P2 stuck-check 自己 POST：非 2xx 不记 notified"
  "w06_p2_sc_post_mutant MC violated P2 改坏：stuck-check 把任何状态码当成功"
  "w07_p2_sc_recheck  MC pass     P2 recheck：交给 orca-wake 只记已交出，送达（already_woken）才算（F1 已修）"
  "w08_p2_sc_recheck_mutant MC violated P2 改坏（F1 修之前的代码）：recheck 看到 send 就记 notified"
  "w09_p4             MC pass     P4 停下 1 小时内一定有 bot 收到或叫醒 Coding助手（F6 已修，F4/F5 一起）"
  "w09a_p4_no_escalate MC pass     P4 同上（和 w09 同一份配置，保留名字对照以前的结果）"
  "w09b_p4_slow_mutant MC violated P4 改坏（F6 修之前，第 4 组的写法）：改报从第一次失败算、completed 不查，1 小时内到不了"
  "w10_p4_fixed       MC pass     P4 以前的假设修法 ca_escalate 已在代码里（和 w09 同一份配置）"
  "w11_p1             MC pass     P1 派活 bot 一直坏也最终有人收到（F2、F4 已修）"
  "w11a_p1_no_escalate MC pass     P1 派活 bot 一直坏：45 分钟发不出去就改报 Coding助手（F4 已修）"
  "w11b_p1_escalate_mutant MC violated P1 改坏（F4 修之前的代码）：派活 bot 一直坏，没有升级 Coding助手"
  "w12_p1_fixed       MC pass     P1 以前的假设修法都已在代码里（和 w11 同一份配置）"
  "w13_p1h            MC pass     P1h webhook 都会恢复：每个停下最终有人收到（F1、F2、F3 已修）"
  "w13a_p1h_only_recheck MC pass     P1h 只剩 F1 时：已修（recheck 发送失败下次再补）"
  "w13e_p1h_recheck_mutant MC violated P1h 改坏（F1 修之前的代码）：recheck 发送失败后不再补"
  "w13b_p1h_only_main MC pass     P1h 只剩 F2 时：已修（主目录 agent 退出、notify-run 没发出去，卡住检查照报）"
  "w13f_p1h_main_mutant MC violated P1h 改坏（F2 修之前的代码）：主目录里包了 notify-run 的退出一律不报"
  "w13c_p1h_only_clean MC pass     P1h 只剩 F3 时：已修（最后一次停下没送达叫醒的干净工作区照报）"
  "w13d_p1h_clean_mutant MC violated P1h 改坏（F3 修之前的代码，且去掉 F6 的 completed 没送达检查）：completed 干净工作区一律放行"
  "w14_p1h_fixed      MC pass     P1h 以前的假设修法都已在代码里（和 w13 同一份配置）"
  "w15_p5             MC pass     P5 一个 bot 的 webhook 坏了只挡发给它自己的（F5 已修）"
  "w15b_p5_hol_mutant MC violated P5 改坏（F5、F4 修之前的 send_all）：一个 bot 坏了挡住 Coding助手 的叫醒"
  "w16_p5_fixed       MC pass     P5 假设修法 no_hol"
  "w17_p1h_cut        MC pass     P1h 扫描最多 2 次没判断到任务（PER-82）：下次接着查，最终有人收到"
  "w17a_p1_cut        MC pass     P1 同上，派活 bot 一直坏"
  "w18_p4_cut1        MC pass     P4 扫描 1 次没判断到任务：1 小时内仍然到得了"
  "w18a_p4_cut2       MC violated P4 扫描 2 次没判断到任务：1 小时到不了（PER-82 之后 P4 的余量）"
  "w19_p1h_cut_forever MC violated P1h 每次都截断时排在后面的工作区一直没判断（发现 F9，第一类阶段内没有游标）"
  "w20_p1h_skip_dismiss_mutant MC violated P1h 改坏：跳过时记成已处理，不留着下次查"
  "h01_p3_dead        Heartbeat pass     P3 自动任务不跑 / Orca 挂了：会告警，且 75 分钟内"
  "h02_p3_dead_mutant Heartbeat violated P3 改坏：查不到运行记录时不报"
  "h03_p3_hang        Heartbeat pass     P3 每次扫描超时被杀：会告警，且 75 分钟内（F7 已修：last_scan = 上次跑完的扫描）"
  "h04_p3_crash       Heartbeat pass     P3 每次扫描出错：会告警，且 75 分钟内（F8 已修）"
  "h05_p3_hang_mutant Heartbeat violated P3 改坏（修之前的代码）：last_scan 取扫描开始时间，超时被杀不告警"
  "h06_p3_crash_mutant Heartbeat violated P3 改坏（修之前的代码）：last_scan 取扫描开始时间，出错不告警"
  "h07_p3_cut         Heartbeat pass     P3 每次扫描都到整轮时限：last_scan 照样前进，靠 scan_slow 告警（PER-82）"
  "h08_p3_cut_mutant  Heartbeat violated P3 改坏：去掉 scan_slow，每次截断没人知道"
  "h09_pw_peer        Heartbeat pass     看守机下线：盯它的那条报出来（iMac 5c2d0575 启用时）"
  "h10_pw_no_peer     Heartbeat violated 看守机下线没人盯（发现 F11，10-31 现网 5c2d0575 停用）"
  "h11_p3_alert_on_target Heartbeat violated P3 告警的 webhook 在被盯的 iMac 上：iMac 整台没了发不出去（发现 F10）"
  "h12_p3w_down_peer  Heartbeat pass     看守机下线且扫描坏了（hang/crash/cut）：有人收到"
  "h13_p3w_double_fault Heartbeat violated 看守机下线且 iMac Orca 挂了：两边一起没，没人知道（B1 已知限制）"
  "l01_p6             Launch    pass     P6 agent 没起来（被拒 / 一直没有第 1 个回合）：一定有 bot 收到，且 START+1 分钟内（第 6 组）"
  "l02_p6_old_mutant  Launch    violated P6 改坏（修之前的代码）：两处都不叫醒"
  "l03_p6_no_fallback_mutant Launch violated P6 改坏：只发派活 bot，发不出去不改发 Coding助手"
  "l04_p6_pre_silent_mutant Launch violated P6 改坏：启动前检查没过时直接退出，不叫醒（PER-80）"
)

# 被建模的代码变了没有：变了模型就是过期的，结果没有意义，直接失败，不跑 TLC。
# --strict：SOURCES.sha256 里有格式不对的行也算失败。文件不存在、读不了时 sha256sum 本身非 0。
if ! drift=$(cd "$repo" && sha256sum -c --quiet --strict "$here/SOURCES.sha256" 2>&1); then
    echo "check.sh: FAIL：模型对应的代码和建模时不一样了（SOURCES.sha256），不跑 TLC："
    echo "$drift" | sed 's/^/  /'
    echo "  按 README「代码变了怎么办」对一遍行号和动作，再更新 SOURCES.sha256。"
    exit 1
fi

[ -x "$JAVA" ] || { echo "check.sh: 找不到 Java：${JAVA}（见 README「安装」）" >&2; exit 2; }
[ -r "$JAR" ] || { echo "check.sh: 找不到 tla2tools.jar：${JAR}（见 README「安装」）" >&2; exit 2; }
jar_sha=$(sha256sum "$JAR" | cut -c1-64)
[ "$jar_sha" = "$JAR_SHA" ] || echo "check.sh: 注意：tla2tools.jar 的 sha256 不是 v1.7.4（${jar_sha}），结果可能和记录的不同" >&2

wait_resources() {
    local n=0 avail load
    while :; do
        avail=$(free -m | awk '/^Mem:/ {print $7}')
        load=$(cut -d' ' -f1 /proc/loadavg)
        if [ "${avail:-0}" -ge 2048 ] && awk "BEGIN{exit !($load <= 8)}"; then return 0; fi
        n=$((n + 1))
        [ $n -le 3 ] || { echo "check.sh: 资源一直不够（可用 ${avail}MB，load ${load}），不跑了" >&2; return 1; }
        echo "check.sh: 可用 ${avail}MB、load ${load}，等 5 分钟（第 $n 次）" >&2
        sleep 300
    done
}

mkdir -p "$out"
sum=$out/summary.tsv
[ ${#want[@]} -gt 0 ] && [ -f "$sum" ] || printf 'name\tmodule\texpect\tresult\tmatch\tseconds\tstates\tnote\n' >"$sum"
commit=$(cd "$repo" && git rev-parse HEAD 2>/dev/null || echo unknown)
echo "commit $commit  tla2tools $jar_sha  $("$JAVA" -version 2>&1 | head -1)"
bad=0
for r in "${RUNS[@]}"; do
    read -r name mod expect note <<<"$r"
    if [ ${#want[@]} -gt 0 ]; then
        hit=0; for w in "${want[@]}"; do case "$name" in "$w"*) hit=1 ;; esac; done
        [ $hit = 1 ] || continue
    fi
    wait_resources || exit 2
    meta=$(mktemp -d "${TMPDIR:-/tmp}/wake-tla.XXXXXX")
    t0=$(date +%s)
    (cd "$here" && timeout 1200 "$JAVA" -Xmx1500m -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers 2 \
        -metadir "$meta" -config "cfg/$name.cfg" "$mod.tla") >"$out/$name.out" 2>&1
    rc=$?
    secs=$(( $(date +%s) - t0 ))
    rm -rf "$meta"
    if grep -q "No error has been found" "$out/$name.out"; then result=pass
    elif grep -qE "is violated|Temporal properties were violated" "$out/$name.out"; then result=violated
    elif [ $rc = 124 ]; then result=timeout
    else result=error; fi
    states=$(grep -oE '[0-9,]+ distinct states found' "$out/$name.out" | tail -1 | cut -d' ' -f1)
    if [ "$result" = "$expect" ]; then m=ok; else m=MISMATCH; bad=1; fi
    printf '%-26s %-9s 期望 %-8s 结果 %-8s %-8s %5ss %12s 状态  %s\n' "$name" "$mod" "$expect" "$result" "$m" "$secs" "${states:--}" "$note"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$mod" "$expect" "$result" "$m" "$secs" "${states:--}" "$note" >>"$sum"
done
[ $bad = 0 ] && echo "全部和期望一致。" || echo "有结果和期望不一致：读 README「结果变了怎么办」。"
exit $bad
