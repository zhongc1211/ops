# box 重活迁移（PER-79，2026-10-20；B2a 去掉 box，PER-146，2026-10-21）

box 每晚要跑 4 个 opus 夜审，另有 Linear 状态对齐和 vllm 上游监控，跑起来会互相挤。这里把 4 个夜审挪到 MBA，
iMac 负责看守和备用；Linear 状态对齐和 vllm 上游监控挪到 iMac。新任务都不在 box 上跑：没有 box 看守，也没有
box 兜底（B2a）。每台机器同一时间只跑一个重活（`scripts/heavy-lock.sh`），新任务的 missed-run grace 都是 120 分钟。

夜审结果的存放位置和会话清单的来源现在默认还在 box，可以用变量改（见「存放位置和清单来源」）；离不离开 box 由 Zack 定。
box 本机的任务（清理、哨兵、EverOS 采集等）不在本方案里，见「待 Zack 决定（不在本方案）」。

本目录只有定义文件和脚本，**没有注册、改动或停掉任何线上 automation**。注册、启用、停用、删除都要 Zack 批，
按下面的「上线顺序」一步一张卡。

## 文件

| 文件 | 内容 |
|---|---|
| `defs.json` | 要新建的 19 个 automation（MBA 9、iMac 10），都以停用状态创建；不改 box 上的任何任务（`edit` 为空） |
| `register.sh mba\|imac [--apply]` | 把 defs.json 变成 `orca automations create` 命令。默认只打印（dry-run），不调用 orca；每条 create 都带 `--disabled` 和 `--missed-run-grace-minutes 120`。`--apply` 只能在对应机器上跑，需要 Zack 先批。`register.sh box` 打印一句说明后退出 2 |
| `make-prompts.py [--check\|--diff]` | 从 `box-baseline/` 里 box 线上提示词原文生成 `prompts/`（逐条替换，每条替换的次数写死，原文变了就报错）；`--check` 只检查提交的文件和生成结果是否一致；`--diff` 打印生成的提示词和 box 原文的差异（逐句），审阅用 |
| `box-baseline/` | 2026-10-20 从 box 只读拉的线上提示词和设置（只有变量名，没有密钥） |
| `prompts/mba/`、`prompts/imac/` | MBA 主跑版、iMac 接替版夜审提示词，iMac 的 Linear 对齐和 vllm 上游监控；`prompts/noop.prompt.md` 给只靠预检干活的任务（iMac 看守、MBA 防睡） |
| `e2e/FAILURE-MODES.md` | 先写的失败方式清单和场景编号（PER-79 一节、B2a 一节） |
| `e2e/run-e2e.sh post\|pre\|both` | 演练脚本（见「演练」） |
| `e2e/mock_webhook.py`、`e2e/ssh-spy`、`e2e/fake-ssh.py`、`e2e/gate-equivalence.py` | 演练用：假 webhook；拒连 box 并记下每次 ssh 的 ssh；不联网、扮演默认存放主机 box 的假 ssh；新旧 `night-review-gate.sh` 逐场景对照 |

用到的脚本（仓库 `scripts/`）：`heavy-lock.sh`、`review-date.sh`、`sync-manifests-from-box.sh`、`night-review-gate.sh`，
以及 `everos-ingest/nightly_addflush.py` 的 `--skip-existing`（接替时去重）。`cleanup-precheck.sh` 和
`box-cleanup.sh --count` 还在仓库里，本方案不再用（box 清理的去留待 Zack 决定）。

## 新的排班（SGT）

| 夜审 | 替代的 box 旧任务 | MBA 主跑 | MBA 补跑 | iMac 看守 | iMac 备用 |
|---|---|---|---|---|---|
| 心月 · 18 | 75b324a4 23:30 | 23:40 | 每 10 分钟（:05 :15 …），只在 23:40–00:05 动 | 00:10 | 每 10 分钟，只在 00:10–03:40 动 |
| dv运维 · 20 官网 | 43c55a22 00:10 | 00:30 | 00:30–00:55 | 01:00 | 01:00–04:30 |
| dv广告 · 21 | 9b5c20e7 00:10 | 00:55 | 00:55–01:20 | 01:25 | 01:25–04:55 |
| vllm · 22 | c392a743 00:30 | 01:20 | 01:20–01:45 | 01:50 | 01:50–05:20 |

任务名：`<夜审> MBA`、`<夜审> MBA 补跑`、`<夜审> 看守 iMac`、`<夜审> 备用 iMac`（例如「vllm · 22 夜审 备用 iMac」）。

另外 3 个：

- MBA 21:40「ops · 夜审防睡 MBA」：预检起 `caffeinate -i -t 15000`（到 01:50），然后退出 1，不起模型。
- iMac 08:47「ops · 12 Linear 状态对齐 iMac」，替代 box 的 bc9ee42b。
- iMac `17 */3`「vllm · 17 上游 PR 监控 iMac」，替代 box 的 349967f6。

夜审都是 `--model opus --effort high`；看守和防睡是 `--model sonnet --effort low`（它们的预检总是退出 1，模型不会起）。
本方案不新建 box 任务，也不改 box 任务定义；上线卡里停用被替代的 box 旧任务，只停用不删除。box 的「心月 · 19 夜审兜底」（27383c07，00:30）怎么处理见「上线顺序」第 5 步。

## 一晚怎么走（`night-review-gate.sh`）

「存放位置」指夜审结果（摘要、台账、日志）拷去的目录：`NR_STORE_HOST:NR_STORE_DIR`，默认 `box:~/xinyue-deploy/nightly-review/`，
就是 box 旧夜审现在写的目录。「做完了」以存放位置里的摘要有「状态：完成」为准。

1. **MBA 主跑 / 补跑**（`primary`）：存放位置已有完成摘要 → 跳过。当晚已经 started（3 小时内）→ 跳过，不改状态。
   不在 MBA 时间到 +25 分钟之间 → 跳过。先记 `state=checking`；用电池，或合盖且没有 SleepDisabled、没有外接显示器
   → 记 `missed reason=asleep`。然后同步清单（`sync-manifests-from-box.sh`，失败写进 SYNC-STATUS，夜审按「清单缺失」报警），
   再拿 heavy-lock（被别的任务占着 → `missed reason=lock_busy`），起一个带 `-t` 的 caffeinate，记 `started`，放行。
2. **夜审本身**：提示词第一行写运行环境；`caffeinate -dimsu -w $PPID`；每步之间 `heavy-lock.sh refresh`；
   最后一步 `notify-run --bot ops-system -- night-review-gate.sh finish ...`：要求摘要里有「状态：完成」，把摘要、台账、
   日志拷到存放位置（远端用 tar over ssh，box 没有 rsync；存放位置是本机时直接拷），记 done，放锁，叫醒 ops-system，
   task 里写 `machine=<mba|imac> reason=<…>`。拷不过去 → 退出 4、记 `rsync_failed`、放锁，ops-system 收到 failed。
3. **iMac 看守**（MBA 时间 +30，`watch`）：存放位置已有完成摘要 → 不管。否则 ssh 到 MBA 读当晚状态：在跑（started / checking，
   不到 60 分钟）→ 不管；否则在 iMac 写接替标记，原因是 `offline`（ssh 连不上）、`asleep`（连得上但当晚没状态，或记了 asleep）、
   `lock_busy`、`stalled`（started 超过 60 分钟还没 done）、`rsync_failed`（MBA 记了 done 但存放位置没有完成摘要）。
4. **iMac 备用**（`backup`，每 10 分钟，只在 MBA 时间 +30 到 +240 之间动）：有接替标记（或这时读 MBA 判为错过）、
   存放位置没完成 → 同步清单（`imac` 那份读本地），拿 iMac 的锁放行，跑 `prompts/imac/` 的接替版（写 EverOS 前去重：
   `--skip-existing`；官网的 `dv_addflush.py` 没有这个开关，按提示词先读回）。iMac 的锁在接替后 60 分钟还拿不到 →
   给 ops-system 发一条 `status=stuck machine=imac reason=lock_busy`，只发一次；锁一空，下一次备用触发就接上，到 +240 为止。

所有叫醒只发 ops-system（`~/.config/grokbot/webhooks/ops-system.env`，按路径读，KEY 只经 stdin 给 curl），不发 Coding助手。
状态文件：`~/.orca-state/night-review/<项目>/<D>.status`（每行 key=value，最后一行为准）、iMac 上的 `<D>.takeover`。
`box-watch` 子命令还在脚本里（发的 stuck 写 `machine=imac`），没有任务用它。

**没有 box 看守以后没人管的情况**（已知，接受或另做）：

- MBA 和 iMac 都没跑成（比如 MBA 睡着、iMac 也离线）：没有任务报警。原方案由 box 看守在 MBA 时间 +150 分钟报 `imac_missed`。
  第二天早上看 ops-system 有没有收到当晚的 done。PR #75（B1，未合并）把盯 iMac ops · 01 的跨机看守挪到 MBA↔iMac，
  iMac 整机离线时那边会报，但它不看夜审。
- 存放位置在 box、box 连不上：MBA 跑完拷不过去（ops-system 收到 failed）；iMac 看守按 `rsync_failed` 接替，再跑一遍，
  也拷不过去，再报一次 failed。一晚两次 opus。
- 夜审内容本身还读 box（只读）：会话清单里 box 那份（box 的 EverOS 采集写的）、`ssh box cat` 读 status.md 和交接文档、
  `ssh box ... orca worktree ps`。Linear 状态对齐把 changes.log 同一行追加到 box（ops-system 读 box 那份）。
  box 连不上时这些步骤按各自提示词的失败处理走。提示词里审查内容的部分没改，归各项目自己的 bot。

## 存放位置和清单来源（默认不变）

| 变量 | 用在 | 默认 | 说明 |
|---|---|---|---|
| `NR_STORE_HOST` | `night-review-gate.sh` | `box` | 夜审结果拷去的主机。`local` 或本机的短主机名（`hostname -s`，不分大小写）= 本机目录，不走 ssh |
| `NR_STORE_DIR` | `night-review-gate.sh` | `~/xinyue-deploy/nightly-review` | 存放目录；`~` 在存放主机上展开 |
| `NR_BOX_HOST`、`NR_BOX_DIR` | `night-review-gate.sh` | — | 旧名字，新名字没设时照旧生效 |
| `SYNC_SRC_HOST` | `sync-manifests-from-box.sh` | `box` | 会话清单的来源主机；`local` 或本机短主机名 = 本机读，不走 ssh |
| `SYNC_SRC_ROOT` | `sync-manifests-from-box.sh` | `/var/lib/everos-ingest` | 来源主机上的绝对路径，下面是 `<项目>/<D>/` |

什么都不设时，判定和现在一样（演练 G1a、G1b 逐场景对照）。唯一有意的变化：默认存放目录现在按字面 `~/xinyue-deploy/nightly-review`
发给存放主机，到那边才展开。原来写成 `${NR_BOX_DIR:-~/xinyue-deploy/nightly-review}`，没加引号的 `~` 在 MBA / iMac 本机
就展开成 `/Users/...`，box 上没有这个目录，所以默认设置下收尾一定拷不过去（演练 N8）。

## 切换到 iMac 存放（本 PR 不启用，Zack 定了再做）

第二套配置：夜审结果和会话清单都放 iMac，box 不再在夜审的数据路径上。

前提（都没做）：

1. box 的 4 个 EverOS 会话采集挪到 iMac（或改成往 iMac 写），清单放在 iMac 的一个绝对路径下，下面记作 `<iMac 清单目录>`，
   布局和 box 的 `/var/lib/everos-ingest/<项目>/<D>/` 一样。
2. 「心月 · 19 夜审兜底」（27383c07）已经停用：它只看 box 上的心月摘要，存放位置挪走以后每晚都会误报。
3. 读 box 上 `~/xinyue-deploy/nightly-review/` 的人和任务（ops-system 等）改读 iMac。需要历史的话，先把 box 上的旧结果只读拷一份到 iMac。

步骤：

1. 另开一个 PR，把默认值改成：`NR_STORE_HOST=imac`、`NR_STORE_DIR=~/xinyue-deploy/nightly-review`（`night-review-gate.sh` 里
   `STOREH=` / `STORED=` 那一行），`SYNC_SRC_HOST=imac`、`SYNC_SRC_ROOT=<iMac 清单目录>`（`sync-manifests-from-box.sh` 里
   `H=` / `SR=` 那一行）。改默认值而不是在每个任务里设变量：夜审最后一步的 finish 在提示词里调用，读不到预检的环境变量。
2. 合并后 MBA、iMac 各自 `git pull` 主检出。iMac 上的闸门认出存放主机是自己，直接拷本地；MBA 经 ssh 拷到 iMac。
3. 第二天早上看：iMac 的 `~/xinyue-deploy/nightly-review/<D>-<项目>.md` 有「状态：完成」；MBA 的 `.status` 是 `state=done`；
   `~/everos-ingest/<项目>/<D>/SYNC-STATUS` 是 `ok`。
4. 回滚：回退那个 PR，两台 Mac `git pull`。

演练里的 W0 用这套设置走了一遍（MBA 主跑、收尾经 ssh 拷到 iMac、iMac 看守看到完成、备用不起），N9、M5b 查了「主机名是自己时不 ssh」。

## 上线顺序（一步一张 Zack 卡；上一步的第一次真实运行过了再走下一步）

每一步在当天夜审之前做完：**同一步里停用被替代的 box 旧任务、启用新任务**，第二天早上按「第一次真实运行要留的证据」看。
两边同时开会在同一晚跑两次 opus、EverOS 写两遍（box 旧提示词不去重）。下面每张卡都要 Zack 本人批。

**合并卡（本 PR）**：

- 合并本身不改现网：没有现网任务调用本 PR 改的脚本，box 上的检出也不拉。回滚是 `git revert` 合并时的那个 squash 提交。
- 卡上锁定 head sha 和 PR 正文的 updatedAt。squash 的提交信息不带 Co-Authored-By，也不带测试结果。只由 Zack 本人在卡上批，agent 不自己合并。
- 卡上写明两处方案变化：一个项目一张卡、同一步停旧启新，第一晚就没有 box 兜底，出问题第二天回滚；MBA 和 iMac 都没跑成时没有任务报警，
  这是新接受的残余（见「一晚怎么走」）。
- 合并之前 Zack 先定 #65（PER-117，vllm · 17 留在 box）关掉还是保留：它和本方案方向相反，两个都合会互相打架。

**总前提**：卡 1 在 PR #75（B1）合并、它的卡 ② 验收过（MBA 的新任务已经在盯 iMac 的 ops · 01）之后再做；卡 2 起最好在 #75 的卡 ④
（停用 box 的 94e4b0bc）之后。

**每张上线卡的做法**：

- 改之前导出到 `~/ops-archive/b2b-<项目>-<日期>/`（卡 1 的 `<项目>` 写 `card1`）：在 box 上只读跑 `orca automations show --id <旧 id> --json`，
  每个要停的旧任务一份；两台 Mac 各自的 `orca automations list --json`。卡 1、卡 2 把 `register.sh` 打印的内容也存进去。
- 按「注册（建成停用）→ 停用 box 旧任务（只停用，不删除）→ 启用新任务」的顺序一次做完，赶在新任务第一次该跑之前。
  `--apply` 只在卡 1（iMac）和卡 2（MBA）跑；卡 3–5 的任务那时已经建好，只核对它们还在、还是停用。
- 最后在 box 上只读看一次旧任务的 runs（`orca automations runs --id <旧 id> --limit 5 --json`），确认它没有按 720 分钟的补跑窗口马上补跑。
- 第二天早上按「第一次真实运行要留的证据」核对，过了才弹下一张。有失败按「回滚」做。

1. **卡 1：拉主检出，iMac 两个任务。**
   - 先拉主检出。这是现网改动：新任务的预检从两台 Mac 的主检出 `~/orca/workspaces/ops` 跑，现网任务也从这里跑脚本
     （比如 iMac 的 ops · 01 每分钟跑 `scripts/stuck-check.sh`）。MBA、iMac 各做一遍，box 上的检出不拉：
     1. 在 `main` 上（`git branch --show-current`）。
     2. `git status --porcelain --untracked-files=no`：MBA 应为空，iMac 只允许那一行已知的 ` M orca-projects.md`。有别的就停下。
     3. 记一次 `git rev-parse HEAD`。
     4. `git fetch`，把这次会一起带进来的已合并 PR 列到卡上（`git log --oneline --first-parent HEAD..origin/main`）。
        `git diff --name-only HEAD origin/main` 里不能有 `orca-projects.md`；里面有现网任务的预检或提示词用到的文件（对照导出的任务清单），
        也列到卡上。
     5. `git merge --ff-only origin/main`，再记一次 `git rev-parse HEAD`，应和 `git rev-parse origin/main` 相同。

     2026-10-22 看的时候，两台 Mac 的主检出和 origin/main 都在 `f828d452`，main 上还没有别的已合并 PR。按「总前提」，卡 1 时至少还会带进
     #75：它改 `scripts/heartbeat-watch.sh`、新加 `scripts/orca-via-ssh`，10-22 的现网任务都不从主检出调用这两个
     （iMac 的 5c2d0575 用 `~/.orca-state/bin/` 里的副本）。
   - 在 iMac 上 `bash automations/migration-1020/register.sh imac` 看打印的 10 条，批了以后 `--apply`（都以停用状态创建）。
   - 停用 box 的 bc9ee42b、349967f6。再把 box 的 `~/.orca-state/vllm-upstream/`（seen.sha 和最新的 report-*.md）只读拷到 iMac
     （iMac 上那份停在 10-14），seen.sha 里的值记到卡上。停用以后再拷，box 那条就不会在拷完之后又跑一次。
   - 启用「ops · 12 Linear 状态对齐 iMac」「vllm · 17 上游 PR 监控 iMac」。
2. **卡 2：vllm。**
   - 前置：
     - MBA、iMac 上 `ssh -o BatchMode=yes box 'test -d ~/xinyue-deploy/nightly-review'` 都通过。
     - MBA、iMac 各跑一次清单同步（box 只读），`<临时目录>/dst/vllm-omni/<昨天>/SYNC-STATUS` 应是 `ok`：
       `SYNC_DST_ROOT=<临时目录>/dst SYNC_STAGE_ROOT=<临时目录>/stage scripts/sync-manifests-from-box.sh vllm-omni <昨天> <mba|imac>`。
       脚本只往 `SYNC_DST_ROOT` 下面写。暂存目录指到空目录，本机那份 transcript 也从 box 拉，会比真跑慢。
     - MBA 接着电源。MBA 的两条 pmset（「待 Zack 卡」）还没定的话，卡上照实写。
     - 卡上写明：两台都没跑成时没有任务报警，靠每天早上人工看 ops-system 有没有收到当晚的 done。
   - 在 MBA 上 `register.sh mba` 看打印的 9 条，批了以后 `--apply`（停用状态）。停用 box 的 c392a743，
     启用 vllm · 22 的 4 个新任务（MBA 主跑、MBA 补跑、iMac 看守、iMac 备用）和「ops · 夜审防睡 MBA」。
3. **卡 3：广告。** 停用 box 的 9b5c20e7，启用 dv广告 · 21 的 4 个新任务。
4. **卡 4：官网。** 停用 box 的 43c55a22，启用 dv运维 · 20 官网的 4 个新任务。
5. **卡 5：心月。** 停用 box 的 75b324a4，启用心月 · 18 的 4 个新任务。27383c07（box 00:30 查心月摘要）由 Zack 在这张卡上定：
   - 和 75b324a4 一起停用（推荐）：MBA 23:40 开始，结果拷到 box 可能晚于 00:30，留着会误报；停了以后两台都没跑成时没人报（见上面的已知情况）。
   - 改到 01:00：这是一次 box edit，等于保留一个 box 看守，和 B2a 的方向相反。
   - 不动：接受误报。

**删旧任务和 box 下线（都另开卡）**：

- 旧任务停用后先留着，替代任务连续 5 次成功后，Zack 批了再删。删之前回滚要用 box 旧任务，box 得在。
- 存放位置和清单来源还是默认的 box 时，box 的 4 个 EverOS 会话采集不能停，box 也不能下线。要先做「切换到 iMac 存放」（另开 PR、另一张卡）。

## 第一次真实运行要留的证据

每个启用的任务第二天早上看一次，记到卡片或 Linear PER-79：

- `orca automations runs <新任务 id>` 的那一次运行：skipped / started、预检输出。
- MBA：`~/.orca-state/night-review/<项目>/<D>.status` 全文；`~/everos-ingest/<项目>/<D>/SYNC-STATUS`；
  `~/.orca-state/heavy.lock.log` 当晚的 acquire / release。iMac 看守那一行（`seen_done` / `seen_running` / `takeover`）。
- 存放位置（默认 box）：`~/xinyue-deploy/nightly-review/<D>-<项目>.md` 有「状态：完成」，台账在。
- ops-system 收到的那条叫醒：task 里的 `machine=` 和 `reason=`。
- EverOS：摘要里的写入计数和读回结果（接替运行时 ALREADY 的数量）。
- Linear 状态对齐、vllm 上游监控：iMac 上那一次的输出；vllm 上游监控没有重复汇报 box 已经报过的 PR。

## 回滚

迁移期：停用新任务，重新启用 box 旧任务。box 旧任务的提示词、时间、grace 都没改过，启用就回到迁移前。逐个项目做，不影响别的。
回滚前也按「每张上线卡的做法」导出一次。重新启用 box 旧任务以后看一次它的 runs：grace 还是 720 分钟，停用期间错过的那一次可能马上补跑；
补跑了就记到卡上，当晚新任务已经写过 EverOS 的话会写重。

| 任务 | 回滚 |
|---|---|
| 某个夜审 | 在 MBA、iMac 上把这个项目的 4 个新任务 `orca automations edit <id> --disabled`；box 上旧任务 `orca automations edit <旧 id> --enabled`。心月：第 5 步停用了 27383c07 的话一起启用 |
| MBA 防睡 | 最后一个夜审项目回滚时停用；已经起的 caffeinate 到 01:50 自己退出 |
| Linear 状态对齐 / vllm 上游监控 | 停用 iMac 上的新任务，启用 box 的 bc9ee42b / 349967f6；vllm 上游监控回滚前把 iMac 的 `~/.orca-state/vllm-upstream/seen.sha` 拷回 box，免得重复汇报 |
| 存放位置（只在做了「切换到 iMac 存放」以后） | 回退那个 PR，两台 Mac `git pull` |
| 脚本和定义 | 回退本 PR 的合并 commit；新任务没启用以前，没有任务调用这些脚本 |

## 待 Zack 决定（不在本方案）

- **box 本机任务的去留**：ops · 04–08、ops · 09/10 box（含 8c40fa83「ops · 10 内存与 CPU 日常清理 box」）、
  1191c819「ops · 11 Orca 工作区夜间清理 box」、ops · 24 box、ops · 30、4 个 box EverOS 会话采集。本方案不新建、不修改、不停用它们。
  PER-79 原来要给两个清理加「有活才放行」的预检（`cleanup-precheck.sh ws|mem`），并把 8 个 box 旧任务的 grace 从 720 改成 120；
  这些 box edit 都拿掉了，脚本还在仓库里。
- **27383c07**：见「上线顺序」第 5 步，推荐和 75b324a4 一起停用。
- **存放位置和清单来源离不离开 box**：见「切换到 iMac 存放」；前提是先挪 box 的 4 个 EverOS 采集。
- **两台都没跑成时要不要另做告警**：见「一晚怎么走」最后一段。

## 待 Zack 卡（没有执行，需要 Zack 决定或动手）

- **定时唤醒**：`sudo pmset repeat wakeorpoweron MTWRFSU 21:35:00`（MBA 睡着时 21:35 自动醒）。要 sudo，没跑。
- **接电源时不睡**：`sudo pmset -c sleep 0`，或系统设置 → 电池 → 选项 →「接电源且显示器关闭时防止自动睡眠」。
  现在 `pmset -g` 里已经有 `SleepDisabled 1`，是谁、什么时候设的不知道；如果它是临时的（比如别的工具设的），合盖时 MBA 会睡，
  主预检会记 asleep，交给 iMac。
- **使用习惯**：夜里 MBA 接着电源；合盖可以，但要接电源。用电池时主预检一律算错过。
- **启用顺序和每一步的批准**：见上面的「上线顺序」。

## 和任务书不一样的地方

- **box 不看守、不兜底（B2a）**：PER-79 原方案的 4 个 box 看守和 9 条 box edit（8 条 grace、2 个清理预检、27383c07 改 01:00）都拿掉了。
- **同一步停旧启新（B2a）**：PER-79 原来是新任务第一次真实运行过了才停 box 旧任务；没有 box 兜底以后改成同一步做，理由见「上线顺序」。
- **同步用 tar，不用 rsync**：box 没有 rsync（2026-10-20 查过）。MBA 到 box 走 DERP 中转只有约 80–100 KB/s，所以另一台 Mac
  的 transcript 从那台 Mac 直接拉（局域网），自己那份读本地，只有 box 自己的会话和对方没有的才从来源主机拉。
- **仓库路径按机器写**：MBA 的 `~/orca/workspaces/<repo>` 不是仓库（只是工作树的父目录），提示词里用 MBA、iMac 各自的主仓库路径
  （`make-prompts.py` 里有表）。
- **合盖规则**：任务书写「合盖算错过」。MBA 现在是合盖、接电源、SleepDisabled 1、醒着，照字面每晚都会跳过。改成：用电池算错过；
  合盖只在没有 SleepDisabled、也没有外接显示器时算错过。
- **同步在拿锁之前**：同步是网络活，预检超时被杀时不会留下一把锁。
- **失败告警发 ops-system**：box 原提示词的失败告警发 Coding助手，迁过来以后一律发 ops-system，note 里写机器。
- **MBA 补跑**：任务书写「*/10 补跑，只在还没成功时」。做成每个项目一个补跑任务，分钟错开主任务（:05 :15 …），只在 MBA 时间到
  +25 分钟之间动，当晚已经 started 就不动；+30 以后交给 iMac。
- **ssh 重试一次**：iMac ↔ box 第一次 ssh 在冷的 DERP 路径上会超时（10-20 18:42 两个方向都遇到），同步和闸门脚本在 255 时重试一次。
- **MBA 跑了超过 60 分钟还没完**：iMac 看守按 stalled 接手，可能和 MBA 同时跑。EverOS 侧靠 `--skip-existing` / 读回去重，
  摘要拷到存放位置时后完成的那份覆盖前一份。
- **官网的去重**：`dv_addflush.py`（deepvision-site 仓库）没有 `--skip-existing`，没改那个仓库，接替版提示词要求先按 session 读回。

## 演练

```
/bin/bash automations/migration-1020/e2e/run-e2e.sh both
```

在 iMac 上跑，MBA 经 ssh 驱动（脚本和假环境拷到 MBA 的 `/tmp/b2a-e2e-*`，跑完删掉）。先跑 `pre`（本分支的 base，`git archive`），
再跑 `post`（本分支），输出 `revert.tsv` 和 `SUMMARY.md`：新加的检查（N*、W0、M5a、M5b）应 post 过、pre 挂；PER-79 留下的
检查两边都过；G1a / G1b（新旧闸门对照）只在 post 跑。产物默认在 `~/.orca-state/e2e/migration-1020-nobox/<时间>/`。

真实的部分：MBA、iMac 上的 /bin/bash 3.2 和这些脚本，iMac ↔ MBA 的 ssh，两台机器上的 notify-run。不真实的部分，所以它是
dry-run 演练，不是线上 E2E：webhook 是 127.0.0.1 上的 `mock_webhook.py`（假 HOME、假 env 文件、假 KEY），存放位置是本机目录
或 iMac 目录，日期是 2099-01-xx、时刻固定（`NR_D`、`NR_NOW`），pmset / ioreg 输出来自文件，`orca` 是只记录的假命令。
box 一次也不连：闸门和同步找到的 ssh 是 `ssh-spy`（拒连 box，记下每次调用）；需要默认存放主机 box 的检查用 `fake-ssh.py`，它不联网。
具体见 `e2e/FAILURE-MODES.md` 的 B2a 一节。
