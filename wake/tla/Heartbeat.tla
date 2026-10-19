------------------------------ MODULE Heartbeat ------------------------------
(***************************************************************************)
(* 卡住检查自己停了会不会告警（P3）。模型来自：                            *)
(*   scripts/stuck-check.sh   iMac「ops · 01 卡住工作检查」每分钟的 precheck  *)
(*                            （--scan，Orca 的 precheck timeoutSeconds 300） *)
(*   scripts/heartbeat-watch.sh  box「ops · 29」每 5 分钟，盯 ops · 01 的   *)
(*                            运行记录里的 @@HB 行（--target ...|20）         *)
(* 一步 = 1 分钟。stuck-check 的一次运行在模型里是一步（真实耗时最多约 4 分钟， *)
(* iMac 日志 10-16～10-19 最长 253 秒），卡死的运行占 5 分钟后被 Orca 杀掉。     *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS
    FailModes,   \* 允许出现的故障：dead / crash / hang
    Mutant,      \* "none" | "no_unreach_alert" | "scan_start"
    INTERVAL,    \* STUCK_INTERVAL_MIN = 15（stuck-check.sh:138）
    PRE_TIMEOUT, \* precheck timeoutSeconds 300 → 5 分钟（自动任务 439cd438 的配置）
    HB_MAX,      \* --target 的 N = 20（自动任务 94e4b0bc 的 precheck 参数）
    UNREACH,     \* HB_UNREACH_MIN = 45（heartbeat-watch.sh:34）
    WATCH_EVERY, \* ops · 29 的 rrule */5 → 5 分钟
    BOUND,       \* P3_BOUND：最后一次跑完的扫描之后多少分钟内必须已告警
    CAP

VARIABLES
    mode,      \* "ok" 或 FailModes 里的一种；坏了就一直坏（P3 讲的是「停了」）
    reach,     \* box 能不能查到 iMac Orca 的运行记录（mode = dead 时可能查不到）
    gateAge,   \* gate.json 的 last 距现在几分钟（stuck-check.sh:1777 在 main() 之前写）
    hbAge,     \* 运行记录里最新一行 @@HB 距现在几分钟
    hbScan,    \* 那行 @@HB 里的 last_scan 距现在几分钟
    doneAge,   \* 最后一次真正跑完的扫描距现在几分钟 = gate.json 的 done（stuck-check.sh:1792-1793，main() 正常返回后才写）
    hang,      \* 一次卡住的运行还要占几分钟（Orca 到 300 秒杀掉）
    failAge,   \* heartbeat-watch 的 fail_since 距现在几分钟（查不到运行记录时）
    wclock,    \* 距 heartbeat-watch 下一次运行还有几分钟
    alerted    \* heartbeat-watch 已经成功报过 heartbeat_stale（state.json 的 alerted）

vars == <<mode, reach, gateAge, hbAge, hbScan, doneAge, hang, failAge, wclock, alerted>>

Inc(x) == IF x < CAP THEN x + 1 ELSE x
Add(x, k) == IF x + k < CAP THEN x + k ELSE CAP

Init ==
    /\ mode = "ok" /\ reach = TRUE
    /\ gateAge \in 0..(INTERVAL - 1)
    /\ hbAge = 0 /\ hbScan = gateAge /\ doneAge = gateAge
    /\ hang = 0 /\ failAge = 0
    /\ wclock \in 0..(WATCH_EVERY - 1)
    /\ alerted = FALSE

(* 出故障（之后不恢复）。dead = Orca 调度器停了 / 自动任务没在跑 / iMac Orca 挂了   *)
(* （可能连运行记录也查不到）；crash = main() 每次都抛异常；hang = main() 每次都超过 *)
(* precheck 的 300 秒被杀。                                                    *)
Fail ==
    /\ mode = "ok"
    /\ \E m \in FailModes :
         /\ mode' = m
         /\ reach' \in (IF m = "dead" THEN BOOLEAN ELSE {TRUE})
    /\ UNCHANGED <<gateAge, hbAge, hbScan, doneAge, hang, failAge, wclock, alerted>>

(* ops · 01 这一分钟的 precheck（stuck-check.sh:1755-1795）。                    *)
(*   闸门没开（距 gate.last 不到 INTERVAL）：heartbeat(1)，@@HB 的 last_scan =   *)
(*     gate.json 的 done（:1758-1762, :1732）。                                    *)
(*   闸门开：先写 gate.json last=NOW、done 照旧（:1777），再 main()（:1782）：     *)
(*     ok    → 写 done=NOW（:1792-1793），heartbeat(rc)，last_scan = done（:1794）  *)
(*     crash → except：rc=4，--scan 时改成 rc=0，done 不变，照样 heartbeat         *)
(*             （:1783-1794）                                                     *)
(*     hang  → 300 秒后被 Orca 杀掉，这次没有 @@HB、done 不变；锁随进程释放        *)
(* Mutant "scan_start"：修之前的代码（PER-67 F7、F8），last_scan 取扫描开始时写的 *)
(*   gate.last，被杀、出错也照样前进。                                            *)
(* 上一个卡住的运行没结束前，Orca 不再起这个 precheck（按不重叠算，心跳更少，     *)
(* 对告警更有利）。                                                            *)
Blocked  == mode = "dead" \/ hang > 0
GateOpen == ~Blocked /\ gateAge >= INTERVAL
PrintsHB == ~Blocked /\ (~GateOpen \/ mode \in {"ok", "crash"})
nGate == IF GateOpen THEN 0 ELSE gateAge
nHb   == IF PrintsHB THEN 0 ELSE hbAge
nDone == IF GateOpen /\ mode = "ok" THEN 0 ELSE doneAge
nScan == IF ~PrintsHB THEN hbScan
         ELSE IF Mutant = "scan_start" THEN (IF GateOpen THEN 0 ELSE gateAge)
         ELSE nDone
nHang == IF hang > 0 THEN hang - 1 ELSE IF GateOpen /\ mode = "hang" THEN PRE_TIMEOUT - 1 ELSE 0

(* heartbeat-watch.sh main()（:188-257），每 WATCH_EVERY 分钟一次。查不到运行记录： *)
(* fail_since 起算，满 UNREACH 分钟才算中断（:195-203）；查到了：最新 @@HB 超过    *)
(* HB_MAX 分钟（:223），或 last_scan 超过 HB_MAX + INTERVAL 分钟（:226）算中断。    *)
(* 中断且没报过 → POST coding-assistant（:233-245）；这里假设 Coding助手 的 webhook *)
(* 可用（发不出去时它每 5 分钟重试，不影响「最终告警」）。                       *)
(* Mutant "no_unreach_alert"：查不到运行记录时一直 continue（去掉 :199-201 的报警）。*)
nFail == IF reach THEN 0 ELSE Add(failAge, WATCH_EVERY)
Down  == IF ~reach THEN Mutant # "no_unreach_alert" /\ nFail >= UNREACH
         ELSE nHb > HB_MAX \/ nScan > HB_MAX + INTERVAL

Step ==
    /\ gateAge' = Inc(nGate) /\ hbAge' = Inc(nHb) /\ hbScan' = Inc(nScan) /\ doneAge' = Inc(nDone)
    /\ hang' = nHang
    /\ IF wclock = 0
         THEN /\ failAge' = nFail /\ alerted' = (alerted \/ Down) /\ wclock' = WATCH_EVERY - 1
         ELSE /\ wclock' = wclock - 1 /\ UNCHANGED <<failAge, alerted>>
    /\ UNCHANGED <<mode, reach>>

Next == Step \/ Fail
Spec == Init /\ [][Next]_vars /\ WF_vars(Step)

(* P3：卡住检查停了（进程死 / 自动任务没跑 / 每次超时 / 每次出错），最终一定告警。 *)
P3 == (mode # "ok") ~> alerted
(* 同一件事的时间版：最后一次跑完的扫描之后 BOUND 分钟还没告警就算违反。         *)
P3_BOUND == doneAge >= BOUND => alerted
(* 模型校准：一切正常时不误报（证明阈值和时序没写错）。                         *)
NoFalseAlarm == mode = "ok" => ~alerted

=============================================================================
