# R5 iMac dry-run 和 R4 的对比

- R5 两次（bash 3.2 10:34:43 / 5.3 10:39:14）worktrees.tsv 各 96 行，除 idle_h 外逐行一样。R4（09:37）96 行，没有新增、没有消失的。
- 「工作区变了」列：R4 到 R5 之间，Orca 里的状态或 Linear 被人改过的。这些变化不是本次改动造成的，也不是我改的。

| 工作区 | R4 | R5 | 工作区变了 | R5 原因 | R5 新看到的 PR |
|---|---|---|---|---|---|
| ops-PER-106-git-sot | SKIP W12 | SKIP W12 | — | 最近 24 小时内有活动 | 1 个 |
| ops-PER-84-everos-docs | SKIP W11 | SKIP W12 | 状态 in-review→completed；Linear 无→PER-84 | 最近 24 小时内有活动 | 0 个 |
| dv官网-FDV-70-iMac-产品页 | SKIP W10 | SKIP W10 | — | Linear 还没关 | 16 个 |
| dv官网-FDV-70-iMac-关于我们 | SKIP W10 | SKIP W10 | — | Linear 还没关 | 18 个 |
| dv官网-FDV-70-iMac-博客 | SKIP W10 | SKIP W10 | — | Linear 还没关 | 18 个 |
| dv官网-FDV-70-全站素材配色GEO | SKIP W10 | SKIP W10 | — | Linear 还没关 | 29 个 |
| dv官网-FDV-70-整版合-staging-上线准备 | SKIP W10 | SKIP W10 | — | Linear 还没关 | 11 个 |
| fdv-70-deslop-r2 | SKIP W10 | SKIP W10 | — | Linear 还没关 | 7 个 |
| PER-56-h3-merge-three | SKIP W10 | SKIP W10 | — | Linear 还没关 | 1 个 |
| PER-56-n7-rootcause | SKIP W10 | SKIP W9 | — | PR 还开着 | 1 个，其中开着的：#8746 |
| PER-8-hunyuan-imac-omni | SKIP W10 | SKIP W10 | — | Linear 还没关 | 1 个 |
| per-8714-schedule-400 | SKIP W19 | SKIP W9 | — | PR 还开着 | 1 个，其中开着的：#8714 |
| per-rebase-main-1017 | SKIP W10 | SKIP W9 | — | PR 还开着 | 1 个，其中开着的：#8746 |
| per56-n10-rootcause-opus | SKIP W10 | SKIP W9 | — | PR 还开着 | 1 个，其中开着的：#8746 |
| auto-run-1-20261013T1530 | SKIP W11 | BACKUP_RM W19 | 状态 in-progress→completed | 没挂 Linear，审查记录 DELETE_OK（xinyue-site/auto-run-1-20261013T1530.md）；先备份被忽略的文件和这份记录 | 0 个 |
| auto-run-2-20261013T1725 | SKIP W11 | SKIP W17 | 状态 in-progress→completed | HEAD fdeb83e 不在已合并的 PR / 远端主分支上 | 0 个 |
| docs-lessons-to-everos | SKIP W11 | BACKUP_RM W19 | 状态 sleep→completed | 没挂 Linear，审查记录 DELETE_OK（xinyue-site/docs-lessons-to-everos.md）；先备份被忽略的文件和这份记录 | 0 个 |
| 心月-CI-CD-第二阶段 | SKIP W17 | SKIP W17 | — | HEAD aa526b5 不在已合并的 PR / 远端主分支上 | 5 个 |
| xinyue-site-cicd | SKIP W11 | SKIP W11 | — | Orca 状态是 in-review，不是 completed（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定） | 7 个 |
| nightly-xinyue-site | SKIP W11 | BACKUP_RM W19 | 状态 in-progress→completed | 没挂 Linear，审查记录 DELETE_OK（xinyue-site/nightly-xinyue-site.md）；目录已不在（HEAD 2f7da6d 已在远端），备份里只有这份记录 | 0 个 |
| xy-combined-src | SKIP W11 | SKIP W17 | 状态 in-progress→completed | HEAD 36c6f4b 不在已合并的 PR / 远端主分支上 | 0 个 |
