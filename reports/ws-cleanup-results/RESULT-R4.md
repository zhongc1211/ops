# PER-139 R4 结果（Zack 10-21 09:18：没挂 Linear 的工作区，要有模型审查记录才放行）

## 结论

- 代码和 18 份审查记录已推到 `zhongc1211/ops-ws-cleanup-script`。PR #73 仍是 draft，head 是 `2a751df36af7f07b851dd8c410b8693b52b61865`。
  - 脚本改动在 1693ad3。2a751df 只加了审查记录和报告。
- 18 个里，12 个 DELETE_OK，6 个 KEEP。
- **按现在的 dry-run，删除名单是空的。** 12 个 DELETE_OK 都过了 W19，但都被后面的规则挡住了（W11、W12、W17），见下面的表。
- 没跑 `--execute` 和 `--close-terminals`，PR 上没发评论，也没用 force 推送。

## 改了什么

- 默认行为不变：W19 一律 SKIP。
- 新参数 `--no-issue-reviews DIR`：读 `DIR/<repo 显示名>/<工作区目录名>.md`。下面三条都满足才放行：
  - 记录里的 `PATH:` 是这个工作区；
  - 只有一行 `VERDICT: DELETE_OK`；
  - `HEAD:` 是 40 位 sha，并且和现在的 HEAD 一样。
- 不放行的都判 SKIP W19，原因写明是哪一种：没有记录、结论是 KEEP、格式不对、PATH 不对、HEAD 不一样。
- `--execute` 复查时会再判一次。dry-run 之后 HEAD 变了，或者记录被改了，都会跳过，不备份也不 rm。
- 放行的工作区照样过后面每一条规则（W10 之后、W11、W12、W17、W13 里的嵌套 git 和非普通文件）。全部通过的才判 BACKUP_RM W19，不会判成普通 RM。
  - 备份里会多一份 `NO-ISSUE-REVIEW.md`：记录原样复制，权限 600，写进 MANIFEST。
  - 目录已不在的也走 BACKUP_RM，这时备份里只有这份记录。
- worktrees.tsv 加了 `review` 列。summary.md 多一行放行个数。DIR 不是目录时退出码 2。
- 失败方式 R1–R13 先写进 `reports/ws-cleanup-rework-r1/FAILURE-MODES.md` 最后一节，然后写用例，最后写代码。

## 测试（假 orca / 假 gh，测试替身，不算 E2E）

命令：`WS_TEST_BASH=<bash> /bin/bash scripts/tests/ws-cleanup-test.sh`，在 iMac 上跑。被测脚本的 blob 是 a25a3ad，和 1693ad3 里的一样。

| 被测脚本 | bash | 结果 |
|---|---|---|
| 1693ad3 | 3.2.57 | 185/185 通过 |
| 1693ad3 | 5.3 | 185/185 通过 |
| 3fdf19a（R3 的代码） | 3.2.57 | 134/185，51 个失败 |

- 比 R3 多了 17 个用例，派活要的四种都在里面：
  - 没有记录（R1）；
  - KEEP 记录（R2）；
  - DELETE_OK 且 sha 对得上：dry-run 判 BACKUP_RM（R3、R6），`--execute` 真的备份并 rm（R11，检查记录进了备份、权限 600、在 MANIFEST 里、内容逐字节一样）；
  - DELETE_OK 但 sha 过时：dry-run 时就过时（R4）；dry-run 之后 HEAD 变了（R9）；dry-run 之后记录被改成别的 sha（R10）。R9、R10 都是跳过，没有 rm 调用。
  - 另外还测了：状态 in-review 的照样被 W11 挡住（R5）、格式不对（R7）、PATH 写的是别的工作区（R8）、不带参数时照旧 SKIP（R12）、目录不存在时退出码 2（R13）。
- 3fdf19a 上失败的 51 个：旧代码不认 `--no-issue-reviews`，带这个参数的 dry-run 和 `--execute` 都是退出码 2。所以挂掉的是全部 R 用例，加上整个 `--execute` 段。不带参数的那些用例都过了。
- 没有测：目录已不在、审查放行的工作区在 `--execute` 下的情况。dry-run 下测过（R6）。备份清单为空时，代码走的是和 R11 相同的路径。
- 产物：`reports/ws-cleanup-rework-r4/tests/`。

## iMac 全量 dry-run（真实环境，只读）

- 命令：`<bash> scripts/ws-cleanup.sh --out <dir> --no-issue-reviews reports/no-issue-review`。
- 09:37 用 `/bin/bash`（3.2）跑一次，紧接着用 `/usr/local/bin/bash`（5.3）跑一次。
  - 两次退出码都是 0，stderr 为空。
  - worktrees.tsv 都是 96 行，除 idle_h 外逐行一样。
  - terminals.tsv 都是 20 行，前 8 列排序后一样。
- 产物：`reports/ws-cleanup-rework-r4/imac/`；和 R3 的逐行对比在 `imac/compare-r3.md`。

| 真实工作区 | R3（08:55） | R4（09:37） |
|---|---|---|
| RM | 0 | 0 |
| BACKUP_RM | 0 | 0 |
| SKIP | 95 | 95 |
| LIST | 1 | 1 |
| 合计 | 96 | 96 |

- 有变化的 18 行都是 R3 的 W19，其余 78 行逐行一样。没有新出现的工作区，也没有消失的。
- 判成 W19 的：R3 是 18 个，R4 剩 6 个，就是那 6 个 KEEP。
- 状态冲突从 11 个回到 14 个。原因是 auto-run-1、ops-PER-84-everos-docs、xinyue-site-cicd 过了 W19 以后又停在了 W11。
- 终端：20 个，全部 SKIP。
- planned 不为空的行（真跑 `--execute` 会动的）：0 个。

## 18 个工作区

| 工作区 | 结论 | 理由（一句） | R4 dry-run |
|---|---|---|---|
| ops / ops-PER-67-e2e-imac | DELETE_OK | 没有自己的提交，HEAD 在 origin/main，干净，completed | SKIP W12（18:15 后到 24 小时） |
| ops / ops-PER-84-everos-docs | DELETE_OK | HEAD 是已合并的 PR #47 的 head，在 main，干净 | SKIP W11（in-review） |
| ops / ops-PER80-drill-gap9 | DELETE_OK | 演练工作区，HEAD 在 main，干净，completed | SKIP W12（19:23 后到 24 小时） |
| ops / ops-PER82-stuck-budget | DELETE_OK | 备注写明没用上、可删，HEAD 在 main | SKIP W12（20:28 后到 24 小时） |
| ops / ops-box-decommission-inventory-1021 | KEEP | box 停用清单还在等 Zack 回 5 项，这个工作区和 BRIEF 是唯一记录 | SKIP W19 |
| ops / ops-unpushed-nested-1020 | KEEP | 同一件事的 PR #57（以及 #45）还开着，返工多半在这里做 | SKIP W19 |
| ops / xinyue-everos-recheck | KEEP | 备注里「补写待 Coding助手 定」还没定，结论只在 Orca 备注里 | SKIP W19 |
| site / ops-per83-verify-dv-site | DELETE_OK | PER-83 对照验证已验收，HEAD 在 main，被忽略的都能重建 | SKIP W12（19:42 后到 24 小时） |
| vllm-omni · H3/C1 / per-8714-schedule-400 | KEEP | 上游 PR #8714 还开着，且已 rebase，这里的 HEAD 不在 PR 现在的历史里；analysis/ 约 756 KB 不在 git 里 | SKIP W19 |
| xinyue-site / auto-run-1-20261013T1530 | DELETE_OK | HEAD 是已合并的 PR #76 的 head | SKIP W11（in-progress） |
| xinyue-site / auto-run-2-20261013T1725 | DELETE_OK | 内容已合进 main（d7ed5b9 的 patch-id 和它一样），原提交也在远端分支上 | SKIP W11（in-progress） |
| xinyue-site / docs-lessons-to-everos | DELETE_OK | 工作已转到 box，经 PR #92 合进 main，这里没有提交 | SKIP W11（sleep） |
| xinyue-site / 心月-CI-CD-第二阶段 | DELETE_OK | HEAD 是 #86 合进 staging 的提交，第六阶段已验收 | SKIP W17（staging 不算主分支） |
| xinyue-site / 心月-EverOS-启动器-v2.1 | KEEP | 还在等 Coding助手 验收，这个工作区是唯一跟踪 | SKIP W19 |
| xinyue-site / 心月-生产-Builds-接入 | KEEP | 卡在等 Zack 三选一，方案只记在 Orca 备注里 | SKIP W19 |
| xinyue-site / xinyue-site-cicd | DELETE_OK | HEAD 是已合并的 PR #84 的 head，已被第二阶段工作区取代 | SKIP W11（in-review） |
| xinyue-site / nightly-xinyue-site | DELETE_OK | 目录已不在，HEAD 是合并 PR #76 的提交，在 origin | SKIP W11（in-progress） |
| xinyue-site / xy-combined-src | DELETE_OK | 目录已不在，HEAD 已在 origin/backup/xy-combined-src-36c6f4b | SKIP W11（in-progress） |

- 记录在 `reports/no-issue-review/<repo>/<工作区>.md`。repo 目录是 `ops`、`site`、`xinyue-site`、`vllm-omni_H3_C1`，和脚本里的 safe_name 规则一样。
- 每份记录有：路径、分支、完整 HEAD、远端哪里有这个 sha、未推送提交数、未跟踪和被忽略的文件、最后活动时间、做的是什么，以及 `VERDICT:` 行加一段理由。
- 写记录前，每个工作区都重新读了现在的 HEAD，和 R3 的 TSV 对过。dry-run 里 12 个 DELETE_OK 都没报 HEAD 不一样。
- 记录里没有邮箱，没有密钥类字样。没读 .dev.vars、*.env 和凭据文件。

## 删除名单

**现在是空的。** 12 个 DELETE_OK 都被后面的规则挡住：
- 4 个 W12（最近 24 小时内有活动）：ops-PER-67-e2e-imac、ops-PER80-drill-gap9、ops-PER82-stuck-budget、ops-per83-verify-dv-site。
  - 它们都是 completed，HEAD 在 main 上。
  - 今天 18:15、19:23、20:28、19:42 之后，各自满 24 小时。这四个时间都是 Orca 记录的最后活动时间加 24 小时。
  - 到时候重跑 dry-run，按现在的数据会是 BACKUP_RM W19。这是推出来的，没有跑过。前提是 HEAD 不变，状态也不被改。
- 7 个 W11（Orca 状态不是 completed）：ops-PER-84-everos-docs、auto-run-1、auto-run-2、docs-lessons-to-everos、xinyue-site-cicd、nightly-xinyue-site、xy-combined-src。要把状态改成 completed 才会往下判。我没改。
- 1 个 W17：心月-CI-CD-第二阶段。HEAD 在 origin/staging，staging 不算主分支或合并目标分支。

## 顺带发现的

- per-8714-schedule-400：脚本的 W9 没认出上游 PR #8714 还开着。
  - 原因是 PR 从 fork 的 `diffusion-attention-schedule-config` 分支开，而工作区分支叫 `zhongc1211/per-8714-schedule-400`，按分支名查不到。
  - 本地的 fork 跟踪引用也是过时的，所以「未推送 0」只是相对那个旧引用算出来的。
  - 这一次靠审查记录 KEEP 挡住了。这个漏洞没改，因为不在这次派活范围里。

## 没跑的

- 真实工作区的 `--execute`、`--close-terminals`：按规矩没跑。
- 真 Orca 演练：没重跑，`--no-issue-reviews` 只有假 orca 用例。
- MBA：这次派活没要求，没跑。

## 要 Zack 定的

1. 7 个 W11 的 DELETE_OK 工作区，要不要在 Orca 里改成 completed。不改的话，它们会一直停在 W11。
2. 心月-CI-CD-第二阶段：要不要把 staging 算进 W17 的合并目标。不算的话，它会一直停在 W17。
3. 上面 per-8714 的 W9 漏洞要不要另开一轮修。
4. R3 遗留的三个 `worktree-ps-*.json` 怎么处理，还没定。
