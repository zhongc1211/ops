# R6 真 Orca 演练（iMac，2026-10-21 11:3x SGT）

- 脚本：`scripts/tests/ws-cleanup-drill.sh`，在 9ce6a53 上跑（`scripts/ws-cleanup.sh` blob b9c46ae）。
  - 顺序：`init` → `DRILL_TAG=r6` 的 `r6-setup`、`r6-dry`、`r6-exec`、`r6-post`。
- 演练仓库：`~/ops-drill/ws-cleanup-drill`，origin 是本地 bare 仓库 `~/ops-drill/origin.git`，不连 GitHub。
  - 用 `orca repo add` 注册成单独的 Orca 项目：repo id `13a60bf6-f713-4397-ba4b-0729dafa93f3`，project id `repo:13a60bf6-f713-4397-ba4b-0729dafa93f3`，显示名 `ws-cleanup-drill`（`repo-add.json`）。
- 演练工作区：`~/ops-drill/wt-r6/h1..h4`，用 `git worktree add` 建，已推送，Orca 状态 completed，都没挂 Linear。
  - 审查记录在 `~/ops-drill/reviews-r6/ws-cleanup-drill/`，副本在 `reviews-r6/`，4 份都是 DELETE_OK，HEAD 是建好时的 HEAD。
- 环境变量：
  - `WS_ARCHIVE=~/ops-drill/archive-r6`：备份不和真的混在一起；
  - `WS_IDLE_H=0`：演练工作区才建几分钟。
  - 每次调用都带 `--repo 13a60bf6-…` 和 `--no-issue-reviews ~/ops-drill/reviews-r6`。
- 每个用例单独跑一次 `--execute`。`--only-from` 名单只含这个用例的那一行（`list-<用例>.tsv`），执行前检查这一行的 id 属于演练仓库、路径在 `~/ops-drill/wt-r6/` 下，不满足就不执行（`*.listcheck`）。
- 没有用 `--close-terminals`，也没有 `--force`。

## 结果

dry-run 用 bash 3.2 和 5.3 各跑一次（`dry-bash3.2/`、`dry-bash5.3/`），退出码 0。4 个演练工作区都是 BACKUP_RM W19，两次结论一样。`--execute` 都用 `/bin/bash`（3.2）跑。

| 用例 | 怎么造 | `--execute` 结果 | 退出码 | 产物 |
|---|---|---|---|---|
| 1 h1-review-ok | 什么都不改 | 已备份再 rm；journal 依次是 backup、recheck「没变化」、rm-start、rm-end（ok）。备份的 MANIFEST 有 `NO-ISSUE-REVIEW.md` 和 `.orca-task/BRIEF.md`，校验通过 | 0 | `c1-execute*`、`manifests/h1-review-ok.MANIFEST.sha256` |
| 2 h2-late-head | dry-run 后在工作区提交一次 | 「跳过：名单里是 BACKUP_RM，这次判定 SKIP W8（有未推送提交 1 个）」；没备份，没 rm，journal 是空的 | 0 | `c2-execute*` |
| 3a h3-gh-fail | 给演练仓库加一个 GitHub remote（`github`，从没 fetch，也没连过），`WS_GH` 指向 `gh-fail-a.sh`：`auth status` 返回 0，其余都失败 | 「跳过：名单里是 BACKUP_RM，这次判定 SKIP W9（PR 查不到（gh repo view …））」；没备份，没 rm | 0 | `c3a-execute*`、`gh-fail-a.sh` |
| 3b h3-gh-fail | `WS_GH` 指向 `gh-fail-b.sh`：全部失败 | summary 第一行「环境不对：gh 不可用（gh auth status 失败）。--execute 什么都没做」 | 5 | `c3b-execute*`、`gh-fail-b.sh` |
| 4 h4-after-backup | `WS_ORCA` 设成真 orca 路径，`WS_AFTER_BACKUP_HOOK=hook-c4.sh`：备份后在工作区提交一次 | 「已备份到 …；跳过：备份后复查有变化（结论 BACKUP_RM W19→SKIP W8；备份清单 .orca-task→空；HEAD 240f835→0155ab3；未推送 0→1；…），没 rm，备份留着」；journal 有 backup 和 recheck 1，没有 rm-start | 0 | `c4-execute*`、`hook-c4.sh`、`manifests/h4-after-backup.MANIFEST.sha256` |

- 「备份清单 .orca-task→空」的原因：复查时结论已变成 SKIP W8，W8 在 W13 之前，所以没算备份清单。
- 用例 3a 失败的是 `gh repo view`：脚本先把 remote 规范成仓库名，这一步也走 gh。这是查不到的一种，照样 SKIP W9。

## 别的工作区没动

- `before-others.txt`、`after-others.txt`：演练仓库以外的 Orca 工作区，前后都是 92 个，排序后 id 列表的 sha256 一样。
- 演练仓库自己的（`before-orca-worktree-list.tsv`、`after-orca-worktree-list.tsv`）：只少了 h1-review-ok。
- `before-git-worktrees.txt`、`after-git-worktrees.txt`：演练仓库的 `git worktree list`。
- `archive-tree.txt`：备份目录里只有 h1、h4 两份，`manifest-check.txt` 两份都是 OK。
- `left-workspaces.txt`：h2、h3、h4 的目录都在，最后一个提交见表。

## 留着没清

按 R6 的要求，演练完没清理：
- Orca 项目 `ws-cleanup-drill`（repo id `13a60bf6-f713-4397-ba4b-0729dafa93f3`），里面还有主工作区和 h2、h3、h4；
- `~/ops-drill/`，包括 `origin.git`、`ws-cleanup-drill`、`wt-r6`、`reviews-r6`、`archive-r6`。

清理要 Zack 卡片批准。
