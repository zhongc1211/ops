# ops 验证地图

这个目录是验证 ops 仓库叫醒链路和运维脚本的维护源。驱动前先读这一页，再按对应的 feature 文件做。所有 feature 都由 `bash .claude/skills/verify-ops/verify.sh run <feature>` 驱动，断言写在 verify.sh 的 `f_<feature>` 函数里，这里写的是它们验证什么、为什么这样驱动。

## 基线前提

- 在 ops 仓库的 checkout 里跑，macOS（`/bin/bash` 3.2 也行）或 Linux；要有 `python3`、`curl`、`git`、`lsof`（Linux 上没有 lsof 时用 `ss`）、`jq`（没有 jq 时 notify-run 退回 python3）。
- `verify.sh launch` 建的沙箱：自己的 `HOME`、PATH 最前面是 `$SB/bin`（假 `pi`、假 `orca` / `orca-ide`、假 Linear）和被测目录的 `wake/bin`，两个本机假 webhook（端口随机，pid 在 `$SB/pids`）。
- 先过 Doctor（`verify.sh doctor`）：HOME 是沙箱、端口归本次进程、被测脚本是这份 checkout。有 `BAD` 就不驱动。
- 不驱动不是本次起的实例：不连真 Orca、真 Linear、真 bot。

## 驱动约定

- 每个 feature 从新沙箱开始（`run` 一次只建一个沙箱，feature 之间共享假端点，所以断言都按 `task` 或 `kind` 过滤，不数总数）。
- 被测脚本按用户会敲的命令行调用，不调内部函数，不用 dry-run 开关冒充真实路径。
- 造漂移、造故障只在沙箱里的东西上做（沙箱 HOME 里装的文件、沙箱里的仓库克隆、复制出来的目录）。checkout 本身不动。
- 故意改坏被测代码时用 `VERIFY_OPS_SUT=<副本>`，见 SKILL.md「Drive」。

## 证明和 skipped

- 每条断言看两样：退出码，以及副作用（假端点收到的请求、notify-run.log 的 http 字段、状态文件、存储目录、假 Linear 的调用记录）。
- 缺前置条件的路径报失败，原因写进那个 feature 的 Gotchas；不为了通过而放松断言。例外是本机没有、又不该联网去拿的东西：DC4 的插件仓库和 wake-tla 的工具，这两项记 skipped。
- skipped 不算通过，也不算失败，在报告里逐条列出。`VERIFY-OPS PASS` 只说明没有失败。

## Feature

| 文件 | 用户视角 | 驱动的真实脚本 |
|---|---|---|
| [wake-chain.md](wake-chain.md) | 用 notify-run 包一个命令，结束后派活的 bot 被叫醒一次 | `wake/bin/notify-run` |
| [agent-launch-gate.md](agent-launch-gate.md) | 用 orca-agent-launch 起 agent，参数不对就拒绝并叫醒 | `wake/bin/orca-agent-launch` → `notify-run --tty` |
| [stuck-check.md](stuck-check.md) | 卡住检查报 agent_gone / agent_idle / agent_silent；心跳停了有人告警 | `scripts/stuck-check.sh`、`scripts/heartbeat-watch.sh`、`wake/bin/orca-wake` |
| [drift-checks.md](drift-checks.md) | 各种 `--check` 报漂移 | `wake/install.sh`、`scripts/sync-bot-rules`、`automations/migration-1020/make-prompts.py`、`bootstrap/claude-plugins/pin-claude-plugins.sh` |
| [night-review-gate.md](night-review-gate.md) | 夜审收尾：摘要没写「状态：完成」就失败 | `scripts/night-review-gate.sh finish` |

### 调用：wake-tla（叫醒模型检查）

`verify.sh run wake-tla` 调现成的 `wake/tla/check.sh --out <沙箱> w0 h0`（`wake-tla-verify` skill 的命令，不复制、不改），退出码 0 记通过，1 记失败，2（环境问题）记 skipped。
没有 Java 17 或 `tla2tools.jar`（默认路径 `~/.local/opt/...`，可用 `TLA_JAVA`、`TLA_JAR` 指定）时不调用，直接记 skipped 并写原因，**不记通过**。
Gotcha：`check.sh` 开跑前用 `free` 和 `/proc/loadavg` 看资源，这两个在 macOS 上没有，会被当成资源不够等 5 分钟、最多 3 次；在 macOS 上装了 TLA 工具也预期是 skipped 或很慢，要在 Linux 上跑这一项。

## 按规矩不跑（skipped 列表）

这些碰生产或真实外部系统，要 Zack 卡，verify-ops 不驱动，报告里列成 skipped，不当通过：

- `sentinels/prod-watch.sh`：读生产部署 id。
- `scripts/ws-cleanup.sh` 非 dry-run：真删工作区。
- 一切 live Orca / Linear / EverOS 写入。
- 真实 webhook（会真的叫醒 bot）。
