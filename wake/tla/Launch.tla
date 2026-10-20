------------------------------- MODULE Launch -------------------------------
(***************************************************************************)
(* agent 没起来时有没有人知道（PER-67 第 6 组，P6）。模型来自：              *)
(*   wake/bin/orca-agent-launch  参数检查没过（退出码 2 / 3）时 wake_reject     *)
(*                               （:51-58，die :59，Linear 写不进去 :162）      *)
(*   wake/bin/notify-run         --tty 包住 claude、带提示词时的 start_watch     *)
(*                               （:165-176，起 :226-232，agent_started :152）  *)
(* 实例：10-19 07:24 iMac term_b8179e9b，--eta 写成 09:30 被拒，没有 notify-run， *)
(* 没有会话，wake.log 里什么都没有。                                         *)
(* 一步 = 1 分钟。派活 bot = ops-bot（任意一个），Coding助手 的 webhook 一直可用 *)
(* （和 P4 一样的前提：兜底通道本身是好的）。                               *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS
    Mutant,   \* "none" | "old"（修之前：两处都不叫醒）| "no_fallback"（只发派活 bot，发不出去不改发 Coding助手）
    START,    \* NOTIFY_RUN_START_MIN = 5
    CAP

VARIABLES
    st,        \* "cmd"（终端里敲了 orca-agent-launch）| "rejected"（检查没过，exit 2/3，什么都没起）
               \* | "hung"（notify-run 起了 claude，一直没有第 1 个回合）| "started"（第 1 个回合出现了）
    t,         \* hung 之后过了几分钟（封顶 CAP）
    up,        \* 派活 bot 的 webhook 现在能不能收
    sent,      \* 已经发过（两处都只发一次）
    notified   \* 有 bot 2xx 收到了「没起来」

vars == <<st, t, up, sent, notified>>

Init == st = "cmd" /\ t = 0 /\ up \in BOOLEAN /\ sent = FALSE /\ notified = FALSE

(* 起 agent 的结果：被拒 / 起了但一直不出第 1 个回合 / 正常起来。 *)
Launch ==
    /\ st = "cmd"
    /\ st' \in {"rejected", "hung", "started"}
    /\ UNCHANGED <<t, up, sent, notified>>

(* 一次发送：先发派活 bot，不通就改发 coding-assistant（一直可用）。 *)
Deliver == up \/ Mutant # "no_fallback"

(* orca-agent-launch 拒绝时马上发（die → wake_reject，发完才 exit）。 *)
RejectWake ==
    /\ st = "rejected" /\ ~sent /\ Mutant # "old"
    /\ sent' = TRUE /\ notified' = Deliver
    /\ UNCHANGED <<st, t, up>>

(* notify-run 的 start_watch：sleep START 分钟后，agent 还在、没有第 1 个回合 → 发一次。 *)
WatchWake ==
    /\ st = "hung" /\ t >= START /\ ~sent /\ Mutant # "old"
    /\ sent' = TRUE /\ notified' = Deliver
    /\ UNCHANGED <<st, t, up>>

(* agent 晚一点起来了（在 START 之前），start_watch 看到第 1 个回合就不发。 *)
LateStart ==
    /\ st = "hung" /\ t < START
    /\ st' = "started"
    /\ UNCHANGED <<t, up, sent, notified>>

(* 过 1 分钟。start_watch 的 sleep 到点就发，不会拖过下一分钟（修后才有这一步）。 *)
Tick ==
    /\ st = "hung" /\ t < CAP
    /\ (t < START \/ sent \/ Mutant = "old")
    /\ t' = t + 1
    /\ UNCHANGED <<st, up, sent, notified>>

WebhookFlip ==
    /\ up' = ~up
    /\ UNCHANGED <<st, t, sent, notified>>

Next == Launch \/ RejectWake \/ WatchWake \/ LateStart \/ Tick \/ WebhookFlip
Spec == Init /\ [][Next]_vars /\ WF_vars(Launch) /\ WF_vars(RejectWake) /\ WF_vars(WatchWake) /\ WF_vars(Tick)

(* P6：agent 没起来（被拒，或一直不出第 1 个回合），最终有 bot 收到；或者它后来起来了   *)
(* （之后由 P1 那条叫醒链负责）。                                                    *)
P6 == (st \in {"rejected", "hung"}) ~> (notified \/ st = "started")
(* 同一件事的时间版：一直没起来的，START + 1 分钟内已经有人收到。 *)
P6_BOUND == (st = "hung" /\ t > START) => notified

=============================================================================
