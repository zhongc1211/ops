# PER-139 返工第 1 轮结果（PR #73，ws-cleanup.sh）

## 结论

- F1–F6 已按评审改完。
- Zack 03:26–03:40 的 6 条决定已并进本轮。
- 演练里发现 3 处问题（D1–D3），也已修好。
- 评审第 4 节的三条预期都对上了：
  - xy-combined-src 是 SKIP；
  - 7 个 CLOSE 终端一个都不关；
  - 8 个要补备份的里，6 个变成 BACKUP_RM，另外 2 个因为状态是 in-review 成了 SKIP。
- 和评审「同意删」不一致的 19 项都是变得更保守：没有一项从 SKIP 变成删。
- `--execute` 只在演练仓库 `~/ops-drill/ws-cleanup-drill` 上真跑过（两轮）。真实工作区没跑过 `--execute`，也没关过任何终端。
- 已推送到 `zhongc1211/ops-ws-cleanup-script`，PR #73 head 是 `5a6b8f8415f3cae01446458813e7a8de43136b97`，仍是 draft。脚本最后一次改动在 4165ac2，5a6b8f8 只加了报告。
- 五项证据评论：https://github.com/zhongc1211/ops/pull/73#issuecomment-6301266627

## 改了什么

代码在 `scripts/ws-cleanup.sh`，提交 5a280d7、4165ac2。失败方式先写在 `reports/ws-cleanup-rework-r1/FAILURE-MODES.md`，再改的代码。

- **F1 W4**：目录不在时，读 git 记录的那条 worktree 的 HEAD。
  - HEAD 读不到，或者不在远端、也没有别的 ref 包含 → SKIP。报告写出提交号和建议的备份分支名。
  - 原因列改成「rm 会删 Orca 记录和 git worktree 记录」。
- **F2 忽略文件**（按 Zack 03:26）：被忽略的文件默认整份备份，只排除一张构建产物 / 缓存清单。
  - 清单写在脚本里，可以用 `WS_REBUILD_DIRS` / `WS_REBUILD_FILES` 整张替换。
  - 嵌套 `.git`、或者有不是普通文件的 → SKIP W13。
  - 每个工作区会备份哪些文件，逐个列在 `backup-files.tsv`。
- **F3 终端**（按 Zack 03:29）：
  - 只关 git 工作区里、不是 main 的终端。folder、main、别的机器上的终端只列出（T8）。
  - 本任务所在工作区的终端都不关（T3）。
  - agent 自己的终端不关（T1）。同一工作区有 agent 时，配套 shell 空闲超过 12 小时才关；其余终端要超过 24 小时；没有 lastOutputAt 的不关。
  - 关之前先重新判定一次，再存档 scrollback、cwd、meta 和找回说明。存档失败就不关。
  - 关的时候不带 `--tab`。
  - `--execute` 默认不关终端，要另外加 `--close-terminals`。
- **F4**：每个工作区单独做异常处理，出错记 ERROR 再接着做下一个。TSV 和 summary 放在 finally 里写；journal.tsv 在每次备份和 rm 前后各写一行。
- **F5**（含 Zack 03:37）：每个工作区动手前，重新取 orca、终端、ps、git、gh、Linear 的实时数据，不用缓存。lastActivityAt、结论或备份清单有变化就跳过，并写原因。Linear 查询失败、超时或找不到 issue，都按不删处理。
- **F6**：PR 按分支逐个仓库查（`gh pr list --head`），没有 1000 条上限。
  - owner 同时认旧名和新名（`gh repo view` 跟随改名）。
  - linkedPR 在 fork 和上游都查。
  - 查询失败 → SKIP W9「PR 查不到」，不当成没有 PR。
- **第一次执行只做审过的名单**：`--execute` 必须带 `--only-from <dry-run 的 worktrees.tsv>`。只处理名单里、重新判定后结论不变的工作区。
- **状态不是 completed 的**：一律 SKIP W11。旧规则本来会删的，原因里写「状态冲突」，等 Zack 定（见下文）。
- **Zack 03:33**：新增 W17。HEAD 要等于已合并 PR 的 head，或者是它的祖先，或者在远端主分支 / 已合并 PR 的目标分支里；不满足就不删。Linear Done 只是前提。
- **Zack 03:39**：W10 没改。
- **Zack 03:40**：加 `--repo <repoId>` 白名单。名单里、或者要动的候选里，只要有一个不在这个 repo 下，整轮中止，退出码 2。
- **D1–D3**（演练第 1 轮发现，4165ac2 修）：
  - 名单里有、但已经变成 SKIP 的，result 写原因；名单里有、Orca 里已经没有的，journal 记 not-found。
  - rm 失败时，result 写 Orca 的 error.message。
  - 备份失败时，拷了一半的目录改名成 `.failed-<时分秒>`，不挡下一次。
- **MEDIUM / LOW 修了的**：
  - M1、M2：W11、W17 和 head_vs_pr 列。
  - M3：先检查 gh、Linear、diagnostics、worktree ps，有一个不能用，`--execute` 什么都不做，退出码 5。gh 在 `/usr/local/bin` 和 `/opt/homebrew/bin` 都找。
  - M4：hostname 必须正好是 iMac 才能 `--execute`。
  - M5：`--precheck` 固定 exit 1；加了 mkdir 锁，被占用时退出码 6。
  - M7：加了 comment（掩码后）、unread、head、head_vs_pr、merged_via、backup_size、rebuild 几列。
  - L1：`--dry-run` 照收。
  - L2：原因列里不再写小时数。
  - L3：原位置的 .dev.vars 不删。
  - L4：备份目录名去掉特殊字符。
  - L5：备份用列表，不再拼字符串再拆。
  - L6：工作区里有打开的终端 → W6 SKIP。
  - L7：默认输出改到 `~/ops-archive/ws-cleanup/reports/`。
  - L9：journal 记录 Orca rm 返回的 JSON（前 300 字）。

## 没修的

- **M6**：agent-probe 按当前目录找 agent，没有接进来。只把 `orca worktree ps` 的 agents 当作第二个来源；ps 不可用时 SKIP。不在 Orca 终端里跑的 agent 仍可能识别不到。原因：agent-probe 的输出格式和超时要另外核对，这轮没做。
- **W8 reflog**：工作区 HEAD 的 reflog 里有、但 HEAD 已经离开的提交，没算进「未推送」。原因：会让很多正常的 rebase 工作区被挡住，需要先定口径。
- **L8**：MBA 走 ssh 时 python 版本的文档说明，没改。脚本在 3.9.6 下能跑，这次 MBA 两次 list-only 都正常。
- **L9 后半**：Orca 删没删分支，没写进 TSV，只在 journal 里。
- **文档里的 `--worktree <selector>`**：没实现。用 `--only-from` 和 `--repo` 代替。
- **F6 剩下的一处**：本地分支名和远端 PR 的分支名不同时（per-8714：本地 `zhongc1211/per-8714-schedule-400`，PR 在 `fork/diffusion-attention-schedule-config`），W9 查不到这个 PR。这次 W17 兜住了，是 SKIP。原因：要按 upstream 跟踪分支和「包含 HEAD 的远端分支」再查一轮，这轮没做。
- **comment 列里的邮箱**：脚本只掩码 URL 和长串，没掩码邮箱。iMac 有一个工作区的 Orca 备注里有半个管理员邮箱。提交进仓库的报告副本里，我把邮箱手动换成了 `<email>`（8 个文件），脚本没改。建议下一轮在 mask() 里加上。
- **演练发现的两点**（详见 `reports/ws-cleanup-rework-r1/drill.md`）：
  - 工作区根目录下被忽略的 FIFO，git 不会列出，所以照样判 RM。FIFO 不存数据，删了不丢东西。
  - 被 `git worktree lock` 的工作区，dry-run 照样判 RM / BACKUP_RM；rm 时 Orca 会拒绝，不会丢东西。可以让 dry-run 直接 SKIP。

## 测试

假 orca / 假 gh 用例：`scripts/tests/ws-cleanup-test.sh`，140 个。
- bash 3.2：140/140 通过，`reports/ws-cleanup-rework-r1/tests/ws-cleanup-test-bash3.2.out`。
- bash 5.3：140/140 通过，`.../ws-cleanup-test-bash5.3.out`。
- 回退测试：把被测脚本换回 d3efbf0，61/140 通过、79 个失败，`.../ws-cleanup-test-old-d3efbf0.out`。
  - 挂的是 F1–F6、W17、终端新规则、备份、`--execute` 路径（旧代码不认 `--only-from` / `--repo`）和 E18。
  - A9 c_open_pr 也挂了，因为假 gh 模拟了 1000 条截断。
  - 新加的 D3「第二次跑不被挡住」在旧代码上能过：旧代码根本不执行，所以也没东西挡它。
  - 这些是测试替身，不算 E2E。

## 真实 dry-run（E2E，只读）

iMac 全量：
- 先在 5a280d7 上跑：04:08 用 bash 3.2，04:11 用 bash 5.3，两次逐行一样。
- 修完 D1–D3 后，04:45 和 04:48 又在 4165ac2 上跑了一次（bash 3.2、5.3）。127 个真实工作区和前一次逐行一样；多出的 25 行是演练仓库，全部 SKIP。
- 结果：
  - 工作区 RM 19、BACKUP_RM 14、SKIP 93、LIST 1。
  - 终端全部 SKIP。
  - 状态冲突 14 个。
- 前后快照对比：`git worktree list` 字节一样；Orca 的 worktree 和终端条数一样，变化都能对上别的会话（`reports/ws-cleanup-rework-r1/imac/proof/proof.md`）。

MBA list-only：04:17、04:18 各跑一次，MBA 只有 bash 3.2。
- 37 个，换到 MBA 上清理的话，会是 BACKUP_RM 1、SKIP 36。
- 终端 22 个，全部 SKIP。
- 两次逐行一样。

和评审第 4 节逐项对照：`reports/ws-cleanup-rework-r1/review-compare.md`。19 项不一致：
- 11 项 W11：状态不是 completed。
- 5 项 W17：HEAD 都在远端分支上，但不在已合并的 PR / 主分支上。
- 3 项从 RM 变成 BACKUP_RM：`public/placeholder/sample/*.webp`，按 03:26 的口径要备份。

## 真 Orca 演练（E2E，Zack 03:40 批）

详见 `reports/ws-cleanup-rework-r1/drill.md`；脚本是 `scripts/tests/ws-cleanup-drill.sh`。

- 第 1 轮在 5a280d7 上跑，发现了 D1–D3。
- 第 2 轮在 4165ac2 上跑。17 个演练工作区，覆盖：
  - E1（sha 对不上）、E2（git lock 导致 rm 失败）、E3（.dev.vars 权限和原文件）、E4a、E4b、E8、E9 / F1、E10、E11、E12、E13、E14；
  - W40 白名单中止；
  - Linear 查不到；
  - W17、W6、W11、W13 嵌套 git。
  - 结果全部符合预期。
- E13：目录已经不在的工作区，`orca worktree rm` 会删掉 Orca 记录、git worktree 记录，以及已在 origin/main 上的本地分支。
- 演练仓库外，Orca 工作区（126 / 127）和终端（18）条数前后一样；9 个真实主仓库的 `git worktree list` 字节一样。
- 旧代码 d3efbf0 对照（只跑 dry-run）：
  - d06（只在本地的提交，目录已删）旧代码判 RM，F1。
  - notes.local、嵌套 git、读不了的文件旧代码会直接删，F2。
  - 旧代码会关 9 个终端，新代码 0 个，F3。

没跑的：
- E4c、E5、E6、E7：要在演练工作区里开终端并起进程，结束后终端要关掉；按规矩不手动关终端，所以没跑，只有假 orca 用例。
- E4d / F6：要 GitHub 上的 PR。新建的私有仓库复现不了改名和超过 1000 个 PR 的情况，所以没建 `zhongc1211/ops-ws-cleanup-drill`。
- 旧代码的 `--execute`：没有白名单，会动真实工作区，没跑。
- `--close-terminals`：在真 Orca 上没跑。

## 要 Zack 定的

1. **14 个状态冲突的工作区**（Orca 状态不是 completed，但 PR 已合并或 Linear 已关）：
   - dvads-fdv-66-email、FDV-39、PER-67 #43、PER-84、PER-86、FDV-65-首页交互e2e、fdv-60-e2e-followup（FDV-60 round2）、FDV-94、心月夜审 run 1（auto-run-1）、PER-48、PER-51、PER-75、PER-46、xinyue-site-cicd（CI/CD 第一阶段）。
   - 选项：
     - a）保持 SKIP，等工作区状态改成 completed 再删（推荐）；
     - b）PR 已合并且 HEAD 在 PR head / 目标分支上时放行；
     - c）逐个定。
   - 清单在 `imac-4165ac2/run1-bash3.2/worktrees.tsv` 里，W11 且原因含「状态冲突」的那些行。
2. **5 个 W17**（HEAD 在远端分支上，但不在已合并的 PR / 主分支上）：r2-F、per-8714、FDV-60-套餐对比、per-49、心月-CI-CD-第二阶段。删了不丢提交。
   - 选项：
     - a）保持 SKIP（推荐，和 03:33 一致）；
     - b）「HEAD 已在任意远端分支上」也算可删。
3. **xy-combined-src**（`/private/tmp/xy-combined-src`，目录已不在）：记录的 HEAD 36c6f4b 只在本地。建议先推到 `backup/xy-combined-src-36c6f4b`，再删。这次没推。
4. **deepvision-ads 的 `.git/info/exclude`（REPORT.md）**：按规矩没改，等你定。
5. **被 git lock 的工作区要不要在 dry-run 就 SKIP**：推荐要，一行改动。
6. **演练留下的东西**：
   - 都在 iMac `~/ops-drill/`：演练仓库、bare origin、没删的演练工作区、备份。
   - Orca 里还有 ws-cleanup-drill 这个项目，d01-clean 里有一个 Orca 自动开的终端。
   - 我没手动 rm、也没关终端。要清的话，在 Orca 里删这个项目，再 `rm -rf ~/ops-drill`。
7. **第一次真实 `--execute`**：要等你批，用法是 `--execute --only-from <审过的 worktrees.tsv>`，默认不关终端。

## 说明

- Zack 03:26–03:40 的 6 条决定，都是代码开始写之后才收到的。
- 03:33 那条（B34–B36 / W17）的代码，和失败方式那次提交是在同一步里改的，不是严格的先写失败方式、后写代码。其余几条都先提交了失败方式。
- 原始 Orca 快照里有别的会话的终端预览和 agent 消息，没有进仓库，放在 iMac `~/ops-archive/ws-cleanup-rework-r1-snapshots/`；仓库里只放 sha256 和对比结果。
