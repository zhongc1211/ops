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
