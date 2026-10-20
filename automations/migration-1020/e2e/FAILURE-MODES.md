# box 重活迁移（PER-79）：失败方式清单（先写清单，再写代码）

写于 2026-10-20，写任何脚本之前。依据：.orca-task/MIGRATION-BRIEF.md、box 上线上 automation 的只读快照
（`orca automations list --json`，2026-10-20 18:0x SGT）、MBA / iMac 的只读检查。时间都是 SGT。

每一条对应 `run-e2e.sh` 里的一个场景。「修前」= base（origin/main）上的仓库 + box 线上提示词原文
（`box-baseline/`）；「修后」= 本分支。每条新断言在修前至少要挂一次（回退测试），修前修后各跑一轮全量，
原始输出都保留，不挑重跑。

## 动手前查到的、会影响设计的事实

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F1 | MBA 和 iMac 都是 `/bin/bash` 3.2.57，BSD date 不认 `-d`；iMac 没装 gdate | `bash --version`、`which gdate` | 日期一律用 python 算（`scripts/review-date.sh`），不依赖 gdate |
| F2 | MBA 上 `~/orca/workspaces/<repo>` 只是工作树的父目录，不是仓库；主仓库在 `~/orca/projects/<repo>`（ops 例外，在 `~/orca/workspaces/ops`）。iMac 又是另一套（`~/claude/site`、`~/pi/remote/xinyue-site` …） | `orca worktree list --json` 的 isMainWorktree | 任务书里「`/workspace/repos/<repo>` 改成 `~/orca/workspaces/<repo>`」在 MBA 上会指到非仓库目录；按机器分别写仓库路径 |
| F3 | box 清单里 box 本机会话的 `transcript_path` 指向 box 的 `/home/box/.claude/projects/...`，不在 `/var/lib/everos-ingest` 下 | 读 2026-10-19 四个项目的 sessions-*.jsonl | 只 rsync 清单目录不够：同步脚本要把这些 transcript 一起拉下来，并把本地副本里的路径改成本机路径 |
| F4 | `nightly_addflush.py` 不查会话是否已写过，重跑会再写一遍（`dv_ads_lessons.py` 有 ALREADY，它没有） | 读代码 | 接替时会重复写 EverOS；加 `--skip-existing`，接替版提示词必须带 |
| F5 | MBA 现在合着盖（AppleClamshellState=Yes）、接电源、`SleepDisabled 1`、Amphetamine 在跑，机器是醒的 | `ioreg`、`pmset -g`、`pmset -g assertions` | 照任务书字面「合盖就算错过」，MBA 每晚都会跳过。改成：用电池算错过；合盖只在没有 SleepDisabled、也没有外接显示器时算错过 |
| F6 | notify-run 没有「退出钩子」，只在命令结束时 POST 一次 | 读 wake/bin/notify-run | 锁的释放放进夜审最后一步，用 notify-run 包住：`notify-run ... -- night-review-gate.sh finish ...`（释放锁 + rsync + 叫醒是同一步）；agent 中途死掉靠 40 分钟作废 |
| F7 | 心月兜底 27383c07 同时查摘要的「状态：完成」和台账 `${D}-xinyue-ledger.jsonl` | 读 night-review-guard-xinyue.sh | rsync 回 box 时台账也要带上 |
| F8 | box 上 1191c819、8c40fa83 现在没有预检（precheck=null），每晚都起 sonnet | automation 快照 | 加预检后才会「没活就不起模型」 |
| F9 | box 上 35 个 completed 工作区一直没被归档（有未推送改动等原因被跳过） | `orca worktree list --json` | 只按「有 completed 工作区」判断，预检每晚都会放行。要按「比上次成功运行多出新的候选」判断，并且每 7 天至少放行一次 |

## A. 要防的失败方式（修前应挂，修后应过）

| # | 失败方式 | 场景 | 修后期望 |
|---|---|---|---|
| A1 | 两个重活同时起（锁被占时照样起） | L1 | 第二个 acquire 退出 1，status 显示持有者 |
| A2 | 两个预检同时 acquire，两个都拿到 | L2 | 8 个并发 acquire，恰好 1 个退出 0 |
| A3 | agent 死了锁永远不放，之后的夜审全被跳过 | L3 | 超过 40 分钟的锁被新的 acquire 收回；39 分钟时不收回 |
| A4 | 别的任务把正在用的锁放掉 | L4 | 名字不对的 release 退出 1，锁还在；本人 release 后锁空 |
| A5 | 夜审跑超过 40 分钟，锁被当成作废收走 | L5 | refresh 之后重新计时 |
| A6 | macOS 上 `date -d` 报错，D 为空或算错天 | D1、D2 | bash 3.2 下 review-date.sh 各时刻、跨月、跨年、闰年都对；MBA / iMac 提示词里没有 `date -d`；修前提示词的日期命令在本机实跑会失败 |
| A7 | 清单拉不到却静默继续（等于审了一个空日子） | M2 | 主机连不上、目录不存在都退出非 0，并写 SYNC-STATUS=failed |
| A8 | 同步把 box 或本地的文件删了 | M1、M3 | 本地多余文件保留；box 上源文件的 sha256 同步前后一致 |
| A9 | 同步后清单里的 transcript_path 还指着 box 路径，写入时全成 FAIL | M1 | 本地清单里每个非空 transcript_path 都是本机可读文件 |
| A10 | 清理任务没活也起模型 | C1 | 真 box 快照：首轮放行；上轮成功后快照没变就退出 1，不记 due、不拿锁；多一个新 completed 工作区就放行；空快照退出 1 |
| A11 | 预检放行前不拿锁，box 同时起 2 个清理 | C1 | 放行时拿到 box 的重活锁；锁被占时退出 1 |
| A12 | MBA 离线时没人接替 | W1 | 看守写接替标记 reason=offline；iMac 备用拿 iMac 锁放行；收尾叫醒 ops-system，task 里有 machine=imac reason=offline |
| A13 | MBA 睡着（用电池 / 合盖且会睡）还照常起，跑到一半睡过去 | W2 | 主预检退出 1，状态 missed reason=asleep；看守判 asleep |
| A14 | MBA 锁被占的那晚没人补 | W3 | 主预检记 lock_busy；看守判 lock_busy 并交给 iMac |
| A15 | iMac 也不行时没人知道，或者报给了 Coding助手 | W4、W7 | iMac 拿锁失败超过 60 分钟、或到 box 看守时间还没完成，给 ops-system 发一条 status=stuck（machine=box），只发一次；Coding助手 的假地址收到 0 条 |
| A16 | MBA 正常完成后 iMac 又跑一遍 | W5、W6 | box 上已有「状态：完成」的摘要时，主预检和备用预检都退出 1 |
| A17 | 接替时把同一天的会话再写一遍 EverOS | E1 | `--skip-existing` 下已有 episode 的会话 result=ALREADY、不写（真 EverOS，只读的 dry-run） |
| A18 | 合盖但接着电源、SleepDisabled=1（MBA 现在的状态）被误判成错过 | W2b | 主预检照常放行 |
| A19 | 运行中途 MBA 睡着 | K1 | 主预检起一个带 -t 的 caffeinate，会自己退出；21:40 的防睡任务起 `caffeinate -i -t 15000` 后退出 1 |
| A20 | 注册脚本误碰线上 automation | R1 | 默认 dry-run，不调用 orca（PATH 里放一个只记录调用的 orca，调用数 0），每条打印的 create 都带 `--missed-run-grace-minutes 120` 和 `--disabled` |
| A21 | 提示词漏改：还写 /workspace/repos、/var/lib/everos-ingest、box load>8、coding-assistant webhook | P1 | 生成的 MBA / iMac 提示词都不含这些；含 caffeinate、heavy-lock refresh、同步、finish、`状态：完成`；`make-prompts.py --check` 通过（提交的文件和生成结果一致） |

## B. 演练本身可能骗人的地方

| # | 风险 | 处理 |
|---|---|---|
| C1 | 叫醒用的是假 webhook，不是真 bot | 是。用 `HOME=<临时目录>` 让 notify-run 和预检读临时的 `ops-system.env` / `coding-assistant.env`，地址指向本机 `wake/tests/mock_webhook.py`。所以这份结果叫「dry-run 演练」，不叫线上 E2E |
| C2 | 「MBA 离线」「box」是替身 | 离线用一个真连不上的 ssh 主机名（ssh 真的失败）；「box 摘要目录」用本地临时目录；清单同步 M1 用真 box（只读 rsync） |
| C3 | 合盖、用电池是替身 | 是。`NR_PMSET_BATT` / `NR_PMSET_G` / `NR_IOREG` 指向文件，文件内容取自本机真实命令输出再改一行；默认不设时读真命令 |
| C4 | 锁「超过 40 分钟」是改 owner 文件里的时间戳 | 是，写明。并发场景（L2）用真进程并发 |
| C5 | 清理预检的数据不是当晚的 | 用 2026-10-20 从 box 只读拉的 `orca worktree list --json` / `orca terminal list --json` 快照；「多一个工作区」「空快照」是在快照上改出来的 |
| C6 | 断言为了修后通过而放宽 | 断言先写在本表，代码照抄；跑出来不符就记 FAIL 并保留，不改界值重跑 |
| C7 | 8c40fa83 的「有没有超阈值进程」在 MBA 上没法真测（box-cleanup.sh 读 Linux /proc，MBA 上 docker 没开） | `box-cleanup.sh --count` 没跑演练，写「没跑」；首次线上运行前在 box 上手动跑一次 `--count` 作为证据（见 README） |
