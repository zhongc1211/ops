-------------------------------- MODULE Wake --------------------------------
(***************************************************************************)
(* 叫醒链路模型（PER-67）。模型来自代码，不是文档；每个动作上方写了对应的  *)
(* 文件:行号（行号对应 wake/tla/README.md 里记的 commit 和 sha256）。     *)
(*                                                                         *)
(* 一个「任务」= orca-agent-launch 经 notify-run --tty 起的一个 agent 会话  *)
(* （wake/bin/orca-agent-launch:77-79,131）。每个任务在模型里只停一次：     *)
(* 停在输入框（paused）或退出（exited），之后可以从 paused 再退出。         *)
(* 叫醒有四条路：                                                          *)
(*   NR  notify-run 退出时 POST（wake/bin/notify-run:119-131）             *)
(*   OW  orca-wake 的 Stop / idle_prompt hook，detached _deliver 进程发     *)
(*       （wake/bin/orca-wake:724-739,764-779,370-423,475-554）            *)
(*   RC  卡住检查调 orca-wake recheck 补叫醒（scripts/stuck-check.sh:      *)
(*       996-1002,1027-1069 + orca-wake:990-1014），和 OW 共用去重键      *)
(*   SC  卡住检查自己 POST：agent_gone 给派活 bot（stuck-check.sh:1047-1061,  *)
(*       1589-1615），「报了没人验收」给 Coding助手（:1729-1747,1364-1458） *)
(*                                                                         *)
(* 时间：一个 Tick = 15 分钟 = 一次卡住检查扫描（stuck-check.sh:141        *)
(* INTERVAL_MIN，闸门 :1694）。一次 POST 连重试都在 1～2 分钟内（notify-run 20s+45s，   *)
(* orca-wake 20s+45s，stuck-check 5/15/45s），所以 Tick 要等在途的发送都结束 *)
(* 才走。webhook 是否可用用 up[b] 表示，随时可以变；down 时每次 POST 返回 *)
(* 0（curl 000 / 超时 / 连不上）或 500。                                    *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS
    NT,            \* 任务数
    NR_TRIES,      \* notify-run 的 NOTIFY_RUN_TRIES，默认 3（notify-run:119）
    OW_TRIES,      \* orca-wake 非限流失败的总次数 = 1 + len(RETRY_DELAYS "20,45") = 3（orca-wake:79,539-543）
    GONE_TICKS,    \* STUCK_GONE_MIN 10 分钟 → 至少 1 个 Tick（stuck-check.sh:115,1055）
    IDLE_TICKS,    \* STUCK_IDLE_MIN 30 分钟 → 2 个 Tick（stuck-check.sh:114,1063；orca-wake --idle-min 30）
    ACCEPT_TICKS,  \* 「标完成超过 1 小时」→ 4 个 Tick（stuck-check.sh:112 THRESH_H，check_reported）
    FULL_TICKS,    \* 第二类约每小时查一次：NOW - last_full >= 55 分钟 → 每 4 次扫描（stuck-check.sh:1729）
    LATE_TICKS,    \* P4 的「超过 1 小时」：停下后第 5 个 Tick 起（60～75 分钟）
    CAP,           \* 计数器封顶，保持状态有限
    CA_ALWAYS_UP,  \* TRUE：Coding助手 的 webhook 一直可用（P4 用）
    Mutant,        \* 故意改坏的变体，"none" = 现在的代码
    Fixes,         \* 假设的修法（只在模型里，证明性质不是空的），{} = 现在的代码
    DISPS,         \* 允许的派活 bot 组合（每个是 1..NT -> Bots 的元组）
    KINDS,         \* 允许的 task/main 组合
    FULL0,         \* 第一次扫描前距上次第二类检查的 Tick 数（相位）
    MayPause,      \* 哪些任务可以停在输入框（场景限制，Tasks = 不限）
    MayComplete,   \* 哪些任务可以标 completed（场景限制，Tasks = 不限）
    HASWORK,       \* 任务工作区做完后有没有要验收的东西（PR / 提交 / 改动）的可选值
    FailCodes      \* webhook 不可用时一次 POST 的 http：0 = curl 000 / 超时 / 连不上，500 = 非 2xx

CA   == "coding-assistant"
Bots == {"ops-bot", CA}
Tasks == 1..NT
OK == 200

VARIABLES
    disp,      \* 每个任务的派活 bot（--bot），整个行为里不变
    work,      \* 任务工作区有要验收的东西（PR、本地提交或未提交改动）；整个行为里不变
    kind,      \* "task" = 任务工作区；"main" = ops 主目录里按终端查的 agent（stuck-check.sh:883-919）
    agent,     \* "running" | "paused" | "exited"
    ws,        \* 工作区看板状态 "in-progress" | "completed"
    up,        \* 每个 bot 的 webhook 现在能不能收（2xx）
    nr,        \* notify-run 发送：[ph: none|sending|ok|failed, n: 第几次, last: 最后一次的 http]
    ow,        \* orca-wake 这次停顿的发送任务：[ph: none|inflight|sent|failed, n, src: hook|recheck, last]
    idlep,     \* 这次停顿的 idle_prompt 通知已经来过
    woken,     \* orca-wake 会话状态里的 woken[seq]（orca-wake:358-365，只在 2xx 后写）
    known,     \* stuck-check agents.json 里这个 key 的记录：none | notified_ow | notified | dismissed
    scLast,    \* stuck-check 最后一次为这个任务 POST 的 http
    seen2,     \* stuck-check notified.json：第二类已报过
    esc,       \* 已升级 Coding助手（EscCand，PER-67 F4、F6）
    accepted,  \* 真相（ghost）：哪些 bot 对这个任务的这次停下返回过 2xx
    age,       \* 停下后过了几个 Tick（封顶 CAP）
    cage,      \* 标 completed 后过了几个 Tick
    fullAge,   \* 距上次第二类检查几个 Tick
    scanned    \* 这个 Tick 里已经扫描过

vars == <<disp, work, kind, agent, ws, up, nr, ow, idlep, woken, known, scLast, seen2, esc,
          accepted, age, cage, fullAge, scanned>>

Inc(x) == IF x < CAP THEN x + 1 ELSE x
Codes(b) == IF up[b] THEN {OK} ELSE FailCodes

TypeOK ==
    /\ disp \in [Tasks -> Bots]
    /\ kind \in [Tasks -> {"task", "main"}]
    /\ agent \in [Tasks -> {"running", "paused", "exited"}]
    /\ ws \in [Tasks -> {"in-progress", "completed"}]
    /\ up \in [Bots -> BOOLEAN]
    /\ known \in [Tasks -> {"none", "notified_ow", "notified", "dismissed"}]
    /\ accepted \in [Tasks -> SUBSET Bots]
    /\ age \in [Tasks -> 0..CAP] /\ cage \in [Tasks -> 0..CAP]

Init ==
    /\ disp \in DISPS
    /\ kind \in KINDS
    /\ work \in [Tasks -> HASWORK]
    /\ agent = [t \in Tasks |-> "running"]
    /\ ws = [t \in Tasks |-> "in-progress"]
    /\ up \in [Bots -> BOOLEAN]
    /\ (CA_ALWAYS_UP => up[CA])
    /\ nr = [t \in Tasks |-> [ph |-> "none", n |-> 0, last |-> 0]]
    /\ ow = [t \in Tasks |-> [ph |-> "none", n |-> 0, src |-> "hook", last |-> 0]]
    /\ idlep = [t \in Tasks |-> FALSE]
    /\ woken = [t \in Tasks |-> FALSE]
    /\ known = [t \in Tasks |-> "none"]
    /\ scLast = [t \in Tasks |-> 0]
    /\ seen2 = [t \in Tasks |-> FALSE]
    /\ esc = [t \in Tasks |-> FALSE]
    /\ accepted = [t \in Tasks |-> {}]
    /\ age = [t \in Tasks |-> 0]
    /\ cage = [t \in Tasks |-> 0]
    /\ fullAge \in FULL0
    /\ scanned = FALSE

NewJob(src) == [ph |-> "inflight", n |-> 0, src |-> src, last |-> 0]

(* ---------------------------------------------------------------- agent *)

(* Claude 回合结束，停在输入框。Stop hook：没有后台任务、没有排队的后续回合时 *)
(* 建 idle 任务（orca-wake:724-739），dispatch_send 认领去重键并起 detached   *)
(* 发送进程（orca-wake:370-423）。有后台任务 / queued_followup / hook 没跑到时 *)
(* 不发（orca-wake:731-736），用 hookFired = FALSE 表示。                    *)
AgentPause(t) ==
    /\ agent[t] = "running" /\ t \in MayPause
    /\ agent' = [agent EXCEPT ![t] = "paused"]
    /\ \E hookFired \in BOOLEAN :
         ow' = [ow EXCEPT ![t] = IF hookFired THEN NewJob("hook") ELSE @]
    /\ age' = [age EXCEPT ![t] = 0]
    /\ UNCHANGED <<disp, work, kind, ws, up, nr, idlep, woken, known, scLast, seen2, esc, accepted, cage, fullAge, scanned>>

(* agent 进程退出（做完 /exit、崩溃、被 kill）。notify-run 的 wait 返回        *)
(* （notify-run:196-205），EXIT trap → finish → send_webhook（notify-run:144-158）。*)
AgentExit(t) ==
    /\ agent[t] \in {"running", "paused"}
    /\ agent' = [agent EXCEPT ![t] = "exited"]
    /\ nr' = [nr EXCEPT ![t] = [ph |-> "sending", n |-> 0, last |-> 0]]
    /\ age' = [age EXCEPT ![t] = IF agent[t] = "running" THEN 0 ELSE @]
    /\ UNCHANGED <<disp, work, kind, ws, up, ow, idlep, woken, known, scLast, seen2, esc, accepted, cage, fullAge, scanned>>

(* agent 做完时把任务工作区标 completed（之后再停下 / 退出）。              *)
MarkCompleted(t) ==
    /\ agent[t] = "running" /\ kind[t] = "task" /\ ws[t] = "in-progress" /\ t \in MayComplete
    /\ ws' = [ws EXCEPT ![t] = "completed"]
    /\ cage' = [cage EXCEPT ![t] = 0]
    /\ UNCHANGED <<disp, work, kind, agent, up, nr, ow, idlep, woken, known, scLast, seen2, esc, accepted, age, fullAge, scanned>>

(* ---------------------------------------------------------------- notify-run *)

(* 一次 curl POST。notify-run:122-130：http=$(curl ... -w '%{http_code}')；     *)
(* log_send 写一行 http=...（:126）；case "$http" in 2??) exit 0（:127）；       *)
(* 第 NOTIFY_RUN_TRIES 次还不行 exit 1（:128）。                               *)
(* Mutant "nr_any_http"：把 :127 的模式 2?? 换成 ?* ，任何非空（含 000）都算成功。 *)
NrAttempt(t) ==
    /\ nr[t].ph = "sending"
    /\ \E code \in Codes(disp[t]) :
         LET ok == IF Mutant = "nr_any_http" THEN TRUE ELSE code = OK
             n1 == nr[t].n + 1
         IN /\ nr' = [nr EXCEPT ![t] = [ph |-> IF ok THEN "ok" ELSE IF n1 >= NR_TRIES THEN "failed" ELSE "sending",
                                        n |-> n1, last |-> code]]
            /\ accepted' = [accepted EXCEPT ![t] = IF code = OK THEN @ \cup {disp[t]} ELSE @]
    /\ UNCHANGED <<disp, work, kind, agent, ws, up, ow, idlep, woken, known, scLast, seen2, esc, age, cage, fullAge, scanned>>

(* ---------------------------------------------------------------- orca-wake *)

(* detached 发送进程的一次 POST（orca-wake:501-554）。ok = 200<=code<300（:518）；*)
(* ok → _mark_sent：写 sent/<sha1> 和 woken[seq]（:525-528,450-453）；         *)
(* 不 ok 且重试用完 → log failed（:541-548），inflight 文件删掉（:442-446）。   *)
(* Mutant "ow_any_http"：把 :518 改成 ok = code is not None（任何 HTTP 回答都算）。*)
OwAttempt(t) ==
    /\ ow[t].ph = "inflight"
    /\ \E code \in Codes(disp[t]) :
         LET ok == IF Mutant = "ow_any_http" THEN code # 0 ELSE code = OK
             n1 == ow[t].n + 1
         IN /\ ow' = [ow EXCEPT ![t] = [ph |-> IF ok THEN "sent" ELSE IF n1 >= OW_TRIES THEN "failed" ELSE "inflight",
                                        n |-> n1, src |-> ow[t].src, last |-> code]]
            /\ woken' = [woken EXCEPT ![t] = IF ok THEN TRUE ELSE @]
            /\ accepted' = [accepted EXCEPT ![t] = IF code = OK THEN @ \cup {disp[t]} ELSE @]
    /\ UNCHANGED <<disp, work, kind, agent, ws, up, nr, idlep, known, scLast, seen2, esc, age, cage, fullAge, scanned>>

(* Claude 约 60 秒没操作发 idle_prompt（orca-wake:764-779），同一个去重键再走  *)
(* dispatch_send：sent 已有 → already_sent（:378-380）；inflight 活着 → 跳过    *)
(* （:390-397）；否则重新认领、再发。没有公平性：idle_prompt 可能不来。      *)
IdlePrompt(t) ==
    /\ agent[t] = "paused" /\ ~idlep[t]
    /\ idlep' = [idlep EXCEPT ![t] = TRUE]
    /\ ow' = [ow EXCEPT ![t] = IF @.ph \in {"none", "failed"} THEN NewJob("hook") ELSE @]
    /\ UNCHANGED <<disp, work, kind, agent, ws, up, nr, woken, known, scLast, seen2, esc, accepted, age, cage, fullAge, scanned>>

(* ---------------------------------------------------------------- webhook 环境 *)

WebhookDown(b) ==
    /\ up[b] /\ ~(b = CA /\ CA_ALWAYS_UP)
    /\ up' = [up EXCEPT ![b] = FALSE]
    /\ UNCHANGED <<disp, work, kind, agent, ws, nr, ow, idlep, woken, known, scLast, seen2, esc, accepted, age, cage, fullAge, scanned>>

WebhookUp(b) ==
    /\ ~up[b]
    /\ up' = [up EXCEPT ![b] = TRUE]
    /\ UNCHANGED <<disp, work, kind, agent, ws, nr, ow, idlep, woken, known, scLast, seen2, esc, accepted, age, cage, fullAge, scanned>>

(* ---------------------------------------------------------------- stuck-check *)

(* 第一类 agent_gone（stuck-check.sh:1047-1061）：任务工作区 in-progress、agent 进程 *)
(* 不在、安静超过 STUCK_GONE_MIN、agents.json 里没有记录（:952-956）。          *)
(* ops 主目录（kind = "main"）里退出的 agent：包了 notify-run 的，notify-run.log 里  *)
(* 这个终端（pane）那次退出发送明确失败了才报（:963-979 → wrapped_exit，agent-probe *)
(* 带回 notify-run.log；PER-67 F2）。Mutant "main_skip"：修之前的代码，包了的一律不报。*)
Gone(t) ==
    /\ agent[t] = "exited" /\ age[t] >= GONE_TICKS /\ known[t] = "none"
    /\ \/ kind[t] = "task" /\ ws[t] = "in-progress"
       \/ Mutant # "main_skip" /\ kind[t] = "main" /\ nr[t].ph = "failed"

(* 停在输入框超过 STUCK_IDLE_MIN，交给 orca-wake recheck（stuck-check.sh:1063-1087, *)
(* wake_recheck :553-609）。主目录不看 workspaceStatus（:883-919,923-925）。     *)
IdleCand(t) ==
    /\ agent[t] = "paused" /\ age[t] >= IDLE_TICKS /\ known[t] = "none"
    /\ (kind[t] = "main" \/ ws[t] = "in-progress")

(* 第二类「报了没人验收」（check_reported，stuck-check.sh:1364-1458；合并成一条 *)
(* 发 Coding助手，cfg "stuck"，:1729-1747）：completed、标完成超过 1 小时、agent *)
(* 没在工作。「已验收」在模型里 = 有 bot 收到过这次停下（假设收到的 bot 一小时内 *)
(* 会 review / 评论 / 归档）。                                                 *)
(* 工作区干净、没有本地提交、没有 PR 的（work = FALSE）：只在最后一次停下送达过    *)
(* 叫醒时放行（:1344-1356，GIT_FACTS 里的 WAKEPY :1183-1229 读 orca-wake 会话的     *)
(* woken[turn] 和之后 notify-run 的 2xx；PER-67 F3）。代码只认 orca-wake / notify-run *)
(* 的送达，比 accepted 窄（不认 stuck-check 自己的 agent_gone），只会多报不会少报， *)
(* 所以模型里按 accepted = {} 才报。                                            *)
(* Mutant "clean_pass"：修之前的代码，干净的一律放行。                           *)
RepCand(t, doFull) ==
    /\ doFull /\ ws[t] = "completed" /\ agent[t] # "running"
    /\ cage[t] >= ACCEPT_TICKS /\ accepted[t] = {} /\ ~seen2[t]
    /\ (work[t] \/ Mutant # "clean_pass")

(* stuck-check 会去叫醒这个任务（agent_gone / ws_broken 自己 POST，或 agent_idle 交给 orca-wake recheck）。 *)
ScTries(t) ==
    \/ kind[t] = "task" /\ ws[t] = "in-progress"
    \/ kind[t] = "main" /\ agent[t] = "paused"
    \/ Mutant # "main_skip" /\ kind[t] = "main" /\ nr[t].ph = "failed"

(* 升级到 Coding助手（PER-67 F4、F6）：                                                 *)
(*   发给派活 bot 的一条失败过、从这次停下起满 STUCK_ESCALATE_MIN 45 分钟 → 改发 coding-assistant  *)
(*   （send_all 的 escalate）；交给 orca-wake 的补叫醒交出过、从停下起满 45 分钟还没 already_woken  *)
(*   → 转报 coding-assistant（wake_recheck 结果处理）。第一次尝试在停下后 10～30 分钟，都早于 45 分钟，*)
(*   所以模型里写成停下后 ESC_TICKS = 3 个 Tick（45 分钟）起、stuck-check 会去叫醒它（ScTries）。     *)
(*   completed / in-review 的任务工作区：最后一次停下没送达过叫醒、已 45 分钟 → 直接报 coding-assistant *)
(*   （check_undelivered，每次扫描都查，不等第二类）。                                          *)
(* 代码只认 orca-wake / notify-run 的送达（比 accepted 窄），也会对已有 bot 收到的任务改发，只会多报。 *)
(* Mutant "slow_escalate"：第 4 组的代码（从第一次失败 / 交出算，模型里写成 5 个 Tick，completed 不查）。*)
(* Mutant "no_escalate" / "old_send_all"：第 4 组之前的代码，没有这条路。                          *)
ESC_TICKS == IF Mutant = "slow_escalate" THEN 5 ELSE 3
EscCand(t) ==
    /\ agent[t] # "running" /\ accepted[t] = {} /\ ~esc[t]
    /\ Mutant \notin {"no_escalate", "old_send_all"} /\ age[t] >= ESC_TICKS
    /\ \/ disp[t] # CA /\ ScTries(t)
       \/ Mutant # "slow_escalate" /\ kind[t] = "task" /\ ws[t] = "completed"

(* recheck 的结果（orca-wake cmd_recheck :938-987，candidate :893-910）：         *)
(*   woken 有这次停顿 → already_woken → stuck-check 记 dismissed（:1151-1153）；  *)
(*   去重键 inflight → skip (inflight)（:1009-1012）→ 下次再查（:1166-1167）；      *)
(*   否则打印 "send idle" 并 gate_and_send（:1013-1014）→ 新的 detached 发送任务。   *)
(* stuck-check 看到 "send" 只记 known[key] = {handed: NOW, via: orca-wake}（:1051-1068），*)
(* 不算叫醒过；带 handed 的 key 下次扫描不跳过（:952-956），再 recheck：送达过就是     *)
(* already_woken → dismissed，发送失败就重新认领同一个去重键再发（PER-67 F1）。        *)
(* 模型里 known 保持 none 即「下次再 recheck」。                                      *)
(* Mutant "sc_handoff"：修之前的代码，看到 send 就记 notified，之后一直跳过。          *)
RecheckOW(t) ==
    IF ~IdleCand(t) THEN ow[t]
    ELSE IF woken[t] \/ ow[t].ph = "inflight" THEN ow[t]
    ELSE NewJob("recheck")
RecheckKnown(t) ==
    IF ~IdleCand(t) THEN known[t]
    ELSE IF woken[t] THEN "dismissed"
    ELSE IF ow[t].ph = "inflight" THEN known[t]
    ELSE IF Mutant # "sc_handoff" THEN known[t]
    ELSE "notified_ow"

(* send_all（stuck-check.sh:1534-1617）：先 direct（第二类合并的一条、以前没发出去的），*)
(* 再 suspects（agent_gone）。一条 post 重试后仍失败 → 这次运行里发给同一个目标的不再发，    *)
(* 发给别的目标的照发（broken 是目标的集合，:1564-1567,1608-1611；PER-67 F5），留到下次。     *)
(* post（:295-309）：200<=code<300 才算成功。                                            *)
(* Mutant "old_send_all"：修之前的代码，一条失败其余全停，也没有 F4 的改发。               *)
(* 一次 post 连 3 次重试约 65 秒：模型里按「这一刻 up[to] 决定」折叠成一步。        *)
(* Mutant "sc_any_http"：把 :303 改成 ok = isinstance(code, int)。                    *)
(* Fix "no_hol"：一条失败不挡后面的。                                              *)
Scan ==
    /\ ~scanned
    /\ LET doFull == fullAge >= FULL_TICKS
           rep == {t \in Tasks : RepCand(t, doFull)}
           RepItem == IF rep # {} THEN <<[k |-> "rep", t |-> 0, to |-> CA]>> ELSE <<>>
           EscItems == SelectSeq([i \in Tasks |-> [k |-> "esc", t |-> i, to |-> CA]], LAMBDA x : EscCand(x.t))
           GoneItems == SelectSeq([i \in Tasks |-> [k |-> "gone", t |-> i, to |-> disp[i]]], LAMBDA x : Gone(x.t))
           items == RepItem \o EscItems \o GoneItems
           L == Len(items)
       IN \E fc \in [1..L -> FailCodes] :
          LET code(i) == IF up[items[i].to] THEN OK ELSE fc[i]
              okc(c) == IF Mutant = "sc_any_http" THEN c # 0 ELSE c = OK
              \* res[i]：TRUE = 发了且算成功；FALSE = 发了失败或被前面的失败挡住
              att[i \in 1..L] == IF i = 1 \/ "no_hol" \in Fixes THEN TRUE
                                 ELSE IF Mutant = "old_send_all" THEN att[i-1] /\ okc(code(i-1))
                                 ELSE \A j \in 1..(i-1) : items[j].to = items[i].to => (att[j] /\ okc(code(j)))
              posted(i) == att[i]
              good(i) == posted(i) /\ okc(code(i))
              real(i) == posted(i) /\ code(i) = OK
              gotT(t, k) == {i \in 1..L : items[i].k = k /\ items[i].t = t}
              repI == {i \in 1..L : items[i].k = "rep"}
          IN
          /\ ow' = [t \in Tasks |-> RecheckOW(t)]
          /\ known' = [t \in Tasks |->
                IF \E i \in gotT(t, "gone") : good(i) THEN "notified" ELSE RecheckKnown(t)]
          /\ scLast' = [t \in Tasks |->
                IF \E i \in gotT(t, "gone") : posted(i) THEN code(CHOOSE i \in gotT(t, "gone") : TRUE) ELSE scLast[t]]
          /\ seen2' = [t \in Tasks |-> IF t \in rep /\ \E i \in repI : good(i) THEN TRUE ELSE seen2[t]]
          /\ esc' = [t \in Tasks |-> IF \E i \in gotT(t, "esc") : good(i) THEN TRUE ELSE esc[t]]
          /\ accepted' = [t \in Tasks |-> accepted[t]
                \cup (IF \E i \in gotT(t, "gone") : real(i) THEN {disp[t]} ELSE {})
                \cup (IF (t \in rep /\ \E i \in repI : real(i)) \/ (\E i \in gotT(t, "esc") : real(i)) THEN {CA} ELSE {})]
          /\ fullAge' = IF doFull THEN 0 ELSE fullAge
    /\ scanned' = TRUE
    /\ UNCHANGED <<disp, work, kind, agent, ws, up, nr, idlep, woken, age, cage>>

(* 过 15 分钟。在途的 POST（最多约 1～2 分钟）都已结束。                       *)
Tick ==
    /\ scanned
    /\ \A t \in Tasks : nr[t].ph # "sending" /\ ow[t].ph # "inflight"
    /\ scanned' = FALSE
    /\ age' = [t \in Tasks |-> IF agent[t] # "running" THEN Inc(age[t]) ELSE age[t]]
    /\ cage' = [t \in Tasks |-> IF ws[t] = "completed" THEN Inc(cage[t]) ELSE cage[t]]
    /\ fullAge' = IF fullAge < FULL_TICKS THEN fullAge + 1 ELSE fullAge
    /\ UNCHANGED <<disp, work, kind, agent, ws, up, nr, ow, idlep, woken, known, scLast, seen2, esc, accepted>>

Next ==
    \/ Tick \/ Scan
    \/ \E t \in Tasks : AgentPause(t) \/ AgentExit(t) \/ MarkCompleted(t)
                        \/ NrAttempt(t) \/ OwAttempt(t) \/ IdlePrompt(t)
    \/ \E b \in Bots : WebhookDown(b) \/ WebhookUp(b)

(* 公平性：扫描和时间一直往前走（卡住检查活着，P3 另查）；在途的发送进程会跑完。 *)
(* agent 不必停下；idle_prompt 不一定来；webhook 可以一直不可用（由性质的前提限定）。*)
Fairness ==
    /\ WF_vars(Tick) /\ WF_vars(Scan)
    /\ \A t \in Tasks : WF_vars(NrAttempt(t)) /\ WF_vars(OwAttempt(t))

Spec == Init /\ [][Next]_vars /\ Fairness

(* ================================================================ 性质 *)

Stopped(t)  == agent[t] # "running"
Accepted(t) == accepted[t] # {}

(* P1（brief 原话）：每个做完或卡住的任务，最终叫醒一个接收了的 bot，或升级叫醒   *)
(* Coding助手。前提：Coding助手 的 webhook 最终一直可用；派活 bot 可以一直坏。     *)
P1 == (<>[]up[CA]) => \A t \in Tasks : Stopped(t) ~> Accepted(t)

(* P1h（弱一档）：所有 bot 的 webhook 最终都一直可用（中断都是有限长的）。        *)
P1h == (\A b \in Bots : <>[]up[b]) => \A t \in Tasks : Stopped(t) ~> Accepted(t)

(* P5（从代码里找到的）：一个 bot 的 webhook 坏了，不挡别的 bot 的叫醒。          *)
(* 派给 Coding助手 的任务，只要 Coding助手 的 webhook 最终一直可用，就会被收到。   *)
P5 == (<>[]up[CA]) => \A t \in Tasks : (disp[t] = CA /\ Stopped(t)) ~> Accepted(t)

(* P2：发送失败绝不会被记成已叫醒 / 成功。分四处记录分别检查。                   *)
P2_NR == \A t \in Tasks : nr[t].ph = "ok" => nr[t].last = OK          \* notify-run exit 0 / notify-run.log
P2_OW == \A t \in Tasks : woken[t] => ow[t].last = OK                  \* sent/<sha1> + woken[seq]
P2_SC_POST == \A t \in Tasks : known[t] = "notified" => scLast[t] = OK  \* agents.json notified（stuck-check 自己 POST）
P2_SC_RECHECK == \A t \in Tasks :                                      \* agents.json notified via orca-wake
    ~(known[t] = "notified_ow" /\ ow[t].src = "recheck" /\ ow[t].ph = "failed")

(* P4：没有任务停下超过 1 小时、没有任何 bot 收到、也没叫醒 Coding助手。           *)
(* 前提 CA_ALWAYS_UP = TRUE（升级通道本身是好的）。                              *)
P4 == \A t \in Tasks : ~(Stopped(t) /\ age[t] >= LATE_TICKS /\ accepted[t] = {})

=============================================================================
