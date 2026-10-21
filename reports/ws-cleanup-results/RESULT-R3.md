# PER-139 R3 结果（Zack 10-21 08:44：没挂 Linear issue 的一律 SKIP）

## 结论

改好了，已推到 `zhongc1211/ops-ws-cleanup-script`，PR #73 仍是 draft，head `0d65612462de871971911ad55f475adc73c9f35e`。
- 脚本改动在 3fdf19a，0d65612 只加了报告和日志。
- 这一轮没跑 `--execute` 和 `--close-terminals`。run1 删掉的 12 个没恢复。PR 上没发评论。

## 核对 run1

`reports/ws-cleanup-exec-1021/imac/run1/worktrees.tsv` 里，result 是「已 rm」或「已备份…；已 rm」的共 32 个，其中 12 个 linear 列是空的，和派活说的一样：
- ops：everos-research、everos-vps-deploy、ops-everos-ingest-commit、ops-tunnel-flaps-1019-imac、xinyue-everos-tailnet、xinyue-night-review-guard
- site：dv官网-AGENTS-测试规矩
- xinyue-site：ops-everos-imac-mcp、pr83-merge、unpushed-cleanup-20261018、心月-AGENTS-对齐、xinyue-ci

run1 不是我跑的。日志里 cmd 是 08:22:59 开始，退出码 0。

## 改了什么

- 新规则 **W19**：Orca 里 `linkedLinearIssue` 为空或只有空白的，判 SKIP，原因以 `NO_LINEAR_ISSUE：` 开头。
- 位置：在 W9（PR 还开着）之后、W10（Linear 未关）之前。所以 PR 已合并、HEAD 在主分支、目录已不在（W4 rm）、要先备份（W13），都排在它后面，压不过它。
- `--execute` 复查走同一个判定。dry-run 时挂着 issue、动手前被摘掉的，结果是「跳过：重新判定变成 SKIP W19」，不会调 rm。
- summary.md 多一行「NO_LINEAR_ISSUE（W19）：n 个」。
- 顺手清理：W10 外面那层 `if ev["linear"]:` 现在必然成立，删掉了，行为不变。
- 失败方式先写进 `reports/ws-cleanup-rework-r1/FAILURE-MODES.md` 最后一节（N1–N8），再写用例和代码。

## 测试（假 orca / 假 gh，测试替身，不算 E2E）

命令：`WS_TEST_BASH=<bash> /bin/bash scripts/tests/ws-cleanup-test.sh`，在 iMac 上跑。

| 被测脚本 | bash | 结果 |
|---|---|---|
| 3fdf19a | 3.2.57 | 168/168 通过 |
| 3fdf19a | 5.3 | 168/168 通过 |
| d1602db（R2 代码） | 3.2.57 | 160/168，8 个失败 |

- R2 是 159 个，这次加了 9 个：
  - dry-run：c_nolin（HEAD 在 origin/main）、c_nolin_pr（有已合并的 PR #62）、c_nolin_gone（目录已不在）、c_nolin_backup（有要备份的文件）、c_nolin_blank（issue 是空白串）。这 5 个都要 SKIP W19、planned 为空。另外还查 summary 的计数、PR #62 确实被看到了。
  - `--execute` 复查：x_late_nolin。dry-run 时是 RM；在等待点把 issue 摘掉后，要跳过 W19，且没有 rm 调用。
- 原有的 RM / BACKUP_RM 用例都挂上了已关的 issue（PER-2；x 项目用 OKX-1）。不挂的话会全变成 W19，原来测的东西就测不到了。它们在 R2 代码上照样通过，说明挂 issue 没改变原来的结论。
- 在 R2 代码上失败的 8 个，都是新加的 N 用例。
- 产物：`reports/ws-cleanup-rework-r3/tests/`。

## iMac 全量 dry-run（真实环境，只读）

- 08:55 用 `/bin/bash`（3.2）、08:57 用 `/usr/local/bin/bash`（5.3）各跑一次。脚本 blob 6feb047，和 3fdf19a 里的一样。
  - 两次退出码 0，stderr 为空。worktrees.tsv 96 行逐行一样。
  - terminals.tsv 20 行，只有本任务所在终端（SKIP T3）的进程顺序不同。
- 产物：`reports/ws-cleanup-rework-r3/imac/`；和 R2 的逐行对比在 `imac/compare-r2.md`。

**合计**（R2 是 07:59 那次；演练仓库已在 08:3x 被清掉，R3 里没有）：

| 真实工作区 | R2 | R3 | 差 |
|---|---|---|---|
| RM | 19 | 0 | −19 |
| BACKUP_RM | 13 | 0 | −13 |
| SKIP | 95 | 95 | 0 |
| LIST | 1 | 1 | 0 |
| 合计 | 128 | 96 | −32 |

- 少掉的 32 个，正好是 run1 删掉的 32 个。R3 里没有新出现的工作区。
- 终端：R2 是 21 个，R3 是 20 个，全部 SKIP。
- 状态冲突从 14 个降到 11 个，有 3 个现在判成了 W19。
- 演练仓库：R2 有 25 个，R3 一个都没有（已清掉，见 `drill-cleanup.txt`）。

**判成 W19 NO_LINEAR_ISSUE 的：18 个。** R2 里它们都已经是 SKIP，所以这次删的数量不变，只是原因换了：
- 11 个原来是 W11（状态不是 completed，其中 3 个是「状态冲突」）：xinyue-site 的 auto-run-1、auto-run-2、docs-lessons-to-everos、心月-EverOS-启动器-v2.1、心月-生产-Builds-接入、xinyue-site-cicd、nightly-xinyue-site、xy-combined-src；ops 的 ops-PER-84-everos-docs、ops-box-decommission-inventory-1021、xinyue-everos-recheck。
- 5 个原来是 W12（最近有活动）：ops-PER-67-e2e-imac、ops-PER80-drill-gap9、ops-PER82-stuck-budget、ops-unpushed-nested-1020、site 的 ops-per83-verify-dv-site。
- 2 个原来是 W17（HEAD 不在已合并的地方）：心月-CI-CD-第二阶段、vllm-omni 的 per-8714-schedule-400。

**另外 1 行有变化，不是这次改动造成的**：ops-stuck-routing-1020 从 W18 回到 W9（PR 还开着）。它 gitdir 里那个陈旧的 `index.lock` 已经没了：07:59 之后被人删的，不是我。run1 的 summary 里 W18 也只剩演练仓库的 2 个。

**按新规则倒推 run1**（只是看 TSV 得出的，没有实际跑）：如果 run1 时已有 W19，删的就是 20 个而不是 32 个。那 12 个都会停在 W19，因为它们的 linear 列都是空的，而 W19 排在 W10 及以后各条之前。

## 日志提交情况

- 已提交 `reports/ws-cleanup-exec-1021/imac/` 下的：`run1/`（worktrees、terminals、backup-files、journal、summary）、`run1.cmd`、`run1.stdout`、`run1.stderr`、`run1.exit`、`drill-cleanup.txt`。
- 提交前扫过：
  - 没有未打码的邮箱（`page@<hash>.webm` 这类文件名不算邮箱）。
  - 没有 webhook、token、私钥、pair code 等字样。
  - `drill-cleanup.txt` 里只有「DRILL_FAKE fixtures」这几个字，是说明演练里假的 .dev.vars，不是密钥本身。
- 没提交 `worktree-ps-before.json`、`worktree-ps-after.json`、`worktree-ps-after-drill.json`：
  - 里面有没打码的邮箱，分别是 6、4、4 处，域名有 gmail.com、yahoo.com、deepvision.sg。
  - 还有别的会话的终端预览、prompt 和 agent 消息。
  - 它们仍在原处，没有进 git，我没动。要不要移到 `~/ops-archive/`（R1 的快照就放在那里），等 Zack 定。

## 没跑的

- 真实工作区的 `--execute`、`--close-terminals`：按规矩没跑。
- MBA list-only：这次派活没要求，没跑。
- 真 Orca 演练：演练仓库已被清掉，没重跑。W19 只有假 orca 用例。
- 注意：`scripts/tests/ws-cleanup-drill.sh` 建的演练工作区，除了 d16，都没挂 Linear。以后要重跑演练，得先给它们挂上已关的 issue，不然会全部停在 W19。这次没改那个脚本。

## 要 Zack 定的

1. 三个 `worktree-ps-*.json` 怎么处理：移到 `~/ops-archive/ws-cleanup-exec-1021-snapshots/`（推荐），还是直接删，还是留在原处。
2. 18 个 W19 的工作区里，有要清的话，先在 Orca 里给它们挂上 Linear issue。脚本不会替它们放行。
