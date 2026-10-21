# R4 iMac dry-run 和 R3 的对比

- R4 两次（bash 3.2 / 5.3）worktrees.tsv 各 96 行，除 idle_h 外逐行一样。
- R3（08:55，3fdf19a）96 行。R4 里新出现的工作区 0 个，R3 有、R4 没有的 0 个。
- planned 不为空的行（真跑 --execute 会动的）：0 个。
- 结论、规则或原因有变化的：18 行，全是 R3 的 W19。其余 78 行一样。

| 工作区 | R3 | R4 | 审查记录 | R4 原因 |
|---|---|---|---|---|
| ops-PER-67-e2e-imac | SKIP W19 | SKIP W12 | ops/ops-PER-67-e2e-imac.md | 最近 24 小时内有活动 |
| ops-PER-84-everos-docs | SKIP W19 | SKIP W11 | ops/ops-PER-84-everos-docs.md | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| ops-PER80-drill-gap9 | SKIP W19 | SKIP W12 | ops/ops-PER80-drill-gap9.md | 最近 24 小时内有活动 |
| ops-PER82-stuck-budget | SKIP W19 | SKIP W12 | ops/ops-PER82-stuck-budget.md | 最近 24 小时内有活动 |
| ops-box-decommission-inventory-1021 | SKIP W19 | SKIP W19 | KEEP | NO_LINEAR_ISSUE：审查结论是 KEEP（ops/ops-box-decommission-inventory-1021.md） |
| ops-unpushed-nested-1020 | SKIP W19 | SKIP W19 | KEEP | NO_LINEAR_ISSUE：审查结论是 KEEP（ops/ops-unpushed-nested-1020.md） |
| xinyue-everos-recheck | SKIP W19 | SKIP W19 | KEEP | NO_LINEAR_ISSUE：审查结论是 KEEP（ops/xinyue-everos-recheck.md） |
| ops-per83-verify-dv-site | SKIP W19 | SKIP W12 | site/ops-per83-verify-dv-site.md | 最近 24 小时内有活动 |
| per-8714-schedule-400 | SKIP W19 | SKIP W19 | KEEP | NO_LINEAR_ISSUE：审查结论是 KEEP（vllm-omni_H3_C1/per-8714-schedule-400.md） |
| auto-run-1-20261013T1530 | SKIP W19 | SKIP W11 | xinyue-site/auto-run-1-20261013T1530.md | Orca 状态是 in-progress，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| auto-run-2-20261013T1725 | SKIP W19 | SKIP W11 | xinyue-site/auto-run-2-20261013T1725.md | Orca 状态是 in-progress，不是 completed |
| docs-lessons-to-everos | SKIP W19 | SKIP W11 | xinyue-site/docs-lessons-to-everos.md | Orca 状态是 sleep，不是 completed |
| 心月-CI-CD-第二阶段 | SKIP W19 | SKIP W17 | xinyue-site/心月-CI-CD-第二阶段.md | HEAD aa526b5 不在已合并的 PR / 远端主分支上 |
| 心月-EverOS-启动器-v2.1 | SKIP W19 | SKIP W19 | KEEP | NO_LINEAR_ISSUE：审查结论是 KEEP（xinyue-site/心月-EverOS-启动器-v2.1.md） |
| 心月-生产-Builds-接入 | SKIP W19 | SKIP W19 | KEEP | NO_LINEAR_ISSUE：审查结论是 KEEP（xinyue-site/心月-生产-Builds-接入.md） |
| xinyue-site-cicd | SKIP W19 | SKIP W11 | xinyue-site/xinyue-site-cicd.md | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） |
| nightly-xinyue-site | SKIP W19 | SKIP W11 | xinyue-site/nightly-xinyue-site.md | Orca 状态是 in-progress，不是 completed |
| xy-combined-src | SKIP W19 | SKIP W11 | xinyue-site/xy-combined-src.md | Orca 状态是 in-progress，不是 completed |
