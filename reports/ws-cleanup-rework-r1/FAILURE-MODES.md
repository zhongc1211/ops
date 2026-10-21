# ws-cleanup.sh 返工第 1 轮：失败方式清单（写代码之前写的）

派活：`.orca-task/REWORK-R1.md`。依据：独立评审 `ops-per139-review-1021/.orca-task/REVIEW.md`（F1–F6、M1–M7、L1–L9、第 6 节 E1–E13）。
第 1 轮 A1–A34 照旧保留，下面是新增的。每条都写成 `scripts/tests/ws-cleanup-test.sh` 里的用例（假 orca / 假 gh / 假 ps，加临时目录里的真 git 仓库），
所以不算 E2E；E2E 是 iMac 全量 dry-run 和 MBA 只列出。需要真 Orca 的（E13 等）只准备演练脚手架，不跑。
`--execute` 只对假 orca 跑：测试脚本先确认 `WS_ORCA` 是临时目录里的假命令，否则直接退出；脚本自己在设了 `WS_ORCA` 但文件不存在时退出码 2，不回落到真 orca。

动手前查到的事实（只读）：

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| G1 | `orca worktree rm --help`：「For Git worktrees, removal also attempts to delete the checked-out local branch … retains … any branch whose changes it cannot prove are already merged」 | `--help` | W4 判「有 ref 包含 HEAD」时，不算这个工作区自己检出的分支 |
| G2 | `orca terminal list --json` 每个终端都有 `lastOutputAt`（毫秒）；`orca worktree ps --json` 有 `agents`（state 有 done / working）、`liveTerminalCount`、`workspaceKind`（git / folder-workspace），126 行、truncated=false | 只读跑了一次 | 终端时间门槛用 lastOutputAt；W5 加上 ps 里的 agents 作为第二个来源 |
| G3 | `orca terminal close` 不带 `--tab` 只关一个窗格 | `--help` | 一律不带 `--tab` |
| G4 | iMac 的 hostname 是 `iMac`；gh 在 `/usr/local/bin/gh`，没有 `/opt/homebrew/bin/gh` | `hostname`、`ls` | gh 兜底两处都试；`--execute` 只认 hostname 精确等于 `iMac` |

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| B1 | 目录不在、git 记录的 HEAD 只在本地（detached，提交不在远端、没有别的 ref 包含）还 rm（F1 / E9） | c_gone_local | SKIP W4，原因里有提交号 |
| B2 | 目录不在、git 里已经没有这条 worktree 记录（读不到 HEAD）还 rm | c_gone_norecord | SKIP W4 |
| B3 | 目录不在、HEAD 已推送：应当可以 rm，原因要说「rm 会删 Orca 记录和 git worktree 记录」 | c_gone_pushed | RM W4，原因列含「git worktree 记录」 |
| B4 | 目录不在、HEAD 只被这个工作区自己的分支包含（rm 会顺手删分支）被当成「有 ref 包含」 | c_gone_ownbranch | SKIP W4 |
| B5 | 被忽略的 test-results/ 被 NOISE 藏起来、不备份就删（F2） | c_testresults | BACKUP_RM W13，backup 列有 test-results |
| B6 | 被忽略的 report.md（不区分大小写规则）、`*.tgz` 不备份就删 | c_report、c_tgz | BACKUP_RM W13 |
| B7 | 被忽略的目录里找到一个要备份的就整目录 `continue`，目录里其余文件漏列 | c_mixed_dir | backup 列是整个目录（scratch），不是只列 TASK.md |
| B8 | 可重建的缓存（node_modules、.next、.open-next、.cloudflare、dist、`*.tsbuildinfo`、next-env.d.ts、`__pycache__`）被当成要备份的；或者它们被删了报告里一字不提 | c_cache_only | RM W14；rebuild 列写出项数（报告里能看到会被删的东西） |
| B9 | 被忽略的东西里有嵌套 `.git`（例如 `.claude/worktrees/x/.git`）照样删 | c_nested_git | SKIP W13 |
| B10 | 被忽略的东西里有 FIFO / socket 等非普通文件，备份时卡住或报错 | c_fifo | SKIP W13（判定时就发现） |
| B11 | 仓库转移后（remote 还是旧 owner），按 owner 过滤导致分支自己的 PR 一个都对不上，open PR 被当成没有（F6） | c_moved_open | SKIP W9 |
| B12 | PR 列表只取最近 N 条，老的 open PR 掉出列表后被当成没有 | c_old_open_pr（假 gh 的 `pr list` 不带 `--head` 时只回最近 1 条） | SKIP W9 |
| B13 | linkedPR 在 fork 和上游同号，取了错的那一个 | c_linked_dup | 用 headRefName 对得上的那个（上游 OPEN）→ SKIP W9 |
| B14 | `gh pr list --head` 失败被当成「没有 PR」 | c_gh_fail（仍保留） | SKIP W9 |
| B15 | Orca 状态不是 completed（in-review / in-progress / sleep / Sleep），只靠 PR 已合并或 Linear 已关就删（M1，先保守） | c_merged_inreview、c_sleep_cap | SKIP W11，原因写「状态冲突，等 Zack 定」 |
| B16 | 工作区里有 Orca 记录的 agent（`orca worktree ps` 的 agents），但终端里看不出来 | c_ps_agent | SKIP W5 |
| B17 | 工作区还有打开的空 shell，rm 会顺手把它停掉（L6；`--execute` 默认不关终端） | c_termhost | SKIP W6 |
| B18 | 关掉有 agent 在跑的工作区里的配套 shell（F3） | t_agent_sib | SKIP T1 |
| B19 | 关掉本任务所在工作区里的其他终端 | t_self_sib | SKIP T3 |
| B20 | 关掉 folder 工作区、main 工作区、不在 worktree list 里的终端 | t_folder、t_main | SKIP T8（不在清理范围） |
| B21 | 刚开的空 shell 被关（没有时间门槛）；lastOutputAt 为空被当成很久 | t_fresh、t_nolast | SKIP T7 |
| B22 | 最后一屏不是空提示符（例如停在一段输出中间）也关 | t_midoutput | SKIP T2 |
| B23 | 计划命令里出现 `--tab` | 所有 CLOSE | 没有 `--tab` |
| B24 | 原因列带随时间变的小时数，两次 dry-run 跨整点结果不同（L2） | c_recent | 原因列没有数字 |
| B25 | 文档里的 `--dry-run` 不认、退出码 2（L1） | G8 | 退出码 0，等同默认 |
| B26 | 默认输出目录在 ops 主工作区里、没被忽略（L7） | 代码检查 | 默认在 `~/ops-archive/ws-cleanup/reports/` |
| B27 | 挂成 precheck 后正常退出 0，Orca 照旧起模型（M5） | G9 `--precheck` | 写完输出，退出码固定 1 |
| E1 | 备份过程中文件在变，sha 对不上还 rm | x_sha（后台进程一直往 .orca-task 里的文件追加） | BACKUP_FAIL，不 rm，原文件还在 |
| E2 | rm 被 Orca 拒绝后重试或加 `--force` | x_rmfail（假 orca 对它的 rm 返回 1） | result 写失败原文，只调用一次 rm，没有 `--force`，退出码 3 |
| E3 | .dev.vars 备份权限不对、内容进了输出；rm 失败后原位置的 .dev.vars 没了（L3） | x_rmfail 带 .dev.vars | 备份文件 600、目录 700；输出和 stdout 里没有假密钥；rm 失败后原文件还在 |
| E4a | 判定后出现未提交改动 | x_late（`WS_PAUSE_FILE` 等待点，期间新建文件） | 跳过，result 写「重新判定变成 SKIP W7」 |
| E4b | 判定后出现新提交（未推送） | x_late2（同上，期间 commit） | 跳过（W8） |
| E4c | 判定后 agent 起来了 | x_late3（同上，期间改 ps / terminal 数据） | 跳过（W5 或 W6） |
| E4d | 判定后 PR 打开了、Linear 重新打开了（缓存没清） | x_late4、x_late5 | 跳过（W9、W10） |
| E5 | 排在后面的工作区在循环中途起了 agent，复查用的是循环开始前的数据 | x_q1…x_q10（假 orca 在第一次 rm 后改 x_q10 的数据） | x_q10 跳过 |
| E6 | 判成可关的终端之后跑起了东西 | t_late（`--close-terminals`，等待点期间改 ps） | 不关 |
| E7 | 判成可关的终端所在 tab 之后拆出新窗格 | t_late_tab | 新窗格没被关（不用 `--tab`，只关原来那个） |
| E8 | 备份里有没有读权限的文件，抛异常让整轮中断、没有输出 | x_noperm（chmod 000）、后面还有 x_after | 这一行 ERROR，x_after 照常处理，TSV / summary / journal 都写出，退出码 3 |
| E9 | 同 B1 | — | — |
| E10 | gh 不可用（PATH 里没有 / `WS_GH` 指向不存在的文件）还 `--execute` | x_nogh | 什么都不做，退出码 5，summary 第一行写原因 |
| E11 | 两个 `--execute` 同时跑 | 锁目录里是活 pid | 第二个退出码 6，什么都不做；锁里是已死 pid 时照常运行 |
| E12 | 同一天第二次跑，备份目录已存在 | x_rmfail 第二次 | BACKUP_FAIL「备份目录已存在」，不 rm，不覆盖 |
| E13 | Orca rm 对目录已不在的工作区实际做了什么 | 需要真 Orca | 只准备演练脚手架，不跑 |
| E14 | `--execute` 不带 `--only-from` 名单，或名单外的工作区被删 | x_notlisted | 不带名单 → 退出码 2；名单外的不动 |
| E15 | 名单里是 RM、重判后备份清单变了（多了被忽略文件） | x_listchanged | 跳过，写原因 |
| E16 | 每个 rm 只在最后统一写结果，中途崩了查不到删了哪些 | journal.tsv | 每次 rm 前后各一行，rm 完立刻落盘 |
| E17 | 不是 iMac（hostname 不是精确的 `iMac`、或者只靠 `WS_HOST`）也能 `--execute` | x_host | 退出码 2 |
| E18 | 设了 `WS_ORCA` 但文件不存在，回落到真的 orca | x_badorca | 退出码 2 |
| E19 | `--execute` 默认把终端也关了 | x_* 全部 | 不带 `--close-terminals` 时假 orca 日志里没有 terminal close |

补充（Zack 10-21 03:26 定，代码开始写之后收到，所以单列）：忽略文件默认全部备份，只排除一张构建产物 / 缓存清单，清单写进脚本、可配置；dry-run 报告要列出每个工作区会备份的忽略文件。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| B28 | 可重建清单写死、改不了；或者 build/、.cache/、.venv/ 这类产物被整份备份 | c_build（build/、.cache/、.venv/）；`WS_REBUILD_DIRS=node_modules` 重跑 c_cache_only | c_build RM W14；换清单后 c_cache_only 的 dist 要备份 → BACKUP_RM |
| B29 | 报告只列被忽略的顶层条目，看不出到底会备份哪些文件 | c_mixed_dir | `backup-files.tsv` 里逐个列出 scratch/ 下的每个文件 |

补充（Zack 10-21 03:29 定，review F3 终端；也是代码开始写之后收到）：有 agent 在跑的工作区，配套的空 shell 空闲超过 12 小时可以关；agent 本身所在终端不关。关之前先存档 scrollback、cwd 和会话信息，存档路径写进报告并写清怎么找回；存档失败就不关。这条把上面 B18 的期望改了。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| B18′ | 有 agent 的工作区里，配套空 shell 空闲超过 12 小时还不关（或者 12 小时内就关） | t_agent_sib（55 小时）、t_agent_sib_fresh（6 小时） | CLOSE T4；SKIP T7 |
| B30 | agent 本身所在的终端被关 | t_agent、t_x_agent | SKIP T1 |
| B31 | 关之前没存档，或者存档不全（scrollback、cwd、终端元数据、找回说明） | t_x_close、t_x_agent_sib（`--execute --close-terminals`） | 存档目录 700、文件 600，有 scrollback.txt、meta.json（含 cwd）、README.txt；result 写存档路径 |
| B32 | 存档失败还照样关 | t_x_arcfail（假 orca 的 `terminal read` 对它返回 1） | 没关，result「存档失败」，计入失败数 |
| B33 | dry-run 报告里看不到要存档到哪 | terminals.tsv 的 archive 列 | CLOSE 行都有存档路径；summary 写怎么找回 |

补充（Zack 10-21 03:33 定，第 4 节 d；代码开始写之后收到）：Linear Done 只是前提，不是充分条件。不管工作区状态写什么，都要逐项过安全核对（未推送提交、工作区改动、忽略文件备份、agent / 终端在跑、HEAD 是否在已合并的分支或 PR 上），任何一项不过就不删。前四项已经是 W8、W7、W13、W5/W6，新加的是 W17。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| B34 | HEAD 已推送到远端分支，但没进主分支、也没有已合并的 PR，状态 completed 就删 | c_head_unmerged | SKIP W17 |
| B35 | Linear 已 Done、状态 completed，但 HEAD 不在已合并的分支 / PR 上，照样删 | c_linear_done_unmerged | SKIP W17 |
| B36 | HEAD 就是已合并 PR 的 head（没进主分支的本地 ref）被误挡 | c_head_pr_merged | RM W14，merged_via 写「PR #… 的 head」 |

补充（Zack 10-21 03:37 / 03:39 / 03:40，代码开始写之后收到）：
- 03:37：每次真删之前都实时查 Linear，不沿用 dry-run 的结果；查询失败、超时、找不到 issue 都不删。
- 03:39：W10 不改，保持严格（挂在总 issue 下、工作区已 completed 的也不放宽）。
- 03:40：R1 验收前允许在专门建的演练仓库上真跑 `--execute`，只删演练工作区；`--execute` 前硬校验每个候选都在 `--repo` 白名单下，有一个不在就整轮中止。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| L37a | 删除前 Linear 查询失败，沿用 dry-run 的「已关」照样删 | x_lin_fail（等待点期间让 YYY 这个 team 查不到） | 跳过，W10「Linear 查不到」 |
| L37b | 删除前 issue 找不到了，照样删 | x_lin_gone（等待点期间 XXX-2 从列表里消失） | 跳过，W10 |
| W40 | `--repo` 白名单外的候选混进名单，照样处理其余的 | 名单里多一行 r-proj 的 id | 退出码 2，一个都不删 |

补充（04:26 真 Orca 演练第 1 轮，在 5a280d7 上跑，`drill-r1-5a280d7/`）：演练里看到的三处，先写失败方式，再改代码。

| # | 失败方式 | 演练里看到的 | 用例 | 期望 |
|---|---|---|---|---|
| D1 | 名单里是 RM / BACKUP_RM，`--execute` 开始时已经变成 SKIP，result 列空着，看不出它为什么没删；名单里有、Orca 里已经没有的，哪里都不记 | d09、d10 在 dry-run 之后改了，execute-1 的 result 是空的；execute-2 里 d02 等已删的没有任何记录 | 同一天第二次跑（xe2）：x_late 现在是 W7，x_ok 已经删了 | x_late 的 result 写「跳过：名单里是 RM，这次判定 SKIP W7」；journal 有 x_ok 的 not-found 行 |
| D2 | `orca worktree rm --json` 失败时 result 只记了输出的最后一行（`}`） | d11-locked 的 result 是「rm 失败…：}」 | 只在真演练里测（假 orca 失败时输出的不是 JSON） | result 写 Orca 的 error.message（例如「Worktree is locked by Git」） |
| D3 | 备份失败（sha 对不上、读不了）以后，拷了一半的目录留在原处，里面还有 MANIFEST，看起来像一份备份，而且第二天再跑会被「备份目录已存在」挡住，永远备份不成 | d12-sha 留下了 MANIFEST 校验不过的目录；d13-noperm 留下了半个目录；execute-2 对两个都报「备份目录已存在」 | x_sha、x_e8a_noperm，再加同一天第二次跑 | 拷了一半的目录改名成 `<目录>.failed-<时分秒>`，原名下没有东西；第二次跑不会报「备份目录已存在」 |

补充（R2，Zack 10-21 07:34）：git 锁在 dry-run 就判 SKIP；报告和 TSV 里的邮箱打码。先写失败方式，再改代码。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| G1 | 工作区 gitdir 里有 index.lock（别的 git 命令在跑或异常退出），dry-run 照样判 RM | c_lk_index | SKIP W18，reason 以 GIT_LOCKED 开头 |
| G2 | merge 没做完（MERGE_HEAD），照样删 | c_lk_merge | SKIP W18 GIT_LOCKED |
| G3 | rebase 没做完（rebase-merge/ 或 rebase-apply/），照样删 | c_lk_rebase、c_lk_am | SKIP W18 GIT_LOCKED |
| G4 | cherry-pick 没做完（CHERRY_PICK_HEAD），照样删 | c_lk_cherry | SKIP W18 GIT_LOCKED |
| G5 | bisect 没做完（BISECT_LOG），照样删 | c_lk_bisect | SKIP W18 GIT_LOCKED |
| G6 | `git worktree lock` 过的（gitdir 里有 locked），dry-run 判 RM，到 rm 才被 Orca 拒绝，而且之前先做了一次备份（R1 演练 d11） | c_lk_wtlock | SKIP W18 GIT_LOCKED |
| G7 | 目录已不在、git 记录被 lock 了，按 W4 判 RM | c_lk_gone | SKIP W18 GIT_LOCKED |
| G8 | 锁检查只认 `<path>/.git` 是目录：linked worktree 的 `.git` 是文件，指向 main 的 `.git/worktrees/<名>`，锁在那里，查不到 | c_lk_index 等都是 linked worktree | 同上 |
| G9 | 锁判定排在 W7 后面：merge 冲突、index.lock 会先被判成 W7，统计不到 GIT_LOCKED | c_lk_merge（有冲突文件也是未提交改动） | 规则是 W18，不是 W7 |
| G10 | dry-run 之后才加锁，`--execute` 不复查照样备份再 rm | x_late_lock（等待点期间 touch index.lock） | 跳过：「重新判定变成 SKIP W18」，没有 backup、没有 rm 调用 |
| G11 | 没有锁的工作区被误判 GIT_LOCKED（例如把 main 的 index.lock 算到每个 linked worktree 头上） | 给 main 仓库造 index.lock，c_ops_common 等照常 | c_ops_common 仍是 RM W14 |
| M1 | 备注、原因等字段里的邮箱原样写进 worktrees.tsv / summary.md / journal.tsv / stdout | c_email 的 comment 写两个邮箱 | 只出现 a***@example.com 这样的形式，原邮箱一处都没有 |
| M2 | 先截断到 60 字再打码，截断后半个邮箱（admin@exam…）认不出来，原样留下（R1 实际出现过） | c_email_long：邮箱跨过第 60 个字 | 不出现原用户名 |
| M3 | 把 `pkg@1.2.3`、`node@20` 这类版本号当邮箱打码 | c_email 的 comment 里带 `pkg@1.2.3` | 原样保留 |
| M4 | 只给 comment 打码，terminals.tsv、journal.tsv、summary.md 里别处出现的邮箱漏掉 | 终端 title / worktree 名带邮箱；execute 的 journal | 所有输出文件里都没有原邮箱 |
| M5 | 文件名 `page@<hash>.webm`（Playwright 录像）被当成邮箱打码，backup-files.tsv 里的路径变了，对不上真文件；`--execute` 拿打码后的备份清单去和实时的比，永远「不一样」（R2 第一次真实 dry-run 看到 16 个） | c_testresults 里加 `test-results/page@0a1b2c3d.webm` | backup-files.tsv 原样写这个文件名 |
| M6 | 名单 TSV 是打过码的，`--execute` 用没打码的 id / 备份清单去对，有邮箱的那行永远对不上 | 只在代码里处理：对比前两边都过同一个打码 | — |

补充（R3，Zack 10-21 08:44）：没挂 Linear issue 的工作区一律 SKIP W19 NO_LINEAR_ISSUE。第一次真 `--execute`（reports/ws-cleanup-exec-1021/imac/run1）删的 32 个里有 12 个没挂 Linear，只凭 PR 已合并 / HEAD 在远端主分支就删了。先写失败方式，再改代码。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| N1 | 没挂 Linear、目录干净、HEAD 在 origin/main，照样 RM W14（run1 里 everos-research 就是这样删的） | c_nolin | SKIP W19，reason 以 NO_LINEAR_ISSUE 开头 |
| N2 | 没挂 Linear，但有已合并的 PR、HEAD 就是 PR 的 head，PR 已合并压过了没有 Linear | c_nolin_pr（PR #62 MERGED） | SKIP W19 |
| N3 | 没挂 Linear、目录已不在、HEAD 在远端，按 W4 RM | c_nolin_gone | SKIP W19 |
| N4 | 没挂 Linear、有不能重建的被忽略文件，按 W13 先备份再删 | c_nolin_backup | SKIP W19，不进 backup-files 以外的任何执行计划（planned 为空） |
| N5 | linkedLinearIssue 是空白串，被当成挂了 issue 去查 Linear，查失败判 W10 而不是 W19；或者被当成挂了、查到别的 | c_nolin_blank（"  "） | SKIP W19 |
| N6 | dry-run 时挂着 Linear（名单里是 RM），动手前 Orca 里把 issue 摘掉了，`--execute` 复查不看，照样删 | x_late_nolin（等待点期间清掉 linkedLinearIssue） | 跳过：「重新判定变成 SKIP W19」，没有 rm 调用 |
| N7 | 挂了 Linear 且已关的工作区被新规则误挡 | 现有 RM / BACKUP_RM 用例都挂上已关的 issue（PER-2、OKX-1） | 结论不变 |
| N8 | summary 里看不出有多少个是因为没挂 Linear 才没删 | out1 | summary 有「NO_LINEAR_ISSUE（W19）：n 个」 |

补充（R4，Zack 10-21 09:18）：W19 默认仍 SKIP；`--no-issue-reviews <目录>` 下有模型逐个审过、写了 `VERDICT: DELETE_OK`、HEAD 和现在一致的记录，才放行，而且走 BACKUP_RM。先写失败方式，再改代码。
记录路径：`<目录>/<repo 名>/<工作区目录名>.md`（名字里不是字母数字 . - 的换成 _）；记录里必须各有一行 `PATH: <路径>`、`HEAD: <40 位 sha>`、`VERDICT: DELETE_OK` 或 `VERDICT: KEEP`。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| R1 | 没有记录也放行 | c_nolin（带 --no-issue-reviews，但没写它的记录） | SKIP W19「没有审查记录」 |
| R2 | 记录写 KEEP 也放行 | c_nolin_pr | SKIP W19「审查结论是 KEEP」 |
| R3 | 记录写 DELETE_OK、HEAD 对得上，却还是 SKIP，或者走了不备份的 RM | c_nolin_backup（有 .dev.vars） | BACKUP_RM W19，planned 写备份 |
| R4 | 记录里的 HEAD 是旧的（审完之后工作区又动过），照样放行 | c_nolin_blank（记录写别的 sha） | SKIP W19「记录里的 HEAD … 和现在的 … 不一样」 |
| R5 | 放行之后跳过了后面的规则（状态不是 completed、最近有活动、HEAD 不在已合并的地方） | c_rev_inreview（DELETE_OK、状态 in-review） | SKIP W11 |
| R6 | 目录已不在的工作区，放行后走 W4 的纯 RM，审查记录没留底 | c_nolin_gone（DELETE_OK） | BACKUP_RM W19 |
| R7 | 记录格式不对（两行 VERDICT、没有 HEAD 行、VERDICT 写成别的词）被宽松地当成 DELETE_OK | c_rev_bad（VERDICT 两行，一行 DELETE_OK 一行 KEEP） | SKIP W19「审查记录格式不对」 |
| R8 | 记录是别的工作区的（复制粘贴改错了名），照样放行 | c_rev_wrongpath（PATH 写别的路径） | SKIP W19「记录里的 PATH 不是这个工作区」 |
| R9 | dry-run 时对得上，动手前工作区 HEAD 换了（换到另一个已推送的提交），`--execute` 复查不看 | x_rev_moved（等待点期间 checkout 到别的远端提交） | 跳过：「重新判定变成 SKIP W19」，不备份、不 rm |
| R10 | dry-run 后记录被改（改成 KEEP、改了 HEAD），`--execute` 沿用 dry-run 的结论 | x_rev_stale_rec（等待点期间把记录的 HEAD 改掉） | 跳过：「重新判定变成 SKIP W19」 |
| R11 | `--execute` 放行的工作区，备份里没有审查记录，事后查不到为什么删 | x_rev_ok | 已备份再 rm；备份目录里有 NO-ISSUE-REVIEW.md（不叫 REVIEW.md，免得和被忽略的同名文件撞），MANIFEST 里有它 |
| R12 | 不带 --no-issue-reviews 时也去读记录目录（例如默认路径），行为悄悄变了 | out1（不带参数） | N1–N8 结果不变 |
| R13 | `--no-issue-reviews` 目录不存在，静默当作全都没有记录，看不出参数写错了 | 带一个不存在的目录 | 退出码 2 |

补充（R5，ops bot 派活）：fork 上换了分支名开的 PR，W9 看不到。实例是 per-8714-schedule-400：工作区分支叫 `zhongc1211/per-8714-schedule-400`，上游 PR #8714 从 fork 的 `diffusion-attention-schedule-config` 开，还开着。R4 只按工作区分支名和 linkedPR 查，所以没查到，是审查记录的 KEEP 挡住的。
- 在真 GitHub 上核对过（10-21）：按 sha 搜 c92d061，上游和 fork 都返回空，因为 PR rebase 过，这个提交已经不在 PR 里了；按 fork 分支名 `--head diffusion-attention-schedule-config` 能查到 #8714 OPEN、owner zhongc1211。按 sha 搜 PR 现在的 head 0b35e03，返回 #8714 和两个叠在它上面的 open PR。
- 所以分两路查：远端分支名和 HEAD sha。HEAD 已经在远端主分支上的不做这两路，因为后来基于 main 的分支都包含它，查下去会把无关的 open PR 算到它头上。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| P1 | HEAD 只在 fork 的另一个分支名上，那个分支有 open PR（PR 已 rebase，head 不是 HEAD），W9 看不到 | c_fork_open（refs/remotes/fork/feat-open，up/proj 有 #70 OPEN、owner me、head 是别的 sha） | SKIP W9「PR 还开着」，pr 列有 #70 OPEN |
| P2 | fork 另一个分支名上的 PR 已合并，被当成 open 挡住；或者新查法查到的已合并 PR 被拿去给 W17 放行，安全修复反而多放行了工作区 | c_fork_merged（#71 MERGED，head 就是 HEAD） | 不是 W9；pr 列有 #71 MERGED；merged_via 为空，SKIP W17（新查法只用来挡） |
| P3 | 按分支名查 PR 失败（gh 出错、网络断），当作没有 PR 放过去 | c_fork_fail（`--head feat-fail` 失败） | SKIP W9「PR 查不到」 |
| P4 | 按 sha 搜 PR 失败，当作没有 PR 放过去 | c_sha_fail（`--search <sha>` 失败） | SKIP W9「PR 查不到」 |
| P5 | 远端分支名上没有 PR，但 HEAD 在另一个分支名（本地没有它的 ref）开的 open PR 里 | c_sha_open（#72 OPEN，headRefName renamed，commits 里有 HEAD） | SKIP W9 |
| P6 | HEAD 已在 origin/main，又被后来基于 main 的 fork 分支包含，那个分支的 open PR 把它挡住 | c_cache_only（fork/later 包含 main，有 #73 OPEN） | 结论不变（RM W14），pr 列没有 #73，没有多出 `--search` 调用 |
| P7 | 同名分支、但 PR 的 headRepositoryOwner 是别人，被算成这个工作区的 PR | c_fork_owner（fork/feat-own，#74 OPEN、owner stranger） | 不算这个 PR：往下判到 SKIP W17 |
| P8 | 目录已不在的工作区没走新查法 | c_fork_gone（detached，HEAD 只在 fork/feat-gone，#75 OPEN） | SKIP W9 |
| P9 | remote URL 不是 GitHub 的分支（本地路径、别的托管），拿去 gh 查，查不到就整行 SKIP | P 的 origin push 是本地路径；c_fork_* 都还有本地 bare 仓库的 ref | 这类 remote 的 ref 跳过，不报「PR 查不到」 |
| P10 | 按 sha 搜会搜到目标分支早已包含 HEAD 的 open PR（第一次真实 dry-run 发现：xinyue-site 的 #99、#101–#106 指向 staging，aa526b5 早在 origin/staging 上），无关的 open PR 把已合并的工作区挡在 W9 | c_sha_base（HEAD 在 upstream/staging，#76 OPEN 指向 staging、commits 里有 HEAD） | 不算 #76；往下判到 SKIP W17 |

P10 的处理：分支名和 sha 两路查到的 open PR，如果本地有它目标分支的远端分支、而且那个分支已经包含 HEAD，就不算。本地没有目标分支的照样算。

P2 改过一次：第二次真实 dry-run 时，心月-CI-CD-第二阶段 因为 sha 搜索查到了已合并、目标分支是 staging 的 PR #88（它的 head 包含 aa526b5），W17 通过，从 SKIP W17 变成了 BACKUP_RM。这次派活是安全修复，不该多放行，所以改成：分支名和 sha 两路查到的 PR 只用来挡（W9），不当作 W17 的已合并证据。要不要放开，等 Zack 定。

补充（R6，dr eggbot 10-21 11:10 审查必改 1）：`--execute` 原来的顺序是复查 → `do_backup`（大工作区要几分钟）→ 直接 `orca worktree rm`。备份期间工作区如果被动了，rm 照样执行，会停掉新开的终端，删掉本地分支和没推送的提交。
改法：BACKUP_RM 的工作区在备份成功后、rm 之前，再跑一次 `collect()` + `safe_eval`，并把结论、规则、备份清单、HEAD、未提交数、未推送数、Linear 和状态、Orca 状态、lastActivityAt、终端数、agent 和这次动手前的复查结果逐项比较。有一项变了就不 rm，备份留着，result 和 journal 写原因。
RM（不备份）的工作区在复查和 rm 之间没有耗时步骤，不再复查一次。
测试和演练用 `WS_AFTER_BACKUP_HOOK`（只在设了 WS_ORCA 时认）：备份成功后，以工作区路径为参数调用它，等它返回后再复查。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| S1 | 备份期间有了新提交（HEAD 变了、出现未推送提交），照样 rm，本地分支和提交一起丢 | x_pb_commit（钩子里提交一次） | 「已备份到 …；跳过：备份后复查有变化（…），没 rm，备份留着」；没有 rm 调用；备份目录还在；journal 有 recheck 行 |
| S2 | 备份期间出现未提交改动，照样 rm | x_pb_dirty（钩子里新建一个未跟踪文件） | 同 S1，原因含 W7 |
| S3 | 备份期间开了终端，rm 会把它停掉 | x_pb_term（钩子里往 term.json 加一个这个工作区的终端） | 同 S1，原因含 W6 或终端数 |
| S4 | 备份期间 agent 进了工作区 | x_pb_agent（钩子里在 wps.json 给它加 agent） | 同 S1，原因含 W5 |
| S5 | 备份期间只是 lastActivityAt 变了（结论没变），被当成没变化 | x_pb_act（钩子里把 lastActivityAt 加 1 毫秒） | 同 S1，原因含 lastActivityAt |
| S6 | 备份期间 Linear 被重新打开 | x_pb_lin（OKZ-1 在钩子里改成 started） | 同 S1，原因含 W10 |
| S7 | 复查本身失败（collect 抛错），被当成没变化，照样 rm | 由 except 分支兜住：异常发生在 rm 之前，记 ERROR，不 rm | 不 rm（代码路径，没有单独用例） |
| S8 | 备份后什么都没变，却因为复查拿到不同的派生值（如 idle_h、备份大小）误判有变化，正常的 BACKUP_RM 全部不删 | x_bk、x_rev_ok（钩子什么都不做） | 照旧「已备份到 …；已 rm」 |
| S9 | 复查跳过时把备份删了或挪了，事后找不回 | S1–S6 | 备份目录和 MANIFEST 还在原处 |

建议项顺手做的（审查建议 2、3、5、6）：

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| S10 | `gh pr list --limit 100` 正好拿到 100 条，可能被截断，却当作查全了 | 假 gh 对 `--head br/c_pr100` 返回 100 条已合并 PR | SKIP W9「PR 查不到（… 拿到 100 条，可能被截断）」 |
| S11 | 主仓库路径不在，`remotes` 返回 []，`prs_for` 当作「没有 PR」放行 | 代码改成抛 QueryFail；目前没有能走到这里的假 orca 数据，没加用例 | SKIP W9「PR 查不到（主仓库路径不在）」 |
| S12 | `WS_LOCK` 设错，指向一个别的目录，结束时 rmtree 删了它 | `WS_LOCK` 指向已有、里面有别的文件的目录：拿锁失败，退出码 6，目录原样 | 不删 |

## R6 addendum（Zack 11:15）：W17 只认 main

改之前先写的失败方式。W17 原来把「工作区自己的 PR 已合并、合进哪个 base 都算」当作放行证据，run1 因此删了 site #60、#61、#75 和 xinyue-site #89 的工作区（都合进 staging）。

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| T1 | 自己分支的 PR 合进 staging，HEAD 只在 staging 上，W17 照样放行 | c_stg_own：PR #77 MERGED，base staging，head 就是 HEAD；HEAD 只在 origin/staging | SKIP W17 |
| T2 | 自己分支的 PR 合进 staging，HEAD 在 PR head 的祖先里，W17 照样放行 | c_stg_anc：PR #78 MERGED，base staging，head 包含 HEAD | SKIP W17 |
| T3 | 合进 staging 的 PR 的 base 被加进「目标分支」，HEAD 在 origin/staging 上就放行 | 同 T1、T2（`bases` 只剩主分支） | SKIP W17 |
| T4 | 改严以后连合进 main 的 PR 也不认了（squash 合并时 HEAD 不在 main 上） | c_main_squash：PR #79 MERGED，base main，head 就是 HEAD，HEAD 不在 origin/main | 过 W17，merged_via 是「PR #79 的 head」 |
| T5 | PR 的 baseRefName 缺失时被当作主分支 | 代码：缺 base 的 PR 不算 | 不放行（代码路径） |
| T6 | 按字面把「HEAD 在自己已推送的分支上」当作已合并：没合并只推送过的工作区也能删，比原来更松 | 不实现；c_stg_own 的 HEAD 在 origin/br/c_stg_own 上，仍要 SKIP W17 | SKIP W17，写进 RESULT 等 Zack 定 |

## R6 真 Orca 演练（`ws-cleanup-drill.sh` 的 r6-* 阶段）

| # | 失败方式 | 演练用例 | 期望 |
|---|---|---|---|
| H1 | 没挂 Linear、审查 DELETE_OK、HEAD 对得上的工作区，真 Orca 下备份里没有审查记录，或者根本没 rm | h1-review-ok | 已备份再 rm；MANIFEST 里有 NO-ISSUE-REVIEW.md，校验通过 |
| H2 | dry-run 之后 HEAD 变了，真 Orca 下照样 rm | h2-late-head（dry-run 后提交一次） | 跳过，没备份，没 rm，工作区还在 |
| H3 | `--execute` 时 gh 查询失败，被当成「没有 PR」放行 | h3-gh-fail：仓库加一个 GitHub remote；3a 的 gh 只让 `auth status` 过；3b 的 gh 全失败 | 3a：SKIP W9「PR 查不到」，没 rm；3b：退出码 5，什么都不动 |
| H4 | 备份和 rm 之间工作区被改，真 Orca 下照样 rm | h4-after-backup（钩子在备份后提交一次） | 「已备份到 …；跳过：备份后复查有变化」，没 rm，备份留着 |
| H5 | `--only-from` 里混进别的仓库或演练目录外的行 | 每次 execute 前检查名单只有这一行演练工作区 | 检查不过就不执行 |
