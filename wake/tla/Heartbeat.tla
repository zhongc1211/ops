------------------------------ MODULE Heartbeat ------------------------------
(***************************************************************************)
(* 卡住检查自己停了会不会告警（P3）。模型来自：                            *)
(*   scripts/stuck-check.sh   iMac「ops · 01 卡住工作检查」每分钟的 precheck  *)
(*                            （--scan，Orca 的 precheck timeoutSeconds 600） *)
(*   scripts/heartbeat-watch.sh  看守机「ops · 29」每 5 分钟，盯 ops · 01 的 *)
(*                            运行记录里的 @@HB 行（--target ...|20）         *)
(*   看守机：10-31 现网是 box；automations/heartbeat-1021 写的部署（MBA）没上线。 *)
(*   两种部署模型一样：看守机离线、经 ssh 或隧道连不上都走 reach / wUp。        *)
(* 一步 = 1 分钟。stuck-check 的一次运行在模型里是一步（真实耗时最多约 4 分钟， *)
(* iMac 日志 10-16～10-19 最长 253 秒），卡死的运行占 10 分钟后被 Orca 杀掉。    *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS
    FailModes,   \* 允许出现的故障：dead / crash / hang / cut
    Mutant,      \* "none" | "no_unreach_alert" | "scan_start" | "no_scan_slow"
    INTERVAL,    \* STUCK_INTERVAL_MIN = 15（stuck-check.sh:153）
    PRE_TIMEOUT, \* precheck timeoutSeconds 600 → 10 分钟（自动任务 439cd438 的配置，10-31 只读核对）
    HB_MAX,      \* --target 的 N = 20（自动任务 94e4b0bc 的 precheck 参数）
    UNREACH,     \* HB_UNREACH_MIN = 45（heartbeat-watch.sh:34）
    WATCH_EVERY, \* ops · 29 的 rrule */5 → 5 分钟
    BOUND,       \* P3_BOUND：最后一次跑完的扫描之后多少分钟内必须已告警
    WatcherFaults,   \* {} 或 {"down"}：看守机可能下线（MBA 睡着、box 断电）
    PEER,            \* TRUE：另一台盯看守机的心跳（iMac 5c2d0575 启用）；10-31 现网停用
    ALERT_ON_TARGET, \* TRUE：告警的收件 webhook 在被盯的那台上（README 发现 F10）
    CAP

VARIABLES
    mode,      \* "ok" 或 FailModes 里的一种；坏了就一直坏（P3 讲的是「停了」）
    reach,     \* 看守机能不能查到 iMac Orca 的运行记录（mode = dead 时可能查不到）
    gateAge,   \* gate.json 的 last 距现在几分钟（stuck-check.sh:2311 在 main() 之前写）
    hbAge,     \* 运行记录里最新一行 @@HB 距现在几分钟
    hbScan,    \* 那行 @@HB 里的 last_scan 距现在几分钟
    doneAge,   \* 最后一次真正跑完的扫描距现在几分钟 = gate.json 的 done（stuck-check.sh:2326-2327，main() 正常返回后才写）
    hang,      \* 一次卡住的运行还要占几分钟（Orca 到 600 秒杀掉）
    failAge,   \* heartbeat-watch 的 fail_since 距现在几分钟（查不到运行记录时）
    wclock,    \* 距 heartbeat-watch 下一次运行还有几分钟
    alerted,   \* heartbeat-watch 已经成功报过 heartbeat_stale（state.json 的 alerted）
    slowAlerted, \* stuck-check 已经报过 scan_slow（track 的 scan_slow，stuck-check.sh:1764-1765）
    wUp,       \* 看守机在线
    wDownAge,  \* 看守机下线几分钟
    peerAlerted \* 盯看守机的那条已经报过看守机中断

vars == <<mode, reach, gateAge, hbAge, hbScan, doneAge, hang, failAge, wclock, alerted,
          slowAlerted, wUp, wDownAge, peerAlerted>>

Inc(x) == IF x < CAP THEN x + 1 ELSE x
Add(x, k) == IF x + k < CAP THEN x + k ELSE CAP

Init ==
    /\ mode = "ok" /\ reach = TRUE
    /\ gateAge \in 0..(INTERVAL - 1)
    /\ hbAge = 0 /\ hbScan = gateAge /\ doneAge = gateAge
    /\ hang = 0 /\ failAge = 0
    /\ wclock \in 0..(WATCH_EVERY - 1)
    /\ alerted = FALSE
    /\ slowAlerted = FALSE /\ wUp = TRUE /\ wDownAge = 0 /\ peerAlerted = FALSE

(* 出故障（之后不恢复）。dead = Orca 调度器停了 / 自动任务没在跑 / iMac Orca 挂了   *)
(* （可能连运行记录也查不到）；crash = main() 每次都抛异常；hang = main() 每次都超过 *)
(* precheck 的 600 秒被杀；cut = 每次都到整轮时限（STUCK_SCAN_BUDGET_S，480 秒），  *)
(* 停在半路但正常退出（PER-82，stuck-check.sh:2010）。                            *)
Fail ==
    /\ mode = "ok"
    /\ \E m \in FailModes :
         /\ mode' = m
         /\ reach' \in (IF m = "dead" THEN BOOLEAN ELSE {TRUE})
    /\ UNCHANGED <<gateAge, hbAge, hbScan, doneAge, hang, failAge, wclock, alerted,
                   slowAlerted, wUp, wDownAge, peerAlerted>>

(* ops · 01 这一分钟的 precheck（stuck-check.sh:2289-2329）。                    *)
(*   闸门没开（距 gate.last 不到 INTERVAL）：heartbeat(1)，@@HB 的 last_scan =   *)
(*     gate.json 的 done（:2290-2296, :2265）。                                    *)
(*   闸门开：先写 gate.json last=NOW、done 照旧（:2311），再 main()（:2316）：     *)
(*     ok    → 写 done=NOW（:2326-2327），heartbeat(rc)，last_scan = done（:2329）  *)
(*     cut   → 和 ok 一样写 done（SCAN_DONE = True，:2010），扫描到发送前超过超时的 60%， *)
(*             scan_slow 发 ops-system（:2012,2222-2254，发不出去下次再发）          *)
(*     crash → except：rc=4，--scan 时改成 rc=0，done 不变，照样 heartbeat         *)
(*             （:2317-2329）                                                     *)
(*     hang  → 600 秒后被 Orca 杀掉，这次没有 @@HB、done 不变；锁随进程释放        *)
(* Mutant "scan_start"：修之前的代码（PER-67 F7、F8），last_scan 取扫描开始时写的 *)
(*   gate.last，被杀、出错也照样前进。                                            *)
(* 上一个卡住的运行没结束前，Orca 不再起这个 precheck（按不重叠算，心跳更少，     *)
(* 对告警更有利）。                                                            *)
Blocked  == mode = "dead" \/ hang > 0
GateOpen == ~Blocked /\ gateAge >= INTERVAL
PrintsHB == ~Blocked /\ (~GateOpen \/ mode \in {"ok", "crash", "cut"})
nGate == IF GateOpen THEN 0 ELSE gateAge
nHb   == IF PrintsHB THEN 0 ELSE hbAge
nDone == IF GateOpen /\ mode \in {"ok", "cut"} THEN 0 ELSE doneAge
nScan == IF ~PrintsHB THEN hbScan
         ELSE IF Mutant = "scan_start" THEN (IF GateOpen THEN 0 ELSE gateAge)
         ELSE nDone
nHang == IF hang > 0 THEN hang - 1 ELSE IF GateOpen /\ mode = "hang" THEN PRE_TIMEOUT - 1 ELSE 0
(* Mutant "no_scan_slow"：去掉 scan_slow。last_scan 照样前进，heartbeat-watch 看不出来。 *)
nSlow == slowAlerted \/ (GateOpen /\ mode = "cut" /\ Mutant # "no_scan_slow")

(* heartbeat-watch.sh main()（:188-257），每 WATCH_EVERY 分钟一次。查不到运行记录： *)
(* fail_since 起算，满 UNREACH 分钟才算中断（:195-203）；查到了：最新 @@HB 超过    *)
(* HB_MAX 分钟（:223），或 last_scan 超过 HB_MAX + INTERVAL 分钟（:226）算中断。    *)
(* 中断且没报过 → POST ops-system（BOT，:33，:233-245）；假设它的 webhook 可用      *)
(* （发不出去时每 5 分钟重试；post() 只发这一个 bot，没有改发，:158-163）。          *)
(* ALERT_ON_TARGET：收件 webhook 在 iMac 上，iMac 整台没了（dead 且查不到）就发不出去。 *)
(* Mutant "no_unreach_alert"：查不到运行记录时一直 continue（去掉 :199-201 的报警）。*)
nFail == IF reach THEN 0 ELSE Add(failAge, WATCH_EVERY)
Down  == IF ~reach THEN Mutant # "no_unreach_alert" /\ nFail >= UNREACH
         ELSE nHb > HB_MAX \/ nScan > HB_MAX + INTERVAL

HookOK == ~(ALERT_ON_TARGET /\ mode = "dead" /\ ~reach)

(* 盯看守机的那条（iMac 5c2d0575）跟着 iMac 的 Orca：mode = dead 时按它也不跑算。     *)
PeerRuns == PEER /\ mode # "dead"

Step ==
    /\ gateAge' = Inc(nGate) /\ hbAge' = Inc(nHb) /\ hbScan' = Inc(nScan) /\ doneAge' = Inc(nDone)
    /\ hang' = nHang
    /\ slowAlerted' = nSlow
    /\ wDownAge' = IF wUp THEN 0 ELSE Inc(wDownAge)
    /\ peerAlerted' = (peerAlerted \/ (PeerRuns /\ ~wUp /\ wDownAge > HB_MAX))
    /\ IF ~wUp
         THEN UNCHANGED <<failAge, alerted, wclock>>
       ELSE IF wclock = 0
         THEN /\ failAge' = nFail /\ alerted' = (alerted \/ (Down /\ HookOK)) /\ wclock' = WATCH_EVERY - 1
         ELSE /\ wclock' = wclock - 1 /\ UNCHANGED <<failAge, alerted>>
    /\ UNCHANGED <<mode, reach, wUp>>

(* 看守机下线（按最坏算，不再回来）。B1 的已知限制：这段时间 ops · 01 没人盯。       *)
WatcherDown ==
    /\ wUp /\ "down" \in WatcherFaults
    /\ wUp' = FALSE
    /\ UNCHANGED <<mode, reach, gateAge, hbAge, hbScan, doneAge, hang, failAge, wclock, alerted,
                   slowAlerted, wDownAge, peerAlerted>>

Next == Step \/ Fail \/ WatcherDown
Spec == Init /\ [][Next]_vars /\ WF_vars(Step)

(* P3：卡住检查停了（进程死 / 自动任务没跑 / 每次超时 / 每次出错），最终一定告警。 *)
P3 == (mode # "ok") ~> (alerted \/ slowAlerted)
(* 同一件事的时间版：最后一次跑完的扫描之后 BOUND 分钟还没告警就算违反。         *)
P3_BOUND == doneAge >= BOUND => alerted
(* 模型校准：一切正常时不误报（证明阈值和时序没写错）。                         *)
NoFalseAlarm == mode = "ok" => ~alerted
(* 看守机下线时：盯它的那条报出来。                                               *)
PW == (~wUp) ~> peerAlerted
(* 看守机也下线时的 P3：要么告警，要么有人知道看守机没了。                        *)
P3W == (mode # "ok") ~> (alerted \/ slowAlerted \/ peerAlerted)

=============================================================================
