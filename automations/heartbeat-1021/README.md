# B1：盯 iMac ops · 01 的跨机看守从 box 挪到 MBA↔iMac（ops 审计，2026-10-21）

iMac「ops · 01 卡住工作检查」（`439cd438`）每分钟跑 `scripts/stuck-check.sh --scan`，每次在 stdout 打一行 `@@HB {...}`。
现在只有 box 上的「ops · 29 卡住检查心跳（盯 iMac ops · 01）」（`94e4b0bc`）盯它。box 已退出开发，box 一停就没人发现 ops · 01 停摆。
这里把这条看守挪到 MBA，iMac 改成盯 MBA 这条：MBA 和 iMac 互相看守。

MBA 的 Orca 没有任何 environment，读不到 iMac 的运行记录；MBA 能 `ssh imac`。所以 MBA 上的 heartbeat-watch 用
`HB_ORCA=scripts/orca-via-ssh`：它把 `orca automations runs|list` 原样转到 `ssh imac zsh -lc 'orca …'`，只放行这两个只读子命令。

**本目录只有定义、脚本和文档，没有建、改、启用、停用任何现网自动任务。下面每一步现网改动都要 Zack 卡片批准，由 ops bot 执行。**

## 谁盯谁

| 阶段 | 盯 iMac ops · 01（`439cd438`）的 | 盯这条看守的 |
|---|---|---|
| 现在 | box ops · 29 `94e4b0bc`（box 的 environment `iMac`） | iMac ops · 29 `5c2d0575`（经 environment `grok-bot` 读 box） |
| 第 3 步起 | box `94e4b0bc` 和 MBA 新任务 | `5c2d0575` 只盯 box |
| 第 4、5 步（并行一晚） | 同上 | `5c2d0575` 盯 box 那条和 MBA 那条 |
| 第 6 步起（上线后） | MBA 新任务（经 `orca-via-ssh` 读 iMac） | `5c2d0575`（经 environment `mba` 读 MBA），box `94e4b0bc` 停用 |

任何时刻 ops · 01 至少有一条看守：MBA 新任务先启用（第 3 步），box 那条最后才停（第 6 步）。

## 文件

| 文件 | 内容 |
|---|---|
| `defs.json` | MBA 新任务的定义；iMac `5c2d0575` 三个阶段（parallel、final、rollback）的预检；`before` 是 10-21 只读核对的现网配置；box `94e4b0bc` 和 ops · 01 的现网配置（只做记录） |
| `register.sh mba\|imac [--stage parallel\|final\|rollback] [--mba-id <id>] [--apply]` | 把 defs.json 变成 `orca automations create/edit` 命令。默认只打印（dry-run），不调用 orca；create 一律 `--disabled`。`--apply` 在对应机器上执行，主机名不对、或者这一步的备份文件不存在就拒绝。本 PR 没有带 `--apply` 跑过 |
| `prompts/noop.prompt.md` | MBA 新任务的提示词：预检永远非 0 退出，模型不会起；万一起了什么都不做 |
| `FAILURE-MODES.md` | 写代码前先写的失败方式清单，对应演练的场景编号 |
| [`scripts/orca-via-ssh`](../../scripts/orca-via-ssh) | 给 `HB_ORCA` 用的 ssh 包装 |
| [`wake/tests/heartbeat-watch-ssh.sh`](../../wake/tests/heartbeat-watch-ssh.sh) | 演练，产物在 [`reports/heartbeat-mba-imac-1021/`](../../reports/heartbeat-mba-imac-1021/) |

MBA 新任务和 box `94e4b0bc` 一样：每 5 分钟、预检超时 240 秒、grace 720、`--fresh-session`。另外加了
`--extra-agent-args=--model haiku --effort low`（MBA 现有任务的写法）：万一预检被改坏、模型被起来，用最便宜的模型。

## 上线顺序

每一步：Zack 卡片批准 → ops bot 执行 → 先备份 → 改 → 核对 → 再走下一步。备份放在执行那台机器的 `~/ops-archive/heartbeat-1021/`。
命令在仓库根目录（`~/orca/workspaces/ops`）跑。下面 `$MBA_ID` 是第 2 步建出来的 MBA 新任务 id。

**0. 合并、拉代码。** 本 PR 合并到 main 后，MBA 和 iMac 的 `~/orca/workspaces/ops` 各自 `git pull --ff-only`。
MBA 上核对 `test -x ~/orca/workspaces/ops/scripts/orca-via-ssh && echo ok`。

**1. MBA 装 heartbeat-watch.sh（MBA）。**
```bash
mkdir -p ~/ops-archive/heartbeat-1021
ls -la ~/.orca-state/bin/heartbeat-watch.sh > ~/ops-archive/heartbeat-1021/mba-bin.before.txt 2>&1   # 10-21 时不存在
[ -f ~/.orca-state/bin/heartbeat-watch.sh ] && cp -p ~/.orca-state/bin/heartbeat-watch.sh ~/ops-archive/heartbeat-1021/heartbeat-watch.sh.mba.before
install -m 755 ~/orca/workspaces/ops/scripts/heartbeat-watch.sh ~/.orca-state/bin/heartbeat-watch.sh
shasum -a 256 ~/orca/workspaces/ops/scripts/heartbeat-watch.sh ~/.orca-state/bin/heartbeat-watch.sh   # 两行一致
```
核对（`--dry-run`，临时状态目录和假 webhook 目录，不发叫醒、不读真凭据）：
```bash
T=$(mktemp -d); mkdir -p "$T/hooks"; printf 'URL=http://127.0.0.1:9/hb-drill\nKEY=hb-drill-dummy-key\n' > "$T/hooks/coding-assistant.env"
HB_STATE_DIR="$T/state" STUCK_WEBHOOK_DIR="$T/hooks" HB_ORCA=$HOME/orca/workspaces/ops/scripts/orca-via-ssh ORCA_SSH_HOST=imac \
  ~/.orca-state/bin/heartbeat-watch.sh --precheck --dry-run --target "iMac ops · 01 卡住工作检查||439cd438-cffe-44dd-bd2b-23b07bfa3d61|20"
echo "rc=$?"; rm -rf "$T"
```
期望：一行「iMac ops · 01 卡住工作检查：正常（最新心跳 …）」，`rc=1`（`--precheck` 正常时退出 1）。

**2. 建停用的任务（MBA）。**
```bash
orca automations list --json > ~/ops-archive/heartbeat-1021/mba-list.before.json
bash automations/heartbeat-1021/register.sh mba            # 看打印的命令
bash automations/heartbeat-1021/register.sh mba --apply
```
核对：`orca automations list --json` 里按名字「ops · 29 心跳互查 MBA（盯 iMac ops · 01）」找到 `$MBA_ID`；
`orca automations show --id $MBA_ID --json`：`enabled` 为 false，precheck、超时 240、rrule `*/5 * * * *` 和 defs.json 一致。

**3. 启用（MBA）。**
```bash
orca automations show --id $MBA_ID --json > ~/ops-archive/heartbeat-1021/$MBA_ID.before.json
orca automations edit $MBA_ID --enabled
```
核对（10 分钟后）：`orca automations runs --id $MBA_ID --json` 最近两次 `status` 为 `skipped_precheck`、`exitCode` 1、
没有 `timedOut`，stdout 有「iMac ops · 01 卡住工作检查：正常」和一行 `@@HB`。这是 Orca 预检环境里经 ssh 连 iMac 的第一次真实证据，演练覆盖不到。
**看到 `@@HB` 以后再做第 4 步**：否则 `5c2d0575` 看到「建好超过 20 分钟、还没有心跳」会报「MBA ops · 29 心跳互查」中断。

**4. iMac 加 MBA 目标（iMac）。**
```bash
orca automations show --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json > ~/ops-archive/heartbeat-1021/5c2d0575-dddc-4d5c-8f73-e47b26ea9a11.before.json
bash automations/heartbeat-1021/register.sh imac --mba-id $MBA_ID            # 看打印的命令
bash automations/heartbeat-1021/register.sh imac --mba-id $MBA_ID --apply
```
核对（10 分钟后）：`orca automations runs --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json` 最新一次 stdout 有两行：
「box ops · 29 卡住检查心跳：正常」「MBA ops · 29 心跳互查：正常」。box 目标排在前面，和现在一样先查。

**5. 并行一晚。** 不改东西。第二天早上核对：MBA 新任务一晚上每次 `exitCode` 1、没有 `timedOut`；
`5c2d0575` 两个目标都正常；box `94e4b0bc`（iMac 上加 `--environment grok-bot`）同一时段的结论和 MBA 新任务对得上；
Coding助手 这一晚收到的 heartbeat_stale / heartbeat_recovered（如果有）时间和来源对得上。

**6. 去掉 box 目标，再停 box 94e4b0bc（iMac）。** 顺序不能反：先停 box 的话，`5c2d0575` 还盯着它，20 分钟后会报「box ops · 29 卡住检查心跳」中断。
```bash
orca automations show --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json > ~/ops-archive/heartbeat-1021/5c2d0575-dddc-4d5c-8f73-e47b26ea9a11.before-final.json
bash automations/heartbeat-1021/register.sh imac --stage final --mba-id $MBA_ID --apply
# 等 5c2d0575 下一次运行只剩「MBA ops · 29 心跳互查：正常」，再停 box 那条：
orca automations show --id 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --json > ~/ops-archive/heartbeat-1021/94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80.before.json
orca automations edit 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --disabled
```
在 box 上跑就去掉 `--environment grok-bot`，备份放 box 的 `~/ops-archive/heartbeat-1021/`。final 顺带把 `5c2d0575` 改名成
「ops · 29 心跳互查（盯 MBA ops · 29）」：任务书没写，是我加的，不要的话删掉 defs.json 里 final 的 `name`。

iMac 已装的 `~/.orca-state/bin/heartbeat-watch.sh` 和 main 只差注释，不用换。

## 回滚

每一行也要 Zack 卡片、由 ops bot 执行；改之前同样先备份（`orca automations show --id <id> --json > ~/ops-archive/heartbeat-1021/<id>.before-rollback.json`）。

| 回到哪一步之前 | 按顺序做 |
|---|---|
| 第 1 步 | MBA：`rm ~/.orca-state/bin/heartbeat-watch.sh`（10-21 时没有这个文件；有 `heartbeat-watch.sh.mba.before` 就拷回去） |
| 第 2、3 步 | MBA：`orca automations edit $MBA_ID --disabled`。box `94e4b0bc` 一直在跑，ops · 01 没断过看守。要删任务用 `orca automations remove $MBA_ID`（连运行记录一起删，另要 Zack 批） |
| 第 4 步 | iMac：`bash automations/heartbeat-1021/register.sh imac --stage rollback --apply`，还原 `5c2d0575` 的名字和预检 |
| 第 6 步（全部回滚） | 1. iMac：`orca automations edit 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --enabled`，等它下一次运行正常（`orca automations runs --id 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --json`）<br>2. iMac：`bash automations/heartbeat-1021/register.sh imac --stage rollback --apply`<br>3. MBA：`orca automations edit $MBA_ID --disabled` |
| 代码 | 回退本 PR 的合并提交。新任务停用后这些脚本不会被调用 |

还原 `5c2d0575` 前，对一下备份和 defs.json 的 `before` 是否一致：
```bash
python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["result"]["automation"]; print(a["name"]); print(a["precheck"]["command"]); print(a["precheck"]["timeoutSeconds"])' \
  ~/ops-archive/heartbeat-1021/5c2d0575-dddc-4d5c-8f73-e47b26ea9a11.before.json
```
不一致（第 4 步之前有人改过）就以备份为准，手写 `orca automations edit … --name … --precheck … --precheck-timeout …`。

## 已知限制

- **告警里写「本机」**：MBA 新任务的目标 environment 是空串，heartbeat-watch 把告警的 machine / worktree 写成「本机」，
  查不到时写「连不上 本机 的 Orca」。这里的「本机」指 HB_ORCA 连到的那台，也就是经 ssh 的 iMac；目标名里写了 iMac。
  任务书要求 heartbeat-watch 逻辑不动，所以没改。
- **MBA 睡着**：box 一直开着，MBA 是笔记本。MBA 睡着超过 20 分钟，`5c2d0575` 会报「MBA ops · 29 心跳互查」中断（醒了报一次已恢复），
  这段时间 ops · 01 没人盯。MBA 现在接电源、`SleepDisabled 1`（见 `automations/migration-1020/README.md`）。
- **超时**：heartbeat-watch 查一次运行记录最多 3 次 × 90 秒，加两次 8 秒等待，最坏 286 秒，超过 240 秒的预检超时。只在 ssh 连上了、
  iMac 上的 orca 却卡住时会碰到：Orca 在 240 秒杀掉预检，这次不打 `@@HB`，`5c2d0575` 20 分钟后报 MBA 那条中断。
  ssh 连不上时每次 10 秒就失败，3 次约 46 秒，走「运行记录查不到」，连续 45 分钟才报。
- **并行那一晚**：`5c2d0575` 一次预检查两个目标。box 的 Orca 卡住时，MBA 目标这一轮可能查不到（整个预检 240 秒被杀）。
  另外 iMac 到 box 的 grok-bot 隧道 10-21 晚上断过几次（19:30、19:49 前后读 box 得到 `remote_runtime_unavailable`），
  这时 box 目标是「运行记录查不到」，连续 45 分钟才报。这和本 PR 之前一样；第 6 步去掉 box 目标后就没有这一项了。
- **包装从主检出调用**：`HB_ORCA` 指向 MBA 的 `~/orca/workspaces/ops/scripts/orca-via-ssh`（任务书的写法），heartbeat-watch.sh 用
  `~/.orca-state/bin/` 的副本。MBA 主检出切到别的分支或者删了这个文件，预检会一直「运行记录查不到」，45 分钟后报警。
- **TLA+ 模型**：`wake/tla/` 的 P3 还是按 box 建的；模型和 `SOURCES.sha256` 留给后续 wake-tla 批次（见 `wake/tla/README.md`）。

## 演练

```bash
wake/tests/heartbeat-watch-ssh.sh     # 在 iMac 的仓库根目录跑；要能 ssh mba，MBA 要能 ssh imac
```
场景、期望、实际结果和原始输出在 [`reports/heartbeat-mba-imac-1021/`](../../reports/heartbeat-mba-imac-1021/README.md)。
全部 `--dry-run`、临时 `HB_STATE_DIR`、假 webhook 目录；不建、不改任何自动任务。
