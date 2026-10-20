# ws-cleanup.sh：失败方式清单 + dry-run 结果（2026-10-21）

派活：`.orca-task/DRYRUN-BRIEF.md`（Zack 01:43「可以，dryrun 吧」）。规则以 `.orca-task/RULES-DRAFT.md` 为准，改动：D1=24h，D2 备份到
`~/ops-archive/ws-cleanup/<日期>/<repo>/<目录名>/` + `MANIFEST.sha256`，D3 保留 30 天、到期只列出，D4 加 evidence/、artifacts/、analysis/、
`*.local.*`，D5 取消（不设上限），D6 改成目录已不在的 Orca 记录直接 rm。执行者：Claude Code（iMac，本工作区）。本轮没有任何一次调用带 `--execute`。

## 1. 失败方式（写代码之前写的）

每条对应 `scripts/tests/ws-cleanup-test.sh` 里的一个用例：用假的 orca / gh（脚本读 fixture JSON，并把每次调用记进日志）、假的 `ps` 输出，
加上在临时目录里真建的 git 仓库（bare origin + 主 clone + `git worktree add`）。这些用例用了测试替身，不算 E2E；E2E 是第 3 节在 iMac / MBA 上的真实 dry-run。

动手前查到的、会影响设计的事实：

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F1 | `orca diagnostics memory` 给的 pid 是 `login`，shell（zsh）是它的子进程 | 本机 13 个终端逐个对 `ps -A -o pid,ppid,comm` | 「空 shell」= login 下只有一个 shell，shell 下面没有子进程；不能把 login 的子进程当成「活进程」 |
| F2 | 终端 `ptyId` = diagnostics 的 `sessionId`；`ORCA_TERMINAL_HANDLE` 是本终端 | 同上；`env` | T3 用这个环境变量认自己 |
| F3 | `linkedPR` 是数字；vllm-omni 的 linkedPR 可能是上游仓库的号（PER-56 → #8746） | `orca worktree list --json`；审计 4b-3 | 先在 fork 的 PR 列表里找，找不到再查上游；都找不到 = 查询失败 = 跳过 |
| F4 | `orca linear list-issues --team PER/FDV --json` 能拿到全部 issue（truncated=false），52 个 linkedLinearIssue 都在里面；状态 type 有 completed / canceled / duplicate | 只读跑了一次 | 「已关」= 这三种 type；按 issue 前缀分 team 查，某个 team 查不到 → 关联到它的工作区全部跳过 |
| F5 | MBA 上没有 PATH 里的 orca，在 `/Applications/Orca.app/Contents/Resources/bin/orca`（1.4.229）；bash 3.2、python 3.13 | `ssh mba` | 脚本自己找 orca（照 automation-reaper.sh）；MBA 用 `ssh mba 'bash -s -- --list-only …' < scripts/ws-cleanup.sh`，不往 MBA 拷脚本 |
| F6 | `orca worktree rm` 会顺手删检出的本地分支（证明不了已合并的保留）；不加 `--force` 时有未跟踪文件会拒绝 | `orca worktree rm --help` | 不加 `--force`；git 忽略的文件不会挡住 rm，所以要先按 W13 备份 |
| F7 | dry-run 不 fetch（fetch 会写 `.git`）。远端 ref 是旧的时，未推送只会多算、不会少算 | — | W8 偏保守，可接受 |

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| A1 | 删掉 main 工作区或 bare 仓库 | c_main | SKIP W1 |
| A2 | 删掉本任务自己所在的工作区 | c_self | SKIP W2 |
| A3 | 处理别的机器的工作区（hostId 不是 local） | c_remote_host | LIST W3 |
| A4 | 删有 agent 在跑的工作区（agentIdentity 非空，或进程树里有 claude/pi/codex 但 agentIdentity 是空的） | c_agent、c_agent_noid | SKIP W5 |
| A5 | 删终端里还有活进程的工作区 | c_proc | SKIP W6 |
| A6 | 终端查不到 pid（diagnostics 里没有）被当成「没进程」 | c_diag_missing、G6 | SKIP W6 |
| A7 | 删有未提交改动的工作区（含未跟踪文件） | c_dirty、c_untracked | SKIP W7 |
| A8 | 删有未推送提交的工作区 | c_unpushed | SKIP W8 |
| A9 | 删分支 PR 还开着的工作区（按分支名，或按 linkedPR，含上游号） | c_open_pr、c_linked_open_pr | SKIP W9 |
| A10 | gh 查不到（网络、权限）被当成「没有 open PR」 | c_gh_fail | SKIP W9（查询失败） |
| A11 | Linear 还没关的工作区被删 | c_linear_open | SKIP W10 |
| A12 | Linear 查不到被当成「已关」 | c_linear_fail | SKIP W10（查询失败） |
| A13 | 没有任何「做完」证据也删 | c_not_done | SKIP W11；in-review 但 PR 已合并的 c_merged_inreview → RM |
| A14 | 24 小时内有活动的被删；`lastActivityAt=0` 被当成「很久没动」 | c_recent、c_zero_recent_commit | SKIP W12 |
| A15 | 带 TASK.md / .orca-task / briefs / .dev.vars / evidence / artifacts / analysis / `*.local.*` 的没备份就删；藏在别的被忽略目录里面的也要找到 | c_backup、c_backup_evidence、c_nested | BACKUP_RM W13 |
| A16 | 把 node_modules/.next/.wrangler/dist 里的东西当成要备份的（或者反过来，因为有缓存目录就不删） | c_cache_only | RM W14 |
| A17 | ops 项目的普通工作区还被当常驻 | c_ops_common | RM W14 |
| A18 | 中文、空格路径处理错，TSV 列错位 | c_chinese | RM W14，TSV 每行列数一致 |
| A19 | 目录不是 git 仓库（git 命令失败）被当成「干净」 | c_not_git | SKIP（查询失败） |
| A20 | 目录不在的 Orca 记录没处理，或者被误加 `--force` | c_missing | RM W4，计划命令里没有 `--force` |
| A21 | git 里登记、Orca 里没有的 worktree 被删 | git_only | LIST W16 |
| A22 | 关了 agent 的终端 / 带 resume id 的终端 / 本任务的终端 / 有活进程的终端 | t_agent、t_resume、t_self、t_proc | SKIP T1 / T2 / T3 / T6 |
| A23 | 读终端屏幕失败被当成「没有 resume id」 | t_read_fail | SKIP T2（查询失败） |
| A24 | 用 `--tab` 关掉整个 tab，连带关掉同一 tab 里还在跑的窗格 | t_tab_sibling | 计划命令不带 `--tab` |
| A25 | 空 shell、已断开的终端没被列为可关 | t_empty、t_dead | CLOSE T4 / T5 |
| A26 | dry-run 实际动了东西：调用了 rm/close，建了备份目录，改了 git 状态 | G1 | 假 orca 日志里没有 rm/close；备份根目录不存在；git 快照前后一致 |
| A27 | `--list-only` 还给出 RM/CLOSE 动作 | G2 | 动作列全部是 LIST |
| A28 | 输出不可重复（顺序随机） | G3 | 连续两次，去掉时间列后 TSV 一样 |
| A29 | `orca worktree list` / `terminal list` 失败还照样出结论 | G4、G5 | 退出码 4，不写结果文件 |
| A30 | 报告里出现 .dev.vars 内容或终端屏幕内容 | G7 | 输出目录和 stdout 里都找不到 fixture 里的假密钥 |
| A31 | 备份的 sha 对不上还继续 rm | E1 | 不 rm，记 BACKUP_FAIL（只在 `--execute` 下才会走到，见下） |
| A32 | rm 被 Orca 拒绝后加 `--force` 重试 | E2 | 记失败原文，不重试 |
| A33 | .dev.vars 被复制（多一份明文）而不是移动，或者权限不是 600 | E3 | 原位置没了，新位置 600，目录 700 |
| A34 | 判定和 rm 之间工作区又有了改动（先判后删的时间差） | E4 | rm 前对这一个工作区重新判一次，结论变了就不删 |

E1–E4 只在 `--execute` 下才会走到。本轮禁止带 `--execute`，所以这四个用例写了，但默认不跑
（要设 `WS_TEST_EXECUTE=1`），结果写「没跑」。
