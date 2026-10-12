# 卡住工作检查 dry-run（2026-10-12 19:27 SGT）

执行者：Claude Code（ops 工作区）。命令：`scripts/stuck-check.sh --dry-run`，退出码 0，用时约 61 秒。
dry-run 不发 webhook，也不记「已通知」状态；下面「将 POST」的行是正式运行时会发出的 JSON。

- iMac：查了 19 个任务工作区，13 个问题。
- box（`orca --environment grok-bot`）：查了 11 个任务工作区，6 个问题。box 上的 `*.done` 标记读不到，没有检查。
- 本机没有 `orca-ide` 命令，脚本用的是 `orca`；没有名为 box 的 environment，box 的 Orca 在 `orca environment list` 里叫 grok-bot。

问题代码：`finished_no_pr` 已收工超过 1 小时没有 PR；`pr_not_reviewed` PR 开了超过 1 小时没有 review 或人工评论；
`agent_idle` agent 超过 1 小时不在工作；`agent_exited` 终端还在但没有 agent。

## 原始输出

```
2026-10-12 19:27:17 SGT 开始（dry-run）（orca=orca，阈值 1.0 小时）
2026-10-12 19:28:03 SGT iMac：查了 19 个任务工作区，13 个问题
2026-10-12 19:28:18 SGT box（--environment grok-bot）：查了 11 个任务工作区，6 个问题；box 上的 *.done 标记读不到，未检查
2026-10-12 19:28:18 SGT 问题 | 心月网站 运维 | agent_idle | 心月 · PER-37 涨水爬楼 | iMac:/Users/jiawenwang/orca/workspaces/xinyue-site/per-37-flood-climb-v2 | claude 处于 done 状态已 14.4 小时，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | deepvision 广告产品 | agent_exited | dv广告 · FDV-36 Ryze 复刻总装 | iMac:/Users/jiawenwang/orca/workspaces/deepvision-ads/fdv-36-build | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 todo，最近活动在 16.5 小时前，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | agent_exited | vllm · PER-7 C1 客户端错误透传 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-1-client-errors | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | agent_exited | vllm · PER-8 C1 schedule 配置与校验 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-2-schedule-config | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | agent_exited | vllm · PER-9 C1 注意力候选按步选择 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-3-candidate-selection | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | agent_exited | vllm · PER-10 C1 模型发布去噪进度 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-4-model-publishers | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | agent_exited | vllm · PER-11 C1 请求执行与 Wan2.2 接入 | iMac:/Users/jiawenwang/orca/workspaces/repository/c1-5-request-execution | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | agent_idle | vllm · PER-12 C2-1 mypy 修复 | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-1-r3-mypy | pi 处于 done 状态已 62.7 小时，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | agent_exited | vllm · PER-12 C2 sigma 窗口策略 | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-1-sigma-policy | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | agent_exited | vllm · PER-13 C2-2 sigma CUDA graph（不推上游，跟进见 PER-18） | iMac:/Users/jiawenwang/orca/workspaces/repository/c2-2-sigma-graphs | 终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 95.1 小时前，没有收工标记，也没有 PR
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | finished_no_pr | vllm · PER-22 C2-1 性能优化（direct register） | iMac:/Users/jiawenwang/orca/workspaces/repository/per-22-direct-register | Linear PER-22 已完成，已 10.2 小时没有 PR（分支 perf/c2-1-r2-perf）
2026-10-12 19:28:18 SGT 问题 | deepvision 广告产品 | finished_no_pr | dv广告 · FDV-35 Ryze 调研 | iMac:/Users/jiawenwang/orca/workspaces/deepvision-ads/fdv-35-ryze | 工作区标为 completed；Linear FDV-35 已完成，已 9.8 小时没有 PR（分支 zack/fdv-35-ryze）
2026-10-12 19:28:18 SGT 问题 | vllm-omni 开发 | finished_no_pr | vllm · PER-14 测试精简 trim 分支（已完成） | iMac:/Users/jiawenwang/orca/workspaces/repository/stack-trim | 工作区标为 completed；Linear PER-14 已完成，已 44.4 小时没有 PR（分支 feat/c2-2-trim）
2026-10-12 19:28:18 SGT 问题 | deepvision 广告产品 | pr_not_reviewed | dv广告 · FDV-36 Ryze 复刻总装 | box:/home/box/orca/workspaces/deepvision-ads/fdv-36-build | PR 已开 16.0 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/1
2026-10-12 19:28:18 SGT 问题 | deepvision 广告产品 | pr_not_reviewed | dv广告 · FDV-38 工作区和组织设置 | box:/home/box/orca/workspaces/deepvision-ads/fdv-38-settings | PR 已开 11.5 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/3
2026-10-12 19:28:18 SGT 问题 | deepvision 广告产品 | pr_not_reviewed | dv广告 · FDV-39 Integrations 和广告账户连接 | box:/home/box/orca/workspaces/deepvision-ads/fdv-39-integrations | PR 已开 11.3 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/4
2026-10-12 19:28:18 SGT 问题 | deepvision 广告产品 | pr_not_reviewed | dv广告 · FDV-40 AI Marketer 聊天 | box:/home/box/orca/workspaces/deepvision-ads/fdv-40-chat | PR 已开 11.0 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/5
2026-10-12 19:28:18 SGT 问题 | deepvision 广告产品 | pr_not_reviewed | dv广告 · FDV-41 定时任务、模板、报告 | box:/home/box/orca/workspaces/deepvision-ads/fdv-41-schedules | PR 已开 9.8 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/6
2026-10-12 19:28:18 SGT 问题 | deepvision 广告产品 | pr_not_reviewed | dv广告 · FDV-37 顶栏和全局弹窗 | box:/home/box/orca/workspaces/deepvision-ads/fdv-37-header | PR 已开 11.7 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/2
2026-10-12 19:28:18 SGT 共 19 个问题，其中 19 个需要通知（其余 24 小时内已通知过）
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "心月网站 运维", "task": "心月 · PER-37 涨水爬楼", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/xinyue-site/per-37-flood-climb-v2", "issue": "agent_idle", "note": "claude 处于 done 状态已 14.4 小时，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "deepvision 广告产品", "task": "dv广告 · FDV-36 Ryze 复刻总装", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/deepvision-ads/fdv-36-build", "issue": "agent_exited", "note": "终端还开着（1 个）但里面没有 agent 在跑，工作区状态 todo，最近活动在 16.5 小时前，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-7 C1 客户端错误透传", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/c1-1-client-errors", "issue": "agent_exited", "note": "终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-8 C1 schedule 配置与校验", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/c1-2-schedule-config", "issue": "agent_exited", "note": "终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-9 C1 注意力候选按步选择", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/c1-3-candidate-selection", "issue": "agent_exited", "note": "终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-10 C1 模型发布去噪进度", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/c1-4-model-publishers", "issue": "agent_exited", "note": "终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-11 C1 请求执行与 Wan2.2 接入", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/c1-5-request-execution", "issue": "agent_exited", "note": "终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-12 C2-1 mypy 修复", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/c2-1-r3-mypy", "issue": "agent_idle", "note": "pi 处于 done 状态已 62.7 小时，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-12 C2 sigma 窗口策略", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/c2-1-sigma-policy", "issue": "agent_exited", "note": "终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 68.1 小时前，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-13 C2-2 sigma CUDA graph（不推上游，跟进见 PER-18）", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/c2-2-sigma-graphs", "issue": "agent_exited", "note": "终端还开着（1 个）但里面没有 agent 在跑，工作区状态 in-progress，最近活动在 95.1 小时前，没有收工标记，也没有 PR"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-22 C2-1 性能优化（direct register）", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/per-22-direct-register", "issue": "finished_no_pr", "note": "Linear PER-22 已完成，已 10.2 小时没有 PR（分支 perf/c2-1-r2-perf）"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "deepvision 广告产品", "task": "dv广告 · FDV-35 Ryze 调研", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/deepvision-ads/fdv-35-ryze", "issue": "finished_no_pr", "note": "工作区标为 completed；Linear FDV-35 已完成，已 9.8 小时没有 PR（分支 zack/fdv-35-ryze）"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "vllm-omni 开发", "task": "vllm · PER-14 测试精简 trim 分支（已完成）", "worktree": "iMac:/Users/jiawenwang/orca/workspaces/repository/stack-trim", "issue": "finished_no_pr", "note": "工作区标为 completed；Linear PER-14 已完成，已 44.4 小时没有 PR（分支 feat/c2-2-trim）"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "deepvision 广告产品", "task": "dv广告 · FDV-36 Ryze 复刻总装", "worktree": "box:/home/box/orca/workspaces/deepvision-ads/fdv-36-build", "issue": "pr_not_reviewed", "note": "PR 已开 16.0 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/1"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "deepvision 广告产品", "task": "dv广告 · FDV-38 工作区和组织设置", "worktree": "box:/home/box/orca/workspaces/deepvision-ads/fdv-38-settings", "issue": "pr_not_reviewed", "note": "PR 已开 11.5 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/3"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "deepvision 广告产品", "task": "dv广告 · FDV-39 Integrations 和广告账户连接", "worktree": "box:/home/box/orca/workspaces/deepvision-ads/fdv-39-integrations", "issue": "pr_not_reviewed", "note": "PR 已开 11.3 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/4"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "deepvision 广告产品", "task": "dv广告 · FDV-40 AI Marketer 聊天", "worktree": "box:/home/box/orca/workspaces/deepvision-ads/fdv-40-chat", "issue": "pr_not_reviewed", "note": "PR 已开 11.0 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/5"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "deepvision 广告产品", "task": "dv广告 · FDV-41 定时任务、模板、报告", "worktree": "box:/home/box/orca/workspaces/deepvision-ads/fdv-41-schedules", "issue": "pr_not_reviewed", "note": "PR 已开 9.8 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/6"}
2026-10-12 19:28:18 SGT dry-run，将 POST：{"bot": "deepvision 广告产品", "task": "dv广告 · FDV-37 顶栏和全局弹窗", "worktree": "box:/home/box/orca/workspaces/deepvision-ads/fdv-37-header", "issue": "pr_not_reviewed", "note": "PR 已开 11.7 小时，没有 review，也没有人评论：https://github.com/zhongc1211/deepvision-ads/pull/2"}
```
