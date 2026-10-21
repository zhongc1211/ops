# box 重活迁移（PER-79）：失败方式清单（先写清单，再写代码）

写于 2026-10-20，写任何脚本之前。依据：.orca-task/MIGRATION-BRIEF.md、box 上线上 automation 的只读快照
（`orca automations list --json`，2026-10-20 18:0x SGT）、MBA / iMac 的只读检查。时间都是 SGT。

每一条对应 `run-e2e.sh` 里的一个场景。「修前」= base（origin/main）上的仓库 + box 线上提示词原文
（`box-baseline/`）；「修后」= 本分支。每条新断言在修前至少要挂一次（回退测试），修前修后各跑一轮全量，
原始输出都保留，不挑重跑。

> 2026-10-21 B2a（PER-146，box 不再出现在新任务的执行路径上）的清单在文末「B2a」一节，现在的 `run-e2e.sh` 按那一节跑。
> B2a 去掉了下面靠 box 的场景：M1a、M1b、M3a、M3b、M1i、C1a–C1e、C2a、C2b、E1。

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
| C1 | 叫醒用的是假 webhook，不是真 bot | 是。用 `HOME=<临时目录>` 让 notify-run 和预检读临时的 `ops-system.env` / `coding-assistant.env`，地址指向本机的 `e2e/mock_webhook.py`（MBA 和 iMac 各起一个，只听 127.0.0.1，900 秒后自己退出）。所以这份结果叫「dry-run 演练」，不叫线上 E2E |
| C2 | 「MBA 离线」「box」是替身 | 离线用一个真连不上的 ssh 主机名（ssh 真的失败）；「box 摘要目录」用本地临时目录；清单同步 M1 用真 box（只读；box 没有 rsync，实际用 tar over ssh，见下面 F10） |
| C3 | 合盖、用电池是替身 | 是。`NR_PMSET_BATT` / `NR_PMSET_G` / `NR_IOREG` 指向文件，文件内容取自本机真实命令输出再改一行；默认不设时读真命令 |
| C4 | 锁「超过 40 分钟」是改 owner 文件里的时间戳 | 是，写明。并发场景（L2）用真进程并发 |
| C5 | 清理预检的数据不是当晚的 | 用 2026-10-20 从 box 只读拉的 `orca worktree list --json` / `orca terminal list --json` 快照；「多一个工作区」「空快照」是在快照上改出来的 |
| C6 | 断言为了修后通过而放宽 | 断言先写在本表，代码照抄；跑出来不符就记 FAIL 并保留，不改界值重跑 |
| C7 | 8c40fa83 的「有没有超阈值进程」在 MBA 上没法真测（box-cleanup.sh 读 Linux /proc，MBA 上 docker 没开） | 写代码时改了做法：C2b 把本分支的 `box-cleanup.sh` 经 stdin 喂给 box 上的 `bash -s -- --count`（不落盘，`--count` 在发信号之前就退出），只在修后跑；修前不跑，因为 origin/main 的版本不认 `--count`，会照常清理。`--count` 大于 0 时真的放行这条路没在 box 上跑到（当时是 0），用 `CLEANUP_COUNT` 演练（C2a） |

## 写代码时新发现的（2026-10-20 18:30–19:10；和对应代码一起写的，不是在代码之前，上面 F3、F6、F7 里的「rsync」按 F10 实际是 tar）

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F10 | box 没有 rsync；MBA 到 box 走 DERP 中转，约 80–100 KB/s（deepvision-site 10-19 的 mba/ imac/ 有 199 MB），MBA 到 iMac 局域网直连约 630 KB/s；两台 Mac 的采集器在 `~/.orca-state/everos-ingest/<p>/<D>/<side>/` 留着同样的文件（iMac 那份和 box 上 imac/ 的 sha256 一致） | `ssh box command -v rsync`、计时拷贝、sha256 比对 | 同步改用 tar over ssh；自己那份读本地，另一台 Mac 的从它那里直接拉，只有 box 自己的会话和对方没有的才从 box 拉 |
| F11 | iMac → box、box → iMac 第一次 ssh 在冷的 DERP 路径上会超时，`tailscale ping` 之后再连就通 | 18:42 两个方向都超时，第二次都通 | 同步和闸门脚本里 ssh 返回 255 时等 5 秒重试一次 |
| F12 | MBA 主任务和 */10 补跑任务可能同一分钟触发，iMac 备用 */10 也可能在 MBA 开跑之前就触发 | 排时间表时 | 见 A22–A24 |

| # | 失败方式 | 场景 | 修后期望 |
|---|---|---|---|
| A22 | 补跑和主任务撞车：后到的那个拿不到锁，把当晚记成 lock_busy，看守据此让 iMac 再跑一遍 | W8a | 当晚已 started（3 小时内）时主预检退出 1，不改状态；补跑分钟错开（5,15,…）；锁是自己这晚的名字时也不记 lock_busy |
| A23 | MBA 晚了很久才醒，补跑在 iMac 已接手之后又跑一遍 | W8c | 补跑只在 MBA 时间到 +25 分钟之间起 |
| A24 | iMac 备用在 MBA 还没开跑（或还在同步清单）时把当晚当成错过 | W8b、W8d、W2d | 备用只在 MBA 时间 +30 到 +240 分钟之间动；主预检一开始就记 state=checking，看守把它当「在跑」；MBA 能连上但没有状态才算 asleep |
| A25 | box 看守在 iMac 接替正在跑时把 box 旧任务叫起来，同一晚跑三遍 | W7a | iMac 记的 started 不到 2 小时就不发 |
| A26 | 收尾失败被当成完成：摘要没写「状态：完成」或拷不回 box 时照样记 done、锁不放 | F1、F2 | 分别退出 3 / 4，记 failed，锁放掉 |
| A27 | 提示词里算 D 的命令在 macOS 上实跑不出日期 | D3a、D3b | MBA 和 iMac 上实跑 4 个夜审提示词的 `D=$(...)`，都得到 YYYY-MM-DD |
| A28 | iMac 跑不了同步（box 只读拉取、对等 Mac 拉取） | M1i | iMac 上的副本实跑同步成功 |

## 场景编号和 run-e2e.sh 里的检查

A1 L1 · A2 L2 · A3 L3a L3b · A4 L4a L4b · A5 L5 · A6 D1a–D1d D2 · A7 M2a M2b · A8 M3a M3b · A9 M1a M1b ·
A10 C1a–C1d C2a C2b · A11 C1a C1e · A12 W1a–W1c · A13 W2a–W2d · A14 W3a W3b · A15 W4 W7b W7c · A16 W5 W6 ·
A17 E1 P1d · A18 W2e · A19 K1a–K1c · A20 R1a–R1c · A21 P1a–P1c · A22 W8a · A23 W8c · A24 W8b W8d W2d ·
A25 W7a · A26 F1 F2 · A27 D3a D3b · A28 M1i · 另有 S1（主预检先同步再拿锁，F6 的推论）。

## B2a（PER-146）：box 不再出现在新任务的执行路径上

写于 2026-10-21，改任何代码之前。依据：.orca-task/BRIEF.md（B2a）、main f828d452 上的本目录、`box-baseline/`、
iMac 和 MBA 上的只读检查。本批不连 box：演练在 iMac 上跑，MBA 经 ssh。

「修前」= 本分支的 base（`git merge-base HEAD origin/main`，`git archive` 出来，不检出）；「修后」= 本分支。
新加的检查（N*、W0、M5a、M5b）修前必须挂；保留的检查（PER-79 里不靠 box 的）修前修后都应过；
G1a、G1b 比的就是修前和修后，只在修后跑。

### 动手前查到的事实

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| G1 | `night-review-gate.sh` 第 48 行 `BOXD=${NR_BOX_DIR:-~/xinyue-deploy/nightly-review}` 里的 `~` 在本机展开，得到 `/Users/jiawenwang/xinyue-deploy/nightly-review`，发给 box 的命令里就是这个路径；box 的家目录是 `/home/box`（上面 F3） | /bin/bash 3.2 实测 | 不设变量时（defs 里的任务都不设），MBA、iMac 查不到 box 上的完成摘要，收尾往 box 拷会失败（退出 4），iMac 看守随后按 asleep 接手重跑。PER-79 演练一直设着 NR_BOX_DIR，没跑到默认值。新的默认值写成字面 `"~/…"`，到存放主机上再展开 |
| G2 | MBA 和 iMac 的 HOME 都是 `/Users/jiawenwang`；`hostname -s` 分别是 `mba`、`iMac` | `ssh mba`、本机 | 第 66 行 `NR_MBA_STATE` 的同样写法因为两台家目录相同，碰巧能用，本批不改。判断「存放主机就是本机」用 `hostname -s` 转小写 |
| G3 | iMac 上 `ssh imac` 连不上自己（host key 校验失败；BatchMode 下不写 known_hosts） | 实测 | 存放主机或清单源主机是本机时必须走本地。「全放 iMac」那套配置在 iMac 上靠这一条才能用 |
| G4 | 两台 Mac 的 `/opt/homebrew/bin`、`/usr/local/bin` 里都没有 ssh、curl、grep、sed、tar | `ls` | 闸门脚本把这两个目录插到 PATH 最前面，演练放在 PATH 里的记录用 ssh 不会被绕过 |
| G5 | MBA 在非交互 ssh 里能 BatchMode 连上 iMac；两台机器上 `ssh -G box` 都解析到 100.64.0.6 | `ssh mba 'ssh imac hostname -s'`、`ssh -G` | 「全放 iMac」配置的 MBA → iMac 拷贝能在演练里真跑；记录用的 ssh 按名字和这个地址拒绝 box |
| G6 | box 旧夜审把摘要、台账写在 box 的 `~/xinyue-deploy/nightly-review/`，文件名和新任务收尾拷过去的一样（默认存放位置就是这个目录）；box 旧的官网、广告、vllm 提示词不写「状态：完成」，只有心月的写 | 读 `box-baseline/` | 新旧任务同一晚都开着时会互相覆盖文件，新闸门也认不出旧任务的完成（心月除外）。上线和回滚的每一步都把「停旧的」和「开新的」放在同一张卡里，不留新旧重叠的一晚 |
| G7 | box 上心月兜底 27383c07 每天 00:30 读 box 上的心月摘要和台账，告警发 Coding助手 | `box-baseline/automations.json`、`everos-ingest/night-review-guard-xinyue.sh` | 不再改 box 任务以后它还是 00:30：MBA 23:40 开跑，50 分钟内没拷到 box 就会误报；iMac 接手的夜里一定误报；存放位置挪到 iMac 后每晚误报。放进 README「待 Zack 决定」 |

### 要防的失败方式（修前应挂，修后应过；B13 是保留项）

| # | 失败方式 | 场景 | 修后期望 |
|---|---|---|---|
| B1 | defs 里还有 box 任务或 box 路径（4 个 box 看守、给 box 旧任务的改动、box 清理预检），注册时会在 box 上建任务、改任务 | N1 | `rg -n 'machine": *"box"' defs.json` 没有输出；defs 里没有 `box-watch`、`/workspace/repos/ops`；edit 为空 |
| B2 | `register.sh box` 照样打印 box 的命令，有人照着在 box 上跑 | N2 | 退出 2，stderr 一行说明，stdout 为空，不调用 orca |
| B3 | 删 box 条目时把 Mac 上的条目删错、改错（名字、台数、grace、`--disabled`） | N3、R1b | `register.sh mba` / `imac` 打印的任务名集合各自和 defs.json 里这台的一致，合起来就是 defs.json 的全部；MBA 9 条、iMac 10 条，每条都带 `--disabled` 和 `--missed-run-grace-minutes 120` |
| B4 | 新变量不生效：设了 NR_STORE_HOST / NR_STORE_DIR，脚本还按 NR_BOX_HOST 拷、按它判断完成 | N4 | NR_BOX_HOST 指向连不上的主机、NR_STORE_HOST=local 时：收尾拷到 NR_STORE_DIR，退出 0；同一晚的备用预检按新位置看到完成，退出 1，不拿锁 |
| B5 | 默认行为变了：不设新变量时判定变了，或者拷到了别处 | G1a、G1b | 新旧 `night-review-gate.sh` 在同一组状态文件上（什么都不设；只设旧变量名）：每次调用的退出码、状态文件、接替标记、同步标记、锁、存放目录里的文件、叫醒的 status / reason / task、同步调用、ssh 的目标主机和命令种类都一样。允许的不同只有三类，逐条列出：G1 的路径写法、B8 的提示文字和 machine、屏幕输出的措辞 |
| B6 | 默认存放目录的 `~` 在本机展开（G1） | N8 | 什么都不设时，发给存放主机的 grep 和 mkdir / tar 命令里是字面 `~/xinyue-deploy/nightly-review/` |
| B7 | 存放主机就是本机时还 ssh 自己，连不上（G3），于是判成没完成、拷不过去 | N9、W0 | iMac 上 NR_STORE_HOST=imac 时收尾走本地，这一步没有 ssh；MBA 上同样的配置经 ssh 拷到 iMac，iMac 看守看到完成（seen_done），备用退出 1 |
| B8 | 卡住时的提示还让人去跑 box 上停用的旧任务 | N5、N7 | iMac 锁被占超过 60 分钟、box-watch（保留，没有任务用）发的 stuck：machine=imac，note 写按 iMac 备用接替，没有「box task」 |
| B9 | 提示词里还有 box 兜底：拷回 box、box 上 01:00 的兜底检查、Linear 连不上改用 box、noop 里的 box-watch | N6 | 生成的提示词和 noop 里都没有这些；收尾那句写存放位置（NR_STORE_HOST / NR_STORE_DIR）；`make-prompts.py --check` 通过（P1c） |
| B10 | 清单源不是 box 时同步跑不通：源是本机（`local` 或本机名） | M5a、M5b | iMac 上 SYNC_SRC_HOST=local、=imac 都同步成功，SYNC-STATUS=ok，每个 transcript_path 是本机可读文件 |
| B11 | 演练连了 box 或真 webhook | X0、X1、W7c | 两台机器上，闸门脚本 PATH 里先找到的 ssh 是记录用的那个；它的记录里没有 box（名字或 100.64.0.6），也没有被拒的调用；叫醒只到两台机器 127.0.0.1 上的假 webhook，KEY 是假的 |
| B12 | 演练杀进程，或留下常驻进程 | X2、K1c | 假 webhook 看到停止文件后自己退出，caffeinate 到时自己退出；演练脚本里没有 kill、pkill |
| B13 | 去掉 box 以后，PER-79 里不靠 box 的行为退化 | L、D、M2、M6、W、F、K、R、P | 和 PER-79 的期望一样（M6：MBA 从 iMac 上的清单同步成功）。这些是保留项，修前也应通过 |

### 演练本身可能骗人的地方

| # | 风险 | 处理 |
|---|---|---|
| H1 | 叫醒用的是假 webhook | 同上面 C1：结果叫 dry-run 演练，不叫 E2E |
| H2 | 默认存放位置（box）的真实拷贝没跑 | 不许连 box。保留项的存放位置用本地目录（NR_BOX_HOST=local，新旧都认）；默认值只在 G1a 里用不联网的假 ssh 跑，路径写法由 N8 单独查 |
| H3 | 对照用的假 ssh 按文件名找文件，不看目录 | 所以 G1a、G1b 比的是判定，不证明 box 上有那个目录；路径写法在对照报告里单列一栏 |
| H4 | 修前跑对照没有意义（新旧都是 base） | G1a、G1b 只在修后跑，修前记 SKIP，不算进回退测试 |
| H5 | box-watch 在 MBA 上代替 box 跑 | 它已经没有任务用，这里只证明子命令还能跑、提示改了 |
| H6 | 「全放 iMac」配置只在演练里设，没有启用 | 是。W0 证明这套配置在两台 Mac 之间走得通；要不要切由 Zack 定，步骤写在 README |

### 写代码时新发现的（B2a；和代码一起写的，不是在代码之前）

| # | 发现 | 改了什么 |
|---|---|---|
| J1 | PER-79 的 K1a 用 `ps -o command=` 看 `-t`；任务书只许 `pgrep -l` 或 `ps -o pid,ppid,rss,etime,comm` | K1a 只看进程名；`-t` 由 K1c 证明（caffeinate 到时自己退出） |
| J2 | N4、N9、W0 只设新变量时，修前的脚本不认它们，会按默认值去连 box | 这三项同时设 `NR_BOX_HOST=nosuchhost.invalid`：修前连不上、直接挂，碰不到 box；修后新变量优先，不受影响。每项跑完放掉两台机器的锁，修前的失败不带进后面的保留项 |
| J3 | M2b 原来用 box 上没有的日期 | 改成 `SYNC_SRC_HOST=mba`（MBA 上没有 `/var/lib/everos-ingest`），同样退出 3 |
| J4 | N8 原计划看 watch / primary 发的 grep | 改成跑 `finish`：一次调用里 mkdir / tar 和 grep 两种命令都有 |
| J5 | PER-79 演练在 MBA 上跑；B2a 要在 iMac 上本机跑看守、备用和 N9 | run-e2e.sh 重写：iMac 本机跑，MBA 从 `/tmp/b2a-e2e-*` 的副本经 ssh 跑，跑完删除 |
| J6 | X2 扫「演练文件里没有结束进程的命令」，扫描规则自己也在演练文件里 | 规则里的词拆开拼；假 webhook 说明里的同一个词换了说法 |
| J7 | W4、W7a、W7b 原来查 `machine=box`，修前修后结果会不同 | 这几项只查条数和 reason（两边都应过）；machine 和提示文字归 N5、N7 |
| J8 | 第一次试跑（未提交的工作区，2026-10-22 00:40）的回退测试抓到演练自己的两处错：N3 的检查取的是 `cat` 的退出码，修前也过；K1a 的 caffeinate 只给 5 秒，修前那次三次 ssh 往返以后它已经到时退出 | N3 改成取比对脚本的退出码；W2e 这一步给 30 秒，K1c 等它到时以后再查 |
| J9 | G1a 里新旧发给 box 的路径不同（修前是本机展开的 `/Users/…`，修后是字面 `~/…`） | 这是 B6 的有意改动：对照报告单列，不计入差异 |

### 去掉的场景

M1a、M1b、M3a、M3b、M1i（真 box 拉清单）、C1a–C1e、C2a、C2b（box 清理预检；本方案不再给 box 加预检）、
E1（读 box 拉来的清单查真 EverOS，还要读 EverOS 凭据）不再跑。对应代码在本批没有改：清单同步从 box 拉的那条路径是默认值，
`cleanup-precheck.sh`、`box-cleanup.sh`、`nightly_addflush.py` 没动。

### 编号对照

B1 N1 · B2 N2 · B3 N3 R1b · B4 N4 · B5 G1a G1b · B6 N8 · B7 N9 W0 · B8 N5 N7 · B9 N6 P1c · B10 M5a M5b ·
B11 X0 X1 W7c · B12 X2 K1c · B13 L1–L5 D1a–D1d D2 D3a D3b M2a M2b M6 W1a–W8d F1 F2 K1a K1b S1 R1a R1b P1a–P1d。
