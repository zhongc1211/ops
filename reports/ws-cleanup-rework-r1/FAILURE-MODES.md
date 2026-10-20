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
