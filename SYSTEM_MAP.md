# SYSTEM_MAP：ops 系统层地图

ops 管的系统层（机器、bot、叫醒链路、守护、夜审、Orca 自动任务）逐条列出「怎么验证它是活的」。格式和项目的 FEATURE_MAP 一样：**功能 / 入口 / 怎么验证 / 验证命令**，每行前面多一列检查 ID，`scripts/ops-verify` 按这张表逐条跑**只读**检查，报告格式见文末。

- 只管系统层，只在 ops 仓库。项目层（deepvision-site 的驱动 CLI + FEATURE_MAP）是 FDV-92，不在这里；两边报告字段一致（ID / 功能 / 结果 / 证据），方便将来共用一种报告。
- 这里不写任何 key、token、webhook URL 的值，只写文件路径和变量名。
- 自动任务清单：2026-10-20 20:15 SGT 三台实时 `orca automations list --json`（box 22 / iMac 16 / MBA 8，共 46 条），和 10-19 的备份 `/workspace/ops/backups/consolidation-20261019/automations/{box,imac,mba}-automations.json`（03:45，45 条）比只多 box `ops · 30`，见第 7 节。
- 现状日期：2026-10-20（PER-92）。只写已合进 main 并装到线上的东西；在跑没合的 PR 只列在第 9 节「待合」，不当成已上线。
- 根 README 里 ops-verify 那一节保持 #28 原样（#48 也在改根 README）；补充说明都写在这里。
- 地图有改动（加机器、加自动任务、改名、停用）时同一个 PR 里改这张表；`ops-verify` 发现实时和地图不一致就判 FAIL。

## 怎么跑

```bash
scripts/ops-verify                      # 全部检查，报告写到 ~/.orca-state/ops-verify/<时间>/report.{md,json}
scripts/ops-verify --only H-imac-01-hb  # 只跑一条（逗号分隔多条，也可写前缀 A-mba-）
scripts/ops-verify --list               # 列出地图里的检查 ID，不跑
scripts/ops-verify --out DIR            # 报告写到 DIR
```

结果：每条 PASS / FAIL / SKIP，都带证据（命令、实际值、阈值）。**有任何 FAIL 退出 1；0 条 PASS 退出 3**（全 SKIP 不算通过）；用法错 2。连不上的机器记 FAIL 或 SKIP 并写原因，不当成通过。

跨机通道（都是只读）：

| 机器 | 通道 | 能查什么 |
|---|---|---|
| box | 本机 | 全部 |
| iMac | box 上 `orca --environment iMac <只读命令>`（`status`、`automations list`、`automations runs`）；box 没有到 iMac 的 ssh key | 自动任务、运行记录、心跳。iMac 上的文件（脚本版本、入口文件、heartbeat.json、webhook 变量名）要开终端探针：`OPS_VERIFY_IMAC_TERMINAL=1`，会在 iMac 的一个工作区（默认 ops 主工作区，`OPS_VERIFY_IMAC_WORKTREE` 可改）开一个临时终端跑一段只读 Python、读完关掉；默认不开，这几项记 SKIP。10-20 20:1x SGT 这个通道间歇报过 `remote_runtime_unavailable`（box 上 environment `iMac` 走 `wss://orca.deepvision.sg/client-ws`），重试后恢复；连不上时 iMac 各项记 FAIL，不当通过 |
| MBA | tailnet ssh（`ssh mba`，`~/.ssh/config` 里的 Host） | 全部（Orca CLI 用 `/Applications/Orca.app/Contents/Resources/bin/orca`） |

可调的环境变量（演练和排障用）：

| 变量 | 默认 | 作用 |
|---|---|---|
| `OPS_VERIFY_SKIP` | 空 | 逗号分隔的检查 ID 或前缀，记 SKIP；`all` = 全部 SKIP |
| `OPS_VERIFY_EVEROS_HEALTH_URL` | EverOS 的 tailnet health 地址（脚本内置，和夜审 prompt 一致） | EverOS health 检查目标 |
| `OPS_VERIFY_EVEROS_HOST` | 脚本内置 | health 请求带的 Host 头 |
| `OPS_VERIFY_HB_FILE` | `~/.orca-state/heartbeat-watch/heartbeat.json` | box 心跳文件 |
| `OPS_VERIFY_HB_MAX_MIN` | `20` | 心跳最长间隔（分钟），和 heartbeat-watch 的 N 一致 |
| `OPS_VERIFY_WAKE_REF` | `origin/main`（F1–F8 已合进 main 并装三台） | W-bin-*、W-scripts-*、G-box-watchdog-rev 版本比对的 git ref（ops-verify 不 fetch，跑前自己 `git fetch`） |
| `OPS_VERIFY_MBA_SSH` | `mba` | MBA 的 ssh 目标 |
| `OPS_VERIFY_IMAC_TERMINAL` | 空 | `1` = 开 iMac 终端探针 |
| `OPS_VERIFY_IMAC_WORKTREE` | iMac ops 主工作区 | 探针终端开在哪个 iMac 工作区（Orca worktree selector，如 `id:<repoId>::<path>`）；演练时指到自己的工作区，不在别人的工作区开终端 |

## 1. 机器

| ID | 功能 | 入口 | 怎么验证 | 验证命令 |
|---|---|---|---|---|
| M-box-orca | box（Grok Bot 电脑，Linux，tailnet 100.64.0.6）：Orca 服务端、box 自动任务、bot 派活的 agent | `orca-ide serve`（tmux `orca-remote`，看门狗拉起） | `orca status --json`：`runtime.state=ready`、`reachable=true` | `scripts/ops-verify --only M-box-orca` |
| M-imac-orca | iMac（macOS，tailnet 100.64.0.4）：卡住检查、orca-bot 守护、哨兵、iMac 采集 | Orca.app；box 侧 environment 名 `iMac` | `orca --environment iMac status --json`：`ready` | `scripts/ops-verify --only M-imac-orca` |
| M-mba-orca | MBA（macOS，tailnet 100.64.0.7）：正式机器（和 box、iMac 同等：叫醒脚本、hook、webhook 配置、自动任务都在册）；MBA 采集、清理、未推送扫描 | Orca.app；`ssh mba` | `ssh mba <orca> status --json`：`ready` | `scripts/ops-verify --only M-mba-orca` |
| T-site-node | EverOS VPS（site，tailnet 100.64.0.5）：EverOS 服务 | tailnet 节点 `site` | `tailscale status --json`：`site` 在线 | `scripts/ops-verify --only T-site-node` |
| E-everos-health | EverOS 服务活着 | tailnet 上 `/health`（带 Host 头；地址见夜审 prompt / `~/.config/everos/*.env` 的 `EVEROS_BASE_URL`） | HTTP 200 | `scripts/ops-verify --only E-everos-health` |
| T-headscale | headscale（tailnet 控制面，`tailscale status` 的 `CurrentTailnet.Name`） | box 的 tailscaled | `BackendState=Running`、本机在线、控制面名字是 headscale | `scripts/ops-verify --only T-headscale` |
| T-imac-node | iMac 在 tailnet 上 | 节点 `imac` | `tailscale status --json`：在线 | `scripts/ops-verify --only T-imac-node` |
| T-mba-node | MBA 在 tailnet 上 | 节点 `mba` | `tailscale status --json`：在线 | `scripts/ops-verify --only T-mba-node` |

## 2. Bot

bot 本身跑在 Grok 侧，各机器只存叫醒它们的 webhook 配置（`~/.config/grokbot/webhooks/<bot>.env`，变量名 `URL`、`KEY`；放行名单 `~/.config/orca-wake/enabled-bots`）。只读能验证的是「配置在、放行名单里有」；bot 真能收到要发一条测试叫醒，见第 8 节（未实现，等 Zack 定）。`B-<bot>` 查 box，`B-mba-<bot>`、`B-imac-<bot>` 查 MBA、iMac（iMac 要终端探针，默认 SKIP）。

| ID | 功能 | 入口 | 怎么验证 | 验证命令 |
|---|---|---|---|---|
| B-coding-assistant | Coding助手：验收、卡住检查和心跳报警的收件人 | `~/.config/grokbot/webhooks/coding-assistant.env` | 文件在、有 `URL=`、`KEY=` 两个变量（不读出值）；在 `~/.config/orca-wake/enabled-bots` | `scripts/ops-verify --only B-coding-assistant` |
| B-deepvision-ops | dv运维 bot | `~/.config/grokbot/webhooks/deepvision-ops.env` | 同上 | `scripts/ops-verify --only B-deepvision-ops` |
| B-deepvision-ads | dv广告 bot | `~/.config/grokbot/webhooks/deepvision-ads.env` | 同上 | `scripts/ops-verify --only B-deepvision-ads` |
| B-deepvision-marketing | dv营销 bot | `~/.config/grokbot/webhooks/deepvision-marketing.env` | 同上 | `scripts/ops-verify --only B-deepvision-marketing` |
| B-vllm-omni | vllm bot | `~/.config/grokbot/webhooks/vllm-omni.env` | 同上 | `scripts/ops-verify --only B-vllm-omni` |
| B-xinyue | 心月 bot | `~/.config/grokbot/webhooks/xinyue.env` | 同上 | `scripts/ops-verify --only B-xinyue` |
| B-test | test bot：演练专用（`--bot test`、`*_FORCE_BOT=test`），不在放行名单里也正常 | `~/.config/grokbot/webhooks/test.env` | 文件在、有 `URL=`、`KEY=` | `scripts/ops-verify --only B-test` |
| B-ops-system | ops 系统 bot：接 ops 派活的叫醒（`orca-agent-launch --bot ops-system`）；EverOS 唯一写入方（见第 5b 节）。#45 合并后卡住检查的告警也改发它（第 9 节） | box `~/.config/grokbot/webhooks/ops-system.env` | 文件在、有 `URL=`、`KEY=`；在 enabled-bots | `scripts/ops-verify --only B-ops-system` |
| B-mba-ops-system | 同上，MBA | MBA `~/.config/grokbot/webhooks/ops-system.env` | 同上（`ssh mba` 跑只读探针，只回变量名） | `scripts/ops-verify --only B-mba-ops-system` |
| B-imac-ops-system | 同上，iMac | iMac `~/.config/grokbot/webhooks/ops-system.env` | 同上（终端探针；默认 SKIP） | `scripts/ops-verify --only B-imac-ops-system` |
| B-imac-coding-assistant | Coding助手，iMac 侧配置：iMac 上的 stuck-check、heartbeat-watch、orca-bot 守护从这里读 | iMac `~/.config/grokbot/webhooks/coding-assistant.env` | 同上（终端探针；默认 SKIP） | `scripts/ops-verify --only B-imac-coding-assistant` |

- box 还有一个 `e2e-down`（`e2e-down.env`，在 box 的 enabled-bots 里）：PER-67 真 E2E 缺口 4/7/8 演练用的「发送必失败」bot，不叫醒任何人，地图不设检查；演练结束删掉时不用改地图。
- dr eggbot 是 Grok Bot 侧的系统 bot（违规检查、周一体检），对 EverOS 只读（查询、核对），box 上没有它的 webhook，不在叫醒链路里。

## 3. 叫醒链路

叫醒修复 F1–F8（#37–#43，main `1883faf`）已合并并装到三台：三台 `~/.local/bin/` 下 6 个叫醒脚本、box/iMac 的 heartbeat-watch、iMac 的 stuck-check 和 `1883faf` 之后的 main 一致（10-20 20:15 SGT 逐个 sha256 对过）。W-bin-*、W-scripts-* 盯的就是这件事：线上和 main 不一致判 FAIL。

| ID | 功能 | 入口 | 怎么验证 | 验证命令 |
|---|---|---|---|---|
| W-bin-box | Orca 完成 → notify-run → webhook → bot：派活统一入口 `orca-agent-launch` 包 `notify-run --tty`，agent 退出时 notify-run 发 webhook；agent 停在输入框时 Claude hook / Pi 扩展调 `orca-wake` 发；`agent-stop` 写主动停止标记 | box `~/.local/bin/{notify-run,orca-agent-launch,orca-wake,orca-wake-hooks,agent-stop,agent-probe}`（`wake/install.sh` 装的 6 个） | 6 个文件都在，sha256 和 `OPS_VERIFY_WAKE_REF` 里 `wake/bin/*`、`scripts/agent-probe` 一致 | `scripts/ops-verify --only W-bin-box` |
| W-bin-mba | 同上，MBA | MBA `~/.local/bin/*` | 同上（`ssh mba` 算 sha256） | `scripts/ops-verify --only W-bin-mba` |
| W-bin-imac | 同上，iMac | iMac `~/.local/bin/*` | 同上（终端探针；默认 SKIP） | `scripts/ops-verify --only W-bin-imac` |
| W-scripts-box | 叫醒相关的其他已装脚本，box：heartbeat-watch（ops · 29）、automation-reaper（ops · 30） | box `~/.orca-state/bin/{heartbeat-watch.sh,automation-reaper.sh}` | sha256 和 ref 里 `scripts/` 同名文件一致 | `scripts/ops-verify --only W-scripts-box` |
| W-scripts-imac | 同上，iMac：heartbeat-watch（ops · 29）、stuck-check（ops · 01，直接从 ops 主工作区跑）、orca-bot 守护（ops · 03） | iMac `~/.orca-state/bin/heartbeat-watch.sh`、`~/orca/workspaces/ops/scripts/{stuck-check.sh,orca-bot-guard.sh}` | 同上（终端探针；默认 SKIP） | `scripts/ops-verify --only W-scripts-imac` |
| W-hooks-box | Claude Code 的 orca-wake hook 条目 | box `~/.claude/settings.json` | `orca-wake-hooks check`（只读）退出 0 | `scripts/ops-verify --only W-hooks-box` |
| W-hooks-mba | 同上，MBA | MBA `~/.claude/settings.json` | `ssh mba ~/.local/bin/orca-wake-hooks check` 退出 0 | `scripts/ops-verify --only W-hooks-mba` |
| W-stuck-chain | stuck-check → coding-assistant：iMac「ops · 01 卡住工作检查」每分钟 `stuck-check.sh --scan`，漏叫的兜底补叫（#45 合并后改发 ops-system） | iMac `$HOME/orca/workspaces/ops/scripts/stuck-check.sh` | 心跳见 H-imac-01-hb；收件人配置见 B-imac-coding-assistant（iMac 上的配置，默认 SKIP）。**不跑 `--send`** | `scripts/ops-verify --only H-imac-01-hb,B-imac-coding-assistant` |

## 4. 守护与心跳

| ID | 功能 | 入口 | 怎么验证 | 验证命令 |
|---|---|---|---|---|
| H-imac-01-hb | stuck-check 心跳：每次跑完 stdout 打 `@@HB {"ts","mode","rc","last_scan"}`，Orca 运行记录里留着 | iMac 自动任务 `439cd438`（ops · 01） | `orca --environment iMac automations runs --id <id>`：最新 `@@HB` 的 `ts` 不超过 20 分钟、`last_scan` 不超过 35 分钟 | `scripts/ops-verify --only H-imac-01-hb` |
| H-box-29-hb | heartbeat-watch 互查（box 侧，盯 iMac ops · 01）：自己每次也打 `@@HB` | box 自动任务 `94e4b0bc`（ops · 29）`~/.orca-state/bin/heartbeat-watch.sh` | 本机运行记录最新 `@@HB` 不超过 20 分钟 | `scripts/ops-verify --only H-box-29-hb` |
| H-box-hbfile | 同上，心跳文件 | box `~/.orca-state/heartbeat-watch/heartbeat.json` | `ts` 不超过 20 分钟、`rc` 是 0 | `scripts/ops-verify --only H-box-hbfile` |
| H-imac-29-hb | heartbeat-watch 互查（iMac 侧，盯 box ops · 29） | iMac 自动任务 `5c2d0575`（ops · 29） | iMac 运行记录最新 `@@HB` 不超过 20 分钟 | `scripts/ops-verify --only H-imac-29-hb` |
| H-imac-hbfile | 同上，iMac 心跳文件 | iMac `~/.orca-state/heartbeat-watch/heartbeat.json` | 终端探针读 `ts`、`rc`（默认 SKIP） | `scripts/ops-verify --only H-imac-hbfile` |
| G-box-watchdog | box Orca 看门狗：45 秒一轮，Orca/隧道不健康时重启；#40 起卡顿/暂停后不误杀 cloudflared、不马上整套重启，每轮写状态文件 | `/workspace/ops/orca-remote/watchdog.sh`（`ensure-watchdog.sh` 拉起），状态 `/workspace/ops/orca-remote/watchdog.state` | 进程在；`watchdog.state` 的 `updated` 不超过 5 分钟（证据附 `state`、local/public 码）；证据附 `watchdog.log` 最近 60 分钟重启次数 | `scripts/ops-verify --only G-box-watchdog` |
| G-box-watchdog-rev | 看门狗版本：#40 的 rev 2026-10-19（`3d8294b` 起在 main，含 #44 的 D 演练） | `/workspace/ops/orca-remote/{watchdog.sh,orca-remote}` | sha256 和 ref 里 `orca-remote/watchdog.sh`、`orca-remote/orca-remote` 一致 | `scripts/ops-verify --only G-box-watchdog-rev` |
| G-imac-orca-bot-guard | orca-bot 守护：iMac 每 5 分钟探 box 的 Orca 公网入口，连续 2 次不通叫 Coding助手 | iMac 自动任务 `30e9bcaa`（ops · 03）`scripts/orca-bot-guard.sh` | iMac 运行记录：最新一次不超过 15 分钟 | `scripts/ops-verify --only G-imac-orca-bot-guard` |

## 5. 夜审

夜审写 EverOS 后的读回检查是 PER-67 a 的事，这里只看「每晚跑了、没失败」。

| ID | 功能 | 入口 | 怎么验证 | 验证命令 |
|---|---|---|---|---|
| N-box-75b324a4 | 心月夜审（模板） | box 自动任务 `75b324a4`（心月 · 18） | 最新运行在 26 小时内、状态 `completed` | `scripts/ops-verify --only N-box-75b324a4` |
| N-box-27383c07 | 心月夜审兜底 | box 自动任务 `27383c07`（心月 · 19），precheck 判断要不要补跑 | 最新运行在 26 小时内、状态 `completed` 或 `skipped_precheck` | `scripts/ops-verify --only N-box-27383c07` |
| N-box-43c55a22 | 官网夜审 | box 自动任务 `43c55a22`（dv运维 · 20） | 最新运行在 26 小时内、`completed` | `scripts/ops-verify --only N-box-43c55a22` |
| N-box-9b5c20e7 | 广告夜审 | box 自动任务 `9b5c20e7`（dv广告 · 21） | 同上 | `scripts/ops-verify --only N-box-9b5c20e7` |
| N-box-c392a743 | vllm 夜审 | box 自动任务 `c392a743`（vllm · 22） | 同上 | `scripts/ops-verify --only N-box-c392a743` |

## 5b. EverOS 归属（#47，PER-84）

- **ops 系统是 EverOS 唯一写入方**：服务端、部署、教训/skill 导入、写入都归 ops 系统（`everos-deploy/*`、`everos-mcp/MCP-WIRING-STANDARD-v2.md`、`everos/deepvision-ads-import/*` 已改）。会写 EverOS 的自动任务：5 条夜审（第 5 节）、各机会话采集（第 6 节名字带「EverOS … 采集」的）、iMac `心月 · 28 EverOS 经验写入`。
- **dr eggbot 只读**：只做查询、核对，不写。
- ops-verify 只查 EverOS 活着（E-everos-health）和这些自动任务在册、在跑；「谁有写权限」要读 key 或发写请求才能验，ops-verify 不做（只读、不读 key 值），不设检查 ID。

## 6. Orca 自动任务（46 条 = 10-20 20:15 三台实时清单）

每条：实时 `orca automations list` 里有同 id、名字一致、enabled 一致；有 precheck 的，入口文件存在且可执行（iMac 的入口文件要终端探针，默认只核对列表并在证据里注明没查文件）。另外每台机器一条汇总检查 `A-<机器>-list`：实时条数和地图一致，多出来的（地图里没有）判 FAIL。

| ID | 机器 | 名字 | 自动任务 id | enabled | 时间 | 入口 | 怎么验证 | 验证命令 |
|---|---|---|---|---|---|---|---|---|
| A-box-list | box | （汇总） | — | — | — | `orca automations list --json` | 条数 = 地图里 box 的条数，没有地图外的 | `scripts/ops-verify --only A-box-list` |
| A-imac-list | iMac | （汇总） | — | — | — | `orca --environment iMac automations list --json` | 同上 | `scripts/ops-verify --only A-imac-list` |
| A-mba-list | MBA | （汇总） | — | — | — | `ssh mba <orca> automations list --json` | 同上 | `scripts/ops-verify --only A-mba-list` |
| A-box-9b5c20e7 | box | dv广告 · 21 夜审 | `9b5c20e7-919f-4e74-80ea-2b57eb9270d9` | 是 | `10 0 * * *` | （无 precheck，模型按 prompt 跑） | 实时列表同 id、同名、enabled=是；夜审见 N-box-9b5c20e7 | `scripts/ops-verify --only A-box-9b5c20e7` |
| A-box-91fa38d4 | box | dv广告 · 26 EverOS 广告会话采集 box | `91fa38d4-83bc-42ae-94ec-9e405c11399d` | 是 | `6 0 * * *` | `/workspace/ops/everos-ingest/collect-box-repo.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-91fa38d4` |
| A-box-207ff52e | box | dv运维 · 14 EverOS 官网会话采集 box | `207ff52e-2dfb-4365-9b3d-3951ef3054ca` | 是 | `5 0 * * *` | `/workspace/ops/everos-ingest/collect-box-deepvision-site.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-207ff52e` |
| A-box-43c55a22 | box | dv运维 · 20 夜审 官网 | `43c55a22-35fb-428e-b0a5-65128ca3c332` | 是 | `10 0 * * *` | （无 precheck，模型按 prompt 跑） | 实时列表同 id、同名、enabled=是；夜审见 N-box-43c55a22 | `scripts/ops-verify --only A-box-43c55a22` |
| A-box-f23cf116 | box | ops · 04 box 内存日志 | `f23cf116-a65f-4c80-8425-5361999530c0` | 是 | `* * * * *` | `/workspace/ops/box-guard/mem-log-once.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-f23cf116` |
| A-box-d14a8742 | box | ops · 05 box 孤儿测试进程守护 | `d14a8742-44ed-4c9a-b684-52c8b6f3acbc` | 是 | `* * * * *` | `/workspace/ops/box-guard/mem-guard-once.py` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-d14a8742` |
| A-box-22e3b787 | box | ops · 06 box 新测试进程 choom | `22e3b787-2108-4976-a2e6-df8ca534c4d2` | 是 | `* * * * *` | `/workspace/ops/box-guard/choom-new.py` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-22e3b787` |
| A-box-b634c71f | box | ops · 07 box 看门狗间隙核对 | `b634c71f-9c6b-400f-b129-3f434fd4ba02` | 是 | `*/10 * * * *` | `/workspace/ops/box-guard/watchdog-gap-check.py` | 实时列表同 id、同名、enabled=是；入口存在且可执行；看门狗本体见 G-box-watchdog | `scripts/ops-verify --only A-box-b634c71f` |
| A-box-c1d53602 | box | ops · 08 box tailscaled+sshd 守护 | `c1d53602-d433-4bf9-9b6c-55e3b154ffa3` | 是 | `*/15 * * * *` | `/workspace/ops/everos-ingest/ensure-sshd-precheck.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-c1d53602` |
| A-box-7a7e7e97 | box | ops · 09 内存与 CPU 负载清理 box | `7a7e7e97-aef2-4858-9d89-4c6d4c267209` | 是 | `7,37 * * * *` | `/workspace/ops/box-guard/pressure-cleanup-precheck.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-7a7e7e97` |
| A-box-8c40fa83 | box | ops · 10 内存与 CPU 日常清理 box | `8c40fa83-8943-4ae3-8d41-8faa3e47d588` | 是 | `37 4 * * *` | （无 precheck，模型按 prompt 跑） | 实时列表同 id、同名、enabled=是 | `scripts/ops-verify --only A-box-8c40fa83` |
| A-box-1191c819 | box | ops · 11 Orca 工作区夜间清理 box | `1191c819-9bb6-4f71-9f1e-7ad5776f3485` | 是 | `17 2 * * *` | （无 precheck，模型按 prompt 跑） | 实时列表同 id、同名、enabled=是 | `scripts/ops-verify --only A-box-1191c819` |
| A-box-bc9ee42b | box | ops · 12 Linear 状态对齐 | `bc9ee42b-77f7-46e2-b6ca-283548db6334` | 是 | `47 8 * * *` | `orca` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-bc9ee42b` |
| A-box-21907e6b | box | ops · 24 未推送扫描 box | `21907e6b-0267-47be-b033-6648816e2a3b` | 是 | `27 * * * *` | `/workspace/ops/sentinels/unpushed-scan.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-21907e6b` |
| A-box-94e4b0bc | box | ops · 29 卡住检查心跳（盯 iMac ops · 01） | `94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80` | 是 | `*/5 * * * *` | `$HOME/.orca-state/bin/heartbeat-watch.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行；心跳见 H-imac-01-hb、H-box-29-hb | `scripts/ops-verify --only A-box-94e4b0bc` |
| A-box-349967f6 | box | vllm · 17 上游 PR 监控 | `349967f6-8d47-46f4-9df0-e3c10107bb4e` | 是 | `17 */3 * * *` | `/workspace/repos/ops/scripts/vllm-upstream-precheck.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-349967f6` |
| A-box-c392a743 | box | vllm · 22 夜审 | `c392a743-f062-426b-8c89-4a4bbcf72a69` | 是 | `30 0 * * *` | （无 precheck，模型按 prompt 跑） | 实时列表同 id、同名、enabled=是；夜审见 N-box-c392a743 | `scripts/ops-verify --only A-box-c392a743` |
| A-box-4ce0c307 | box | vllm · 27 EverOS 会话采集 box | `4ce0c307-dd48-4678-9f30-6868b4924d06` | 是 | `20 0 * * *` | `/workspace/ops/everos-ingest/collect-box-repo.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-4ce0c307` |
| A-box-14999b4f | box | 心月 · 13 EverOS 会话采集 box | `14999b4f-f7a9-4e18-be87-f1b68c14f1d3` | 是 | `0 22 * * *` | `/workspace/ops/everos-ingest/collect-box.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-box-14999b4f` |
| A-box-75b324a4 | box | 心月 · 18 夜审 | `75b324a4-bf7d-414d-83b7-325a4030a3ea` | 是 | `30 23 * * *` | （无 precheck，模型按 prompt 跑） | 实时列表同 id、同名、enabled=是；夜审见 N-box-75b324a4 | `scripts/ops-verify --only A-box-75b324a4` |
| A-box-27383c07 | box | 心月 · 19 夜审兜底 | `27383c07-27b1-4417-9aaa-b15a46fd68b3` | 是 | `30 0 * * *` | `/workspace/ops/everos-ingest/night-review-guard-xinyue.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行；夜审见 N-box-27383c07 | `scripts/ops-verify --only A-box-27383c07` |
| A-box-b33089be | box | ops · 30 自动任务 claude 清理（box） | `b33089be-ef9a-40af-a364-4416e0b57200` | 是 | `7,37 * * * *` | `$HOME/.orca-state/bin/automation-reaper.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行；**备份（03:45）之后新增** | `scripts/ops-verify --only A-box-b33089be` |
| A-imac-8b06646f | iMac | dv广告 · 26 EverOS 广告会话采集 iMac | `8b06646f-e4f2-4be6-b5f7-bc3acfb351a0` | 是 | `2 0 * * *` | `/Users/jiawenwang/.orca-state/bin/everos-ingest/collect-imac-repo.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-8b06646f` |
| A-imac-827e1814 | iMac | dv营销 · 16 SEO/GEO 周检 | `827e1814-648b-41d5-bd9a-7d21c3e1f981` | 是 | `47 8 * * 1` | `$HOME/.orca-state/bin/seo-weekly-precheck.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-827e1814` |
| A-imac-34fe1ab0 | iMac | dv运维 · 14 EverOS 官网会话采集 iMac | `34fe1ab0-7b3d-4e6a-917a-2c254e0e6dc6` | 是 | `1 0 * * *` | `/Users/jiawenwang/.orca-state/bin/everos-ingest/collect-imac-deepvision-site.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-34fe1ab0` |
| A-imac-439cd438 | iMac | ops · 01 卡住工作检查 | `439cd438-cffe-44dd-bd2b-23b07bfa3d61` | 是 | `* * * * *` | `$HOME/orca/workspaces/ops/scripts/stuck-check.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行；心跳见 H-imac-01-hb | `scripts/ops-verify --only A-imac-439cd438` |
| A-imac-c7692ae9 | iMac | ops · 02 卡住工作检查 codex 备用 | `c7692ae9-9949-43b4-94d5-4e1a51411645` | 是 | `53 8-23 * * *` | `$HOME/.orca-state/bin/orca-fallback.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-c7692ae9` |
| A-imac-30e9bcaa | iMac | ops · 03 orca-bot 守护（iMac 拉起 box） | `30e9bcaa-87cc-4e56-a601-50c39d1c4e84` | 是 | `*/5 * * * *` | `/Users/jiawenwang/orca/workspaces/ops/scripts/orca-bot-guard.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行；运行记录见 G-imac-orca-bot-guard | `scripts/ops-verify --only A-imac-30e9bcaa` |
| A-imac-c498bba3 | iMac | ops · 09 内存与 CPU 负载清理 iMac | `c498bba3-3b5c-4e8a-be39-d9797ac17e1b` | 是 | `7,37 * * * *` | `$HOME/.orca-state/bin/pressure-cleanup-precheck.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-c498bba3` |
| A-imac-b0e92e5c | iMac | ops · 10 内存与 CPU 日常清理 iMac | `b0e92e5c-c746-4147-9ec5-48453f24ed35` | 是 | `FREQ=DAILY;BYHOUR=4;BYMINUTE=37` | `$HOME/.orca-state/bin/orca-due.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-b0e92e5c` |
| A-imac-5d8c9d50 | iMac | ops · 11 Orca 工作区夜间清理 iMac | `5d8c9d50-6640-4747-bd37-a9a69703f1cb` | 是 | `17 2 * * *` | （无 precheck，模型按 prompt 跑） | 实时列表同 id、同名、enabled=是 | `scripts/ops-verify --only A-imac-5d8c9d50` |
| A-imac-93dd232e | iMac | ops · 15 CF 用量监控 | `93dd232e-a3cf-4b85-823b-ce116d2bd0ae` | 是 | `17 21 * * *` | `$HOME/.orca-state/bin/cf-usage-check.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-93dd232e` |
| A-imac-b3473001 | iMac | ops · 23 生产版本哨兵 | `b3473001-6869-4ed0-9b70-9a51d5ad6f1c` | 是 | `10,25,40,55 * * * *` | `$HOME/.orca-state/bin/sentinels/prod-watch.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-b3473001` |
| A-imac-6f9d3cff | iMac | ops · 24 未推送扫描 iMac | `6f9d3cff-c8aa-4af9-84b6-fa967e5f79c2` | 是 | `29 * * * *` | `$HOME/.orca-state/bin/sentinels/unpushed-scan.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-6f9d3cff` |
| A-imac-5c2d0575 | iMac | ops · 29 心跳互查（盯 box ops · 29） | `5c2d0575-dddc-4d5c-8f73-e47b26ea9a11` | 是 | `*/5 * * * *` | `$HOME/.orca-state/bin/heartbeat-watch.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行；心跳见 H-imac-29-hb | `scripts/ops-verify --only A-imac-5c2d0575` |
| A-imac-89faa2a6 | iMac | vllm · 27 EverOS 会话采集 iMac | `89faa2a6-f699-4649-9848-0ed18ad35e6e` | 是 | `16 0 * * *` | `/Users/jiawenwang/.orca-state/bin/everos-ingest/collect-imac-repo.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-89faa2a6` |
| A-imac-60eeb06e | iMac | 心月 · 13 EverOS 会话采集 iMac | `60eeb06e-98b0-4d7a-ae41-4a45fed35dbb` | 是 | `50 21 * * *` | `/Users/jiawenwang/.orca-state/bin/everos-ingest/collect-imac.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-60eeb06e` |
| A-imac-e5f593e2 | iMac | 心月 · 28 EverOS 经验写入 | `e5f593e2-701f-4693-95d1-ce9c2fb4d7af` | 是 | `20 0,7 * * *` | `$HOME/.orca-state/bin/everos-ingest/skills-import/skills-import.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-imac-e5f593e2` |
| A-mba-679f7c06 | MBA | dv广告 · 26 EverOS 广告会话采集 MBA | `679f7c06-363c-462d-b097-92e843c6e053` | 是 | `2 0 * * *` | `$HOME/.orca-state/bin/everos-ingest/collect-mba-repo.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-mba-679f7c06` |
| A-mba-25ec90b7 | MBA | dv运维 · 14 EverOS 官网会话采集 MBA | `25ec90b7-4171-4aa1-96c5-25f1a9252fde` | 是 | `1 0 * * *` | `$HOME/.orca-state/bin/everos-ingest/collect-mba-deepvision-site.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-mba-25ec90b7` |
| A-mba-62d18b16 | MBA | ops · 09 内存与 CPU 负载清理 MBA | `62d18b16-74ca-4c7f-a670-04197e7652fe` | 是 | `7,37 * * * *` | `$HOME/.orca-state/bin/pressure-cleanup-precheck.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-mba-62d18b16` |
| A-mba-56357524 | MBA | ops · 10 内存与 CPU 日常清理 MBA | `56357524-b0e2-4a0e-803f-077740ab8701` | 是 | `FREQ=DAILY;BYHOUR=4;BYMINUTE=37` | `$HOME/.orca-state/bin/orca-due.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-mba-56357524` |
| A-mba-ed1add9a | MBA | ops · 11 Orca 工作区夜间清理 MBA | `ed1add9a-bafe-4812-af5d-e78ca9bc59db` | 是 | `17 2 * * *` | （无 precheck，模型按 prompt 跑） | 实时列表同 id、同名、enabled=是 | `scripts/ops-verify --only A-mba-ed1add9a` |
| A-mba-bd1c94e9 | MBA | ops · 24 未推送扫描 MBA | `bd1c94e9-312f-48eb-a46c-9a62a0de6ba1` | 是 | `29 * * * *` | `$HOME/.orca-state/bin/sentinels/unpushed-scan.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-mba-bd1c94e9` |
| A-mba-fc1dd06a | MBA | vllm · 27 EverOS 会话采集 MBA | `fc1dd06a-de08-40a2-9f26-19106f6cd3ba` | 是 | `16 0 * * *` | `$HOME/.orca-state/bin/everos-ingest/collect-mba-repo.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-mba-fc1dd06a` |
| A-mba-5a9491fe | MBA | 心月 · 13 EverOS 会话采集 MBA | `5a9491fe-32f0-4a73-950d-58197a13b12e` | 是 | `50 21 * * *` | `$HOME/.orca-state/bin/everos-ingest/collect-mba.sh` | 实时列表同 id、同名、enabled=是；入口存在且可执行 | `scripts/ops-verify --only A-mba-5a9491fe` |

## 7. 对账

| 来源 | box | iMac | MBA | 合计 |
|---|---|---|---|---|
| 备份 2026-10-19 03:45（权威清单） | 21 | 16 | 8 | 45 |
| 本地图 | 22 | 16 | 8 | 46 |
| 差异 | +1：`ops · 30 自动任务 claude 清理（box）`（`b33089be`，10-19 04:54 建，PER-66 第 6 项） | 0 | 0 | +1 |
| 实时 2026-10-20 20:15 SGT（`orca automations list --json`，box 本机 / iMac 本机 / MBA `ssh mba`） | 22 | 16 | 8 | 46 |
| 实时和本地图 | 一致（id、名字、enabled、precheck 入口） | 一致 | 一致 | 0 |

## 8. 可选项（等 Zack 定，未实现）

- **发测试 wake 看 bot 收到**：给 test bot 发一条叫醒（`--bot test`），确认 webhook → bot 整条通。这其实就是演练（Zack 10-19 01:59「演练先不搞」），而且只能发 test bot，不能叫醒真 bot（花 Grok 额度、会打断审批卡片）。`ops verify` 默认只读，不做这项；Zack 同意后再加，加了也只发 test。
- **stuck-check 跑一轮**：`--scan` 有状态写入（pending.json、指纹），`--send` 会发 webhook，都不是只读；现在只读它留在运行记录里的心跳。

## 9. 待合（在跑、没合 main，不算已上线）

| PR / 工作 | 改什么 | 合并装上后地图要改 |
|---|---|---|
| #45 | 卡住检查：ops 工作区的告警发 ops-system；脱离父进程的子 agent 不再报「没包 notify-run」（`scripts/stuck-check.sh`、`scripts/agent-probe`） | W-stuck-chain 收件人改 B-imac-ops-system；W-bin-*、W-scripts-imac 跟着比新版本 |
| PER-88 叫醒预过滤 | `wake/**` 预过滤 | W-bin-* 跟着比新版本 |
| #48（PER-83/PER-89） | bootstrap/claude-plugins：pstack、compound-engineering 锁版本；根 README | 如果加了三台插件版本检查，同步加 ID |

## 报告格式

`report.json`：

```json
{"tool": "ops-verify", "map": "SYSTEM_MAP.md", "commit": "<sha>", "started": "...", "host": "box",
 "summary": {"PASS": 0, "FAIL": 0, "SKIP": 0}, "exit": 0,
 "checks": [{"id": "E-everos-health", "feature": "...", "status": "PASS", "evidence": "...", "seconds": 0.4}]}
```

`report.md`：同样内容的表格（ID / 功能 / 结果 / 证据）。字段和 FEATURE_MAP 的驱动 CLI 报告对齐：一行一条，结果三选一，证据必填。
