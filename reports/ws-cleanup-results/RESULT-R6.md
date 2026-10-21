# PER-139 R6 结果（dr eggbot 评审 3 处必改 + Zack 11:15 W17 补充）

## 结论

- 3 处必改都做了，Zack 11:15 的 W17 补充也做了。已推到 `zhongc1211/ops-ws-cleanup-script`，没用 force，没 rebase。PR #73 仍是 draft，没合并。
  - 代码：`9ce6a532c0bf1b1382f1e8d71814aa3ecf2843b9`（脚本 blob b9c46ae）。
  - 报告：`2f53765848d661054e1251e96e1c498e28dfb073`。
  - 最后一个提交只加了这份 RESULT 的副本 `reports/ws-cleanup-results/RESULT-R6.md`，head 见文末。
- 现在的 iMac dry-run 里没有可删的工作区（RM 0、BACKUP_RM 0）。
- 真实工作区上没跑 `--execute` 和 `--close-terminals`。`--execute` 只在演练项目的演练工作区上跑过。
- 演练项目和 `~/ops-drill` 留着没清（见最后一节）。

## ① 备份后、rm 前再复查

- BACKUP_RM 备份成功后，重新 `collect()` + `safe_eval`。比对的项目：
  - 结论、备份清单、HEAD、未提交、未推送；
  - Linear、Orca 状态、lastActivityAt；
  - 终端数、agent。
- 有任何变化，结果写成「已备份到 …；跳过：备份后复查有变化（…），没 rm，备份留着」，journal 记 `recheck … 1 <原因>`；没变化记 `recheck … 0 没变化`，再 rm。
  - 复查本身出错时走原来的 except 分支：记 ERROR，不 rm。这条没有单独用例。
  - 普通 RM 没有备份这一步，动手前已经复查过，所以只给 BACKUP_RM 加了这一次复查。
- 测试钩子 `WS_AFTER_BACKUP_HOOK`：只在设了 `WS_ORCA` 时认。
- 失败方式 S1–S12 先写进了 `reports/ws-cleanup-rework-r1/FAILURE-MODES.md`。
- 桩测试：在备份和复查之间改动工作区，6 种各一个用例，断言都是没有 rm 调用、备份目录和 MANIFEST 还在、journal 有原因：
  - S1：新提交；
  - S2：未提交改动；
  - S3：新终端；
  - S4：agent 出现；
  - S5：lastActivityAt 变了；
  - S6：Linear 被重新打开。
  - S8：什么都没变的 x_bk、x_rev_ok 照常备份并 rm。

## Zack 11:15：W17 只认主分支

- 改成：HEAD 要在远端主分支上，或者在一个合进主分支的已合并 PR 里。合进 staging 等其他 base 的 PR 一律不算（`head_merged`），已合并 PR 的 base 也不再算作「目标分支」。
  - sha 或别的分支名查到的 PR 照旧只挡不放。
  - 「主分支」是 main、master，加上 Orca 里主工作区所在的分支（xinyue-site 是 `feat/xinyue-site`），这部分没改。
- 失败方式 T1–T6 先写了。桩测试：
  - T1：自己分支的 PR #77 合进 staging，HEAD 也在 origin/staging 和自己已推送的分支上 → SKIP W17，merged_via 为空；
  - T2：合进 staging 的 PR head 包含 HEAD → SKIP W17；
  - T4：squash 合进 main 的 PR #79，HEAD 不在 origin/main → 照样过 W17，merged_via「PR #79 的 head」。
- **没有实现的一条，要 Zack 定。** 11:15 原话是「W17 只认两种证据：HEAD 在 main 上，或 HEAD 在工作区自己已推送的分支上」。
  - 照字面做，后一种是「推送过就算」，不要求合并，比改之前还松。
  - run1 那 4 个的 HEAD 都在各自已推送的分支上（见下表），照字面它们照样会放行。这和 addendum 想挡住它们的意思冲突。
  - 所以按更严的读法做了：不认「只在自己分支上」。测试 T1 / T6 就是按这个写的。要放开，等 Zack 说。

### run1（08:23）在新规则下的那 4 个

只读核对：`git merge-base --is-ancestor` 加 `git branch -r --contains`，用的是本地远端引用，没 fetch，没改任何分支；PR 的 base 和 head 用 `gh pr view` 查。

| PR | 工作区（已被 run1 删） | HEAD | PR base | 在 origin/staging | 在 origin/main | 在自己已推送的分支 |
|---|---|---|---|---|---|---|
| site（deepvision-site）#60 | site / dv运维-CI-自动部署 | dc83d86 | staging | 在 | 在 | 在（zhongc1211/dv-ci-deploy） |
| site #61 | site / dv官网-AGENTS-测试规矩 | dcb3eb3 | staging | 在 | 在 | 在（zhongc1211/dv官网-AGENTS-测试规矩） |
| site #75 | site / dv运维-FDV-78-EverOS-走-tailnet | 1748c32 | staging | 在 | 不在 | 在（zhongc1211/dv运维-FDV-78-everos-tailnet） |
| xinyue-site #89 | xinyue-site / 心月-PER-54-文档合并与-feed-monster-排查 | f261e48 | staging | 在 | 不在（`feat/xinyue-site`、`main` 都不在） | 在（fix/feed-monster-wait-for-fresh-tray） |

- 4 个的 HEAD 都在 origin/staging 上。
- 按新规则，它们都不会再因为「PR #N 的 head」放行。
- 但 #60、#61 的 HEAD 现在也在 origin/main 上：site 的 origin/main 最后一次提交是 10-20 18:56，早于 run1。所以按现在的本地引用，这两个照样会过 W17（「在 origin/main」），真正会被挡住的是 #75 和 #89。
- run1 当时本地 origin/main 是什么状态，日志里没有记录，查不到。
- 这 4 个 PR 的 head 仓库 owner：site 的是 futuredeepvision，xinyue-site 的是 zhongc1211。

### 原来 R6.md 里「W17 不改代码」那条

已被 11:15 的补充取代，所以改了代码。dr eggbot 评审里提到的「心月-CI-CD-第二阶段 #88 合进 staging」照旧是 SKIP W17。

## 测试（假 orca / 假 gh，测试替身，不算 E2E）

命令：`WS_TEST_BASH=<bash> <bash> scripts/tests/ws-cleanup-test.sh`，iMac。

| 被测脚本 | bash | 结果 |
|---|---|---|
| 9ce6a53 | 3.2.57 | 213/213 通过 |
| 9ce6a53 | 5.3 | 213/213 通过 |
| 06f9cc8（R5 的代码） | 3.2.57 | 198/213，15 个失败 |

- 比 R5 多了 14 个检查：S1–S6、S8、S10、S12、T1（2 个）、T2、T4（2 个）。
- 旧代码上挂的 15 个里：
  - 12 个是新行为：S1–S6、S8、S10、S12、T1 两个、T2；
  - 3 个（P7、P9、P10）结论一样，都是 SKIP W17，只是 W17 的原因文字换了，断言跟着改了。
  - T4 在旧代码上也过，这是对的。
- S11（主仓库路径不在）只改了代码，没有能走到那里的假数据，没加用例。
- 产物：`reports/ws-cleanup-rework-r6/tests/`。

## iMac 全量 dry-run（真实环境，只读）

- 命令：`<bash> scripts/ws-cleanup.sh --out <dir> --no-issue-reviews reports/no-issue-review`，在 9ce6a53 上跑。
- 11:38 用 `/bin/bash`（3.2）跑一次，11:43 用 `/usr/local/bin/bash`（5.3）跑一次。两次退出码都是 0，stderr 为空。
- 产物：`reports/ws-cleanup-rework-r6/imac/`；逐行对比在 `imac/compare-r5.md`。

| | R5（10:34，3.2） | R6（11:38，3.2） | R6（11:43，5.3） |
|---|---|---|---|
| RM | 0 | 0 | 0 |
| BACKUP_RM | 3 | 0 | 0 |
| SKIP | 92 | 96 | 97 |
| LIST | 1 | 2 | 1 |
| 合计 | 96 | 98 | 98 |

和 R5 的逐行差异（3.2 对 3.2）：

| 工作区 | R5 | R6 | 原因 |
|---|---|---|---|
| xinyue-site / auto-run-1-20261013T1530 | BACKUP_RM W19 | 没有 | run2 11:07 删了 |
| xinyue-site / docs-lessons-to-everos | BACKUP_RM W19 | 没有 | run2 删了 |
| xinyue-site / nightly-xinyue-site | BACKUP_RM W19 | 没有 | run2 删了 |
| ws-cleanup-drill / 主工作区 | 没有 | SKIP W1 | 演练仓库，R6 新建 |
| ws-cleanup-drill / h2-late-head | 没有 | SKIP W8 | 演练后留下的（有未推送提交） |
| ws-cleanup-drill / h3-gh-fail | 没有 | SKIP W9 | 演练加的 GitHub remote 是不存在的仓库，gh 查不到 |
| ws-cleanup-drill / h4-after-backup | 没有 | SKIP W8 | 演练后留下的（钩子提交的） |
| ops / ops-PER126-p2-sampler | 没有 | LIST W16 | 11:40 别的会话新建，那时还只在 git 里；5.3 那次已在 Orca 里，SKIP W5 |
| xinyue-site / auto-run-2、per-49-check-only、心月-CI-CD-第二阶段、xy-combined-src；deepvision-ads / r2-F；site / dv官网-FDV-60-套餐对比 | SKIP W17 | SKIP W17 | 只是原因文字换了 |

- 没有哪个工作区因为新的 W17 改判：现在没有靠「合进 staging 的 PR」过 W17 的。
- W9 17 个，W19 5 个，状态冲突 12 个。
- 4 个 W12 的（ops-PER-67-e2e-imac 等）还没满 24 小时。
- 3.2 和 5.3 两次只差 ops-PER126-p2-sampler 那一行，其余行除随时间变的列外一样。

## ③ 真 Orca 演练

- 建法：
  - 新建 `~/ops-drill`：本地 bare origin 加 `ws-cleanup-drill` clone；
  - 用 `orca repo add` 注册成单独的 Orca 项目（repo id `13a60bf6-f713-4397-ba4b-0729dafa93f3`，project id `repo:13a60bf6-f713-4397-ba4b-0729dafa93f3`，显示名 ws-cleanup-drill）；
  - 4 个演练工作区放在 `~/ops-drill/wt-r6/`，审查记录在 `~/ops-drill/reviews-r6/`。
- 在 9ce6a53 上跑：`scripts/tests/ws-cleanup-drill.sh init`，再用 `DRILL_TAG=r6` 跑 `r6-setup`、`r6-dry`、`r6-exec`、`r6-post`。
  - 每个用例单独跑一次 `--execute`。`--only-from` 只含这一行演练工作区，执行前先检查 id 和路径。
  - 每次都带 `--repo 13a60bf6-…`；`WS_ARCHIVE=~/ops-drill/archive-r6`，`WS_IDLE_H=0`。
- dry-run（3.2、5.3）：4 个都是 BACKUP_RM W19，两次一样。
- 产物：`reports/ws-cleanup-rework-r6/drill/`，说明在 `drill/README.md`。

| 用例 | `--execute` 结果 | 退出码 | 产物 |
|---|---|---|---|
| 1 没挂 Linear、DELETE_OK、HEAD 对得上（h1-review-ok） | 已备份再 rm。journal：backup 0 → recheck 0「没变化」→ rm-end ok。MANIFEST 有 `NO-ISSUE-REVIEW.md` 和 `.orca-task/BRIEF.md`，校验 OK | 0 | `drill/c1-execute*`、`drill/manifests/h1-review-ok.MANIFEST.sha256` |
| 2 dry-run 后 HEAD 变了（h2-late-head） | 「跳过：名单里是 BACKUP_RM，这次判定 SKIP W8」，没备份，没 rm | 0 | `drill/c2-execute*` |
| 3a gh 除 `auth status` 外都失败（h3-gh-fail，先给演练仓库加了一个从没 fetch 的 GitHub remote） | 「跳过：…这次判定 SKIP W9（PR 查不到（gh repo view …））」，没备份，没 rm | 0 | `drill/c3a-execute*`、`drill/gh-fail-a.sh` |
| 3b gh 全部失败 | 「环境不对：gh 不可用（gh auth status 失败）。--execute 什么都没做」 | 5 | `drill/c3b-execute*`、`drill/gh-fail-b.sh` |
| 4 备份期间被改（h4-after-backup，钩子在备份后提交一次） | 「已备份到 …；跳过：备份后复查有变化（结论 BACKUP_RM W19→SKIP W8；HEAD 240f835→0155ab3；未推送 0→1；…），没 rm，备份留着」。journal：backup 0、recheck 1，没有 rm-start。备份 MANIFEST 校验 OK | 0 | `drill/c4-execute*`、`drill/hook-c4.sh`、`drill/manifests/h4-after-backup.MANIFEST.sha256` |

- 用例 3 原本要的是「`WS_GH` 指向一直失败的 gh → SKIP W9」。但脚本 `--execute` 开头会先跑 `gh auth status`，gh 全失败时整轮在开头就以退出码 5 停下，走不到 W9。所以拆成了 3a、3b 两次。
- 用例 4 要设 `WS_ORCA`（钩子只在测试模式下认），设的就是真 orca 的路径。
- 别的工作区：
  - 演练仓库以外的 Orca 工作区前后都是 92 个，排序后 id 列表的 sha256 一样（`drill/before-others.txt`、`after-others.txt`）；
  - 演练仓库里只少了 h1-review-ok（`before-` / `after-orca-worktree-list.tsv`）；
  - 演练里没关过终端。

## ② PR #73 描述

- 只用了 `gh pr edit 73 --body-file reports/ws-cleanup-results/PR73-BODY-R6.md`。改完 PR 仍是 draft，线上 body 和文件一致（只差末尾换行）。
- 新描述删了「没有任何一次调用带 `--execute`」「`--execute` 这条路径…没验证过」「55/55 通过」和 aeb576b 的旧数字，也删了 claude.ai 会话链接。
- 新描述加了：
  - 规则版本 R1–R6 和 10:57 定稿；
  - W17 现在的口径和没实现的那半句；
  - run1、run2 两次真 `--execute` 的事实；
  - R6 dry-run 的数字；
  - 「为什么安全」；
  - E2E、演练、日志、RESULT 的路径。
- 历史提交里的会话链接没动，没改写历史。新提交按要求的署名格式还带 `Claude-Session` 行。
- 旧描述存在 `reports/ws-cleanup-results/PR73-BODY-before-R6.md`，新描述在 `PR73-BODY-R6.md`，diff 在 `PR73-BODY-R6.diff`。diff 如下：

```diff
@@ 删掉的段落 @@
-规则按 Zack 10-21 01:43 定的版本 …… 这个 PR 里没有任何一次调用带 `--execute`，也没挂到 ops·11，没改任何 automation。
-完整说明在 `reports/ws-cleanup-dryrun-1021/RESULT.md`。第 1 节失败方式清单是写代码之前提交的（0b11d67）。
-## dry-run 结果（iMac RM 41、BACKUP_RM 9、SKIP 73、LIST 1；MBA LIST 34；和审计报告逐条对照）
-## 只读证明（跑前跑后的 orca JSON、git worktree list 对比）
-## 跑了什么（55/55 通过；aeb576b 上的 dry-run；MBA ssh 跑法）
-## 没跑（`--execute` 这条路径……没写成用例，也没验证过；box）
-## 要 Zack 看的（RESULT.md 第 4 节的 5 条建议）
-（会话链接）
@@ 新加的段落 @@
+开头：默认 dry-run；`--execute --only-from` 才备份和 rm，不加 --force；终端要另加 --close-terminals
+## 规则版本（01:43 底稿，R1–R6，10:57 定稿，11:15 W17 口径，没实现的那半句）
+## 已经真跑过的 `--execute`（run1 08:23 删 32、13 个先备份、12 个没挂 Linear；W17 那 4 个；run2 11:07 删 3）
+## 现在的 dry-run（R6，iMac，只读）（3.2 / 5.3 的计数表，和 R5 比）
+## 为什么安全（iMac、--only-from、锁、动手前复查、备份后复查、先备份、不加 --force、rm 不重试、查不到就跳过）
+## 验证（E2E：iMac dry-run、真 Orca 演练 4 个用例、run1/run2 日志；替身用例 213 个另列，不算 E2E；RESULT 在 reports/ws-cleanup-results/）
+## 要 Zack 定的（W17 那半句；演练项目清理）
```

逐行的完整 diff 在 `reports/ws-cleanup-results/PR73-BODY-R6.diff`（106 行）。上面是按段落缩写的，方便看。存档的旧描述和 diff 里，会话链接那一行换成了「（会话链接，存档时已去掉）」，其余是原文。

## ④ 评审建议

| # | 建议 | 做了没 | 说明 |
|---|---|---|---|
| 1 | main_branches 用 defaultBranchRef | 没做 | 大改动，R6.md 说可以不做 |
| 2 | `--limit 100` 会截断 | 做了 | 正好拿到 `--limit` 条就当作查不到，SKIP W9（S10） |
| 3 | 主仓库路径不在时 remotes 是 [] | 做了 | 改成 None，`prs_for` 抛 QueryFail，SKIP W9（S11，没有用例） |
| 4 | PR 描述写清 W17 的 staging 行为 | 做了 | 11:15 后改成新口径写进描述 |
| 5 | 权限测试按平台 | 做了 | `mode()` 在 macOS 用 `stat -f %Lp`，别处用 `stat -c %a`；只在 iMac 上跑过，没在 GNU 系统上跑 |
| 6 | 锁目录只有 pid 时才 rmtree | 做了 | 拿锁时清旧锁、结束时释放锁，都先检查目录里只有 pid；不是就退出码 6、不删（S12） |
| 7 | 审查记录由另一个会话写 | 没做 | R4 的 18 份记录是本会话写的，这轮没要求重写；以后再有审查记录，可以派给别的会话 |
| 8 | 去掉 claude.ai 链接 | 部分 | PR 描述里去掉了；提交信息按署名要求还带，历史没改 |
| 9 | RESULT 不在分支里 | 做了 | RESULT-R1..R6 和 dr eggbot 评审复制到 `reports/ws-cleanup-results/` |

## 留着没清的

- Orca 项目 `ws-cleanup-drill`（repo id `13a60bf6-f713-4397-ba4b-0729dafa93f3`）：主工作区，加 h2-late-head、h3-gh-fail、h4-after-backup 三个演练工作区，没开终端。
- `~/ops-drill/`：
  - `origin.git`、`ws-cleanup-drill`（多了一个指向不存在仓库的 `github` remote）；
  - `wt-r6/`、`reviews-r6/`；
  - `archive-r6/`，里面有 h1、h4 的备份。
- 清理要 Zack 卡片。办法：在 Orca 里删 ws-cleanup-drill 这个项目，再 `rm -rf ~/ops-drill`。

## 没跑的

- 真实工作区的 `--execute`、`--close-terminals`：按规矩没跑。
- 演练里的 `--close-terminals`：演练工作区没有终端，没跑。
- GNU 系统上的权限测试：没有这样的机器，没跑。
- MBA：这轮没要求，没跑。

## 要 Zack 定的

1. W17 要不要加「HEAD 在工作区自己已推送的分支上也算」。现在没加。加的话，没合并、只推送过的工作区也能删，run1 那 4 个也会放行。
2. 演练项目和 `~/ops-drill` 什么时候清。
3. 之前几轮留下的事项照旧：W11 状态冲突 12 个、R3 的三个 `worktree-ps-*.json`。

## head

这份副本提交之前的 head 是 2f53765848d661054e1251e96e1c498e28dfb073；副本所在的提交见 `git log -- reports/ws-cleanup-results/RESULT-R6.md`。
