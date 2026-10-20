# 卡住工作检查：规则更新后的 dry-run（2026-10-12 19:53 SGT）

执行者：Claude Code（ops 工作区）。命令：`scripts/stuck-check.sh --dry-run`，退出码 0，用时约 70 秒。
dry-run 不发 webhook，也不记「已通知」状态；「将 POST」那一行是正式运行时会发出的 JSON。
规则更新前的 dry-run（19:27）在提交 05a2099 的同名文件里。

## 新规则

每个开发 bot 有自己的 webhook，coding agent 做完或卡住时自己叫醒派活的 bot。脚本只做兜底，
只向 `~/.config/grokbot/stuck-webhook.env`（Coding助手）POST，不读也不发 bot 自己的 webhook。
payload 字段是 `bot / task / worktree / status / note`，`status` 只有两个值：

| status | 含义 | 判断依据 |
|---|---|---|
| `reported_not_accepted` | agent 已报完成或卡住，超过 1 小时没人验收 | 已报：工作区标 completed/in-review、Linear 卡片 completed、有 `*.done` 标记、工作区备注以完成/卡住类字样开头（DONE/PARTIAL/BLOCKED/完成/卡住/阻塞，或「等 xx 拍板/验收/确认」）、或已开 PR。已验收：PR 有 review 或人工评论、PR 已合并或关闭、工作区已归档、Linear 卡片 canceled |
| `stopped_no_report` | agent 中途停掉、没有报 | 没有任何「已报」信号也没有 PR，并且 agent 超过 1 小时不在工作，或终端还在但没有 agent，或工作区标 in-progress 但终端已全部关闭 |

其他改动：

- 一次检查只发一条 POST。只有一个问题时原样发；多个问题合并成一条：`note` 逐条列出全部条目，`bot` 列出涉及的 bot，
  `task` 写「卡住工作检查：N 条」，`worktree` 写「多个（见 note）」，`status` 一致时沿用、不一致时写 `mixed`。
- 同一件事（同一工作区 + 同一 status）只报一次，不再每 24 小时重发。问题连续 24 小时没再出现才从记录里清掉。
- agent 正在工作的工作区不报（包括被叫回去返工的）。
- 同一张 Linear 卡在别的工作区还在做或已报的，旧工作区不报（本次跳过了 iMac 上已迁到 box 的 FDV-36）。
- `bot` 字段改用 bot webhook 的文件名：deepvision-ops、deepvision-ads、vllm-omni、xinyue；对不上的写「未映射」。
- webhook 的 URL 和 KEY 不写进输出和日志。

## 本次结果

iMac 查了 20 个任务工作区，box（`orca --environment grok-bot`）查了 13 个。共 18 个问题，18 个都是首次，正式运行会合并成 1 条 POST 发出。

| bot | status | 数量 | 工作区 |
|---|---|---|---|
| vllm-omni | stopped_no_report | 8 | c1-1 至 c1-5、c2-1-r3-mypy、c2-1-sigma-policy、c2-2-sigma-graphs |
| vllm-omni | reported_not_accepted | 2 | per-22-direct-register、stack-trim |
| deepvision-ads | reported_not_accepted | 7 | iMac fdv-35-ryze；box fdv-36 至 fdv-41 的 6 个未 review 的 PR |
| 未映射 | stopped_no_report | 1 | adrunner/ui-校正（in-progress，终端已全关，130 小时没有活动） |

和 19:27 那次相比：iMac 的 fdv-36-build 因任务已迁到 box 被跳过；per-37-flood-climb-v2 在 19:36 开了 PR #61，
未满 1 小时，不报；adrunner/ui-校正 是新规则才覆盖到的（终端全关的 in-progress 工作区）。

## 验证

- 已验证：把 webhook 指到本机临时监听端口、状态目录指到临时目录，连跑两次正式模式。第一次只发出 1 条
  （字段是 bot/note/status/task/worktree，note 里列了全部 18 个问题），第二次发出 0 条。两次输出和日志里都没有出现 URL 或 KEY。
- 未运行：对真实 Coding助手 webhook 的正式发送。下一次定时运行（20:23）会把 18 条存量合并成 1 条发出。

## 限制

- 脚本看不到 agent 有没有真的 POST 过 bot webhook，「已报」只能从上表那些信号推断。
- `~/.config/grokbot/webhooks/` 已建好（4 个 bot 各一个文件）。脚本不读这些文件。
- box 上的 `*.done` 标记读不到，没有检查。
- 没有 PR 的任务没有明确的「已验收」信号，只会在归档工作区或取消 Linear 卡片后停止出现；因为只报一次，不会重复打扰。

## 原始输出

```
2026-10-12 19:53:58 SGT 开始（dry-run）（orca=orca，阈值 1.0 小时）
2026-10-12 19:55:10 SGT iMac：查了 20 个任务工作区，13 个问题
2026-10-12 19:55:26 SGT box（--environment grok-bot）：查了 13 个任务工作区，6 个问题；box 上的 *.done 标记读不到，未检查
2026-10-12 19:55:26 SGT 跳过 | dv广告 · FDV-36 Ryze 复刻总装 | iMac:/Users/jiawenwang/orca/workspaces/deepvision-ads/fdv-36-build：FDV-36 在别的工作区还在做或已报，视为任务已迁走
2026-10-12 19:55:26 SGT 问题 | vllm-omni | stopped_no_report | vllm · PER-7 C1 客户端错误透传 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-1-client-errors | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | stopped_no_report | vllm · PER-8 C1 schedule 配置与校验 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-2-schedule-config | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | stopped_no_report | vllm · PER-9 C1 注意力候选按步选择 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-3-candidate-selection | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | stopped_no_report | vllm · PER-10 C1 模型发布去噪进度 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-4-model-publishers | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | stopped_no_report | vllm · PER-11 C1 请求执行与 Wan2.2 接入 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-5-request-execution | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | stopped_no_report | vllm · PER-12 C2-1 mypy 修复 | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-1-r3-mypy | pi 停在 done 状态已 63.2 小时，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | stopped_no_report | vllm · PER-12 C2 sigma 窗口策略 | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-1-sigma-policy | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | stopped_no_report | vllm · PER-13 C2-2 sigma CUDA graph（不推上游，跟进见 PER-18） | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-2-sigma-graphs | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 95.6 小时前，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | reported_not_accepted | vllm · PER-22 C2-1 性能优化（direct register） | iMac:/Users/jiawenwang/orca/workspaces/repository/per-22-direct-register | Linear PER-22 已完成，已 10.6 小时没人验收（没有 PR，分支 perf/c2-1-r2-perf）
2026-10-12 19:55:26 SGT 问题 | deepvision-ads | reported_not_accepted | dv广告 · FDV-35 Ryze 调研 | iMac:/Users/jiawenwang/orca/workspaces/deepvision-ads/fdv-35-ryze | 工作区标为 completed；Linear FDV-35 已完成，已 10.2 小时没人验收（没有 PR，分支 zack/fdv-35-ryze）
2026-10-12 19:55:26 SGT 问题 | 未映射 | stopped_no_report | ui 校正 | iMac:/Users/jiawenwang/orca/workspaces/adrunner/ui-校正 | 终端已全部关闭，没有 agent，工作区状态 in-progress，最近活动在 130.5 小时前，没有完成或卡住的报告，也没有 PR
2026-10-12 19:55:26 SGT 问题 | vllm-omni | reported_not_accepted | vllm · PER-14 测试精简 trim 分支（已完成） | iMac:/Users/jiawenwang/orca/workspaces/repository/stack-trim | 工作区标为 completed；Linear PER-14 已完成，已 44.9 小时没人验收（没有 PR，分支 feat/c2-2-trim）
2026-10-12 19:55:26 SGT 问题 | deepvision-ads | reported_not_accepted | dv广告 · FDV-36 Ryze 复刻总装 | box:/home/box/orca/workspaces/deepvision-ads/fdv-36-build | agent 已开 PR 16.4 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/1
2026-10-12 19:55:26 SGT 问题 | deepvision-ads | reported_not_accepted | dv广告 · FDV-38 工作区和组织设置 | box:/home/box/orca/workspaces/deepvision-ads/fdv-38-settings | agent 已开 PR 11.9 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/3
2026-10-12 19:55:26 SGT 问题 | deepvision-ads | reported_not_accepted | dv广告 · FDV-39 Integrations 和广告账户连接 | box:/home/box/orca/workspaces/deepvision-ads/fdv-39-integrations | agent 已开 PR 11.8 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/4
2026-10-12 19:55:26 SGT 问题 | deepvision-ads | reported_not_accepted | dv广告 · FDV-40 AI Marketer 聊天 | box:/home/box/orca/workspaces/deepvision-ads/fdv-40-chat | agent 已开 PR 11.5 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/5
2026-10-12 19:55:26 SGT 问题 | deepvision-ads | reported_not_accepted | dv广告 · FDV-41 定时任务、模板、报告 | box:/home/box/orca/workspaces/deepvision-ads/fdv-41-schedules | agent 已开 PR 10.3 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/6
2026-10-12 19:55:26 SGT 问题 | deepvision-ads | reported_not_accepted | dv广告 · FDV-37 顶栏和全局弹窗 | box:/home/box/orca/workspaces/deepvision-ads/fdv-37-header | agent 已开 PR 12.2 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/2
2026-10-12 19:55:26 SGT 共 18 个问题，其中 18 个需要通知（其余已通知过，同一件事不重复报）
2026-10-12 19:55:26 SGT dry-run，将 POST 1 条（含 18 个问题）：{"bot": "vllm-omni、deepvision-ads、未映射", "task": "卡住工作检查：18 条", "worktree": "多个（见 note）", "status": "mixed", "note": "共 18 条（stopped_no_report 9，reported_not_accepted 9）：\n1. [vllm-omni] stopped_no_report | vllm · PER-7 C1 客户端错误透传 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-1-client-errors | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR\n2. [vllm-omni] stopped_no_report | vllm · PER-8 C1 schedule 配置与校验 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-2-schedule-config | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR\n3. [vllm-omni] stopped_no_report | vllm · PER-9 C1 注意力候选按步选择 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-3-candidate-selection | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR\n4. [vllm-omni] stopped_no_report | vllm · PER-10 C1 模型发布去噪进度 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-4-model-publishers | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR\n5. [vllm-omni] stopped_no_report | vllm · PER-11 C1 请求执行与 Wan2.2 接入 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-5-request-execution | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR\n6. [vllm-omni] stopped_no_report | vllm · PER-12 C2-1 mypy 修复 | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-1-r3-mypy | pi 停在 done 状态已 63.2 小时，没有完成或卡住的报告，也没有 PR\n7. [vllm-omni] stopped_no_report | vllm · PER-12 C2 sigma 窗口策略 | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-1-sigma-policy | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.5 小时前，没有完成或卡住的报告，也没有 PR\n8. [vllm-omni] stopped_no_report | vllm · PER-13 C2-2 sigma CUDA graph（不推上游，跟进见 PER-18） | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-2-sigma-graphs | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 95.6 小时前，没有完成或卡住的报告，也没有 PR\n9. [vllm-omni] reported_not_accepted | vllm · PER-22 C2-1 性能优化（direct register） | iMac:/Users/jiawenwang/orca/workspaces/repository/per-22-direct-register | Linear PER-22 已完成，已 10.6 小时没人验收（没有 PR，分支 perf/c2-1-r2-perf）\n10. [deepvision-ads] reported_not_accepted | dv广告 · FDV-35 Ryze 调研 | iMac:/Users/jiawenwang/orca/workspaces/deepvision-ads/fdv-35-ryze | 工作区标为 completed；Linear FDV-35 已完成，已 10.2 小时没人验收（没有 PR，分支 zack/fdv-35-ryze）\n11. [未映射] stopped_no_report | ui 校正 | iMac:/Users/jiawenwang/orca/workspaces/adrunner/ui-校正 | 终端已全部关闭，没有 agent，工作区状态 in-progress，最近活动在 130.5 小时前，没有完成或卡住的报告，也没有 PR\n12. [vllm-omni] reported_not_accepted | vllm · PER-14 测试精简 trim 分支（已完成） | iMac:/Users/jiawenwang/orca/workspaces/repository/stack-trim | 工作区标为 completed；Linear PER-14 已完成，已 44.9 小时没人验收（没有 PR，分支 feat/c2-2-trim）\n13. [deepvision-ads] reported_not_accepted | dv广告 · FDV-36 Ryze 复刻总装 | box:/home/box/orca/workspaces/deepvision-ads/fdv-36-build | agent 已开 PR 16.4 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/1\n14. [deepvision-ads] reported_not_accepted | dv广告 · FDV-38 工作区和组织设置 | box:/home/box/orca/workspaces/deepvision-ads/fdv-38-settings | agent 已开 PR 11.9 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/3\n15. [deepvision-ads] reported_not_accepted | dv广告 · FDV-39 Integrations 和广告账户连接 | box:/home/box/orca/workspaces/deepvision-ads/fdv-39-integrations | agent 已开 PR 11.8 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/4\n16. [deepvision-ads] reported_not_accepted | dv广告 · FDV-40 AI Marketer 聊天 | box:/home/box/orca/workspaces/deepvision-ads/fdv-40-chat | agent 已开 PR 11.5 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/5\n17. [deepvision-ads] reported_not_accepted | dv广告 · FDV-41 定时任务、模板、报告 | box:/home/box/orca/workspaces/deepvision-ads/fdv-41-schedules | agent 已开 PR 10.3 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/6\n18. [deepvision-ads] reported_not_accepted | dv广告 · FDV-37 顶栏和全局弹窗 | box:/home/box/orca/workspaces/deepvision-ads/fdv-37-header | agent 已开 PR 12.2 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/2"}
```

## 补记（2026-10-13 08:10 SGT）：正式发送修复

10-12 20:24 到 23:55 的 7 次定时运行，合并后的那一条 POST 全部失败（日志里是 `POST 失败（URLError）`），Coding助手没有收到任何卡住检查的消息。
原因：脚本用 Python 自带的 HTTP 库发 https，这台 iMac 上的 python.org Python 3.13 没有装根证书，证书校验失败。
之前的测试用的是本机 http 监听端口，没有覆盖到 https。

修复：发送改用 `curl`（URL 和 KEY 经 stdin 传入，不出现在进程参数里）。已在本机监听端口验证成功和失败两条路径；
对真实 webhook 的发送要看 10-13 08:23 之后的定时运行，日志在 `~/.orca-state/stuck-check/stuck-check.log`。
失败的那几次没有记「已通知」，所以存量会在下一次成功发送时合并成一条发出。
