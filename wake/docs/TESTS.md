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
- 当时发现的缺口：pi-subagents 的后台 runner 启动即崩溃时，不会发出 `subagent:async-complete`，扩展会一直等，不发叫醒；这时也还没有会话状态文件，`orca-wake recheck` 记 `no_state_for_pid`。已修复，见下一节。
- 限制同上：只核对发送方状态码；限额暂停是注入事件模拟；webhook 不可达没对真实 webhook 测；补叫醒用 `--idle-min 0` 手动触发。

## Pi 后台 runner 崩溃与等待上限

修复：扩展监听 `subagent:process-terminal`，runner 退出 90 秒后仍没有 `async-complete` 就照常叫醒；后台子代理最多等 30 分钟。两台机器上都用专用测试 webhook 测，扩展用 `pi -ne -e <新扩展> -e <pi-subagents>` 加载，正式安装的旧扩展作对照。崩溃用 pi-subagents 自带的 `PI_SUBAGENTS_TEST_RUNNER_EXECUTION_MODULE` 指向一个 import 时就抛错的模块，runner 在启动握手之后报 `Subagent runner startup failed`，与第二台机器上 EP2 的失败方式相同（当时是依赖版本不对导致 import 报错）。

| # | 场景 | 预期 | 实际（叫醒均 HTTP 200） |
|---|---|---|---|
| X1 | runner 被 SIGKILL | 1 | pi-subagents 自己的过期 run 核对把 run 标为 failed 并送回结果，主会话续轮后 1 次（20 秒后）。没有走到新代码，旧扩展也能处理这种情况 |
| X2 | 后台子代理正常完成（sleep 40） | 1 | 1 次（FINAL-DONE 之后） |
| X3 | 等待上限设为 90 秒，子代理 sleep 200 | 2 | STARTED 后 90 秒 1 次；子代理完成、续轮后又 1 次 |
| X4 | runner import 报错（第一台机器） | 1 | runner 失败后 1 分 42 秒 1 次 |
| X4o | 同上，旧扩展 | 0（缺口） | 0 次，复现了缺口 |
| X5 | runner import 报错（第二台机器） | 1 | runner 失败后 1 分 41 秒 1 次 |
| X5o | 同上，旧扩展 | 0（缺口） | 0 次 |

限制：只核对发送方状态码和时间，叫醒正文里新加的 note 没有核对（wake.log 不记正文）。

## 卡住检查接入补叫醒（端到端）

卡住检查（不在本仓库）按 DESIGN「补叫醒」一节接入 `orca-wake recheck`，在两台机器上用专用测试 webhook 测。会话用 `notify-run --tty -- claude --model haiku` 启动；「Esc」指让模型写长文时按 Esc 打断，这样没有 Stop，hook 不叫醒。卡住检查按正式排期的时间点（每 15 分钟）运行，第三轮漏跑了一次（见 F2）。

| # | 机器 | 场景 | 预期 | 实际（叫醒均 HTTP 200） |
|---|---|---|---|---|
| R1 | 第一台 | 放行的 bot，Esc | Esc 后 30–45 分钟 1 次 | 42 分钟时 recheck 发 1 次，之后不再处理 |
| R2 | 第一台 | 不在名单里的 bot，Esc | 只写 wake.log | 第一次检查漏掉（Orca 状态停在 working，见下方问题 8）。修复后 51 分钟时写 shadow，没有发送 |
| R3 | 第一台 | hook 已叫醒过 | 不重发 | recheck 返回 `already_woken`，不发 |
| R4 | 第一台 | 不经 notify-run 的会话 | 按卡住检查原来的方式报 | recheck 返回 `no_state_for_pid`，卡住检查按原方式发 1 次 |
| R5 | 第一台 | 放行的 bot，Esc，13 分钟后 Claude Code 往 transcript 追加元数据 | 30–45 分钟 1 次 | 修复前：42 分钟时 `recent_activity`，57 分钟才发（问题 7） |
| R5b | 第一台 | 同上，修复后；Esc 21 分钟后手动追加一行不带时间戳的记录 | 30–45 分钟 1 次 | 44 分钟时发 1 次。追加后立即对比：旧版本不列为候选，新版本列为候选 |
| F1 | 第二台 | 放行的 bot，Esc | 30–45 分钟 1 次，走 recheck | 40 分钟时发 1 次，但卡住检查查进程超时，退回原来的方式发送，没经过 orca-wake（问题 9） |
| F2 | 第二台 | 修复后重测：放行的 bot，Esc | 30–45 分钟 1 次，走 recheck | 那台机器的 Orca 断线重连后丢了所有 agent 状态，「等待输入」检测一直超时；测试循环又漏跑了一次检查。卡住检查只能按屏幕计时，54 分钟时判为 agent_silent，按原来的方式发 1 次。没走 recheck，原因在 Orca 状态，不在本仓库 |
| F3 | 第二台 | 绕开 Orca 状态，直接调用卡住检查的查进程和 recheck 函数（Esc 后用 `--idle-min 1`） | recheck 发 1 次，再查不重发 | 不到 1 分钟时 `recent_activity`；之后发 1 次（stuck-check-recheck）；再查 `already_woken` |

限制：只核对发送方状态码；「1 小时未验收」、agent_silent、agent_gone 没改，未专门重测。

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
7. 补叫醒用 transcript 的文件修改时间判断「30 分钟内有新动静」。Claude Code 在 Esc 13 分钟后往 transcript 追加了不带时间戳的元数据，补叫醒因此推迟一轮检查（R5：Esc 后 42 分钟本该发，变成 57 分钟）→ 改为取 transcript 里最后一条带时间戳记录的时间，找不到时间戳才用文件修改时间（e2e R5b 验证）。
8. Esc 中断后 Orca 记录的 agent 状态一直是 working，卡住检查原来的 agent_idle 判断不到（R2）→ 状态 30 分钟没变、所有终端都停在输入框时也交给 recheck。
9. 卡住检查在第二台机器上查进程超时，拿不到 pid，退回原来的 agent_idle 发送，可能和 hook 重复（F1）→ 拿不到 pid 时这次不报，下次再查。

## 升级后复测

Claude Code 或 Pi 升级后，至少重跑 C1、C2、C3、C4、C8、C11 和 P1、P2、P4，以及 `tests/unit.sh`。
