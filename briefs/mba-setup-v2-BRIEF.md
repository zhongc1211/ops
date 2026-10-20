# MBA 配置补齐 + 自检（v2，在 MBA 本机做）

背景：Zack 要 MBA（主机名 mba，tailnet 100.64.0.7）和 iMac（100.64.0.4，`ssh imac` 或 tailnet）配成一样的环境。Grok Bot 的 box（100.64.0.6）现在挂了，不要依赖它。

要核对并补齐的（以 iMac 为准，先对比再补）：
1. 全局 agent 文件：~/.claude/CLAUDE.md、~/.claude/settings.json、~/.pi/agent 下的 AGENTS/skills（含 human-communication）、各仓库的 AGENTS.md/CLAUDE.md。
2. 叫醒系统：~/.local/bin/notify-run 能跑；~/.config/grokbot/stuck-webhook.env 和 webhooks/*.env 存在（只看是否存在和变量名，绝不打印值）；用 notify-run 发一次测试叫醒，报告里 machine 要显示 mba。
3. EverOS：四个项目的 MCP 都在 claude 里配好（claude mcp list），各连一次 health；~/.config/everos/*.env 存在（不打印值）。
4. 工具链：node/nvm、gh（已登录 zhongc1211）、git 身份、runpodctl、各仓库能 fetch。
5. Orca：五个仓库都在 Orca 里有项目；Linear 连接正常。iMac 上的 Orca 定时任务列出来，对比 MBA，但不要在 MBA 上新建或启用任何定时任务（会和 iMac 重复跑），只列出差异。
6. Orca 配对：MBA 和 iMac 互相配对是否已通；box 挂着就记为「待 box 恢复」，不要硬试。

规矩：不打印、不提交任何密钥/token；密钥文件只通过 tailnet 复制（scp），不经聊天或 git。不动生产，不花钱。同一操作最多重试 2 次，失败就记下来。

交付：写 ~/orca/workspaces/ops/briefs/mba-setup-v2-RESULT.md，按上面 6 项逐条写「通过/补了什么/还缺什么（为什么）」，最后一行写总结。
