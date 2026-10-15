# 测试清单与结果

**测试环境**：第一台机器（macOS），Claude Code 2.1.300（另测 2.1.299），Pi 1.0.4。所有叫醒都发到本机 `tests/mock_webhook.py`（127.0.0.1），没有发给任何真实 bot。每个场景通过 `notify-run --tty` 在独立 tmux 会话里启动，Claude 用 haiku 模型，Pi 用 xai/grok-4.3。第二台机器（Linux）的结果见「第二台机器（Linux）」一节。

「预期次数」只算叫醒 webhook（wake-hook 和 stuck-check-recheck），不含 agent 退出或测试结束时 notify-run 自己发的 done / failed / killed。

## 真实测试 webhook 端到端（第二轮）

之后用一个专用测试 webhook（只记日志、不叫醒 bot）重跑了 Claude 18 个场景（C1–C4、C6–C8、C10–C12、C14–C18、C21、C23、C24、C27 的对应场景）和 Pi 7 个场景。28 次叫醒全部 HTTP 200、第 1 次尝试成功，有效场景结果都与下表预期一致。限制：只核对了发送方的状态码，没有核对接收方记录的正文；C14 仍是注入事件模拟；webhook 不可达（C19）没有对真实 webhook 重测。测试会话用 `ORCA_WAKE_CONFIG_DIR` 指向只放行测试 bot 的名单，其余代码路径与生产相同。

## 第二台机器（Linux）

Linux（内核 6.12），系统自带 Python 3.13，Claude Code 2.1.300（另测 2.1.299）。安装方式与 README 相同，`orca-wake-hooks check` 五项都是 ok。

- `tests/unit.sh`：27 项全部通过。
- 专用测试 webhook 端到端：Claude 18 个场景（与上一节相同），18 次叫醒全部 HTTP 200、第 1 次尝试成功，结果都与下表预期一致；各会话退出时 notify-run 的 done 也都是 HTTP 200。父进程校验走 `/proc`，嵌套 `claude -p`、嵌套 notify-run、`bash -c "...; true"` 都正确记 `parent_mismatch`。
- Pi 1.0.4（用 Node 22 运行；Pi 1.0.4 要求 Node 22.19 以上）：P1–P7 对应的 7 个场景都与预期一致，4 次叫醒全部 HTTP 200。安装时必须按锁定版本装依赖（`npm ci`）：用 `npm install` 时依赖会解析到更新的 1.2.x，主程序不受影响，但 pi-subagents 的后台 runner 启动即报错。
- 已知缺口：pi-subagents 的后台 runner 启动即崩溃时，不会发出 `subagent:async-complete`，扩展会一直等，不发叫醒；这时也还没有会话状态文件，`orca-wake recheck` 记 `no_state_for_pid`。
- 限制同上：只核对发送方状态码；限额暂停是注入事件模拟；webhook 不可达没对真实 webhook 测；补叫醒用 `--idle-min 0` 手动触发。

## 离线测试

`tests/unit.sh`：临时目录 + 本地模拟 webhook，不需要 Claude 或 Pi。最近一次：27 项全部通过。覆盖 idle 去重、后台 shell、needs_input、error、blocked、parent_mismatch、静音、影子模式、Pi send 去重、webhook 不可达后补叫醒、排队续轮（queued_followup）、等待期内新回合（superseded）、非派出会话、hook 无 stderr 输出。

## Claude Code

| # | 场景 | 预期次数 | status | 实际 |
|---|---|---|---|---|
| C1 | 正常完成 | 1 | idle | 通过：Stop 后 1 次 |
| C2 | Stop 已叫醒，约 60 秒后 idle_prompt | 0（不重复） | — | 通过：idle_prompt 记 `already_sent` |
| C3 | 后台 shell 运行 75 秒 | 1（shell 结束后续轮） | idle | 通过：Stop、idle_prompt 都记 `background_work`，续轮 1 次 |
| C4 | 后台子 agent | 1（结果回来后） | idle | 通过：前两轮跳过，第三轮 1 次 |
| C5 | 子 agent 刚结束、通知还在排队时 Stop | 1 | idle | 首轮实现叫了 2 次，加入 8 秒等待和 `queued_followup` 后重测 1 次；`queued_followup` 用真实 transcript 回放验证 |
| C6 | 会话里嵌套 `claude -p` | 1（只外层） | idle | 通过：内层记 `parent_mismatch` |
| C7 | 会话里嵌套 `notify-run --tty -- claude -p` | 1（只外层） | idle | 通过：内层没有覆盖外层变量，记 `parent_mismatch` |
| C8 | AskUserQuestion 超过数秒未答 | 2 | needs_input + idle | 通过 |
| C9 | AskUserQuestion 很快回答 | 1 | idle | 通过（快答时权限通知未触发） |
| C10 | 权限弹窗后按 Esc 拒绝 | 1 + 补叫醒 1 | needs_input，之后 idle（recheck） | 通过。首轮发现 needs_input 被当成「已叫醒」导致补叫醒跳过，修复后重测通过 |
| C11 | StopFailure（不存在的模型） | 1 | error | 通过：之后的 idle_prompt 记 `error_already_reported` |
| C12 | 已叫醒后下一轮 API 报错（本地代理注入 400） | 2 | idle，error | 通过 |
| C13 | StopFailure 之后 idle_prompt 是否再发 | 0 | — | 通过（见 C11、C12） |
| C14 | 已叫醒后出现限额暂停 | 1 | blocked | 通过，**模拟**：真实限额无法触发，向活会话的 hook 注入 `quota_auto_resume_stale`；随后注入的 `quota_auto_resume_disabled` 同键去重 |
| C15 | 另一个 Stop hook 先 block 一次 | 1 | idle | 通过：正文是 block 之后的最终消息 |
| C16 | `session_crons` 非空（/loop） | 0 | — | 通过：每次 Stop、idle_prompt 都记 `background_work` |
| C17 | 人接手：放 `.orca-wake-mute` 再删掉 | 2（静音期间 0） | idle | 通过 |
| C18 | `notify-run -- bash -c "claude ..."`（单条命令） | 见实际 | idle | 叫醒 1 次：bash 对单条命令直接 exec，claude 仍是直接子进程 |
| C18d | `notify-run -- bash -c "claude ...; true"` | 0 | — | 通过：记 `parent_mismatch` |
| C19 | webhook 不可达（503） | 3 次失败 + 补叫醒 1 | idle | 通过：失败记 `all_attempts_failed`，恢复后补叫 1 次，再补记 `already_woken` |
| C20 | 已叫醒的停顿再跑补叫醒 | 0 | — | 通过：`already_woken` |
| C21 | Esc 中断（没有 Stop） | 补叫醒 1 | idle | 通过：note 写明本回合没有 Stop |
| C22 | 完成后按键（压掉 idle_prompt） | 1 | idle | 通过 |
| C23 | hook 叫醒后 agent `/exit` | 1 + notify-run done | idle，done | 通过：bot 按 task 合并 |
| C24 | 不经 notify-run 自己开的会话 | 0 | — | 通过：不写日志、不建状态文件 |
| C25 | 前台子 agent | 1 | idle | 通过。2.1.300 中 Agent 工具即使要求前台，Stop 的 `background_tasks` 也有 `subagent: running`，按后台处理 |
| C26 | Orca 升级后 hook 仍在 | — | — | **未测**：无法在测试中触发 Orca 升级。hook 条目与 Orca 自己的条目分开写，`orca-wake-hooks check` 可随时检查 |
| C27 | Claude Code 2.1.299 | 1 | idle | 通过（其余场景在 2.1.300） |

## Pi

| # | 场景 | 预期次数 | status | 实际 |
|---|---|---|---|---|
| P1 | 正常完成 | 1 | idle | 通过 |
| P2 | 后台子代理运行中先回复，结果回来后再回复 | 1 | idle | 通过：子代理运行时不叫，最终回复后 1 次 |
| P3 | `PI_SUBAGENT_CHILD=1`（后台 runner） | 0 | — | 通过（P2 的 runner 也没有发送） |
| P4 | 对话框超过 6 秒未答 | 1 | needs_input | 通过（工具内弹框和命令弹框各测一次） |
| P5 | 对话框 6 秒内回答 | 0 | — | 通过（2 秒内回答） |
| P6 | 模型调用出错 | 1 | error | 通过（OAuth 刷新失败、额度不足各一次） |
| P7 | print / json 模式 | 0 | — | 通过：只有 notify-run 的 done。rpc 模式走同一判断，未实测 |

对话框测试用的是测试专用扩展（工具和 `/` 命令里调用 `ctx.ui.select`），与 ask_user 走同一个 `ui_prompt_start` 事件；该测试模型通过 codemode 调用 ask_user 时没有弹出界面。

## wake.log 片段（会话 id 已替换为 `<sid>`）

C3 后台 shell：

```
{"event": "skip", "hook": "Stop", "reason": "background_work", "turn": 1, "active_tasks": ["shell:running"]}
{"event": "skip", "hook": "Notification/idle_prompt", "reason": "background_work", "turn": 1, "active_tasks": ["shell:running"]}
{"event": "state", "hook": "UserPromptSubmit", "note": "turn 2 started"}
{"event": "send", "key": "claude:<sid>:idle:2", "http": 200, "attempt": 1, "source": "wake-hook"}
{"event": "skip", "reason": "already_sent", "key": "claude:<sid>:idle:2", "source": "wake-hook"}
```

C19 webhook 不可达后补叫醒：

```
{"event": "send", "key": "claude:<sid>:idle:1", "http": 503, "attempt": 1, "source": "wake-hook"}
{"event": "send", "key": "claude:<sid>:idle:1", "http": 503, "attempt": 2, "source": "wake-hook"}
{"event": "skip", "reason": "inflight", "key": "claude:<sid>:idle:1", "source": "wake-hook"}
{"event": "send", "key": "claude:<sid>:idle:1", "http": 503, "attempt": 3, "source": "wake-hook"}
{"event": "failed", "reason": "all_attempts_failed", "key": "claude:<sid>:idle:1", "source": "wake-hook"}
{"event": "send", "key": "claude:<sid>:idle:1", "http": 200, "attempt": 1, "source": "stuck-check-recheck"}
{"event": "recheck_skip", "hook": "recheck", "reason": "already_woken", "seq": "1"}
```

C18d 经 `bash -c` 包装：

```
{"event": "skip", "hook": "UserPromptSubmit", "reason": "parent_mismatch", "agent_parent": <bash>, "dispatch_pid": <notify-run>}
{"event": "skip", "hook": "Stop", "reason": "parent_mismatch", ...}
```

P2 Pi 后台子代理：

```
{"event": "send", "key": "pi:<sid>:idle:<leaf>", "http": 200, "attempt": 1, "source": "wake-hook"}   (tail: FINAL-DONE)
```

## 测试中发现并已修复的问题

1. 子 agent 结束、通知排队时 Stop 看到的后台任务为空，叫醒 2 次（C5）→ Stop 后等 8 秒，期间开始新回合则作废；transcript 有未出队的 `enqueue` 时不叫。
2. needs_input 被记成「本回合已叫醒」，Esc 拒绝后补叫醒跳过（C10）→ needs_input 不再标记。
3. 另一个 Stop hook block 一次时正文是 block 前的消息（C15）→ 发送前改取本回合最后一次 Stop 的消息。
4. python.org 的 macOS Python 没有 CA 证书，HTTPS webhook 会失败 → 依次尝试 `SSL_CERT_FILE`、certifi、系统证书文件。
5. 发送进程用 fork 时，Python 报「多线程进程 fork」警告 → 改为启动独立进程。
6. 机器负载很高时 `ps` 超时，父进程校验误判 `parent_mismatch`（C16 后段、C25 首轮）→ 改为直接从内核读父进程。

## 升级后复测

Claude Code 或 Pi 升级后，至少重跑 C1、C2、C3、C4、C8、C11 和 P1、P2、P4，以及 `tests/unit.sh`。
