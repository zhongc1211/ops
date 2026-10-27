# R6 dry-run 和 R5 的逐行对比（bash 3.2，按 Orca id 对齐，W16 这种没有 id 的按路径）

R5：reports/ws-cleanup-rework-r5/imac/run1-bash3.2（10:34）；R6：run1-bash3.2（11:38）。只列 verdict、rule、reason、pr、merged_via、status、head、linear、review 有变化的行。

R5: {'SKIP': 92, 'LIST': 1, 'BACKUP_RM': 3} total 96
R6: {'SKIP': 96, 'LIST': 2} total 98

| 工作区 | R5 | R6 | 变了的字段 |
|---|---|---|---|
| xinyue-site / auto-run-1-20261013T1530 | BACKUP_RM W19 | 没有 | 消失 |
| xinyue-site / auto-run-2-20261013T1725 | SKIP W17 | SKIP W17 | reason：HEAD fdeb83e 不在已合并的 PR / 远端主分支上 → HEAD fdeb83e 不在合进主分支的 PR / 远端主分支上（staging 等不算） |
| xinyue-site / docs-lessons-to-everos | BACKUP_RM W19 | 没有 | 消失 |
| xinyue-site / per-49-check-only | SKIP W17 | SKIP W17 | reason：HEAD 91b1476 不在已合并的 PR / 远端主分支上 → HEAD 91b1476 不在合进主分支的 PR / 远端主分支上（staging 等不算） |
| xinyue-site / 心月-CI-CD-第二阶段 | SKIP W17 | SKIP W17 | reason：HEAD aa526b5 不在已合并的 PR / 远端主分支上 → HEAD aa526b5 不在合进主分支的 PR / 远端主分支上（staging 等不算） |
| xinyue-site / nightly-xinyue-site | BACKUP_RM W19 | 没有 | 消失 |
| xinyue-site / xy-combined-src | SKIP W17 | SKIP W17 | reason：HEAD 36c6f4b 不在已合并的 PR / 远端主分支上 → HEAD 36c6f4b 不在合进主分支的 PR / 远端主分支上（staging 等不算） |
| ws-cleanup-drill / ws-cleanup-drill | 没有 | SKIP W1 | 新出现 |
| ws-cleanup-drill / h2-late-head | 没有 | SKIP W8 | 新出现 |
| ws-cleanup-drill / h3-gh-fail | 没有 | SKIP W9 | 新出现 |
| ws-cleanup-drill / h4-after-backup | 没有 | SKIP W8 | 新出现 |
| deepvision-ads / r2-F | SKIP W17 | SKIP W17 | reason：HEAD d772986 不在已合并的 PR / 远端主分支上 → HEAD d772986 不在合进主分支的 PR / 远端主分支上（staging 等不算） |
| site / dv官网-FDV-60-套餐对比 | SKIP W17 | SKIP W17 | reason：HEAD 755d3e5 不在已合并的 PR / 远端主分支上 → HEAD 755d3e5 不在合进主分支的 PR / 远端主分支上（staging 等不算） |
| ops / ops-PER126-p2-sampler | 没有 | LIST W16 | 新出现 |
