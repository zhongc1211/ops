# 卡住检查和心跳互查（stuck-check.sh、heartbeat-watch.sh）

Orca 自动任务每 15 分钟跑一次卡住检查：in-progress 的工作区里，agent 进程没了（agent_gone）、停在输入框太久（agent_idle）、进程在但终端太久没输出（agent_silent），就叫醒负责的 bot；同一工作区没有新活动只报一次。卡住检查每次打 `@@HB` 心跳，另一台机器上的 heartbeat-watch 读它，心跳过期就叫醒 ops-system，恢复后报一次。

## Sub-features

- `SC1` agent_gone：工作区有终端、进程表里没有 agent、2 小时没活动 → 恰好 1 条。
- `SC2` agent_idle：进程在，Orca 状态 done，终端停在输入框（tui-idle），2 小时 → 先问被测目录的 `orca-wake recheck`，它回 `no_state_for_pid` 后按老办法报，恰好 1 条。
- `SC3` agent_silent：进程在，Orca 状态 working，终端 2 小时没新输出 → 恰好 1 条。
- `SC4` 三条都是 `source=stuck-check status=stuck`；第 2 次检查（夹具不变）不再报。
- `SC5` 两次检查都在 stdout 打 `@@HB {…}`。
- `HB1` 回放的最新心跳在 30 分钟前（阈值 20）→ ops-system 收到 1 条 `heartbeat_stale`；再查不重复。
- `HB2` 心跳回到 2 分钟前 → 1 条 `heartbeat_recovered`。

## How to get to it (user POV)

- 「ops · 01 卡住工作检查」自动任务：`scripts/stuck-check.sh --scan` 当 precheck，复核后 `--send`；codex 备用和手动运行用不带参数（查一遍直接发）。
- 心跳互查自动任务：`scripts/heartbeat-watch.sh --precheck --target "名字|environment|自动任务 id|N"`。

## Driving it with verify.sh

Preconditions: 沙箱 PATH 里 `orca` / `orca-ide` 是 `vo.py orca`（`terminal wait` 对名字含 `idle` 的终端回 satisfied，其余交给 `wake/tests/fake_orca.py`）；`vo.py stuck-fixture` 写 `$SB/orca.json`（3 个 in-progress 工作区 `/fake/ws/verify-gone|idle|silent`）和 `$SB/probe.json`（两个本次起的 `sleep 600` 当 idle、silent 的 agent 进程）。

- 跑：`bash .claude/skills/verify-ops/verify.sh run stuck-check`（约 10 秒）。
- stuck-check 不带参数跑两次，环境：`STUCK_STATE_DIR=$SB/stuck-state`、`STUCK_WEBHOOK_DIR=$HOME/.config/grokbot/webhooks`（沙箱）、`STUCK_PROBE=$SB/bin/agent-probe.py`、`STUCK_ORCA_WAKE=<被测目录>/wake/bin/orca-wake`、`STUCK_MBA_ENV=`（不查 MBA）、`STUCK_POST_GAP=0`。
- 结果：`vo.py count "$SB/mock/a.jsonl" kind=agent_gone task=verify-gone worktree=iMac:/fake/ws/verify-gone` 为 1 且 `kind=agent_gone` 总数为 1；idle、silent 同理；第 2 次后 `source=stuck-check status=stuck` 仍是 3。
- heartbeat-watch：`HB_ORCA=wake/tests/hb-replay/orca`、`HB_STATE_DIR=$SB/hb-state`、目标 `ops01-卡住检查||439cd438-cffe-44dd-bd2b-23b07bfa3d61|20`（回放夹具里的自动任务 id），先 `HB_REPLAY_AGE_S=1800` 跑两次，再 `HB_REPLAY_AGE_S=120` 跑一次。

## Gotchas

- `STUCK_PROBE` 是用 python 跑的（`[sys.executable, PROBE]`），不能指向 shell 脚本；假 probe 是 `$SB/bin/agent-probe.py`。
- stuck-check 先找 `orca-ide` 再找 `orca`；`wake/tests/fake-orca/` 里也有 `orca-ide`，所以沙箱 `bin` 里两个名字都要放替身，否则 tui-idle 永远是 timeout，agent_idle 测不到。
- 映射文件按 `~/orca/workspaces/ops/orca-projects.md` 读，沙箱 HOME 里没有，日志会说「bot 一律记为未映射」，消息都转给 coding-assistant。断言因此只看 kind / task / worktree，不看派活 bot。
- agent_idle 必须真的经过 orca-wake：`STUCK_ORCA_WAKE=/usr/bin/false`（wake/tests 里的写法）会让 recheck 失败、这次不报。用被测目录的真 orca-wake + 沙箱的 `ORCA_WAKE_STATE_DIR`，它回 `no_state_for_pid`。
- 夹具里的时间是「现在 − 2 小时」，阈值用默认（gone 10 分钟、idle 30 分钟），不改阈值。
- 这些是外部边界替身：Orca CLI（假 orca + 夹具）、agent-probe 读的进程表、heartbeat 读的运行记录（回放）。stuck-check.sh、heartbeat-watch.sh、orca-wake 都是真脚本。
