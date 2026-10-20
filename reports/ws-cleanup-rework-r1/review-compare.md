# R1 dry-run 和 REVIEW 第 4 节逐项对照

数据：
- iMac 全量 dry-run，2026-10-21 04:08（bash 3.2）和 04:11（bash 5.3）SGT，在 5a280d7 上，bash 3.2（`imac/run1-bash3.2/`）和 bash 5.3（`imac/run2-bash5.3/`）各跑一次，两次结论、规则、原因逐行一样（见 `imac/proof/proof.md`）。
- MBA list-only，04:17 和 04:18 SGT，MBA 只有 bash 3.2，跑了两次（`mba/run1-bash3.2/`、`mba/run2-bash3.2/`），两次逐行一样。
- 修了 D1–D3 以后，04:45 和 04:48 在 4165ac2 上又全量跑了一次（`imac-4165ac2/`，bash 3.2、5.3 各一次）。127 个真实工作区的结论、规则、原因和 5a280d7 那次逐行一样；多出来的 25 行是演练仓库里留下的工作区，全部 SKIP。
- 表格由 `review_compare.py` 从 REVIEW.md 和 `imac/run1-bash3.2/worktrees.tsv` 生成（`review-compare-table.md`）。

## 结论

评审的三条预期都成立：
- xy-combined-src：SKIP W4（HEAD 36c6f4b 不在远端，报告给了 commit 和建议的备份分支名）。
- 7 个 CLOSE 终端：一个都不关（5 个 T7：同一工作区有 agent，配套 shell 12 小时内有输出；1 个 T3：本任务工作区；1 个 T8：folder 工作区）。MBA 上评审提到的 4 个也都 SKIP（2 个 T8 main 工作区，2 个 T7）。
- 8 个要补备份的：6 个变成 BACKUP_RM，备份清单里有评审点名的文件（FDV-76 两份 report.md、xinyue-lessons-import.tgz、test-results/ 等）。另外 2 个（#38 per-51、#47 PER-46）是 SKIP W11，见下面第 1 条。

和评审「同意删」不一致的有 19 项，全部是这轮新规则更保守造成的，没有一项是从 SKIP 变成删：

1. **SKIP W11，Orca 状态不是 completed（11 项）**：#1、#5、#8、#27、#31、#33、#35、#38、#39、#47、#50 的状态是 in-review / in-progress / sleep / Sleep。REWORK-R1 要求「Orca 状态不是 completed 的候选一律保守 SKIP，等 Zack 定」。其中 10 项旧规则会按 PR 已合并或 Linear 已关删掉，报告原因里写了「状态冲突」（#1 nightly-xinyue-site 是 W4 目录不在的那条，状态 in-progress，没有 PR、Linear，所以原因里没写状态冲突）。#38、#47 如果 Zack 放行，下一轮会先过 W13，test-results/ 不在构建产物清单里，会进备份。
2. **SKIP W17，HEAD 不在已合并的 PR 或远端主分支上（5 项）**：按 Zack 03:33「Linear Done 只是前提，HEAD 要在已合并分支/PR 上」。这 5 个的 HEAD 都已经推到远端分支上，删了不丢提交，但都不是「已合并」：
   - #3 r2-F：HEAD d772986 只在 origin/zhongc1211/release-1-r2-fdv66-imac，没有对应的已合并 PR。
   - #19 per-8714：HEAD 在 fork/diffusion-attention-schedule-config（上游 PR #8714 还开着）。本地分支名和 fork 分支名不同，W9 按本地分支名查不到这个 PR；W17 兜住了。这是 F6 剩下的一处：没修，原因写在 RESULT-R1。
   - #21 FDV-60-套餐对比：比已合并的 #62 多 3 个提交，只在远端同名分支上（评审 M2）。
   - #36 per-49：只在 `-local-91b1476` 备份分支上（评审 M2）。
   - #43 心月-CI-CD-第二阶段：detached HEAD aa526b5，只在若干 origin/archive/* 和 docs 分支上，没有已合并 PR。
3. **从 RM 变成 BACKUP_RM（3 项）**：#23、#24、#29 有被忽略的 `public/placeholder/sample/*.webp`（各 12 个文件 382 KB）。Zack 03:26 定了「忽略文件默认全部备份，只排除构建产物清单」，这些不在清单里，所以先备份再删。评审当时按旧口径没把它们算成损失。

其余 31 项和评审一致：RM W14 19 项；BACKUP_RM W13 11 项（评审要求补备份的 6 项，加上原来就是 BACKUP_RM 的 #18、#25、#26、#30、#32）；SKIP W4 1 项（xy-combined-src）。

评审 50 个以外没有新的 RM / BACKUP_RM 候选。iMac 这次的总数是 RM 19、BACKUP_RM 14、SKIP 93、LIST 1；终端 20 个全部 SKIP。

## 只读证明（iMac）

`imac/proof/proof.md`：dry-run 前后各存了 `orca worktree list --json`、`orca worktree ps --json`、`orca terminal list --json`、每个主仓库的 `git worktree list --porcelain`。
- git worktree list：518 行，前后字节一样。
- worktree list / ps：条数一样（126 / 127），没有新增或消失；变化只有 Orca 自己的 sortOrder，以及别的会话在跑造成的 lastOutputAt / preview / agents / status（本任务工作区、本机管理、bot 定位评审 B 等）。
- terminal list：多了 1 个 `term_fd5d42f7`（ops-botrole-review-pi-1021 的 pi 会话，是别的会话开的），没有少的。

## 逐项表

| # | 工作区 | 旧脚本 | 评审判断 | R1 结论 | R1 原因 |
|---|---|---|---|---|---|
| 1 | `/private/tmp/nightly-xinyue-site` | RM W4 | 同意 | SKIP W11 | Orca 状态是 in-progress，不是 completed |
| 2 | `/private/tmp/xy-combined-src` | RM W4 | **不同意**：应 SKIP | SKIP W4 | 目录已不在；记录的 HEAD 36c6f4b 不在远端，也没有别的 ref 包含（先推到 backup/xy-combined-src-36c6f4b） |
| 3 | `~/orca/r2-F` | RM W14 | 同意 | SKIP W17 | HEAD d772986 不在已合并的 PR / 远端主分支上 |
| 4 | `deepvision-ads/dvads-fdv-64-oauth` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 5 | `deepvision-ads/dvads-fdv-66-email` | RM W14 | 同意 | SKIP W11 | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 6 | `deepvision-ads/dvads-privacy-facts` | RM W14 | 同意删，但先备份 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 2 个文件 5 KB |
| 7 | `deepvision-ads/dvads-prod-admin-secret` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 8 | `deepvision-ads/dv广告-FDV-39-Meta沙盒入Business` | RM W14 | 同意（不丢东西） | SKIP W11 | Orca 状态是 sleep，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 9 | `deepvision-ads/dv广告-FDV-62-AGENTS-测试规矩` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 10 | `deepvision-ads/dv广告-FDV-76-隐私页GEO` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 11 | `ops/everos-research` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 12 | `ops/everos-vps-deploy` | RM W14 | 同意删，但先备份 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 1 个文件 10 KB |
| 13 | `ops/ops-PER-66-叫醒漏叫修复第二批` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 14 | `ops/ops-everos-ingest-commit` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 15 | `ops/ops-tunnel-flaps-1019-imac` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 16 | `ops/xinyue-everos-tailnet` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 17 | `ops/xinyue-night-review-guard` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 18 | `repository/PER-7-review-导入挪顶部` | BACKUP_RM W13 | 同意 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 2 个文件 6 KB |
| 19 | `repository/per-8714-schedule-400` | BACKUP_RM W13 | 同意（不丢东西） | SKIP W17 | HEAD c92d061 不在已合并的 PR / 远端主分支上 |
| 20 | `site/dv官网-AGENTS-测试规矩` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 21 | `site/dv官网-FDV-60-套餐对比` | RM W14 | 同意（不丢东西） | SKIP W17 | HEAD 755d3e5 不在已合并的 PR / 远端主分支上 |
| 22 | `site/dv官网-FDV-63-AGENTS对齐` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 23 | `site/dv官网-FDV-65-base-205187c` | RM W14 | 同意 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 12 个文件 382 KB |
| 24 | `site/dv官网-FDV-65-base-683f287` | RM W14 | 同意 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 12 个文件 382 KB |
| 25 | `site/dv官网-FDV-65-iMac整轮e2e` | BACKUP_RM W13 | 同意 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 1577 个文件 950925 KB |
| 26 | `site/dv官网-FDV-65-testing-Builds修复` | BACKUP_RM W13 | 同意 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 15 个文件 59 KB |
| 27 | `site/dv官网-FDV-65-首页交互e2e` | BACKUP_RM W13 | 同意 | SKIP W11 | Orca 状态是 Sleep，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 28 | `site/dv官网-Open-Design-重设计` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 29 | `site/dv运维-CI-自动部署` | RM W14 | 同意 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 12 个文件 382 KB |
| 30 | `site/dv运维-FDV-78-EverOS-走-tailnet` | BACKUP_RM W13 | 同意 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 45 个文件 133 KB |
| 31 | `site/fdv-60-e2e-followup` | RM W14 | 同意 | SKIP W11 | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 32 | `site/fdv-92-rerun-imac` | BACKUP_RM W13 | 同意 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 280 个文件 39660 KB |
| 33 | `xinyue-site/auto-run-1-20261013T1530` | RM W14 | 同意 | SKIP W11 | Orca 状态是 in-progress，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 34 | `xinyue-site/ops-everos-imac-mcp` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 35 | `xinyue-site/per-48-prod` | RM W14 | 同意 | SKIP W11 | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 36 | `xinyue-site/per-49-check-only` | RM W14 | 同意（不丢东西） | SKIP W17 | HEAD 91b1476 不在已合并的 PR / 远端主分支上 |
| 37 | `xinyue-site/per-50-flood-timeout` | RM W14 | 同意删，但先备份 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 37 个文件 8536 KB |
| 38 | `xinyue-site/per-51-quality-recover` | RM W14 | 同意删，但先备份 | SKIP W11 | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 39 | `xinyue-site/per-75-oss-games` | RM W14 | 同意（不丢东西） | SKIP W11 | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 40 | `xinyue-site/pr83-merge` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 41 | `xinyue-site/unpushed-cleanup-20261018` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 42 | `xinyue-site/心月-AGENTS-对齐` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 43 | `xinyue-site/心月-CI-CD-第二阶段` | RM W14 | 同意 | SKIP W17 | HEAD aa526b5 不在已合并的 PR / 远端主分支上 |
| 44 | `xinyue-site/心月-EverOS-MCP-v2-接线` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 45 | `xinyue-site/心月-PER-27-模型不可用提示` | RM W14 | 同意删，但先备份 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 2 个文件 44 KB |
| 46 | `xinyue-site/心月-PER-28-失败按钮` | RM W14 | 同意删，但先备份 | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 2 个文件 44 KB |
| 47 | `xinyue-site/心月-PER-46-泡泡砰砰核心玩法` | BACKUP_RM W13 | 同意，备份要加 test-results/ | SKIP W11 | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| 48 | `xinyue-site/心月-PER-54-文档合并与-feed-monster-排查` | RM W14 | 同意 | RM W14 | 条件全部满足 |
| 49 | `~/pi/remote/xinyue-ci` | BACKUP_RM W13 | 同意，备份要加 test-results/ | BACKUP_RM W13 | 有被忽略、不能重建的文件（先整份备份）；备份 13 个文件 1161 KB |
| 50 | `~/pi/remote/xinyue-site-cicd` | RM W14 | 同意 | SKIP W11 | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |

| 终端 | 机器 | R1 结论 | R1 原因 |
|---|---|---|---|
| term_e7d55df8 | iMac | SKIP T7 | 同一工作区有 agent 的配套 shell，最近 12 小时内有输出 |
| term_fda1fd63 | iMac | SKIP T7 | 同一工作区有 agent 的配套 shell，最近 12 小时内有输出 |
| term_e34518f4 | iMac | SKIP T3 | 本任务所在工作区的终端 |
| term_053bc025 | iMac | SKIP T7 | 同一工作区有 agent 的配套 shell，最近 12 小时内有输出 |
| term_759189b1 | iMac | SKIP T7 | 同一工作区有 agent 的配套 shell，最近 12 小时内有输出 |
| term_4045de0c | iMac | SKIP T8 | 不在清理范围（folder / main / 别的机器 / 不在 worktree list） |
| term_ee7c21a9 | iMac | SKIP T7 | 同一工作区有 agent 的配套 shell，最近 12 小时内有输出 |
| term_16efda20 | MBA | SKIP T8 | 不在清理范围（folder / main / 别的机器 / 不在 worktree list） |
| term_bd5a15ec | MBA | SKIP T8 | 不在清理范围（folder / main / 别的机器 / 不在 worktree list） |
| term_1de8accf | MBA | SKIP T7 | 同一工作区有 agent 的配套 shell，最近 12 小时内有输出 |
| term_5610c4cc | MBA | SKIP T7 | 同一工作区有 agent 的配套 shell，最近 12 小时内有输出 |
