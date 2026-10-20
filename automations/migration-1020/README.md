# box 重活迁移（PER-79，2026-10-20）

box 每晚要跑 4 个 opus 夜审、2 个 sonnet 清理，另有 Linear 状态对齐和 vllm 上游监控，跑起来会互相挤。这里把
4 个夜审挪到 MBA，iMac 负责看守和备用，box 只做最后的兜底；Linear 状态对齐和 vllm 上游监控挪到 iMac；
留在 box 的两个清理加上「有活才放行」的预检。所有重活的 missed-run grace 从 720 改成 120 分钟，
每台机器同一时间只跑一个重活（`scripts/heavy-lock.sh`）。

本目录只有定义文件和脚本，**没有注册、改动或停掉任何线上 automation**。注册、启用、停用、删除都要 Zack 批，
按下面的「上线顺序」一步一步来。

## 文件

| 文件 | 内容 |
|---|---|
| `defs.json` | 要新建的 23 个 automation（MBA 9、iMac 10、box 4）和要改的 9 个 box 旧任务 |
| `register.sh mba\|imac\|box [--apply]` | 把 defs.json 变成 `orca automations create/edit` 命令。默认只打印（dry-run），不调用 orca；每条 create 都带 `--disabled` 和 `--missed-run-grace-minutes 120`。`--apply` 只能在对应机器上跑，需要 Zack 先批 |
| `make-prompts.py [--check\|--diff]` | 从 `box-baseline/` 里 box 线上提示词原文生成 `prompts/`（逐条替换，每条替换的次数写死，原文变了就报错）；`--check` 只检查提交的文件和生成结果是否一致 |
| `box-baseline/` | 2026-10-20 从 box 只读拉的线上提示词和设置（只有变量名，没有密钥） |
| `prompts/mba/`、`prompts/imac/` | MBA 主跑版、iMac 接替版夜审提示词，iMac 的 Linear 对齐和 vllm 上游监控；`prompts/noop.prompt.md` 给只靠预检干活的看守任务 |
| `make-prompts.py --diff` | 打印生成的提示词和 box 原文的差异（逐句），审阅用；不提交 |
| `e2e/FAILURE-MODES.md` | 先写的失败方式清单和场景编号 |
| `e2e/run-e2e.sh post\|pre\|both`、`e2e/mock_webhook.py` | 演练脚本和假 webhook |

用到的脚本（仓库 `scripts/`）：`heavy-lock.sh`、`review-date.sh`、`sync-manifests-from-box.sh`、
`night-review-gate.sh`、`cleanup-precheck.sh`，改了 `box-cleanup.sh`（加 `--count`）和
`everos-ingest/nightly_addflush.py`（加 `--skip-existing`）。

## 新的排班（SGT）

| 夜审 | box 旧任务（现在） | MBA 主跑 | MBA 补跑 | iMac 看守 | iMac 备用 | box 看守 |
|---|---|---|---|---|---|---|
| 心月 · 18 | 75b324a4 23:30 | 23:40 | 每 10 分钟（:05 :15 …），只在 23:40–00:05 动 | 00:10 | 每 10 分钟，00:10–03:40 动 | 02:10 |
| dv运维 · 20 官网 | 43c55a22 00:10 | 00:30 | 00:30–00:55 | 01:00 | 01:00–04:30 | 03:00 |
| dv广告 · 21 | 9b5c20e7 00:10 | 00:55 | 00:55–01:20 | 01:25 | 01:25–04:55 | 03:25 |
| vllm · 22 | c392a743 00:30 | 01:20 | 01:20–01:45 | 01:50 | 01:50–05:20 | 03:50 |

另外：MBA 21:40「ops · 夜审防睡 MBA」（预检起 `caffeinate -i -t 15000` 到 01:50，然后退出 1，不起模型）；
iMac 08:47「ops · 12 Linear 状态对齐 iMac」（原 bc9ee42b）；iMac `17 */3`「vllm · 17 上游 PR 监控 iMac」（原 349967f6）；
box 心月兜底 27383c07 从 00:30 改到 01:00；box 两个清理 1191c819 / 8c40fa83 加预检 `cleanup-precheck.sh ws|mem`。
夜审都是 `--model opus --effort high`，看守和防睡是 `--model sonnet --effort low`（它们的预检总是退出 1，模型不会起）。

## 一晚怎么走（`night-review-gate.sh`）

1. **MBA 主跑 / 补跑**（`primary`）：box 上已有「状态：完成」的摘要 → 跳过。当晚已经 started（3 小时内）→ 跳过，不改状态。
   不在 MBA 时间到 +25 分钟之间 → 跳过。先记 `state=checking`；用电池，或合盖且没有 SleepDisabled、没有外接显示器
   → 记 `missed reason=asleep`。然后同步清单（`sync-manifests-from-box.sh`，失败写进 SYNC-STATUS，夜审按「清单缺失」报警），
   再拿 heavy-lock（被别的任务占着 → `missed reason=lock_busy`），起一个带 `-t` 的 caffeinate，记 `started`，放行。
2. **夜审本身**：提示词第一行写运行环境；`caffeinate -dimsu -w $PPID`；每步之间 `heavy-lock.sh refresh`；
   最后一步 `notify-run --bot ops-system -- night-review-gate.sh finish ...`：要求摘要里有「状态：完成」，把摘要、台账、
   日志用 tar over ssh 拷回 box 的 `~/xinyue-deploy/nightly-review/`（box 没有 rsync），记 done，放锁，叫醒 ops-system，
   task 里写 `machine=<mba|imac> reason=<…>`。
3. **iMac 看守**（MBA 时间 +30，`watch`）：ssh 到 MBA 读当晚状态。done → 不管；在跑（started / checking，不到 60 分钟）→ 不管；
   否则在 iMac 写接替标记，原因是 `offline`（ssh 连不上）、`asleep`（连得上但当晚没状态，或记了 asleep）、`lock_busy`、
   `stalled`（started 超过 60 分钟还没 done）、`rsync_failed`（MBA 记了 done 但 box 上没有完成摘要）。
4. **iMac 备用**（`backup`，MBA 时间 +30 到 +240）：有接替标记、box 上没完成 → 同步清单（`imac` 那份读本地），拿 iMac 的锁放行，
   跑 `prompts/imac/` 的接替版（写 EverOS 前去重：`--skip-existing`；官网的 `dv_addflush.py` 没有这个开关，按提示词先读回）。
   iMac 的锁在接替后 60 分钟还拿不到 → 给 ops-system 发一条 `status=stuck machine=box reason=lock_busy`，只发一次。
5. **box 看守**（MBA 时间 +150，`box-watch`）：box 上还没完成摘要，而 iMac 也没有 2 小时内的 started → 给 ops-system 发一条
   `status=stuck machine=box reason=imac_missed`，只发一次。ops-system 收到后手动跑 box 上停用的旧任务（`orca automations run <id>`，
   这一步本身要 Zack 同意）。

所有叫醒只发 ops-system（`~/.config/grokbot/webhooks/ops-system.env`，按路径读，KEY 只经 stdin 给 curl），不发 Coding助手。
状态文件：`~/.orca-state/night-review/<项目>/<D>.status`（每行 key=value，最后一行为准）、iMac 上的 `<D>.takeover`。

## 上线顺序（每一步都要 Zack 批；一步过了第一次真实运行再走下一步）

0. 合并到 main 后：MBA、iMac 的 `~/orca/workspaces/ops` 和 box 的 `/workspace/repos/ops` 各自 `git pull`。
1. **grace 和锁**：在 box 上 `bash automations/migration-1020/register.sh box` 看打印的 edit 命令，批了以后 `--apply`
   （或逐条手动跑）。这一步把 8 个旧任务的 grace 改成 120，给两个清理加预检，兜底改 01:00，并新建 4 个 box 看守（停用状态）。
2. **box 清理预检**：先在 box 上跑一次 `bash scripts/box-cleanup.sh --count` 和 `bash scripts/cleanup-precheck.sh ws`
   看输出（ws 第一次会放行并拿锁、记 due，跑完要 `heavy-lock.sh release orca-ws-cleanup`）；之后两个清理照常定时。
3. **iMac 两个任务**：先把 box 的 `~/.orca-state/vllm-upstream/`（seen.sha 和最新的 report-*.md）只读拷到 iMac
   （iMac 上那份停在 10-14），然后在 iMac 上 `register.sh imac`，只启用「Linear 状态对齐 iMac」和「上游 PR 监控 iMac」；
   第一次真实运行通过后停用 box 的 bc9ee42b、349967f6。
4. **MBA vllm** → 5. **广告** → 6. **官网** → 7. **心月**：每个项目一起启用 MBA 主跑、MBA 补跑、iMac 看守、iMac 备用、box 看守 5 个任务；
   第一次真实运行通过后停用 box 的旧夜审。MBA 防睡任务在第 4 步一起启用。
8. **兜底时间**：27383c07 改 01:00（第 1 步已经打印了这条命令；如果第 1 步没一起跑，就在第 7 步之后跑）。

旧任务：第一次真实运行通过后停用，替代任务连续 5 次成功后，Zack 批了再删。

## 第一次真实运行要留的证据

每个启用的任务第二天早上看一次，记到 PR 评论或 Linear PER-79：

- `orca automations runs <新任务 id>` 的那一次运行：skipped / started、预检输出。
- MBA：`~/.orca-state/night-review/<项目>/<D>.status` 全文；`~/everos-ingest/<项目>/<D>/SYNC-STATUS`；
  `~/.orca-state/heavy.lock.log` 当晚的 acquire / release。
- box：`~/xinyue-deploy/nightly-review/<D>-<项目>.md` 有「状态：完成」，台账在；兜底 27383c07 当晚没报警（心月）。
- ops-system 收到的那条叫醒：task 里的 `machine=` 和 `reason=`。
- EverOS：摘要里的写入计数和读回结果（接替运行时 ALREADY 的数量）。
- 清理：`cleanup-precheck` 的输出（候选数、新候选数），没活的夜里应是 skipped。

## 回滚（逐个任务，不影响别的）

| 任务 | 回滚 |
|---|---|
| 某个夜审（MBA 主跑 / 补跑 / iMac 看守 / iMac 备用 / box 看守） | 在 MBA、iMac、box 上把这个项目的 5 个新任务 `orca automations edit <id> --disabled`；box 上旧任务 `orca automations edit <旧 id> --enabled`（grace 120 保留，或 `--missed-run-grace-minutes 720` 改回原值）。旧提示词没改过，原样还在 box 上 |
| MBA 防睡 | 停用这个任务；已经起的 caffeinate 到 01:50 自己退出 |
| Linear 状态对齐 / vllm 上游监控 | 停用 iMac 上的新任务，启用 box 的 bc9ee42b / 349967f6；vllm 上游监控回滚前把 iMac 的 `~/.orca-state/vllm-upstream/seen.sha` 拷回 box，免得重复汇报 |
| 两个清理的预检 | 清掉 1191c819 / 8c40fa83 的预检，回到每晚都跑。`orca automations edit --help` 没写清空预检的写法（`--extra-agent-args=` 是空值清空，`--precheck` 没说），回滚前先在一个停用的测试任务上试 `--precheck ''`；不行就把预检改成 `true` |
| grace 120 | `orca automations edit <id> --missed-run-grace-minutes 720` |
| 兜底时间 | `orca automations edit 27383c07 --trigger '30 0 * * *'` |
| 脚本 | 回退合并 commit；没启用新任务时这些脚本不会被调用 |

## 待 Zack 卡（没有执行，需要 Zack 决定或动手）

- **定时唤醒**：`sudo pmset repeat wakeorpoweron MTWRFSU 21:35:00`（MBA 睡着时 21:35 自动醒）。要 sudo，没跑。
- **接电源时不睡**：`sudo pmset -c sleep 0`，或系统设置 → 电池 → 选项 →「接电源且显示器关闭时防止自动睡眠」。
  现在 `pmset -g` 里已经有 `SleepDisabled 1`，是谁、什么时候设的不知道；如果它是临时的（比如别的工具设的），合盖时 MBA 会睡，
  主预检会记 asleep，交给 iMac。
- **使用习惯**：夜里 MBA 接着电源；合盖可以，但要接电源。用电池时主预检一律算错过。
- **启用顺序和每一步的批准**：见上面的「上线顺序」。
- **box 看守叫醒之后的手动运行**：`orca automations run <box 旧任务 id>` 要不要授权 ops-system 直接跑。

## 和任务书不一样的地方

- **同步用 tar，不用 rsync**：box 没有 rsync（2026-10-20 查过）。MBA 到 box 走 DERP 中转只有约 80–100 KB/s，所以另一台 Mac
  的 transcript 从那台 Mac 直接拉（局域网），自己那份读本地，只有 box 自己的会话和对方没有的才从 box 拉。
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
  摘要拷回 box 时后完成的那份覆盖前一份。
- **官网的去重**：`dv_addflush.py`（deepvision-site 仓库）没有 `--skip-existing`，没改那个仓库，接替版提示词要求先按 session 读回。

## 演练

```
/bin/bash automations/migration-1020/e2e/run-e2e.sh both
```

先跑 `pre`（origin/main + box 原提示词，每项都应 FAIL），再跑 `post`（本分支，每项都应 PASS），输出 `revert.tsv`。
产物默认在 `~/.orca-state/e2e/migration-1020/<时间>/`。演练用了假 webhook、本地目录代替 box 的摘要目录、文件代替 pmset/ioreg 输出、
2099 年的日期，所以它是 dry-run 演练，不是线上 E2E；真机部分是 MBA 和 iMac 上的 /bin/bash 3.2、iMac 经 ssh 读 MBA、
box 只读拉清单和快照、EverOS 只读查重。具体见 `e2e/FAILURE-MODES.md` 的「演练本身可能骗人的地方」。
