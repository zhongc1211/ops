# B1：盯 iMac ops · 01 的跨机看守从 box 挪到 MBA↔iMac（ops 审计，2026-10-21）

iMac「ops · 01 卡住工作检查」（`439cd438`）每分钟跑 `scripts/stuck-check.sh --scan`，每次在 stdout 打一行 `@@HB {...}`。
现在只有 box 上的「ops · 29 卡住检查心跳（盯 iMac ops · 01）」（`94e4b0bc`）盯它。box 已退出开发，box 一停就没人发现 ops · 01 停摆。
这里把这条看守挪到 MBA，iMac 改成盯 MBA 这条：MBA 和 iMac 互相看守。

MBA 的 Orca 没有任何 environment，读不到 iMac 的运行记录；MBA 能 `ssh imac`。所以 MBA 上的 heartbeat-watch 用
`HB_ORCA=~/.orca-state/bin/orca-via-ssh`（仓库里的 `scripts/orca-via-ssh`，和 heartbeat-watch.sh 一样装到 `~/.orca-state/bin/`）：
它把 `orca automations runs|list` 原样转到 `ssh imac zsh -lc 'orca …'`，只放行这两个只读子命令，每次 ssh 最多 70 秒。

**本目录只有定义、脚本和文档，没有建、改、启用、停用任何现网自动任务。下面每一步现网改动都要 Zack 卡片批准，由 ops bot 执行。**

## 谁盯谁

| 阶段 | 盯 iMac ops · 01（`439cd438`）的 | 盯这条看守的 |
|---|---|---|
| 现在 | box ops · 29 `94e4b0bc`（box 的 environment `iMac`） | iMac ops · 29 `5c2d0575`（经 environment `grok-bot` 读 box） |
| 卡 ② 启用以后（第 3 步起） | box `94e4b0bc` 和 MBA 新任务 | `5c2d0575` 只盯 box |
| 卡 ③ 以后（第 4、5 步，并行一晚） | 同上 | `5c2d0575` 盯 box 那条和 MBA 那条 |
| 卡 ④ 以后（第 6 步起，上线后） | MBA 新任务（经 `orca-via-ssh` 读 iMac） | `5c2d0575`（经 environment `mba` 读 MBA），box `94e4b0bc` 停用 |

任何时刻 ops · 01 至少有一条看守：MBA 新任务先启用（第 3 步），box 那条最后才停（第 6 步）。

## 文件

| 文件 | 内容 |
|---|---|
| `defs.json` | MBA 新任务的定义；iMac `5c2d0575` 三个阶段（parallel、final、rollback）的预检和超时；`before` 是 10-21 只读核对的现网配置；box `94e4b0bc` 和 ops · 01 的现网配置（只做记录） |
| `register.sh mba\|imac [--stage parallel\|final\|rollback] [--mba-id <id>] [--apply]` | 把 defs.json 变成 `orca automations create/edit` 命令。默认只打印（dry-run），不调用 orca；create 一律 `--disabled`。`--apply` 在对应机器上执行，主机名不对、或者这一步的备份文件不存在就拒绝。本 PR 没有带 `--apply` 跑过 |
| `prompts/noop.prompt.md` | MBA 新任务的提示词：预检永远非 0 退出，模型不会起；万一起了什么都不做 |
| `FAILURE-MODES.md` | 写代码前先写的失败方式清单，对应演练的场景编号；审查 7ac1220 以后的第二轮、复审 99358b0 以后的第三轮写在最后两节 |
| [`scripts/orca-via-ssh`](../../scripts/orca-via-ssh) | 给 `HB_ORCA` 用的 ssh 包装，MBA 上装到 `~/.orca-state/bin/orca-via-ssh` |
| [`wake/tests/heartbeat-watch-ssh.sh`](../../wake/tests/heartbeat-watch-ssh.sh) | 演练；[`wake/tests/heartbeat-watch-ssh-rollback.sh`](../../wake/tests/heartbeat-watch-ssh-rollback.sh) 是回退测试。产物在 `reports/heartbeat-mba-imac-1021*/` |

MBA 新任务和 box `94e4b0bc` 一样：每 5 分钟、grace 720、`--fresh-session`；预检超时是 330 秒（box 是 240）。另外加了
`--extra-agent-args=--model haiku --effort low`（MBA 现有任务的写法）：万一预检被改坏、模型被起来，用最便宜的模型。
330 秒按最坏情况定：ssh 每次最多 70 秒，查一次运行记录最多 3 次、中间等 2 × 8 秒，共 226 秒；少见情况再查一次 list，共 296 秒，
加起动约 4 秒（见「已知限制」）。

## 上线顺序

每张卡：Zack 卡片批准 → ops bot 执行 → 先备份 → 改 → 核对 → 再走下一张。备份放在执行那台机器的 `~/ops-archive/heartbeat-1021/`；
要拿掉的文件也挪到这里，不删。下面 `$MBA_ID` 是第 2 步建出来的 MBA 新任务 id。

| 卡 | 步骤 | 在哪台 |
|---|---|---|
| 合并卡 | 合并本 PR | GitHub |
| 卡 ② | 第 0–3 步：MBA 拉代码、装两个脚本、建停用的任务、启用 | MBA |
| 卡 ③ | 第 4 步：`5c2d0575` 加 MBA 目标（并行版） | iMac |
| 卡 ④ | 第 5 步并行一晚；第 6 步去掉 box 目标、停用 box `94e4b0bc` | iMac |

### 合并卡

- 卡上锁定 PR 的 head sha 和正文的 updatedAt。
- squash 的提交信息里不带 Co-Authored-By，也不带测试结果。
- 合并本身不改现网。回滚：`git revert -m 1 <合并提交>`，开 PR 合回去。

### 卡 ②：MBA 拉代码、装脚本、建任务（停用）、启用（MBA）

会动的：MBA 主检出 `~/orca/workspaces/ops`（只快进）、`~/.orca-state/bin/heartbeat-watch.sh`、`~/.orca-state/bin/orca-via-ssh`，
新建一条自动任务。

前提：
- MBA 桌面登录着、接着电源。
- `test -f ~/.config/grokbot/webhooks/coding-assistant.env && echo ok` 输出 `ok`（只测存在，不读内容）。
- 这张卡期间 box `94e4b0bc` 保持启用。

**0. 拉代码（只在 MBA）。** 本 PR 合并到 main 以后：
```bash
mkdir -p ~/ops-archive/heartbeat-1021
cd ~/orca/workspaces/ops
git rev-parse --abbrev-ref HEAD                  # 要是 main
git status --porcelain --untracked-files=no      # 要是空的（未跟踪的工作区目录不算）
git rev-parse HEAD > ~/ops-archive/heartbeat-1021/mba-ops-head.before.txt
git pull --ff-only
git rev-parse HEAD > ~/ops-archive/heartbeat-1021/mba-ops-head.after.txt
```
不在 main、有已跟踪文件的改动、或者不能快进，就停下来报给 Zack；不切分支、不 stash、不合并。

iMac 不拉代码。iMac 用的是已装的 `~/.orca-state/bin/heartbeat-watch.sh`，和 main 只差注释，本 PR 的文件它都用不到，不用换；
iMac 主检出里有 ops · 01 每分钟都读的未提交文件（`orca-projects.md`），在那里 pull 属于没有卡片的现网改动。
iMac 上要跑 `register.sh` 时（卡 ③、卡 ④、回滚），每张卡开头把 main 浅克隆到备份目录，在那里跑，不碰主检出：
```bash
M=~/ops-archive/heartbeat-1021/main-$(date +%Y%m%d-%H%M%S)
git clone -q --depth 1 --branch main "$(git -C ~/orca/workspaces/ops remote get-url origin)" "$M"
git -C "$M" log -1 --format='%H %s'              # 要是合并本 PR 以后的 main
```

**1. 装 heartbeat-watch.sh 和 orca-via-ssh（MBA）。**
```bash
cd ~/orca/workspaces/ops
mkdir -p ~/.orca-state/bin
ls -la ~/.orca-state/bin/ > ~/ops-archive/heartbeat-1021/mba-bin.before.txt 2>&1   # 10-21 时两个文件都没有
for f in heartbeat-watch.sh orca-via-ssh; do
  [ -f ~/.orca-state/bin/$f ] && cp -p ~/.orca-state/bin/$f ~/ops-archive/heartbeat-1021/$f.mba.before
  install -m 755 scripts/$f ~/.orca-state/bin/$f
done
shasum -a 256 scripts/heartbeat-watch.sh ~/.orca-state/bin/heartbeat-watch.sh scripts/orca-via-ssh ~/.orca-state/bin/orca-via-ssh
```
核对：每个文件的两行 sha256 一样。再跑一次 `--dry-run`（临时状态目录和假 webhook 目录，不发叫醒、不读真凭据）：
```bash
T=$(mktemp -d); mkdir -p "$T/hooks"; printf 'URL=http://127.0.0.1:9/hb-drill\nKEY=hb-drill-dummy-key\n' > "$T/hooks/coding-assistant.env"
HB_STATE_DIR="$T/state" STUCK_WEBHOOK_DIR="$T/hooks" HB_ORCA=$HOME/.orca-state/bin/orca-via-ssh ORCA_SSH_HOST=imac \
  ~/.orca-state/bin/heartbeat-watch.sh --precheck --dry-run --target "iMac ops · 01 卡住工作检查||439cd438-cffe-44dd-bd2b-23b07bfa3d61|20"
echo "rc=$?"; rm -rf "$T"
```
期望：一行「iMac ops · 01 卡住工作检查：正常（最新心跳 …）」，`rc=1`（`--precheck` 正常时退出 1）。

**2. 建停用的任务（MBA）。**
```bash
cd ~/orca/workspaces/ops
orca automations list --json > ~/ops-archive/heartbeat-1021/mba-list.before.json
bash automations/heartbeat-1021/register.sh mba            # 看打印的命令
bash automations/heartbeat-1021/register.sh mba --apply
```
核对：`orca automations list --json` 里按名字「ops · 29 心跳互查 MBA（盯 iMac ops · 01）」找到 `$MBA_ID`；
`orca automations show --id $MBA_ID --json`：`enabled` 为 false，precheck、超时 330、rrule `*/5 * * * *` 和 defs.json 一致。

**3. 启用（MBA）。**
```bash
orca automations show --id $MBA_ID --json > ~/ops-archive/heartbeat-1021/$MBA_ID.before.json
orca automations edit $MBA_ID --enabled
```
核对（10 分钟后）：`orca automations runs --id $MBA_ID --json` 里至少两次运行 `status` 是 `skipped_precheck`、`exitCode` 1、
没有 `timedOut`；stdout 有「iMac ops · 01 卡住工作检查：正常」和一行 `@@HB`，`@@HB` 里 `rc` 是 0；每次的 `durationMs` 记下来。
这是 Orca 预检环境里经 ssh 连 iMac 的第一次真实证据，演练覆盖不到。

卡 ② 的回滚：停用 MBA 新任务，装上的两个文件挪走（回滚表「第 2、3 步」）。

### 卡 ③：iMac `5c2d0575` 加 MBA 目标（iMac）

前提：卡 ② 的核对里已经看到 MBA 新任务的 `@@HB`。没看到就先别做：这时做这一步，`5c2d0575` 看到「建好超过 20 分钟、还没有心跳」
会报「MBA ops · 29 心跳互查」中断。

**4. 加 MBA 目标（iMac）。** 先照第 0 步把 main 浅克隆到 `$M`。
```bash
B=~/ops-archive/heartbeat-1021/5c2d0575-dddc-4d5c-8f73-e47b26ea9a11.before.json
orca automations show --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json > "$B"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["result"]["automation"]; d=next(e for e in json.load(open(sys.argv[2]))["edit"] if e["stage"]=="parallel")["before"]; print(a["name"]==d["name"], a["precheck"]["command"]==d["precheck"], a["precheck"]["timeoutSeconds"]==d["precheckTimeout"])' \
  "$B" "$M/automations/heartbeat-1021/defs.json"   # 要三个 True
bash "$M/automations/heartbeat-1021/register.sh" imac --mba-id $MBA_ID            # 看打印的命令，超时是 600
bash "$M/automations/heartbeat-1021/register.sh" imac --mba-id $MBA_ID --apply
```
不是三个 True（之前有人改过）就停下来报给 Zack。
核对（10 分钟后）：`orca automations runs --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json` 最新一次没有 `timedOut`，stdout 有两行：
「box ops · 29 卡住检查心跳：正常」「MBA ops · 29 心跳互查：正常」。box 目标排在前面，和现在一样先查。

卡 ③ 的回滚：`bash "$M/automations/heartbeat-1021/register.sh" imac --stage rollback --apply`（回滚表「第 4 步」）。

### 卡 ④：并行一晚，然后去掉 box 目标、停用 box `94e4b0bc`（iMac）

**5. 并行一晚。** 不改东西。并行一晚是 plan D1，要 Zack 确认；这一晚要跨过 02:17 的 ops · 11。第二天早上要有这些证据：
- MBA 新任务整晚每次 `exitCode` 1、没有 `timedOut`、`@@HB` 的 `rc` 都是 0，记下最长的 `durationMs`；
- `5c2d0575` 两个目标的结论，和 box `94e4b0bc`（iMac 上加 `--environment grok-bot`）同一时段的结论对得上；
- 没有误报。Coding助手 这一晚收到的 heartbeat_stale / heartbeat_recovered（如果有）逐条对上原因；
- iMac 上 `pgrep -fl 'zsh -lc orca'` 和 sshd 的进程数没有越积越多。

**6. 去掉 box 目标，再停 box 94e4b0bc（iMac）。** 先照第 0 步把 main 浅克隆到 `$M`。顺序不能反：先停 box 的话，`5c2d0575` 还盯着它，
20 分钟后会报「box ops · 29 卡住检查心跳」中断。
```bash
orca automations show --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json > ~/ops-archive/heartbeat-1021/5c2d0575-dddc-4d5c-8f73-e47b26ea9a11.before-final.json
bash "$M/automations/heartbeat-1021/register.sh" imac --stage final --mba-id $MBA_ID --apply
# 等 5c2d0575 下一次运行只剩「MBA ops · 29 心跳互查：正常」，再停 box 那条（只停，不删）：
orca automations show --id 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --json > ~/ops-archive/heartbeat-1021/94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80.before.json
orca automations edit 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --disabled
```
在 box 上跑就去掉 `--environment grok-bot`，备份放 box 的 `~/ops-archive/heartbeat-1021/`。final 把 `5c2d0575` 的预检超时改成 300，
顺带改名成「ops · 29 心跳互查（盯 MBA ops · 29）」：改名是任务书没写、我加的，不要的话删掉 defs.json 里 final 的 `name`。

卡 ④ 上要告诉 Zack 三件残余风险：
- iMac 和 MBA 同时停，没人报；
- MBA 睡着或重启，会空档 20–45 分钟，但会报出来；关盖、拔电源时的设置（D6，要 sudo）还没定；
- `5c2d0575` 本身没人盯（见「已知限制」）。

卡 ④ 的回滚：先重新启用 box、等它正常，再还原 `5c2d0575`，最后停用 MBA 新任务（回滚表「第 6 步」）。
box 真正下线以后，这条回滚就不成立了，只能修 MBA 这边往前走。

## 回滚

每一行也要 Zack 卡片、由 ops bot 执行；改之前同样先备份（`orca automations show --id <id> --json > ~/ops-archive/heartbeat-1021/<id>.before-rollback.json`）。
iMac 上的 `register.sh` 用浅克隆的 main（`$M`，见第 0 步）。文件只挪不删；自动任务只停用，不删，不用 `orca automations remove`。

| 回到哪一步之前 | 按顺序做 |
|---|---|
| 第 1 步 | MBA：`d=~/ops-archive/heartbeat-1021/removed-$(date +%Y%m%d-%H%M%S); mkdir -p "$d" && mv ~/.orca-state/bin/heartbeat-watch.sh ~/.orca-state/bin/orca-via-ssh "$d"/`。备份目录里有 `*.mba.before` 就拷回 `~/.orca-state/bin/`（10-21 时两个都没有） |
| 第 2、3 步 | MBA：`orca automations edit $MBA_ID --disabled`，再做上一行。box `94e4b0bc` 一直在跑，ops · 01 没断过看守 |
| 第 4 步 | iMac：`bash "$M/automations/heartbeat-1021/register.sh" imac --stage rollback --apply`，还原 `5c2d0575` 的名字、预检和超时（240） |
| 第 6 步（全部回滚） | 1. iMac：`orca automations edit 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --enabled`，等它下一次运行正常（`orca automations runs --id 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --json`）<br>2. iMac：`bash "$M/automations/heartbeat-1021/register.sh" imac --stage rollback --apply`<br>3. MBA：`orca automations edit $MBA_ID --disabled` |
| 代码 | `git revert -m 1 <合并提交>`，开 PR 合回去。新任务停用后这些脚本不会被调用 |

还原 `5c2d0575` 前，对一下备份和 defs.json 的 `before` 是否一致：
```bash
python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["result"]["automation"]; print(a["name"]); print(a["precheck"]["command"]); print(a["precheck"]["timeoutSeconds"])' \
  ~/ops-archive/heartbeat-1021/5c2d0575-dddc-4d5c-8f73-e47b26ea9a11.before.json
```
不一致（第 4 步之前有人改过）就以备份为准，手写 `orca automations edit … --name … --precheck … --precheck-timeout …`。

## 已知限制

- **超时**：MBA 新任务的预检超时 330 秒（复审的条件，原来是 240）。ssh 每次最多 70 秒（包装里 perl 的 `alarm`），
  heartbeat-watch 查一次运行记录最多 3 次、中间等 2 × 8 秒，最坏 226 秒。
  - 少见情况：还没见过目标的心跳、心跳又没有或过期时，heartbeat-watch 还要查一次 list（建好时间），也经 ssh。runs 前两次各卡满 70 秒、
    第三次才成功，再加 list 70 秒，共 296 秒，加起动约 4 秒，在 330 以内。上线后见过一次心跳，就不走这条路了。
  - 没有 70 秒上限时要等 heartbeat-watch 自己的 90 秒超时：查运行记录最坏 286 秒，在 330 以内；少见情况最坏 376 秒，超过 330，
    这一轮被 Orca 杀掉，不写 fail_since、不打 `@@HB`。演练 S12、S12.old 用真时间跑过，见 PR 描述。
  - 330 比 5 分钟的间隔长：一轮预检超过 300 秒时，下一轮的预检会和它同时跑一小段。Orca 建运行只按计划时间去重，没看到
    「上一轮没完就不起下一轮」（读的是 iMac 上 Orca 1.4.224 的代码，MBA 的 1.4.229 没核对）；heartbeat-watch 写 state 不加锁，
    最坏是同一时刻发两条告警。只有预检超过 300 秒才会这样，常见最坏 226 秒碰不到。`5c2d0575` 并行版（超时 600）也一样。
  - ssh 连不上时每次 10 秒就失败，3 次约 46 秒，走「运行记录查不到」，连续 45 分钟才报。
  - `5c2d0575` 的目标经 iMac 本机 orca 的 environment 读，不经包装，每个目标最坏还是 286 秒。并行版两个目标最坏 572 秒，超时改成 600
    （Orca 的上限）；最终版一个目标，改成 300；回滚版还原成现网的 240，和今天一样，单个目标卡满时也放不下。
- **告警里写「本机」**：MBA 新任务的目标 environment 是空串，heartbeat-watch 把告警的 machine / worktree 写成「本机」，
  查不到时写「连不上 本机 的 Orca」。这里的「本机」指 HB_ORCA 连到的那台，也就是经 ssh 的 iMac；目标名里写了 iMac。
  任务书要求 heartbeat-watch 逻辑不动；在包装里改写参数，又会把只读转发变成改参数，所以这次没改。收到这条告警时，「本机」是 iMac，不是 MBA。
- **`5c2d0575` 本身没人盯**：MBA 那条只盯 iMac ops · 01。让 MBA 顺便盯 `5c2d0575` 要多一个经 ssh 的目标，最坏 452 秒，
  超过 330 秒的超时和 5 分钟的间隔，留给后续 PR。
- **iMac 和 MBA 同时停**：没人报。
- **只看时间，不看 rc**：被盯的那条 `@@HB` 里 rc 不是 0（比如告警发不出去）也判正常。本 PR 之前就是这样，留给后续。
- **MBA 睡着**：box 一直开着，MBA 是笔记本。MBA 睡着超过 20 分钟，`5c2d0575` 会报「MBA ops · 29 心跳互查」中断（醒了报一次已恢复），
  这段时间 ops · 01 没人盯。MBA 现在接电源、`SleepDisabled 1`（见 `automations/migration-1020/README.md`）；关盖、拔电源时的设置（D6）还没定。
- **并行那一晚**：iMac 到 box 的 grok-bot 隧道 10-21 晚上断过几次（19:30、19:49、20:20、20:25 前后读 box 得到 `remote_runtime_unavailable`），
  这时 box 目标是「运行记录查不到」，连续 45 分钟才报。这和本 PR 之前一样；第 6 步去掉 box 目标后就没有这一项了。
- **装好的是副本**：MBA 上的 heartbeat-watch.sh 和 orca-via-ssh 都是 `~/.orca-state/bin/` 里的副本，主检出切分支、改文件都不影响它们。
  反过来，main 里这两个文件改了，要另开卡片重装、比 sha。
- **ssh 半路断线**：包装加了 `ServerAliveInterval=15`、`ServerAliveCountMax=2`，MBA 这边约 30 秒退出。没演练。
- **TLA+ 模型**：`wake/tla/` 的 P3 还是按 box 建的；模型和 `SOURCES.sha256` 留给后续 wake-tla 批次（见 `wake/tla/README.md`）。

## 演练

```bash
wake/tests/heartbeat-watch-ssh.sh            # 在 iMac 的仓库根目录跑；要能 ssh mba，MBA 要能 ssh imac。约 5 分钟（S12 要等真时间）
wake/tests/heartbeat-watch-ssh-rollback.sh   # 回退测试：代码换回 base f828d452、defs 换成现网版，同一套演练整轮跑一次，看该挂的是不是挂了
```
场景、期望、实际结果和原始输出写在产物目录的 `README.md`（`HB_DRILL_OUT` 指定目录，默认 `reports/heartbeat-mba-imac-1021/`）。
回退测试的期望写在 [`FAILURE-MODES.md`](FAILURE-MODES.md)「回退测试的期望」和「回退测试的期望（第二轮）」，结果在产物目录的 `ROLLBACK.md`。
每次运行的 commit 和产物目录列在 PR 描述里。
heartbeat-watch 都用临时 `HB_STATE_DIR`；除 S12 外都带 `--dry-run`。S12 不带（要看它写下的 state.json 和 `@@HB`），webhook 目录是空的，
PATH 里放了只记录调用的假 curl。不发叫醒，不建、不改任何自动任务。
