---------------------------------- MODULE MC ----------------------------------
(* TLC 的 cfg 写不了函数，派活 bot / task-main 组合在这里定义，cfg 里用 <- 代入。 *)
EXTENDS Wake

AnyDisp  == [Tasks -> Bots]                       \* 所有派活组合
AnyKind  == [Tasks -> {"task", "main"}]           \* 任务工作区或 ops 主目录，所有组合
OpsThenCA == {<<"ops-bot", "coding-assistant">>}  \* P5：任务 1 派给 ops-bot，任务 2 派给 Coding助手
BothTask == {<<"task", "task">>}
AnyPhase == 0..FULL_TICKS
AnyWork  == BOOLEAN
WithWork == {TRUE}
AllTasks == Tasks
OnlyT2   == {2}                                  \* P5：任务 1 只会退出（挡路的那条 agent_gone）
===============================================================================
