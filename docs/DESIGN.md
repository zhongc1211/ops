# 设计

本文由方案 v5（v4 正文 + v5 修订）整理，并按实现和测试中的发现做了补充。补充的地方标了「实现补充」。

## 问题

派活 bot 用 `notify-run --tty` 在终端里启动交互式 Claude Code 或 Pi。agent 做完停在输入框，不会自己退出；`notify-run` 只在进程退出时发 webhook，所以派活 bot 收不到通知。让 agent 自己 `/exit` 做不到；`claude -p` 没有交互、会话也不留存，不采用。

## 目标

- 不依赖 agent 自觉汇报。
- 会话保持可交互、可留存。
- Claude Code 和 Pi 都覆盖。
- 同一次停顿只叫一次。
- 漏发能被补上。

## 只处理派出的主会话

`notify-run --tty` 导出 `ORCA_DISPATCH_BOT`、`ORCA_TASK_ID`、`ORCA_DISPATCH_ISSUE`、`ORCA_DISPATCH_PID`（notify-run 自己的 pid）、`ORCA_DISPATCH_TS`；外层已经设置时不覆盖。

- Claude hook 命令以 `[ -z "${ORCA_DISPATCH_BOT:-}" ] ||` 开头，没有派活变量时直接结束，不写任何文件。
- hook 用 `WAKE_AGENT_PID=$PPID` 把 claude 进程的 pid 交给 orca-wake；Pi 扩展传 `process.pid`。
- orca-wake 校验「agent 的父进程 == `ORCA_DISPATCH_PID`」。嵌套的 `claude -p`、`pi -p`、`notify-run -- bash -c "...; claude"` 都不满足，跳过并在 `wake.log` 记 `parent_mismatch`。
- 实现补充：父进程直接从内核读（macOS 用 libproc `proc_pidinfo`，Linux 读 `/proc/<pid>/stat`），`ps` 只做后备。测试中机器负载很高时 `ps` 超过 5 秒超时，导致误判 `parent_mismatch`，因此改掉。
- 子 agent 只触发 SubagentStop，不在 hook 列表里。

## Claude Code

| 事件 | 处理 |
|---|---|
| UserPromptSubmit | 回合号加 1，清掉上一回合的 Stop 记录 |
| Stop | 记录 `last_assistant_message`、`background_tasks`、`session_crons`。有未完成的后台任务或 `session_crons` 非空 → 只记日志不叫；否则 status=idle |
| Notification `idle_prompt`（约 60 秒无操作） | 兜底。本回合已报 error → 不叫；本回合 Stop 时有后台 shell/monitor 或 crons → 不叫；其余发 idle（去重键与 Stop 相同，Stop 已发过就不会重复） |
| PermissionRequest | 记下工具名和问题，供下一条通知使用 |
| Notification `permission_prompt` | status=needs_input，正文是待确认的问题 |
| StopFailure | status=error，附错误类型 |
| Notification `quota_auto_resume_disabled` / `quota_auto_resume_stale` | status=blocked |

hook 全部 `async: true`、`timeout: 10`。orca-wake 判断完立即返回，发送交给独立进程。

实现补充：

- **发送进程**：不用 fork，改为启动一个新的 orca-wake 进程（新会话、标准输入输出接 /dev/null）。python.org 的 macOS Python 在部分启动方式下自带一个系统线程，fork 会报多线程警告，也有死锁风险。
- **Stop 后等待 8 秒**（`ORCA_WAKE_SETTLE_S`）：后台子 agent 刚结束、结果通知还在队列里时，Stop 看到的后台任务已经为空，但 Claude 马上会自动续一轮。等待期间若开始了新回合，这次叫醒作废（`superseded`），由新回合的 Stop 负责。
- **排队中的后续回合**：Stop 时 transcript 最后一条 `queue-operation` 是 `enqueue`（还没 `dequeue`），说明马上有续轮，这次不叫（`queued_followup`）。transcript 格式不是公开接口，所以这条规则只用来少叫一次，idle_prompt 和补叫醒仍然兜底。
- **另一个 Stop hook block 一次**：同一回合会出现两次 Stop。发送前重新读状态文件，用这一回合最后一次 Stop 的消息作为正文。
- 2.1.300 实测：要求 Agent 工具前台运行时，Stop 的 `background_tasks` 里仍有 `subagent: running`，按后台子 agent 处理（结果回来后的续轮再叫）。

## Pi

扩展 `~/.pi/agent/extensions/dispatch-wake.ts`（不用 `orca-` 前缀，避免被 Orca 的更新覆盖或删除）。

- 没有 `ORCA_DISPATCH_BOT`、或 `PI_SUBAGENT_CHILD=1`（pi-subagents 的后台 runner）→ 扩展不做任何事。
- `ctx.mode` 不是 `tui`（print、json、rpc）或会话有 `parentSession` → 跳过。
- `agent_settled` → idle；`agent_before_settle` 给出 `outcome=error` 时改发 error。
- 监听 `subagent:async-started` / `subagent:async-complete`：还有后台子代理在跑时只挂起；最后一个完成后等 10 秒，期间没有新的 `agent_start` 才发，否则由续轮的 `agent_settled` 负责。
- `ui_prompt_start` 后 6 秒仍未 `ui_prompt_end` → needs_input；6 秒内回答不发。
- 去重序号是停顿时会话 leaf entry 的 id。

## 去重

- 去重键 = `agent:session_id:status:停顿序号`。Claude 的序号是回合号（needs_input 为 `回合号.第几次权限请求`）；Pi 是 leaf entry id。
- webhook 返回 2xx 后才写已发标记（`sent/<sha1>`）。发送期间有 `inflight` 锁，防止 Stop 和 idle_prompt 同时发。
- 去重键写进 webhook 正文的 `dedup_key`，bot 端可以据此丢弃重复。
- 失败重试：共 3 次，间隔 20 秒、45 秒；全部失败写 `failed`，不写已发标记，留给补叫醒。
- 实现补充：needs_input 发出后不算「这一回合已叫醒」，否则用户在弹窗按 Esc 后，补叫醒会误认为已经叫过。

## webhook 正文

沿用 notify-run 的字段：`bot`、`task`、`issue`、`machine`、`exit_code`（固定 null）、`status`、`log_tail`（agent 最后一条消息，最多 4000 字）、`duration_s`。新增：

- `status`：idle / needs_input / error / blocked（notify-run 自己仍发 done / failed / killed）
- `source`：wake-hook / stuck-check-recheck（notify-run 发的是 notify-run）
- `dedup_key`、`agent`、`session_id`、`seq`、`note`、`worktree`（会话工作目录）、`orca_worktree_id`、`orca_terminal`、`wake_version`

## 补叫醒（卡住检查）

方案：只把现有卡住检查里的 agent_idle 一项改为「核对补叫醒」，agent_silent、agent_gone 等其他检测保留；排期改为每天运行、凌晨每小时一次。

- 卡住检查发现 agent 停在输入框时调用 `orca-wake recheck --agent-pid <pid>`。
- orca-wake 读会话状态：进程已不在、父进程变了、本停顿已有成功叫醒、或会话 30 分钟内有新动静 → 跳过；否则补发一次 idle（`source=stuck-check-recheck`），沿用同一个去重键。
- 兜的情况：Esc 中断（没有 Stop）、按键压掉 idle_prompt、webhook 三次都失败、hook 漏发。
- 延迟：30 分钟阈值 + 15 分钟检查周期，Esc 中断后最长约 45 分钟才补叫。
- 卡住检查脚本的改动不在这个仓库，也还没做。

## 静音与影子模式

- 人接手会话：在工作目录（向上到 git 根）放 `.orca-wake-mute`，该会话不再叫醒，删掉恢复。保留 Stop 立即叫醒（方案 A）。
- 实现补充：影子模式。`~/.config/orca-wake/enabled-bots` 里没有的 bot 只写 `wake.log`（`event: shadow`）并按已发处理去重，不发 webhook。用于上线前在真实会话上观察判断结果。

## bot 端约定（不在本仓库实现）

- 同一 `dedup_key` 只处理一次；同一 task 收到多条时以最新 status 为准：done / idle → 验收；needs_input → 回终端答复；error / blocked → 排查或上报。
- `source` 为 wake-hook、stuck-check-recheck、notify-run 的通知同等对待，只按 `dedup_key` 和 task 合并。
- 交接格式：agent 最后一条消息写「结论 + 报告路径」，长日志留在文件里。

## 兜底与回滚

- notify-run 保留，兜进程崩溃或被杀。
- 回滚：`orca-wake-hooks remove` 删 hook 条目，删 Pi 扩展；notify-run 和卡住检查保持原样即恢复现状。

## 不采用

- 让 agent 做完自己发 webhook 或自己 `/exit`：依赖 agent 自觉，做不到可靠。
- 以用户身份把消息送进 bot 对话的接口：需要账号级密钥，消息会绕过 bot 规则，bot 忙时会丢。
