# ops

Zack 的运维仓库：EverOS 记忆系统、派活 agent 的叫醒和守护、box 运维和 Orca 定时任务（automations）用的脚本。
Orca 项目和工作区清单见 [orca-projects.md](orca-projects.md)。

## EverOS 记忆系统

| 目录 | 内容 |
|---|---|
| [`everos-deploy/`](everos-deploy/) | site VPS 上 EverOS 的部署方案、安装记录、DNS、导入证据 |
| [`everos/`](everos/) | 各项目旧记忆（LESSONS 等）导入 EverOS 的脚本和记录 |
| [`everos-ingest/`](everos-ingest/) | 会话采集、夜审写记忆（心月、广告）和相关守护脚本 |
| [`everos-mcp/`](everos-mcp/) | coding agent 接入标准（v2.x）、启动器模板、pi 扩展、验证证据 |
| [`everos-incidents/`](everos-incidents/) | 事故和变更记录：524 超时、开 embedding、qwen3 重排转发 |

## 叫醒和守护

| 路径 | 内容 |
|---|---|
| [`wake/`](wake/) | agent 停下时叫醒派活 bot：`orca-wake`、`orca-wake-hooks`、`notify-run`、Pi 扩展。原 `orca-agent-wake` 仓库，2026-10-17 并入（保留历史） |
| [`wake/install.sh`](wake/install.sh) | 在 iMac / box 上安装叫醒脚本和 `agent-probe`（`--check` 只比对） |
| [`scripts/stuck-check.sh`](scripts/stuck-check.sh) | 卡住工作检查（Orca 自动化每分钟 precheck，约 15 分钟扫一次），兜底补叫醒；也查 ops 主目录里的 agent 和没包 notify-run 的 agent；依赖 orca-wake 的 `sent/` 状态。扫描时长防护（单项超时、整轮时限、scan-history.json、scan_slow 告警，PER-82）见脚本开头，演练 `wake/tests/stuck-check-scan-guard.sh` |
| [`scripts/agent-probe`](scripts/agent-probe) | 列出本机 agent 和 notify-run 进程，给卡住检查用 |
| [`scripts/heartbeat-watch.sh`](scripts/heartbeat-watch.sh) | 盯另一台机器上卡住检查的心跳（自动任务运行记录里的 `@@HB`），太久没有就报警、恢复报一次 |
| [`wake/bin/orca-agent-launch`](wake/bin/orca-agent-launch) | 统一的起 agent 入口，强制经 notify-run；带 `--issue` 时给 Linear 卡写负责 bot 和 due（`--eta`） |
| [`wake/bin/agent-stop`](wake/bin/agent-stop) | 主动停 agent：先写「主动停止」标记再发信号，卡住检查看到标记就不报 agent_gone |
| [`scripts/automation-reaper.sh`](scripts/automation-reaper.sh) | 关掉做完不退出的 Orca 自动任务 agent（已写结果、空闲超过 2 小时），没写结果的不动 |
| [`scripts/orca-bot-guard.sh`](scripts/orca-bot-guard.sh) | orca-bot 公网守护（iMac「ops · 03」的 precheck），连续不通叫醒 Coding助手，记 webhook 的 HTTP 码 |
| [`sentinels/`](sentinels/) | ops · 23 生产版本哨兵（iMac 每 15 分钟，生产台账）和 ops · 24 未推送扫描（两台机器每小时） |
| [`orca-remote/`](orca-remote/) | box 上 Orca 的看门狗 `watchdog.sh` 和 `ensure-watchdog.sh` |
| [`wake/tla/`](wake/tla/) | 叫醒系统的 TLA+ 模型检查（PER-67）：`wake/tla/check.sh` 一条命令复跑；改叫醒 / 卡住检查代码时用 skill `wake-tla-verify` |
| [`reports/wake-fixes-2026-10-17.md`](reports/wake-fixes-2026-10-17.md) | 叫醒系统 10-17 修复记录 |

## box 运维和定时任务

| 路径 | 内容 |
|---|---|
| [`scripts/box-cleanup.sh`](scripts/box-cleanup.sh) | box 清理（夜间 / 负载高时） |
| [`scripts/orca-due.sh`](scripts/orca-due.sh)、[`scripts/orca-ok.sh`](scripts/orca-ok.sh) | Orca 自动化的到期 / 成功标记 |
| [`scripts/naming-check.py`](scripts/naming-check.py) | Orca 工作区命名检查 |
| [`scripts/seo-weekly-precheck.sh`](scripts/seo-weekly-precheck.sh)、[`scripts/vllm-upstream-precheck.sh`](scripts/vllm-upstream-precheck.sh) | 定时任务的预检 |
| [`reports/`](reports/) | 各次检查和整理的报告 |

定时任务只放在 Orca automations 里，命名「项目 · 编号 描述」。
