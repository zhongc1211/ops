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
| `FAILURE-MODES.md` | 写代码前先写的失败方式清单，对应演练的场景编号；审查 7ac1220 以后的第二轮、复审 99358b0 以后的第三轮、套 lockf 的第五轮、第五轮补充的「锁一直被占着」写在最后四节 |
| [`scripts/orca-via-ssh`](../../scripts/orca-via-ssh) | 给 `HB_ORCA` 用的 ssh 包装，MBA 上装到 `~/.orca-state/bin/orca-via-ssh` |
| [`scripts/lock-held-alert`](../../scripts/lock-held-alert) | 写在两个 precheck 的 lockf 前面：退出码照 lockf 的交出去；锁一直被占着、连续跳过满 45 分钟时告警一次，锁放开后报恢复。MBA、iMac 都装到 `~/.orca-state/bin/lock-held-alert` |
| [`wake/tests/heartbeat-watch-ssh.sh`](../../wake/tests/heartbeat-watch-ssh.sh) | 演练；[`wake/tests/heartbeat-watch-ssh-rollback.sh`](../../wake/tests/heartbeat-watch-ssh-rollback.sh) 是回退测试。产物在 `reports/heartbeat-mba-imac-1021*/` |

MBA 新任务和 box `94e4b0bc` 一样：每 5 分钟、grace 720、`--fresh-session`；预检超时是 330 秒（box 是 240）。另外加了
`--extra-agent-args=--model haiku --effort low`（MBA 现有任务的写法）：万一预检被改坏、模型被起来，用最便宜的模型。
330 秒按最坏情况定：ssh 每次最多 70 秒，查一次运行记录最多 3 次、中间等 2 × 8 秒，共 226 秒；少见情况再查一次 list，共 296 秒，
加起动约 4 秒（见「已知限制」）。
330 秒比 5 分钟的间隔长，所以 precheck 外面套了 `/usr/bin/lockf -k -t 0 $HOME/.orca-state/heartbeat-watch/mba-hb-watch.lock`：
上一轮还没跑完时，这一轮拿不到锁，立刻退出 75，不起 heartbeat-watch。`5c2d0575` 的并行版（超时 600）也套了，锁文件是 `5c2d0575.lock`。
锁一直被占着时每一轮都退出 75，这条看守就停了，所以 lockf 前面再写一层 `~/.orca-state/bin/lock-held-alert`（仓库里的 `scripts/lock-held-alert`）：
它照原样跑后面的 lockf 命令，退出码不变；连续跳过时在锁文件旁边的 `<锁文件>.skips.json` 记次数，从第一次跳过起满 45 分钟告警一次，
锁放开后报一次恢复（见「已知限制」里的「锁一直被占着」）。

## 上线顺序

每张卡：Zack 卡片批准 → ops bot 执行 → 先备份 → 改 → 核对 → 再走下一张。备份放在执行那台机器的 `~/ops-archive/heartbeat-1021/`；
要拿掉的文件也挪到这里，不删。下面 `$MBA_ID` 是第 2 步建出来的 MBA 新任务 id。

| 卡 | 步骤 | 在哪台 |
|---|---|---|
| 合并卡 | 合并本 PR | GitHub |
| 卡 ② | 第 0–3 步：MBA 拉代码、装三个脚本、建停用的任务、启用 | MBA |
| 卡 ③ | 第 4 步：iMac 装 lock-held-alert，`5c2d0575` 加 MBA 目标（并行版） | iMac |
| 卡 ④ | 第 5 步并行一晚；第 6 步去掉 box 目标、停用 box `94e4b0bc` | iMac |

### 合并卡

- 卡上锁定 PR 的 head sha 和正文的 updatedAt。
- squash 的提交信息里不带 Co-Authored-By，也不带测试结果。
- 合并本身不改现网。回滚：`git revert -m 1 <合并提交>`，开 PR 合回去。

### 卡 ②：MBA 拉代码、装脚本、建任务（停用）、启用（MBA）

会动的：MBA 主检出 `~/orca/workspaces/ops`（只快进）、`~/.orca-state/bin/heartbeat-watch.sh`、`~/.orca-state/bin/orca-via-ssh`、
`~/.orca-state/bin/lock-held-alert`、`~/.orca-state/heartbeat-watch/`（新建），新建一条自动任务。

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

iMac 不拉代码。iMac 用的是已装的 `~/.orca-state/bin/heartbeat-watch.sh`，和 main 只差注释，不用换；本 PR 的文件里 iMac 只用到
lock-held-alert，卡 ③ 第 4 步从浅克隆装。iMac 主检出里有 ops · 01 每分钟都读的未提交文件（`orca-projects.md`），在那里 pull 属于没有卡片的现网改动。
iMac 上要跑 `register.sh` 时（卡 ③、卡 ④、回滚），每张卡开头把 main 浅克隆到备份目录，在那里跑，不碰主检出：
```bash
M=~/ops-archive/heartbeat-1021/main-$(date +%Y%m%d-%H%M%S)
git clone -q --depth 1 --branch main "$(git -C ~/orca/workspaces/ops remote get-url origin)" "$M"
git -C "$M" log -1 --format='%H %s'              # 要是合并本 PR 以后的 main
```

**1. 装 heartbeat-watch.sh、orca-via-ssh 和 lock-held-alert，建锁文件的目录（MBA）。**
```bash
cd ~/orca/workspaces/ops
mkdir -p ~/.orca-state/bin
ls -la ~/.orca-state/bin/ > ~/ops-archive/heartbeat-1021/mba-bin.before.txt 2>&1   # 10-21 时前两个文件都没有；lock-held-alert 是这次新加的
ls -la ~/.orca-state/heartbeat-watch/ > ~/ops-archive/heartbeat-1021/mba-hb-dir.before.txt 2>&1   # 10-21 时这个目录没有
mkdir -p ~/.orca-state/heartbeat-watch   # precheck 里 lockf 的锁文件放这里；目录不在时 lockf 退出 73，每轮都没有 @@HB
for f in heartbeat-watch.sh orca-via-ssh lock-held-alert; do
  [ -f ~/.orca-state/bin/$f ] && cp -p ~/.orca-state/bin/$f ~/ops-archive/heartbeat-1021/$f.mba.before
  install -m 755 scripts/$f ~/.orca-state/bin/$f
done
for f in heartbeat-watch.sh orca-via-ssh lock-held-alert; do shasum -a 256 scripts/$f ~/.orca-state/bin/$f; done
```
核对：每个文件的两行 sha256 一样。再照 precheck 的写法（经 lock-held-alert 和 lockf）跑一次 `--dry-run`（临时状态目录和假 webhook 目录，
不发叫醒、不读真凭据）：
```bash
T=$(mktemp -d); mkdir -p "$T/hooks"; printf 'URL=http://127.0.0.1:9/hb-drill\nKEY=hb-drill-dummy-key\n' > "$T/hooks/coding-assistant.env"
HB_STATE_DIR="$T/state" STUCK_WEBHOOK_DIR="$T/hooks" HB_ORCA=$HOME/.orca-state/bin/orca-via-ssh ORCA_SSH_HOST=imac \
  ~/.orca-state/bin/lock-held-alert /usr/bin/lockf -k -t 0 ~/.orca-state/heartbeat-watch/mba-hb-watch.lock \
  ~/.orca-state/bin/heartbeat-watch.sh --precheck --dry-run --target "iMac ops · 01 卡住工作检查||439cd438-cffe-44dd-bd2b-23b07bfa3d61|20"
echo "rc=$?"; rm -rf "$T"
```
期望：一行「iMac ops · 01 卡住工作检查：正常（最新心跳 …）」，`rc=1`（`--precheck` 正常时退出 1）；锁空着、没有跳过的记录时，
lock-held-alert 什么都不打。`rc=73`、stderr 有 `cannot open` 是锁文件的目录不在（上面的 `mkdir -p` 没做）；`rc=127` 是 lock-held-alert 没装上。
跑完 `~/.orca-state/heartbeat-watch/` 里留一个空的 `mba-hb-watch.lock`（`-k` 不删它），不用管。

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
`exitCode` 73、stderr 有 `cannot open` 是锁文件的目录不在，回第 1 步补 `mkdir -p`；`exitCode` 127 是 lock-held-alert 没装上，回第 1 步。
以后偶尔有一次 `exitCode` 75、stderr 是 `lockf: …: already locked`、stdout 只有 lock-held-alert 的一行「锁被占着，这一轮没起
heartbeat-watch.sh；已连续跳过 1 轮…」，是上一轮还没跑完、这一轮被跳过（见「已知限制」）；下一次拿到锁的那一轮 stdout 多一行
「锁拿到了，之前连续跳过 1 轮…」。连着出现就是有一轮卡住了，用 `pgrep -l lockf` 看一下，不要杀进程，报给 Zack。
连续跳过满 45 分钟，lock-held-alert 给 Coding助手 发一条 `heartbeat_stale`（`source` 是 `lock-held-alert`），锁放开后发一条 `heartbeat_recovered`。

可选：验证 Orca 把退出 75 记成 `skipped_precheck`（演练没法验证，见「已知限制」）。第 3 步启用以后，在 MBA 上拿住锁 6 分钟：
```bash
/usr/bin/lockf -k -t 0 ~/.orca-state/heartbeat-watch/mba-hb-watch.lock sleep 360   # 前台跑，Ctrl-C 提前结束
```
这条命令自己马上退出 75，是正好有一轮在跑，等它跑完再试。
这期间的那一轮应该是 `status` `skipped_precheck`、`exitCode` 75、错误文字「Precheck exited with code 75.」、没有 `@@HB`，
stdout 只有 lock-held-alert 那一行「…已连续跳过 1 轮…；到 45 分钟才报」；放开以后的下一轮 stdout 有「锁拿到了，之前连续跳过 1 轮…」，
`~/.orca-state/heartbeat-watch/mba-hb-watch.lock.skips.json` 没了。6 分钟到不了 45 分钟，不会告警。
这时 box `94e4b0bc` 还在盯 ops · 01，MBA 新任务要到卡 ③ 才有人盯，少一轮 `@@HB` 不会引起告警。

卡 ② 的回滚：停用 MBA 新任务，装上的三个文件和 `~/.orca-state/heartbeat-watch/` 挪走（回滚表「第 2、3 步」）。

### 卡 ③：iMac `5c2d0575` 加 MBA 目标（iMac）

前提：卡 ② 的核对里已经看到 MBA 新任务的 `@@HB`。没看到就先别做：这时做这一步，`5c2d0575` 看到「建好超过 20 分钟、还没有心跳」
会报「MBA ops · 29 心跳互查」中断。

会动的：iMac `~/.orca-state/bin/lock-held-alert`（新装）、`5c2d0575` 的预检和超时。

**4. 装 lock-held-alert，加 MBA 目标（iMac）。** 先照第 0 步把 main 浅克隆到 `$M`。并行版的 precheck 经 `~/.orca-state/bin/lock-held-alert` 起，
没装就每轮退出 127，两个目标都没人查，所以先装、试跑，再改任务。
```bash
B=~/ops-archive/heartbeat-1021/5c2d0575-dddc-4d5c-8f73-e47b26ea9a11.before.json
orca automations show --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json > "$B"
python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["result"]["automation"]; d=next(e for e in json.load(open(sys.argv[2]))["edit"] if e["stage"]=="parallel")["before"]; print(a["name"]==d["name"], a["precheck"]["command"]==d["precheck"], a["precheck"]["timeoutSeconds"]==d["precheckTimeout"])' \
  "$B" "$M/automations/heartbeat-1021/defs.json"   # 要三个 True
ls -la ~/.orca-state/bin/ > ~/ops-archive/heartbeat-1021/imac-bin.before.txt 2>&1   # 10-22 时没有 lock-held-alert
[ -f ~/.orca-state/bin/lock-held-alert ] && cp -p ~/.orca-state/bin/lock-held-alert ~/ops-archive/heartbeat-1021/lock-held-alert.imac.before
install -m 755 "$M/scripts/lock-held-alert" ~/.orca-state/bin/lock-held-alert
shasum -a 256 "$M/scripts/lock-held-alert" ~/.orca-state/bin/lock-held-alert   # 两行一样
T=$(mktemp -d); mkdir -p "$T/hooks"; printf 'URL=http://127.0.0.1:9/hb-drill\nKEY=hb-drill-dummy-key\n' > "$T/hooks/coding-assistant.env"
HB_STATE_DIR="$T/state" STUCK_WEBHOOK_DIR="$T/hooks" \
  ~/.orca-state/bin/lock-held-alert /usr/bin/lockf -k -t 0 ~/.orca-state/heartbeat-watch/5c2d0575.lock \
  ~/.orca-state/bin/heartbeat-watch.sh --precheck --dry-run --target "box ops · 29 卡住检查心跳|grok-bot|94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80|20" \
  --target "MBA ops · 29 心跳互查|mba|$MBA_ID|20"
echo "rc=$?"; rm -rf "$T"   # 要两行「…：正常」、rc=1，lock-held-alert 什么都不打
bash "$M/automations/heartbeat-1021/register.sh" imac --mba-id $MBA_ID            # 看打印的命令，超时是 600
bash "$M/automations/heartbeat-1021/register.sh" imac --mba-id $MBA_ID --apply
```
不是三个 True（之前有人改过）就停下来报给 Zack。试跑不是 `rc=1`、两行「正常」，也停下来，先别 `--apply`。
试跑在 `~/.orca-state/heartbeat-watch/` 里留一个空的 `5c2d0575.lock`，不用管；状态用的是临时目录，不碰 `5c2d0575` 的真状态。
核对（10 分钟后）：`orca automations runs --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json` 最新一次没有 `timedOut`，stdout 有两行：
「box ops · 29 卡住检查心跳：正常」「MBA ops · 29 心跳互查：正常」。box 目标排在前面，和现在一样先查。

卡 ③ 的回滚：`bash "$M/automations/heartbeat-1021/register.sh" imac --stage rollback --apply`，再挪走 lock-held-alert（回滚表「第 4 步」）。

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
| 第 1 步 | MBA：`d=~/ops-archive/heartbeat-1021/removed-$(date +%Y%m%d-%H%M%S); mkdir -p "$d" && mv ~/.orca-state/bin/heartbeat-watch.sh ~/.orca-state/bin/orca-via-ssh ~/.orca-state/bin/lock-held-alert ~/.orca-state/heartbeat-watch "$d"/`（锁文件和 `*.skips.json` 在 `~/.orca-state/heartbeat-watch/` 里，一起挪走）。备份目录里有 `*.mba.before` 就拷回 `~/.orca-state/bin/`（10-21 时这几个文件和 `~/.orca-state/heartbeat-watch/` 都没有） |
| 第 2、3 步 | MBA：`orca automations edit $MBA_ID --disabled`，再做上一行。box `94e4b0bc` 一直在跑，ops · 01 没断过看守 |
| 第 4 步 | iMac：1. `bash "$M/automations/heartbeat-1021/register.sh" imac --stage rollback --apply`，还原 `5c2d0575` 的名字、预检和超时（240）<br>2. 等 `5c2d0575` 下一次运行用回现网的预检（stdout 只有「box ops · 29 卡住检查心跳：…」一个目标），再挪走这次加的文件：`d=~/ops-archive/heartbeat-1021/removed-$(date +%Y%m%d-%H%M%S); mkdir -p "$d" && mv ~/.orca-state/bin/lock-held-alert "$d"/; mv ~/.orca-state/heartbeat-watch/5c2d0575.lock* "$d"/ 2>/dev/null`。`~/.orca-state/heartbeat-watch/` 是 `5c2d0575` 的状态目录，目录本身和里面别的文件不动 |
| 第 6 步（全部回滚） | 1. iMac：`orca automations edit 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --enabled`，等它下一次运行正常（`orca automations runs --id 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --json`）<br>2. iMac：做「第 4 步」那一行<br>3. MBA：`orca automations edit $MBA_ID --disabled` |
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
  - 330 比 5 分钟的间隔长，两轮预检可能重叠，见下面「两轮预检重叠」。
  - ssh 连不上时每次 10 秒就失败，3 次约 46 秒，走「运行记录查不到」，连续 45 分钟才报。
  - `5c2d0575` 的目标经 iMac 本机 orca 的 environment 读，不经包装，每个目标最坏还是 286 秒。并行版两个目标最坏 572 秒，超时改成 600
    （Orca 的上限）；最终版一个目标，改成 300；回滚版还原成现网的 240，和今天一样，单个目标卡满时也放不下。
- **两轮预检重叠**：MBA 新任务的预检超时 330 秒、`5c2d0575` 并行版 600 秒，都比 5 分钟的间隔长。一轮预检超过 300 秒时，Orca 照常起下一轮，
  不等上一轮跑完。这是读两台现装 Orca 的代码得出的（iMac 10-21 23:15 前后自己升级到 1.4.235，MBA 是 1.4.229；前几轮读的是 iMac 的 1.4.224），
  没在真机上验证。MBA 新任务常见最坏 226 秒，碰不到；少见情况 296 秒加起动约 4 秒，正好在边上；并行版两个目标最坏 572 秒。
  - 不加锁会怎样：heartbeat-watch 两个进程各读一份旧状态、各写回整份；`save_json` 不加锁，临时文件名固定是 `state.json.tmp`。
    后存的一轮盖掉先存的：同一次中断报两次、漏报一次中断、「已恢复」不发、45 分钟的计时偏；两轮恰好同时写时，state.json 可能被写坏，
    下一轮按空状态从头算，所有目标的记录一起丢。
  - 现在的做法：这两个 precheck 外面套了 `/usr/bin/lockf -k -t 0 <锁文件>`，锁文件在 `~/.orca-state/heartbeat-watch/`，每个任务一个
    （`mba-hb-watch.lock`、`5c2d0575.lock`），lockf 前面再写 `lock-held-alert`（见下面「锁一直被占着」）。上一轮还在跑时，这一轮立刻退出 75，
    不起 heartbeat-watch，不读也不写 heartbeat-watch 的状态，也没有 `@@HB`，stdout 只有 lock-held-alert 的一行；
    上一轮被 Orca 超时杀掉（整个进程组）以后锁就放开，下一轮拿得到。持锁的 lockf 被 SIGKILL、SIGTERM、SIGSEGV 杀掉时锁也马上放开，
    `-k` 留下的锁文件不挡下一次拿锁。演练 S13、S14 在两台真机的临时目录里看过这几点。
  - 退出 75 时 Orca 记 `skipped_precheck`：依据是两台 Orca 的代码（退出码不是 0 就记 `skipped_precheck`）和运行记录里退出码 1、2、255 的记法，
    没在真机上验证：要让 Orca 跑一轮带锁的预检，就得建任务或改现网任务。第 3 步后面写了启用以后怎么手动看一次。
  - 被跳过的那一轮没有 `@@HB`。MBA 新任务跳过一轮，iMac `5c2d0575` 看到它的两次心跳之间就多隔 5 分钟：上一轮跑过 300 秒、正常结束时，
    间隔约 10 分钟，在 20 分钟的阈值以内；上一轮被超时杀掉（它本来就没有 `@@HB`）时，间隔约 15 分钟加下一轮的用时，下一轮也跑了 5 分钟以上
    就会过 20 分钟，iMac 可能报一次 MBA 那条中断。
  - 锁文件的目录要先有：MBA 上第 1 步 `mkdir -p`，漏了每轮退出 73、没有 `@@HB`。iMac 上这个目录已经有了。
  - 挡不住的：最终版（超时 300）和回滚版（240）没套 lockf，这次只要求套 MBA 新任务和并行版；锁按任务分，两个任务共用一个状态目录时
    互相挡不住（现在每台只有一个任务用 heartbeat-watch）；有人只杀 lockf 一个进程时锁放开，它起的 heartbeat-watch 还在跑，下一轮会和它同时跑。
  - 后续：heartbeat-watch.sh 自己加锁、临时文件按进程取名。这次按要求不改 heartbeat-watch.sh，留给后续 PR，和 wake-tla 模型的更新一起做。
- **锁一直被占着**：每一轮都退出 75，这条看守就停了。锁能一直被占着，要么有人手动拿着锁，要么持锁的进程卡住、又不在 Orca 会杀的进程组里
  （heartbeat-watch 一轮有上限，到超时 Orca 杀整个进程组）。`lock-held-alert` 管这件事：
  - 每次 lockf 退出 75，在锁文件旁边的 `<锁文件>.skips.json` 记这一串跳过的第一次时间和次数，stdout 打一行「…已连续跳过 N 轮…」。
    从第一次跳过起满 45 分钟的那一轮（5 分钟一轮，是第 10 或 11 次）告警一次：发给 coding-assistant（和 heartbeat-watch 同一个 bot、同样的
    webhook 文件），`kind` `heartbeat_stale`，`source` `lock-held-alert`，写明主机、锁文件、第一次跳过的时间、跳过了几轮、这段时间没在查的目标。
    之后的跳过不再报。拿到锁的那一轮跑完清掉记录；报过警的再发一条 `heartbeat_recovered`。
  - 跳过的一轮不打 `@@HB`：对面的 heartbeat-watch 只看 `@@HB` 的时间、不看 `rc`，打了会当这边还活着（FAILURE-MODES F34）。
  - 退出码一律照 lockf 的交出去；lock-held-alert 自己出错（状态文件读写失败、发告警出错）只在 stderr 写一行。
  - 演练：S15 外部拿住锁，阈值用环境变量改成 15 秒，看到第 3 轮告警、第 4 轮不重复、锁放开后第 5 轮报恢复、第 6 轮什么都不打；
    默认的 45 分钟由 S15 的 .45 看，状态文件是演练写的（假装第一次跳过在 44、46 分钟前）。没真等 45 分钟。告警只发给了假 curl。
  - 每轮只发一次，curl 最多 20 秒；发不出去（没有 webhook 配置、POST 失败）就在 stdout 写「没发出去」，下一轮跳过时再发；
    「已恢复」发不出去时留着报过的记录，下一次拿到锁再发。这条路没演练。
  - 拿到锁的那一轮要报恢复时多一次 POST：MBA 那条最坏 296 秒加起动约 4 秒、再加 20 秒，在 330 以内；并行版 572 加 20，在 600 以内。
  - 两个 lock-held-alert 同时写状态文件（拿锁的那一轮结束时清掉，同时有一轮跳过、记一次）：临时文件按进程取名，再 `os.replace` 换上去，
    文件不会写坏，谁后写算谁的。清掉的记录被盖回「跳过 1 次」，下一轮拿到锁就清掉；跳过的一次被盖掉，告警晚一轮。没演练。
  - 记录是旧的（任务在一次跳过之后被停用，很久以后再启用，第一轮又正好跳过）：从旧的第一次跳过算起，可能马上就过 45 分钟、提前报一次。
  - 从卡 ③ 起，MBA 的锁一直被占着时报两次：iMac `5c2d0575` 20 分钟报「MBA ops · 29 心跳互查」中断，MBA 的 lock-held-alert 45 分钟
    再报一次锁被占着；恢复时也是两条。两条说的不是一回事（对面看到的现象、这边的原因），没合并。
  - 退出 73（锁文件的目录没了）不计数、不报：状态文件也写不了。MBA 上从卡 ③ 起 iMac 会报（没有 `@@HB`）。iMac 上这个目录是
    `5c2d0575` 的状态目录，现在就有；被人删掉的话，并行版每轮退出 73，没人报。
  - 收件方（Coding助手）怎么处理 `source` 是 `lock-held-alert` 的 `heartbeat_stale`、`heartbeat_recovered`，没验证。
  - 最终版（超时 300）和回滚版没套 lockf，也没有 lock-held-alert。
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
- **装好的是副本**：MBA 上的 heartbeat-watch.sh、orca-via-ssh、lock-held-alert 和 iMac 上的 lock-held-alert 都是 `~/.orca-state/bin/` 里的副本，
  主检出切分支、改文件都不影响它们。反过来，main 里这几个文件改了，要另开卡片重装、比 sha。
- **ssh 半路断线**：包装加了 `ServerAliveInterval=15`、`ServerAliveCountMax=2`，MBA 这边约 30 秒退出。没演练。
- **TLA+ 模型**：`wake/tla/` 的 P3 还是按 box 建的，模型里也没有 lockf；`wake/tla/README.md` 的假设 4（Orca 不让同一个任务的预检重叠）
  和上面「两轮预检重叠」不符。这次 wake-tla 没跑：两台都没有 Java 17 和 tla2tools（iMac 只有 Java 8，MBA 没有 Java）；`check.sh` 用 `free`
  和 `/proc/loadavg`，只能在 Linux 上跑；`SOURCES.sha256` 里 stuck-check.sh、heartbeat-watch.sh 两项已经和代码对不上，要先更新模型，结果才有意义。
  模型和 `SOURCES.sha256` 留给后续 wake-tla 批次，到时要把「被跳过的那一轮没有 `@@HB`」建进去。

## 演练

```bash
wake/tests/heartbeat-watch-ssh.sh            # 在 iMac 的仓库根目录跑；要能 ssh mba，MBA 要能 ssh imac。S12、S15 要等真时间
wake/tests/heartbeat-watch-ssh-rollback.sh   # 回退测试：代码换回 base f828d452、defs 换成现网版，同一套演练整轮跑一次，看该挂的是不是挂了
```
场景、期望、实际结果和原始输出写在产物目录的 `README.md`（`HB_DRILL_OUT` 指定目录，默认 `reports/heartbeat-mba-imac-1021/`）。
回退测试的期望写在 [`FAILURE-MODES.md`](FAILURE-MODES.md) 标题带「回退测试」的几节，
结果在产物目录的 `ROLLBACK.md`。每次运行的 commit 和产物目录列在 PR 描述里。
heartbeat-watch 都用临时 `HB_STATE_DIR`；除 S12、S13 外都带 `--dry-run`。S12、S13 不带（要看写下的 state.json 和 `@@HB`），webhook 目录是空的，
PATH 里放了只记录调用的假 curl。lock-held-alert 不看 `--dry-run`：S15 里它真发告警，发给假 webhook 配置（`STUCK_FORCE_BOT=ops-system`，
`127.0.0.1:9` 的假地址），PATH 里的假 curl 记下请求体、回 200。锁文件和 lock-held-alert 的状态文件都在临时目录里，
不碰 `~/.orca-state/heartbeat-watch/` 下的真文件（S10 核对）；precheck 里的 `~/.orca-state/bin/lock-held-alert` 换成仓库里那份的临时副本。
S14 的 kill、term、crash 只给演练自己起的那个 lockf 发 SIGKILL、SIGTERM、SIGSEGV，发之前核对 pid、ppid 和命令名。
crash 每跑一次，macOS 在那台机器多写一份 lockf 的崩溃报告（`lockf-<日期>-<时间>.ips`）：iMac 上在 `~/Library/Logs/DiagnosticReports/`，
MBA 上在 `/Library/Logs/DiagnosticReports/`；两台「共享 Mac 分析」都关着，报告只留在本机，演练不删（FAILURE-MODES F36、F37）。不发叫醒，不建、不改任何自动任务。
