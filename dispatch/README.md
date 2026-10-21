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
| `install.sh` | 不装 | `--check` / `--dry-run` / `--install` / `--uninstall [--move-data]` |
| `tests/sampler-stub.sh` | 不装 | 桩测（假 orca/ps/sysctl/df/launchctl/backup.sh，临时 HOME） |
| `tests/e2e-real-10min.sh` | 不装 | 真机每分钟跑一次、共 10 分钟（本机，或 `--ssh mba` 经 stdin），临时 HOME，产物写 `reports/per126-p2-sampler/e2e-<host>/` |
| `tests/FAILURE-MODES.md` | 不装 | 先列的失败方式清单，和用例一一对应 |

两个脚本都是 `#!/usr/bin/python3 -I`（系统自带 3.9，`-I` 不从脚本目录加载模块），开头自己补 PATH（含 `/Applications/Orca.app/Contents/Resources/bin`）。shell 部分（`install.sh`、测试、桩）兼容 bash 3.2，过 `wake/tests/lint-bash32-utf8.sh`。

## 每次采什么

数据都在 `~/.local/state/ops-v5/samples/<host>/` 下（`<host>` 默认是 `hostname -s` 转小写：`imac`、`mba`），每天两个文件：

- `YYYY-MM-DD.jsonl`：每分钟一行，只放会变的读数。
- `YYYY-MM-DD.sessions.jsonl`：会话字典。会话的静态字段只在当天第一次出现或有变化时写一行，按 `sid`（paneKey + sessionId 的 sha1 前 10 位）和每分钟记录对上。

每分钟一行的内容：

- 顶层：`schema`（`ops-v5-sample/2`）、`sampler_version`、`ts`（带时区）、`minute`、`host`、`ok`（没有任何错误）、`orca_ok`、`errors[]`（`{step, error}`）、`self`（本次耗时、rss、CPU）。
- `machine.orca`：`orca diagnostics memory --json` 的 `availableMemory`、`totalMemory`、`freeMemory`、`loadAverage1m`、`cpuCoreCount`、`availableMemorySource`、`collectedAt`。
- `machine` 后备读数（每次都记，Orca 不可用时回放用它估算）：`memorystatus_level`、`vm_loadavg`、`hw_memsize`、`disk_home_avail_kb`（`df -k ~`）。
- `sessions[]`：每个会话的 `sid`、`pid`、`memory`、`cpu`、`state`、`since`（agent 状态开始时间）、`found`（ps 里找到 pid）、`tree_rss_kb`、`n_procs`、`n_agents`、`agent_type`。
- `orphan_agents`：不在任何会话进程树里的顶层 agent 进程，只记个数 `n`、rss 合计 `rss_kb` 和按进程名的个数 `by_comm`。
- `agent_count`：`in_sessions`、`orphan`、`total`。

会话字典一行：`schema`（`ops-v5-session-dict/1`）、`ts`、`sid`、`static`（`paneKey`、`sessionId`、`worktreeId`、`worktreeName`、`repoName`、`handle`、`agentType`、`workingMode`、`linkedLinearIssue`；对不上终端时为 null）。

进程列表只用 `ps -A -o pid,ppid,rss,etime,comm`，不采命令行和环境变量。prompt、preview、lastAssistantMessage、comment 等正文一律不存（桩测里埋了标记串断言，E2E 扫描了真机数据）。「顶层 agent」= comm 在 `AGENT_COMMS` 里、且祖先里没有 agent 的进程，所以 claude 拉起的 node MCP 不重复计数。

数据量（2026-10-21 真机 10 分钟实测，22–23 个会话）：每分钟一行约 4.2–4.3KB，每天约 6.2MB；字典第一次约 14KB，之后只在会话变化时追加。

## 失败无害

- 每个外部命令都限时：orca ≤ `ORCA_TIMEOUT_SEC`（10 秒），ps/sysctl/df ≤ `CMD_TIMEOUT_SEC`（5 秒），整轮 ≤ `ROUND_TIMEOUT_SEC`（30 秒，按剩余预算逐步缩短单步上限，另有 32 秒的 SIGALRM 兜底）。子进程开在新的进程组里，超时整组 SIGKILL 并回收，不留僵尸。
- Orca 不在、挂住、坏 JSON、`ok:false`：`orca_ok=false`，照记机器级后备读数。`worktree ps`/`terminal list` 失败只让字典里的 handle 等为 null。
- 锁：`fcntl.flock` 非阻塞锁 `~/.local/state/ops-v5/ops-v5-sampler.lock`，被占就跳过；同一分钟已有记录就跳过。
- 不删数据。上限有两个：`samples/<本机>/` 下已有 `MAX_DAYS`（9）天的数据且今天还没文件，或总大小加本次要写的超过 `MAX_TOTAL_MB`（350MB）。到上限就停写：日志记 ERROR，`ops-v5-sampler.status` 写 `state=full` 和原因，`install.sh --check` 报警。ops 把旧文件挪走后，下一分钟自动恢复写入。
  选停写而不是挪到归档目录：挪在同一块盘上不腾空间，归档目录也会一直长；停写能让数据保持完整，由 ops 决定挪到哪。
  按 6.2MB/天算，9 天约 56MB，350MB 是按最坏情况（会话数翻几倍）留的余量；24 小时采样离两个上限都很远。
- 日志 `ops-v5-sampler.log` 和 launchd 的 `ops-v5-sampler.launchd.log` 超过 `LOG_MAX_KB`（512KB）就挪到 `log-archive/<名字>.<时间>`，重名加 `-n`，不覆盖。同名归档到 `LOG_ARCHIVE_MAX`（20）份后不再挪、日志停写（数据和状态文件照写）。
- 状态文件 `ops-v5-sampler.status`：`ok`、`full`、`config_error`、`write_error`，每次运行原子覆盖。
- 退出码：0 正常/跳过/到上限停写，3 配置缺失或版本错，4 写盘失败。

## 调度：LaunchAgent

选 LaunchAgent（`com.zhongc1211.ops-v5-sampler`，`StartInterval 60`，`ProcessType Background`、`Nice 10`、`LowPriorityIO`），不用 Orca 自动任务：

1. 采样器要观察 Orca 本身（Orca 卡住、重启、内存高的时段正是要采的），调度不能依赖 Orca。
2. Orca 自动任务的停用/重建回滚有未核实的问题（dr eggbot 意见 ③④）；LaunchAgent 的装卸是 `launchctl bootstrap/bootout` 两条命令，回滚路径清楚。
3. launchd 不会并发拉起同一个 job，再加 flock 锁，手工跑和定时跑也不会撞。

## 回放

```
ops-v5-sample-replay --ssh imac --ssh mba --json /tmp/replay.json
ops-v5-sample-replay --dir ~/.local/state/ops-v5/samples --reserve-gb 1,1.5,2 --floor-gb 0.5,1,1.5 --load-max 8,12,16 --free-pct 5,10,15
```

`--ssh` 只在远端跑 `find "$HOME/.local/state/ops-v5/samples" -type f -name "????-??-??.jsonl" -exec cat {} +`（会话字典不拉）。算法和保守假设写在脚本开头的说明里，要点：

- 门槛 1：合成候选每分钟独立判 `availableMemory − R ≥ F` 且 `load ≤ L` 且磁盘 ≥ D，找最长连续「起不了」和超过 60 分钟的窗口；缺数据的分钟单列，不算起不了。
- 门槛 2：从头模拟放行（每分钟最多一个），假设模拟 agent 放行即用满 R、持续 30 分钟（被动数据里它没真跑，availableMemory 看不到它，所以扣 R）；看每次放行后 30 分钟内 `(availableMemory − 在跑数 × R) / totalMemory` 的最低值是否低于 X。
- 建议初值：两台都过两条门槛的组合里，取下限最大、R 最大、负载上限最小的一组；另给会话进程树 rss 的 p90，以及按 agent 类型分开的 p90/p99，作为 R 的参考。被动采样只定初值。

## 安装（要等 dr eggbot 审 → ops bot 验收 → Zack 点卡，本 PR 不装）

每台各做一次：

1. `dispatch/install.sh --dry-run`：看会建哪些路径；确认 `~/ops-archive/per126-v5-backup-1021/<机器>/tools/backup.sh` 存在。
2. `dispatch/install.sh --install`：
   1. 先跑 `backup.sh --label p2-sampler`。失败、install-log.tsv 没多一行、或新行的 label 不对，都退出非 0，什么都不装。
   2. 打印快照目录和 MANIFEST sha256。
   3. 装脚本、配置（已存在不覆盖）、plist；内容不同的旧文件先挪到 `<归档>/p2-sampler-bak-<时间>/`，不留在 `~/.local/bin` 或 `~/Library/LaunchAgents`。
   4. `launchctl bootstrap gui/501 …`。MBA 上要用户已登录桌面，否则 `gui/501` 域不存在，bootstrap 会失败。
   5. 写 `<归档>/p2-sampler-installed-<时间>.tsv`（4 个文件的路径和 sha256），并在 install-log.tsv 追加一行 `p2-sampler-installed`。
3. 装完 3 分钟后跑 `dispatch/install.sh --check`，应该全部正常：已加载、采样器状态 ok、最近一次采样 ≤ 180 秒。

## 24 小时之后

采样器会一直跑，直到到上限停写（9 天或 350MB）或被卸载。拿到 24 小时数据后：

1. 在任一台跑 `ops-v5-sample-replay --ssh imac --ssh mba --json …` 出建议初值。
2. 要停就 `dispatch/install.sh --uninstall`（见下）。不卸也行，到上限后 `--check` 会报警，不会写满磁盘。

## 安装后会新建或改动的路径（iMac、MBA 相同，`<host>` 分别是 `imac`、`mba`）

两台 `HOME` 都是 `/Users/jiawenwang`，uid 都是 501。`~/.local/bin/` 和 `~/Library/LaunchAgents/` 已存在；`~/.config/dispatch/` 和 `~/.local/state/ops-v5/` 两台都不存在，整个是新根目录。`<归档>` = `~/ops-archive/per126-v5-backup-1021/<机器>`（已存在）。

| 路径 | 谁建 | v5-scope.tsv 规则 |
|---|---|---|
| `~/.local/bin/ops-v5-sampler`、`~/.local/bin/ops-v5-sample-replay` | install | `.local/bin/ops-v5-*` |
| `~/.config/dispatch/`、`~/.config/dispatch/sampler.env` | install（已存在不覆盖） | `.config/dispatch/*` |
| `~/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist` | install | `Library/LaunchAgents/com.zhongc1211.ops-v5-*` |
| `~/.local/state/ops-v5/`、`samples/`、`samples/<host>/YYYY-MM-DD.jsonl`、`YYYY-MM-DD.sessions.jsonl` | install / 采样器 | `.local/state/ops-v5/*` |
| `~/.local/state/ops-v5/ops-v5-sampler.lock`、`.status`、`.log`、`.launchd.log`、`log-archive/` | 采样器 / launchd | `.local/state/ops-v5/*` |
| `<归档>/snapshots/<时间>-p2-sampler/`、`install-log.tsv` 一行 | backup.sh | 归档目录，不在 scope 里 |
| `<归档>/p2-sampler-installed-<时间>.tsv`、`install-log.tsv` 一行、`p2-sampler-bak-<时间>/`（只在重装且内容不同时） | install | 归档目录 |
| `<归档>/removed-<时间>/`（含 `MOVED.tsv`） | uninstall | 归档目录 |

调度项：每台一个 LaunchAgent `gui/501/com.zhongc1211.ops-v5-sampler`。没有 Orca 自动任务。

## 卸载（每台各做一次）

```
dispatch/install.sh --uninstall              # bootout，再把 plist、两个脚本、配置挪到 <归档>/removed-<时间>/
dispatch/install.sh --uninstall --move-data  # 同上，并把 ~/.local/state/ops-v5/ 下采样器的数据、日志、状态也挪过去
dispatch/install.sh --check                  # 应全部报缺失/未加载
```

不删任何文件。挪走的每个文件记在 `removed-<时间>/MOVED.tsv`，保留原来相对 HOME 的层次，要恢复就挪回去。
