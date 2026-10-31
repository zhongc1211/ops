# #96 模型对照：10-20 以来的代码改动

base：`e2252d21e10c0787058c7eebdb34b175fc11ced5`。范围：每个被建模文件自 `SOURCES.sha256` 上次更新（`126e165`，10-20）以来的全部提交，以及更早但当时没进 SOURCES 的提交。逐个读了 `git show <sha> -- <文件>`。

SOURCES 旧记录的来源：notify-run、orca-agent-launch 是 `126e165`；orca-wake 是 `a83052a`；stuck-check.sh 是 `47e038d`；heartbeat-watch.sh 是 `ed89044`。

下面「P6 不变」这类结论来自读代码和 TLC 结果，不是真机演练。

## wake/bin/notify-run

| 提交 | 日期 | 摘要 | 落在模型哪个动作 | 模型改没改 | 理由 |
|---|---|---|---|---|---|
| `0876dcf`（#83） | 10-28 | `send_webhook` 带事件参数，发 ops-system 时加 Idempotency-Key，payload 清洗 | `NrAttempt`、`AgentExit` | 只改行号注释 | 重试次数和 `2??` 判断没变，成败结局和原来一样 |
| `126e165` | 10-20 | `$var` 改 `${var}` | 无 | 没改 | 只是写法，已在旧 SOURCES 里 |

## wake/bin/orca-wake

| 提交 | 日期 | 摘要 | 落在模型哪个动作 | 模型改没改 | 理由 |
|---|---|---|---|---|---|
| `0876dcf`（#83） | 10-28 | Idempotency-Key，`build_payload` 清洗 | `OwAttempt`、`AgentPause`、`IdlePrompt` | 只改行号注释 | `job["dedup_key"]` 恒有；`ok` 判断和 `_mark_sent` 没变；行号 +2/+10 |

## wake/bin/orca-agent-launch

| 提交 | 日期 | 摘要 | 落在模型哪个动作 | 模型改没改 | 理由 |
|---|---|---|---|---|---|
| `0932568`（#48） | 10-29 | `--settings` 合并，禁 superpowers，失败走 `die` | Launch `Start` | 只改行号注释 | 新失败走已有的 `die` → `wake_reject`，就是模型的 `rejected` |
| `3e0d9e4`（#89） | 10-29 | 全角括号的花括号写法，文案 | 无 | 没改 | 只有写法和文案 |
| `e2252d2`（#93） | 10-29 | 启动前检查，`--bare`/`-nc`/env 开关，没过走 `die` | Launch `Start`、`RejectWake` | 改了：加状态 `rejected_pre`、Mutant `pre_silent`、`l04` | 多一条更早的拒绝路径。脚本只有 `set -u`（:27），没有 `set -e`，python 失败也到 :179 / :393 的 `die`，所以仍然叫醒，P6 的语义不变。单独建状态是为了让「这条路不叫醒」查得出来（`l04` violated） |

附带发现（读代码，没演练）：#48 之后 `-- claude` 零参数启动变成 `claude --settings <file>`，notify-run 的 `start_watch` 条件（`$#>1` 且末参不以 `-` 开头）成立，5 分钟后可能误报 agent_not_started。只会多报，不影响 P6。

## scripts/stuck-check.sh

| 提交 | 日期 | 摘要 | 落在模型哪个动作 | 模型改没改 | 理由 |
|---|---|---|---|---|---|
| `f6408d0`（PER-82） | 10-20 | orca 调用 30 秒超时、整轮 80% 预算、90% 后不重试、截断也写 `SCAN_DONE`、超过 60% 报 scan_slow | Wake `Scan`；Heartbeat `Step`、`nDone` | 改了：Wake 加 `CUT_MAX`、`cutLeft`、`CutChoices`，`skip_dismiss` 变体；Heartbeat 加 mode `cut`、`slowAlerted`、`no_scan_slow` 变体 | 行为改动：一次扫描可以没判断到任务，last_scan 照样前进。`past_hard` 只少重试或留到下次，P2 不变；`STUCK_NO_SEND` 是演练开关，模型外 |
| `f66c5cd`（PER-105） | 10-20 | 第 94 行注释 | 无 | 没改 | 只改注释 |
| `fdab089`（PER-105） | 10-20 | 同一行注释 | 无 | 没改 | 只改注释 |
| `e5c61f1`（PER-105） | 10-20 | 撤回第 94 行的改动 | 无 | 没改 | 三个提交合起来对这个文件没有净改动，所以默认的 `git log` 不显示，要加 `--full-history` |
| `12680cc`（PER-134） | 10-21 | dry-run 的 HIST 修复 | 无 | 没改 | dry-run 不发送，模型外 |

## scripts/heartbeat-watch.sh

| 提交 | 日期 | 摘要 | 落在模型哪个动作 | 模型改没改 | 理由 |
|---|---|---|---|---|---|
| `f66c5cd` | 10-20 | 注释 | 无 | 没改 | 只改注释 |
| `fdab089` | 10-20 | 注释 | 无 | 没改 | 只改注释 |
| `cd4f4ee`（#75，B1） | 10-22 | `BOT = "ops-system"`，部署注释 | Heartbeat `Step`、`Down` | 改了：告警收件人注释；加 `WatcherFaults`、`PEER`、`ALERT_ON_TARGET`、`wUp`、`wDownAge`、`peerAlerted`、`WatcherDown`、`HookOK`、`PeerRuns`，性质 `PW`、`P3W`，检查 h09–h13 | 收件 webhook 换到 iMac 转发器，`post()` 没有改发。B1 引入的「看守机下线」和「收件 webhook 在被盯的机器上」两种情况，旧模型表达不了 |

## 没变的文件

`wake/bin/orca-wake-hooks`、`wake/bin/agent-stop`、`wake/pi/dispatch-wake.ts`：自 `126e165` 没有提交，哈希和旧 SOURCES 一致。

`scripts/agent-probe`：旧 SOURCES 没有它。`cf84ed8` 之后没变（`af95da54bf99000a`）。F2 的 `wrapped_exit` 依赖它的输出，所以这次加进 SOURCES，共 9 项。

## 模型改动清单

- `wake/tla/Wake.tla:46,52`：常量 `CUT_MAX`、`CUT_FOREVER`
- `wake/tla/Wake.tla:74,113`：变量 `cutLeft`
- `wake/tla/Wake.tla:287-297`：`CutChoices` 和说明
- `wake/tla/Wake.tla:301-338`：`Scan` 按 cut 屏蔽第一类、第二类；Mutant `skip_dismiss`（:327）
- `wake/tla/Wake.tla` 全部 `文件:行号` 注释更新
- `wake/tla/Heartbeat.tla:17,24-26`：Mutant `no_scan_slow`，常量 `WatcherFaults`、`PEER`、`ALERT_ON_TARGET`
- `wake/tla/Heartbeat.tla:19`：`PRE_TIMEOUT` 按现网 600 秒
- `wake/tla/Heartbeat.tla:40,88-97,118`：mode `cut`、`slowAlerted`、`nSlow`
- `wake/tla/Heartbeat.tla:102-113`：告警发 ops-system，`HookOK`、`PeerRuns`
- `wake/tla/Heartbeat.tla:129-133`：动作 `WatcherDown`
- `wake/tla/Heartbeat.tla:139-147`：`P3` 接受 `slowAlerted`，新增 `PW`、`P3W`
- `wake/tla/Launch.tla:18,24,38,49,82`：Mutant `pre_silent`，状态 `rejected_pre`，P6 含 `rejected_pre`
- `wake/tla/cfg/*.cfg`：所有 w* 加 `CUT_MAX = 0`；所有 h* `PRE_TIMEOUT = 10` 并加三个新常量；新增 15 份
- `wake/tla/MC.tla:9`：`OneTask`（w18b 用）
- `wake/tla/trace.py:9-23`：动作对应的代码行号更新，加 `WatcherDown`
- `wake/tla/check.sh:49-55,62-68,72`：新增 15 行检查
- `wake/tla/check.sh`：哈希不符直接失败，见 PR 描述

P3 的放宽要说明：旧 P3 是「最终 alerted」，新 P3 是「最终 alerted 或 slowAlerted」。截断时 last_scan 正常前进，heartbeat-watch 按设计不报，告警由 stuck-check 的 scan_slow 发。这条放宽只在 mode `cut` 上起作用，其余 mode 的 `slowAlerted` 恒为 FALSE。`h08` 去掉 scan_slow 后 violated，证明它没有放成空性质。

w18 的期望要说明：先按 pass 写，TLC 给出 violated。反例每一步都对得上代码（`stuck-check.sh:1102` 的 `retrying` 分支），不是模型错，所以按发现处理（README F12），期望改成 violated，另加 w18b 确认任务工作区截断 1 次仍然成立。

## SOURCES.sha256 前后对比

| 文件 | 旧（前 16 位） | 新（前 16 位） |
|---|---|---|
| wake/bin/notify-run | 4ce9845ef12349d4 | d047ff8907733c25 |
| wake/bin/orca-agent-launch | 907611083b053b4b | 648017c2b8152e11 |
| wake/bin/orca-wake | ab75137c97142a40 | c966b7c343ee0cb0 |
| wake/bin/orca-wake-hooks | 1a5e66d777618c76 | 1a5e66d777618c76 |
| wake/bin/agent-stop | 7cc0ebefd5b5c53a | 7cc0ebefd5b5c53a |
| wake/pi/dispatch-wake.ts | 350c898595552ed6 | 350c898595552ed6 |
| scripts/stuck-check.sh | f7c44d4b864c3170 | b444cc8b585a846b |
| scripts/heartbeat-watch.sh | a36d3dc8a88702a8 | f7fd401cc68536d2 |
| scripts/agent-probe | 不在 SOURCES | af95da54bf99000a |
