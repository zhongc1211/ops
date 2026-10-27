# PER-139 R5 结果（安全修复：fork 上换了分支名开的 PR，W9 看不到）

## 结论

- 已修好并推到 `zhongc1211/ops-ws-cleanup-script`。PR #73 仍是 draft，head 是 `a1cac54c1be1bb4d2465ac635061d3f8547a5939`。
  - 脚本改动在 5e19598，a1cac54 只加了报告。
  - 推送没有用 force。
- per-8714-schedule-400 现在由脚本自己判成 SKIP W9「PR 还开着」，pr 列是 #8714 OPEN，不再靠审查记录的 KEEP 挡。
- 和 R4 比，本次改动没有让任何工作区变得可以删，只把 4 行从别的 SKIP 规则改判成 SKIP W9。
- 这次 dry-run 里有 3 个 BACKUP_RM（R4 是 0 个）。原因是 09:37 之后有人在 Orca 里把它们的状态改成了 completed，不是本次改动造成的，也不是我改的。见下面「删除名单」。
- 没跑 `--execute` 和 `--close-terminals`，PR 上没发评论。

## 改了什么

改的是 `prs_for`。原来只按工作区分支名和 linkedPR 查。现在 HEAD 不在任何远端主分支上时，再加两路查询：

1. **按远端分支名查。** 对每个包含 HEAD 的远端分支，例如 `fork/diffusion-attention-schedule-config`，到所有相关仓库执行 `gh pr list --head <分支名> --state all`。
   - 只认 `headRepositoryOwner` 等于那个 remote owner 的 PR。
   - 只看 fetch URL 是 GitHub 的 remote。
2. **按 HEAD sha 查。** 对所有相关仓库执行 `gh pr list --search <sha> --state all`。

查询失败时的处理：
- 两路里任何一次 gh 调用失败，都判 SKIP W9「PR 查不到（…）」。
- 找出包含 HEAD 的远端分支的 git 命令失败，也判 SKIP W9。

在真实 GitHub 上核对过：
- 按 sha 搜 c92d061（8714 工作区的 HEAD），上游和 fork 都返回空。PR rebase 过，这个提交已经不在 PR 里了。
- 按 fork 分支名查，能查到 #8714 OPEN、owner 是 zhongc1211。
- 所以只按 sha 搜挡不住 8714，起作用的是第 1 路。

第一次真实 dry-run 后又补了两条限制：
- **P10：** 新查法查到的 open PR，如果本地有它目标分支的远端分支，而且那个分支已经包含 HEAD，就不算。
  - 原因：按 sha 搜，会搜到 xinyue-site 指向 staging 的 #99、#101–#106。aa526b5 早在 origin/staging 上，这些 PR 和这些工作区无关。
  - 本地没有目标分支的，照样算开着。
- **P2：** 新查法查到的 PR 只用来挡（W9），不当作 W17 的已合并证据。
  - 原因：第二次真实 dry-run 里，sha 搜索查到了已合并到 staging 的 #88，它的 head 包含 aa526b5。结果 心月-CI-CD-第二阶段 过了 W17，从 SKIP 变成了 BACKUP_RM。
  - 这次派活是安全修复，不该多放行，所以改成只挡不放。要放开的话，改一行就行，等 Zack 定。

失败方式 P1–P10 先写进了 `reports/ws-cleanup-rework-r1/FAILURE-MODES.md`。P10 和 P2 的改动是真实 dry-run 发现问题后补写的，那一节里注明了。

## 测试（假 orca / 假 gh，测试替身，不算 E2E）

命令：`WS_TEST_BASH=<bash> /bin/bash scripts/tests/ws-cleanup-test.sh`，在 iMac 上跑。被测脚本的 blob 是 fc796d6，和 5e19598 里的一样。

| 被测脚本 | bash | 结果 |
|---|---|---|
| 5e19598 | 3.2.57 | 199/199 通过 |
| 5e19598 | 5.3 | 199/199 通过 |
| 2a751df（R4 的代码） | 3.2.57 | 192/199，7 个失败 |

- 比 R4 多了 14 个检查，派活要的三种都在里面：
  - fork 上换了分支名的 open PR（P1：PR 已 rebase，head 不是 HEAD）→ SKIP W9；
  - fork 上换了分支名的已合并 PR（P2）→ 不算 open，记进 pr 列，但不给 W17 放行，结果 SKIP W17；
  - 查询失败：按分支名查失败（P3）、按 sha 搜失败（P4）→ 都是 SKIP W9「PR 查不到」。
- 另外还测了：
  - 只有 sha 搜索能找到的 open PR（P5）；
  - HEAD 已在 origin/main 时，不做新查询，不被后来基于 main 的 open PR 挡住，也没有多出 `--search` 调用（P6）；
  - 同名分支、但 owner 是别人的 PR 不算（P7）；
  - 目录已不在的工作区也走新查法（P8）；
  - 不是 GitHub 的 remote 不拿去查（P9）；
  - 目标分支已包含 HEAD 的 open PR 不算（P10）。
- R4 代码上挂的 7 个是 P1、P2、P3、P4、P5、P8、P10。P6、P7、P9 在旧代码上本来就过，因为旧代码根本不查这些。
- 没有测的：`--execute` 复查时 PR 状态变化的情况。复查走的是同一个 `safe_eval`，所以这次没加 x_ 用例。
- 产物：`reports/ws-cleanup-rework-r5/tests/`。

## iMac 全量 dry-run（真实环境，只读）

- 命令：`<bash> scripts/ws-cleanup.sh --out <dir> --no-issue-reviews reports/no-issue-review`。
- 10:34 用 `/bin/bash`（3.2）跑一次，10:39 用 `/usr/local/bin/bash`（5.3）跑一次。
  - 两次退出码都是 0，stderr 为空。
  - worktrees.tsv 都是 96 行，除 idle_h 外逐行一样。
  - terminals.tsv 20 行，全部 SKIP。
- 前两次 dry-run（10:12、10:24）跑的是修 P10、P2 之前的代码，结果已被覆盖，没进仓库。上面那两条限制就是从这两次的结果里发现的。
- 产物：`reports/ws-cleanup-rework-r5/imac/`；和 R4 的逐行对比在 `imac/compare-r4.md`。

| 真实工作区 | R4（09:37） | R5（10:34） |
|---|---|---|
| RM | 0 | 0 |
| BACKUP_RM | 0 | 3 |
| SKIP | 95 | 92 |
| LIST | 1 | 1 |
| 合计 | 96 | 96 |

- W9 从 12 个变成 16 个。
- 停在 W19 的（还有 KEEP 记录、没放行的）从 6 个变成 5 个。
- 状态冲突从 14 个变成 12 个。

### 本次改动造成的判定变化（都是 SKIP → SKIP）

| 工作区 | R4 | R5 | 新看到的 open PR |
|---|---|---|---|
| per-8714-schedule-400 | SKIP W19（靠 KEEP 记录） | SKIP W9 | 上游 #8714 |
| PER-56-n7-rootcause | SKIP W10 | SKIP W9 | 上游 #8746 |
| per-rebase-main-1017 | SKIP W10 | SKIP W9 | 上游 #8746 |
| per56-n10-rootcause-opus | SKIP W10 | SKIP W9 | 上游 #8746 |

- 另有 11 行规则没变，只是 pr 列多了新查到的 PR。其中多是 dv官网 的 FDV-70 系列：sha 搜索查到了 staging 上已合并的一串 PR，有 7 到 29 个。
- 心月-CI-CD-第二阶段 照旧是 SKIP W17，P2 的限制起了作用。

### 工作区本身变了造成的变化（不是本次改动，也不是我改的）

09:37 到 10:34 之间，Orca 里这 7 个工作区的状态被改成了 completed：
- auto-run-1、docs-lessons-to-everos、nightly-xinyue-site → BACKUP_RM W19（审查记录是 DELETE_OK，HEAD 对得上）；
- auto-run-2、xy-combined-src → SKIP W17；
- ops-PER-84-everos-docs → 还挂上了 PER-84，现在是 SKIP W12；
- xinyue-site-cicd → 照旧 SKIP W11（仍是 in-review）。

## 删除名单（真跑 `--execute --only-from` 会动的，这次没跑）

3 个，全部是 BACKUP_RM W19：

| 工作区 | 为什么能删 | 备份里有什么 |
|---|---|---|
| xinyue-site / auto-run-1-20261013T1530 | 审查 DELETE_OK；HEAD 是 PR #76 的 head（原来的查法查到的） | 只有 NO-ISSUE-REVIEW.md（没有被忽略的文件） |
| xinyue-site / docs-lessons-to-everos | 审查 DELETE_OK；HEAD 在 origin/feat/xinyue-site | 只有 NO-ISSUE-REVIEW.md |
| xinyue-site / nightly-xinyue-site | 审查 DELETE_OK；目录已不在，HEAD 2f7da6d 已在远端 | 只有 NO-ISSUE-REVIEW.md |

- 这 3 个能进名单，是因为有人把状态改成了 completed。审查记录是我 09:36 写的，HEAD 至今没变。
- 4 个 W12 的（ops-PER-67-e2e-imac 等）今天 18:15 之后才会满 24 小时，现在还是 SKIP W12。

## 没跑的

- 真实工作区的 `--execute`、`--close-terminals`：按规矩没跑。
- 真 Orca / 真 GitHub 演练：没做，新查法只有假 gh 用例和真实 dry-run。
- MBA：这次派活没要求，没跑。

## 要 Zack 定的

1. 新查法查到的已合并 PR，要不要也算 W17 的已合并证据？
   - 现在不算（推荐，安全修复只挡不放）。
   - 算的话，心月-CI-CD-第二阶段 会变成 BACKUP_RM，依据是 #88 已合并到 staging、head 包含 aa526b5。
2. 删除名单里的 3 个，要不要真跑 `--execute`？需要另外批准。
3. 之前几轮留下的事项照旧：W11 状态冲突、R3 的三个 `worktree-ps-*.json`。
