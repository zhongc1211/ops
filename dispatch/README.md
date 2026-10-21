# dispatch/：PER-126 v5 前提 2，被动采样器

v5 的阈值（`thresholds.env` 里的下限、预扣额、负载上限）需要初值。这里的采样器在 iMac 和 MBA 上每分钟各采一次本机读数，连续采 24 小时；回放工具读这些数据，按 v5「上线」一节的两条门槛算结果、给初值。

采样器只读：不派活，不改 Orca、Linear 的任何状态，不杀进程。本目录不实现 dispatch 本身、ticket、心跳或队列。

## 文件

| 仓库路径 | 装到 | 作用 |
|---|---|---|
| `bin/ops-v5-sampler` | `~/.local/bin/ops-v5-sampler` | 采一次，追加一行 JSON |
| `bin/ops-v5-sample-replay` | `~/.local/bin/ops-v5-sample-replay` | 回放两台的 samples，算门槛、分位数、建议初值 |
| `config/sampler.env.in` | `~/.config/dispatch/sampler.env` | 配置，必须有 `SAMPLER_CONFIG_VERSION=1` |
| `launchd/com.zhongc1211.ops-v5-sampler.plist.in` | `~/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist` | LaunchAgent，`StartInterval 60` |
| `install.sh` | 不装 | `--check` / `--dry-run` / `--install` |
| `tests/sampler-stub.sh` | 不装 | 桩测（假 orca/ps/sysctl/df/launchctl） |
| `tests/FAILURE-MODES.md` | 不装 | 先列的失败方式清单，和用例一一对应 |

两个脚本都是 `#!/usr/bin/python3 -I`（系统自带 3.9，`-I` 不从脚本目录加载模块），开头自己补 PATH（含 `/Applications/Orca.app/Contents/Resources/bin`）。shell 部分（`install.sh`、测试、桩）兼容 bash 3.2，过 `wake/tests/lint-bash32-utf8.sh`。

## 每次采什么

一行一条记录，写到 `~/.local/state/dispatch/samples/<host>/YYYY-MM-DD.jsonl`（`<host>` 默认是 `hostname -s` 转小写：`imac`、`mba`）。

- 顶层：`schema`（`ops-v5-sample/1`）、`sampler_version`、`ts`（带时区）、`minute`、`host`、`ok`（没有任何错误）、`orca_ok`、`errors[]`（`{step, error}`）、`self`（本次耗时、rss、CPU）。
- `machine.orca`：`orca diagnostics memory --json` 的 `availableMemory`、`totalMemory`、`freeMemory`、`loadAverage1m`、`cpuCoreCount`、`availableMemorySource`、`collectedAt`。
- `machine` 后备读数（每次都记，Orca 不可用时回放用它估算）：`memorystatus_level`、`vm_loadavg`、`hw_memsize`、`disk_home_avail_kb`（`df -k ~`）。
- `sessions[]`：每个 Orca 会话的 `worktreeId`、`worktreeName`、`repoName`、`sessionId`、`paneKey`、`pid`、`memory`、`cpu`；
  `terminal`（按 paneKey 对 `orca terminal list` 的 `tabId:leafId` 和 `orca worktree ps` 的 agents，只取 `handle`、`state`、`workingMode`、`stateStartedAt`、`agentType`、`linkedLinearIssue`，对不上为 null）；
  `proc`（`found`、进程树 `tree_rss_kb`、`n_procs`、顶层 agent 列表、`agent_type`）。
- `orphan_agents[]`：不在任何会话进程树里的顶层 agent 进程，只有 `pid`、`ppid`、`rss_kb`、`etime`、`comm`（basename）。
- `agent_count`：`in_sessions`、`orphan`、`total`。

进程列表只用 `ps -A -o pid,ppid,rss,etime,comm`，不采命令行和环境变量。prompt、preview、lastAssistantMessage、comment 等正文一律不存（桩测里埋了标记串断言）。「顶层 agent」= comm 在 `AGENT_COMMS` 里、且祖先里没有 agent 的进程，所以 claude 拉起的 node MCP 不重复计数。

## 失败无害

- 每个外部命令都限时：orca ≤ `ORCA_TIMEOUT_SEC`（10 秒），ps/sysctl/df ≤ `CMD_TIMEOUT_SEC`（5 秒），整轮 ≤ `ROUND_TIMEOUT_SEC`（30 秒，按剩余预算逐步缩短单步上限，另有 32 秒的 SIGALRM 兜底）。子进程开在新的进程组里，超时整组 SIGKILL 并回收，不留僵尸。
- Orca 不在、挂住、坏 JSON、`ok:false`：`orca_ok=false`，照记机器级后备读数。`worktree ps`/`terminal list` 失败只让 `terminal=null`。
- 锁：`fcntl.flock` 非阻塞锁 `~/.local/state/dispatch/ops-v5-sampler.lock`，被占就跳过；同一分钟已有记录就跳过。
- 轮转：保留 `RETENTION_DAYS`（14）天、自己目录 `*.jsonl` 总量 ≤ `MAX_TOTAL_MB`（200MB），超了从最旧删；只删 `samples/<本机>/` 下名字是 `YYYY-MM-DD.jsonl` 的普通文件，当天文件不删（当天文件单独到上限就停写并记日志）。
- 日志 `ops-v5-sampler.log` 和 launchd 的 `ops-v5-sampler.launchd.log` 超过 `LOG_MAX_KB`（512KB）轮转成 `.1`，各最多两份。
- 退出码：0 正常/跳过，3 配置缺失或版本错，4 写盘失败。

## 调度：LaunchAgent

选 LaunchAgent（`com.zhongc1211.ops-v5-sampler`，`StartInterval 60`，`ProcessType Background`、`Nice 10`、`LowPriorityIO`），不用 Orca 自动任务：

1. 采样器要观察 Orca 本身（Orca 卡住、重启、内存高的时段正是要采的），调度不能依赖 Orca。
2. Orca 自动任务的停用/重建回滚有未核实的问题（dr eggbot 意见 ③④）；LaunchAgent 的装卸是 `launchctl bootstrap/bootout` 两条命令，回滚路径清楚。
3. launchd 不会并发拉起同一个 job，再加 flock 锁，手工跑和定时跑也不会撞。

## 回放

```
ops-v5-sample-replay --ssh imac --ssh mba --json /tmp/replay.json
ops-v5-sample-replay --dir ~/.local/state/dispatch/samples --reserve-gb 1,1.5,2 --floor-gb 0.5,1,1.5 --load-max 8,12,16 --free-pct 5,10,15
```

`--ssh` 只在远端跑 `find ~/.local/state/dispatch/samples -name '*.jsonl' -exec cat {} +`。算法和保守假设写在脚本开头的说明里，要点：

- 门槛 1：合成候选每分钟独立判 `availableMemory − R ≥ F` 且 `load ≤ L` 且磁盘 ≥ D，找最长连续「起不了」和超过 60 分钟的窗口；缺数据的分钟单列，不算起不了。
- 门槛 2：从头模拟放行（每分钟最多一个），假设模拟 agent 放行即用满 R、持续 30 分钟（被动数据里它没真跑，availableMemory 看不到它，所以扣 R）；看每次放行后 30 分钟内 `(availableMemory − 在跑数 × R) / totalMemory` 的最低值是否低于 X。
- 建议初值：两台都过两条门槛的组合里，取下限最大、R 最大、负载上限最小的一组；另给会话进程树 rss p90 作为 R 的下限参考。被动采样只定初值。

## 安装后会新建或改动的路径（iMac、MBA 相同，`<host>` 分别是 `imac`、`mba`）

两台 `HOME` 都是 `/Users/jiawenwang`，uid 都是 501。`~/.local/bin/` 和 `~/Library/LaunchAgents/` 已存在；`~/.config/dispatch/` 和 `~/.local/state/dispatch/` 两台都不存在，整个是新根目录。

| 路径 | 谁建 | 说明 |
|---|---|---|
| `~/.local/bin/ops-v5-sampler` | install | 新文件 |
| `~/.local/bin/ops-v5-sample-replay` | install | 新文件 |
| `~/.local/bin/ops-v5-sampler.bak-<时间>`、`ops-v5-sample-replay.bak-<时间>` | install | 只在重装且内容不同时 |
| `~/.config/dispatch/`、`~/.config/dispatch/sampler.env` | install | 新根目录；已存在不覆盖 |
| `~/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist`（及 `.bak-<时间>`） | install | 新文件 |
| `~/.local/state/dispatch/`、`~/.local/state/dispatch/samples/` | install | 新根目录 |
| `~/.local/state/dispatch/samples/<host>/YYYY-MM-DD.jsonl` | 采样器 | 数据 |
| `~/.local/state/dispatch/ops-v5-sampler.lock` | 采样器 | 锁 |
| `~/.local/state/dispatch/ops-v5-sampler.log`、`.log.1` | 采样器 | 自身日志 |
| `~/.local/state/dispatch/ops-v5-sampler.launchd.log`、`.launchd.log.1` | launchd / 采样器轮转 | stdout/stderr |

调度项：每台一个 LaunchAgent `gui/501/com.zhongc1211.ops-v5-sampler`。没有 Orca 自动任务。

## 卸载（每台各做一次）

```
launchctl bootout gui/$(id -u)/com.zhongc1211.ops-v5-sampler
mkdir -p ~/ops-v5-sampler-removed
mv ~/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist ~/ops-v5-sampler-removed/
mv ~/.local/bin/ops-v5-sampler ~/.local/bin/ops-v5-sample-replay ~/ops-v5-sampler-removed/
mv ~/.config/dispatch/sampler.env ~/ops-v5-sampler-removed/ && rmdir ~/.config/dispatch
# 数据可选保留；不要了再挪走：mv ~/.local/state/dispatch ~/ops-v5-sampler-removed/state
dispatch/install.sh --check   # 应全部报缺失/未加载
```
