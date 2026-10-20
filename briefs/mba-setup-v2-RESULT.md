# MBA 配置补齐 + 自检（v2）结果

- 执行：Claude Code（Opus 5.5），在 MBA 本机跑（hostname `mba`，tailnet 100.64.0.7，用户 jiawenwang），2026-10-18 18:15–18:35 SGT。
- 本次没有改任何配置文件，也没有新建、启用或停用定时任务。唯一的写操作：发了一次测试叫醒；把 iMac 的 host key 加进 MBA 的 `~/.ssh/known_hosts`（见下文「iMac 连不上」）。
- 没有打印或提交任何密钥。env 文件只看了「是否存在、权限、变量名」。

## 阻塞：MBA 连不上 iMac，以 iMac 为准的逐项对比没做成

- `ssh imac` 失败：MBA 的 `~/.ssh/config` 没有 `imac` 这个 Host，`known_hosts` 里也没有它的 host key。
- 改用 `100.64.0.4`：`tailscale status` 显示 100.64.0.4 = imac，直连，所以接受了它的 host key（ED25519 `SHA256:1Y5VJH9N6fSn+1VqqeXvYFdrXkMvNii8D2puk/NiXyI`）。之后被拒：`Permission denied (publickey,password,keyboard-interactive)`。MBA 上的 `id_ed25519`、`id_rsa` 都不在 iMac 的 `authorized_keys` 里；ssh-agent 里没有 key。试过用户名 jiawenwang、zack、zhongc、xiangrong.zhong，都被拒。按规矩不再重试。
- 反方向是通的：PR #21 记录了 box 上的 Claude Code 当时是经 iMac `ssh mba` 来配 MBA 的。
- 影响：第 1 项（全局 agent 文件）、第 5 项的 iMac 定时任务清单，都只核了 MBA 这一边，没能和 iMac 对比。下面列出 MBA 的哈希值，在 iMac 上跑一条命令就能对比。

## 1. 全局 agent 文件 —— MBA 侧齐全；和 iMac 的对比没做

MBA 上都有：

| 文件 / 目录 | sha256 前 16 位 | 说明 |
|---|---|---|
| `~/.claude/CLAUDE.md` | a2c6169f14e0c012 | 772 字节，修改时间 10-03，今天没动过 |
| `~/.claude/settings.json` | 847f3c8e5bdca175 | 14 类 hook、18 个插件；今天 14:16 有备份 `settings.json.bak-20261018-mba-setup`，说明上一轮配置时替换过 |
| `~/.pi/agent/AGENTS.md` | 9d4ec9cd7f5e8c44 | 4364 字节，今天 15:48 更新 |
| `~/.pi/agent/settings.json` | 4ebc33178e88b087 | |
| `~/.pi/agent/skills/`（32 个文件，含 `human-communication/SKILL.md`） | 8ff82597535b31bb | |
| `~/.pi/agent/extensions/`（5 个：dispatch-wake、everos、orca-agent-status、orca-prefill、orca-titlebar-spinner） | 173382abf510e9d2 | |
| `~/.claude/skills/`（260 个文件） | c70efbaba05d3f42 | 今天 15:48 有备份 `skills.bak-20261018-mba-setup.tgz` |

各仓库的 AGENTS.md / CLAUDE.md：xinyue-site、deepvision-site、deepvision-ads、vllm-omni 都有 AGENTS.md。五个仓库刚 fetch 过，都和 origin 一致（behind=0），这两个文件没有本地改动。ops 仓库没有 AGENTS.md / CLAUDE.md，和 origin 一致。这些文件进了 git，只要 iMac 那边也和 origin 同步，两台机器就一致。

还缺：和 iMac 的逐文件对比。在 iMac 上跑下面这条，和上表对比即可（settings.json 里有本机路径，哈希值不同不一定是问题，要看 diff）：

```bash
cd ~ && for f in .claude/CLAUDE.md .claude/settings.json .pi/agent/AGENTS.md .pi/agent/settings.json; do shasum -a256 "$f" | cut -c1-16 | tr '\n' ' '; echo "$f"; done; for d in .pi/agent/skills .pi/agent/extensions .claude/skills; do echo "$(cd $d && find . -type f -not -name .DS_Store | LC_ALL=C sort | xargs shasum -a256 | shasum -a256 | cut -c1-16) $d/"; done
```

## 2. 叫醒系统 —— 通过

- `~/.local/bin/` 下的 `notify-run`、`orca-wake`、`orca-wake-hooks`、`agent-probe`，以及 Pi 扩展 `dispatch-wake.ts`：`wake/install.sh --check` 显示全部「一致」（和 ops main 相同）。
- `orca-wake-hooks check`：UserPromptSubmit、Stop、StopFailure、PermissionRequest、Notification 都是 ok。
- `~/.config/grokbot/stuck-webhook.env` 存在，权限 600，变量名 `URL KEY`。
- `~/.config/grokbot/webhooks/` 下有 7 个文件（coding-assistant、deepvision-ads、deepvision-marketing、deepvision-ops、test、vllm-omni、xinyue），权限都是 600，变量名都是 `URL KEY`。webhook 指向 api2.cursor.sh，不经过 box。
- 测试叫醒：`notify-run --bot test --task "MBA setup v2 自检：测试叫醒（无需处理）" --no-tty -- bash -c 'echo ...'`，结果 `http=200 第1次`，日志一行：`2026-10-18T18:20:59+0800 bot=test status=done exit=0 http=200 try=1`。payload 里的 machine 取的是 `$(hostname)`，本机就是 `mba`。接收端有没有显示 mba，我这边看不到，需要在 test bot 那边看一眼。

## 3. EverOS —— 通过

- `~/.config/everos/` 下有 xinyue.env、deepvision.env、dv-ads.env、vllm-omni.env，权限都是 600。变量名都是 `EVEROS_BASE_URL EVEROS_API_KEY EVEROS_APP_ID EVEROS_PROJECT_ID EVEROS_AGENT_ID EVEROS_ASSISTANT_SENDER_ID EVEROS_USER_ID`。
- 在四个仓库的主 checkout 里跑 `claude mcp list`，everos 都是 `✔ Connected`，分别对应启动器 everos-mcp-xinyue、-deepvision、-dv-ads、-vllm-omni。启动器日志 `~/.local/state/everos-mcp/endpoint.log` 里四条都是 `endpoint=tailnet health=200`。
- 每个项目各打一次 `/health`：tailnet（100.64.0.5）四个都是 200（35–58 ms），公网 everos.deepvision.sg 四个也都是 200（0.7–1.2 s）。服务端版本 1.4.2，llm/embed/rerank 都为 true，cascade healthy。
- 顺带发现（不在本项范围）：Claude 插件 `plugin:github:github` 的 MCP 在四个仓库都连不上，报 `HTTP 400 Authorization header is badly formatted`，看起来是 GitHub token 环境变量没配或格式不对。没去动它。`gh` CLI 本身是好的。

## 4. 工具链 —— 通过

- nvm 0.40.3，node v22.23.2（nvm default）。
- gh：已登录 zhongc1211，scopes 为 gist、read:org、repo。
- git 全局身份：`zack <huixindaddy@yahoo.com>`。iMac 上的设置没能核对。
- runpodctl 2.15.0：`~/.runpod/config.toml` 存在，权限 600，里面有 apikey 和 apiurl 两项；只读的 `runpodctl get pod` 能正常返回，当前没有 pod。
- 各仓库 fetch：ops、xinyue-site、deepvision-site、deepvision-ads、vllm-omni（origin）都成功，vllm-omni 的 upstream 也成功。五个仓库都和上游一致。

## 5. Orca —— 项目和 Linear 通过；定时任务只核了 MBA 侧

- Orca 1.4.229，runtime 状态 ready。
- 五个仓库都在 Orca 里有项目，ID 和 PR #21 写的一致：ops 659a8841、xinyue-site 1c963975、deepvision-site d1fae3d4、deepvision-ads 4e5bd73a、vllm-omni c1ee517c。另外还有 Zack 自己建的 `local`，没动。
- Linear：`orca linear team list` 列出 FDV（deepvision）和 PER（personal），`orca linear issue PER-37` 能读到内容。连接正常。
- MBA 上已经有 8 个定时任务，全部是 enabled，2026-10-18 16:04 由上一轮配置创建，不是这次建的。我都没动：

  | 名称 | 时间 | 做什么 |
  |---|---|---|
  | 心月 · 13 EverOS 会话采集 MBA | 每天 21:50 | 采集 MBA 本机会话，推到 box |
  | dv运维 · 14 EverOS 官网会话采集 MBA | 每天 00:01 | 同上 |
  | dv广告 · 26 EverOS 广告会话采集 MBA | 每天 00:02 | 同上 |
  | vllm · 27 EverOS 会话采集 MBA | 每天 00:16 | 同上 |
  | ops · 09 内存与 CPU 负载清理 MBA | 每小时 :07 / :37 | 本机有压力时清理 |
  | ops · 10 内存与 CPU 日常清理 MBA | 每天 04:37 | 本机日常清理 |
  | ops · 11 Orca 工作区夜间清理 MBA | 每天 02:17 | 清理 MBA 上的 Orca 工作区 |
  | ops · 24 未推送扫描 MBA | 每小时 :29 | 扫描 MBA 工作区，日志写到 box |

  从名字和预检脚本看，这些都只处理 MBA 本机的数据，不会和 iMac 的同名任务重复干同一件事。但 iMac 上的清单拉不到，所以没法逐条对比。
- 风险：box 挂着，4 个会话采集任务和「ops · 24」都要 ssh 到 box。采集脚本连不上 box 时以 exit 2 退出、不推送（`cannot reach box over ssh; nothing pushed`）；未推送扫描会把日志存进 pending.log，等能连上时补发。所以不会出错，但 box 恢复前 MBA 的会话进不了夜审。
- 注意：「ops · 10」要跑 `~/orca/workspaces/ops/scripts/mem-cpu-cleanup.sh`，这个文件在 MBA 的 ops 仓库里是未跟踪状态（没进 git），iMac 上不一定有。没替它提交。
- 还缺：iMac 定时任务的清单和对比。在 iMac 上跑 `orca automations list`，或者打通 MBA→iMac 的 ssh 后重跑这一项。

## 6. Orca 配对 —— MBA→iMac 没配；iMac→MBA 据记录已配；box 待恢复

- MBA 上 `orca environment list` 显示 `No saved environments`，`orca host list` 只有本机。也就是说，MBA 还不能操作 iMac 的 Orca。
- iMac→MBA：按 orca-projects.md 第 7 节（PR #21）的记录，iMac 上用 `orca --environment mba` 来配 MBA，所以这个方向是通的。我在 MBA 上没法验证。
- 补配 MBA→iMac 需要 iMac 上 Orca 生成的配对码，而 MBA 连不上 iMac，没能做。
- box（100.64.0.6）：tailscale 显示 offline，ssh 超时。按 brief 记为「待 box 恢复」，没有反复试。

## 需要 Zack 做的（按顺序）

1. 打通 MBA→iMac 的 ssh（在 iMac 上操作）：把 MBA 的公钥 `~/.ssh/id_ed25519.pub`（注释 huixindaddy@yahoo.com）追加到 iMac 的 `~/.ssh/authorized_keys`。可以在 iMac 上跑 `ssh mba cat .ssh/id_ed25519.pub >> ~/.ssh/authorized_keys`。然后在 MBA 的 `~/.ssh/config` 里加 `Host imac / HostName 100.64.0.4 / User <iMac 用户名>`。
2. 在 iMac 的 Orca 里生成配对码，在 MBA 上跑 `orca environment add`。
3. 前两步做完后，重跑第 1 项和第 5 项的 iMac 对比（第 1 项的命令在上面）。
4. 在 test bot 那边看一眼 18:20:59 收到的那条叫醒，machine 是不是显示 mba。

总结：MBA 侧的叫醒系统、EverOS（4 个项目）、工具链、Orca 项目和 Linear 都通过，测试叫醒 http 200；MBA 连不上 iMac（公钥没授权），所以全局文件和 iMac 定时任务的对比没做，MBA→iMac 的 Orca 配对没配，box 配对待 box 恢复；没有新建或启用任何定时任务，MBA 上已有 8 个，都是上一轮建的 MBA 专属任务。
