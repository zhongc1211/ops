# ops PR #73 审查（dr eggbot，2026-10-21 11:10 SGT）

- PR：https://github.com/zhongc1211/ops/pull/73（draft，base main，分支 `zhongc1211/ops-ws-cleanup-script`）
- 审查的 head：`a1cac54c1be1bb4d2465ac635061d3f8547a5939`。审查时 head 没有变（GitHub updatedAt 10:44:55 SGT；iMac 工作区 `ops-cleanup-rules-draft-1021` 的 HEAD 也是 a1cac54）。
- 脚本：`scripts/ws-cleanup.sh` 在 5e19598 和 a1cac54 的 blob 都是 `fc796d6`，和 R5 dry-run 记录的 `script-blob.txt` 一致。
- 看过的材料：
  - 整份脚本（927 行）和 2a751df→5e19598 的 diff；
  - iMac 上的 `.orca-task/RESULT-R1~R5.md`，这几份不在 PR 分支里，只在工作区；
  - `reports/ws-cleanup-rework-r5/`（README、compare-r4、两次 dry-run）；
  - `reports/no-issue-review/`（18 份记录）；
  - `reports/ws-cleanup-exec-1021/imac/run1`；
  - `reports/ws-cleanup-rework-r1/{FAILURE-MODES.md,drill.md}`。
- 只读核对过：
  - iMac 上各主工作区的分支和 remote；
  - GitHub 上 xinyue-site 的默认分支（`feat/xinyue-site`）；
  - run1 里所有「PR #N 的 head」对应 PR 的 baseRefName。
- 在 box 上用假 orca / gh 重跑了 `scripts/tests/ws-cleanup-test.sh`，结果见「可重跑性」一节。
- 没有用真数据跑脚本，没删东西，没 push，没在 GitHub 上评论。

## 结论：要改（changes needed）

四个重点（W9、W19、W17、删前复查）的判定逻辑大体是对的，而且查不到时都按跳过处理。下面三件是必改项，改完前不建议弹合并卡。

## 重点逐项

### W9：fork 上换了分支名的 PR
`prs_for`（ws-cleanup.sh:251-318）分三路查：
1. 按工作区分支名查，`headRepositoryOwner` 要是本仓库任一 remote 的 owner；
2. 按 linkedPR 查；
3. HEAD 不在任何远端主分支上时，按包含 HEAD 的每个远端分支名查（owner 要等于那个 remote 的 owner），再按 HEAD sha 搜。

查不到时的处理：
- 下面这些失败都会抛 QueryFail，判 SKIP W9「PR 查不到」：
  - `gh` 返回非 0（216-221、271、307、313）；
  - JSON 读不出；
  - 找不到 gh；
  - `canon` 失败（213）；
  - `for-each-ref --contains` 失败（293）。
- `carries()`（295-300）里 `merge-base` 失败时也当作 PR 开着。

在真实 dry-run 里，per-8714-schedule-400 现在被判成 SKIP W9 #8714 OPEN，不再靠 KEEP 记录挡。

注意：这一路只用本地的远端跟踪引用来找分支名，过时的引用照样能用来按名字查 PR，per-8714 就是这样查到的。

P10 的放过条件：open PR 的目标分支已经包含 HEAD，就不算这个 PR。这时工作区的提交已经在远端分支上，删了不丢东西。

### W19：没挂 issue 的工作区要有审查记录
`no_issue_review`（388-403）的检查：
- 记录里 PATH、HEAD（40 位）、VERDICT 各正好一行；
- PATH 的 realpath 要等于这个工作区；
- VERDICT 是 KEEP 就挡；
- HEAD 要和现在完全一样。

另外：
- 空白串也算没挂 issue（408）。
- 放行的照样过后面 W10 到 W17、W13 每一条，最后一律 BACKUP_RM。审查记录作为 NO-ISSUE-REVIEW.md 进备份和 MANIFEST（679-682）。
- 不带 `--no-issue-reviews` 时一律 SKIP。
- `--execute` 复查时走同一个 `safe_eval`，记录和 HEAD 会重新比一次。

没问题。

### W17：只认合进自己 PR 的目标分支或主分支，staging 不算
`head_merged`（502-514）放行的只有三种：
- HEAD 等于已合并 PR 的 head，或者是它的祖先；
- HEAD 在远端主分支上；
- HEAD 在「这个工作区自己的已合并 PR」的目标分支上。

按 sha、按别的分支名查到的 PR 带 `_extra`，不当作已合并的证据（505）。所以心月-CI-CD-第二阶段（#88 合进 staging，是 sha 搜到的）还是 SKIP W17。这和 Zack 03:33 的原话一致（「在远端主分支 / 已合并 PR 的目标分支里」），也符合 10:57「按 R5，不开例外」。

要知道的一点：工作区自己的 PR 合进 staging 时，照样算通过。run1 就这样删了 4 个：site #60、#61、#75，xinyue-site #89，这 4 个 PR 的目标分支都是 staging。如果「staging 不算」的意思是任何情况都不算，就要改代码。我理解是不用改，但建议在 PR 描述里写清楚（见下面的建议项）。

### 真删前的实时复查
`execute`（762-779）对每个工作区都会：
- 重新 `collect()`，拿到实时的 orca、终端、ps、Linear 数据，gh 也不走缓存；
- 比较 lastActivityAt；
- 用 `safe_eval` 重新判定，结论和备份清单都要和名单里的一样，否则跳过；
- 然后先备份，再 `orca worktree rm`。

问题出在备份和 rm 之间没有再复查一次，见必改第 1 条。

## 必改

1. **备份完到 rm 之间没有复查**（scripts/ws-cleanup.sh:763-779）。
   - 现在的顺序是：复查（768）→ `do_backup`（774，被忽略的文件逐个算 sha，大工作区要几分钟）→ 直接 `orca worktree rm`（779）。
   - 备份期间如果有 agent 进了这个工作区、开了终端、提交了或者改了状态，rm 照样执行。
   - 脚本自己在 W6 写了「rm 会把它停掉」，也就是会把终端停掉。drill d07 也表明 rm 会把本地分支一起删掉。所以这期间新提交、还没推送的东西会丢。
   - 改法：备份成功后，rm 之前再做一次 `collect()` + `safe_eval`（至少要看 agent、终端、HEAD、未提交、未推送这几项）。结论变了就不 rm，备份留着，result 和 journal 写明原因。
   - 要补一个用例：在备份和 rm 之间的等待点改动工作区，确认没有调用 rm。
2. **PR 描述过时，而且违反描述规矩**（PR #73 body）。
   - 还写着「这个 PR 里没有任何一次调用带 `--execute`」和「`--execute` 路径没验证过」。实际上 `reports/ws-cleanup-exec-1021/imac/run1` 是 08:23 SGT 在真实工作区上跑的 `--execute`：删了 32 个，其中 13 个先备份，12 个没挂 Linear（W19 就是因为这件事才加的）。
   - 规则版本写的还是「Zack 10-21 01:43」，没写 R1 到 R5 和 10:57 的定稿；数字还停在 aeb576b（RM 41 等）。
   - 「`bash scripts/tests/ws-cleanup-test.sh` … 55/55 通过」这句属于规矩明令不许写进 PR 描述的单测句。
   - 没有「为什么安全」这一节。
   - 要重写。按 R5 现状写：规则顺序，`--execute` 的护栏（只在 iMac、要带 `--only-from`、有锁、复查、不加 `--force`、先备份），run1 做过什么，R5 dry-run 的结果，E2E 产物路径，以及一节「为什么安全」。
3. **R2 到 R5 的改动没有真 Orca 上的 `--execute` 端到端验证**（reports/ws-cleanup-rework-r5/README.md:3-7；RESULT-R5「没跑的」一节）。
   - 真 Orca 演练只在 R1（4165ac2）跑过，覆盖不到 W18、W19、`--no-issue-reviews` 和 R5 的新查法。
   - R5 里查询失败的分支、执行时的 W19 复查，只有假 orca / gh 用例（README 自己写了「不算 E2E」）。
   - 规矩是只认 E2E，所以在第一次带 `--no-issue-reviews` 的真 `--execute` 之前，要在 5e19598（或修完第 1 条后的 head）上用 `scripts/tests/ws-cleanup-drill.sh` 在真 Orca 上至少补跑下面几种，产物进 `reports/ws-cleanup-rework-r5/drill/`：
     - 没挂 issue、DELETE_OK、HEAD 对得上：应该 BACKUP_RM，备份里有 NO-ISSUE-REVIEW.md；
     - dry-run 之后把 HEAD 换掉：应该跳过；
     - 让 `WS_GH` 指向一个总是失败的 gh：应该 SKIP W9，没有 rm；
     - 第 1 条修完后，备份和 rm 之间工作区被改动：应该不 rm。
   - 演练仓库 `~/ops-drill` 已经在 08:3x 被清掉了，要重建。
   - fork 换名 PR 查到这件事，在真实 dry-run 里已经有 per-8714 → W9 的正例，可以不另外造 GitHub 仓库。

## 其他要求逐项

- `orca worktree rm` 不加 `--force`（779），rm 失败不重试。全脚本只有三处会删或挪东西：
  - `orca worktree rm`；
  - `orca terminal close`（802，只关名单里、存档成功的终端）；
  - 锁目录的 rmtree（832、916）。
  - 失败的备份是改名留着（`set_aside`），不删。
- 删除前都有检查：`--execute` 只能在主机名正好是 `imac` 的机器上跑（91-93），而且要带 `--only-from`。环境查不到（preflight）就什么都不做，退出码 5。另一个 `--execute` 在跑就退出码 6。
- 备份：可重建清单以外的被忽略文件，一律先算 sha 再复制、核对，文件 0600、目录 0700，有 MANIFEST。sha 对不上或者复制失败就不 rm。这符合 Zack 03:26 的决定。
- secret：在整个 diff（30490 行）里扫了 token、key、私钥和邮箱，没有发现真的。邮箱只有测试里的 example.com 和 `page@<hash>.webm` 这类文件名。`SECRET-MARKER` 是测试里的占位符。
- 可重跑性：
  - 在 box（Linux、bash 5.2、git 2.47）上重跑假 orca 用例，结果是 196/199。挂的 3 条（E3、R11、B31）都是权限检查用了 macOS 的 `stat -f %Lp`：GNU stat 的 `-f` 不会报错，所以退不到 `stat -c`。这不是脚本的问题。
  - 在 iMac 上可以照 RESULT-R5 里的命令重跑。

## 建议（不挡合并）

1. **「主分支」怎么定。** `main_branches` 现在用的是 Orca 主工作区当前签出的分支，再加上 main 和 master（170、520）。远端的哪个 remote 的同名分支都算（301、512-513），fork 的 main 也算。现在的数据没问题：各主工作区都在默认分支上，xinyue-site 的默认分支就是 feat/xinyue-site。但如果哪天有人在主工作区签出了 staging，staging 就会被当成主分支。建议改成用 GitHub 的 defaultBranchRef，并且只认上游 / projectId 那个仓库的 remote。
2. `gh pr list --limit 100`（270、306、312）查满 100 条时没有提示，可能被截断。建议正好拿到 100 条时，当作查不到。
3. 主仓库路径不在时，`remotes` 返回 []，`prs_for` 直接返回「没有 PR」（260、521），这是放行而不是跳过。现在靠后面 git 命令失败兜住，建议改成抛 QueryFail。
4. 在 PR 描述里写明 W17 的口径：自己的 PR 合进 staging 算通过，别的途径查到的 PR 合进 staging 不算。run1 按这个口径删过 4 个。请 Zack 确认这就是「staging 不算」的意思。
5. 用例里的权限检查改成先判断平台，或者在 README 里写明只在 macOS 上跑。
6. 锁目录 rmtree 之前先确认目录里只有 `pid` 文件，免得 `WS_LOCK` 设错时删了别的目录。
7. 审查记录（18 份）和脚本出自同一个 PER-139 会话。以后可以考虑换一个会话或模型来写，审查会更独立。
8. PR 描述和提交信息里有 claude.ai 的会话链接，可以去掉。
9. `.orca-task/RESULT-R*.md` 不在 PR 分支里，只在 iMac 的工作区。验收材料最好放进 `reports/`，或者在描述里写清楚放在哪。

## 要转告 Zack 和 ops bot 的情况（不属于代码问题）

- R5 的删除名单里有 3 个 BACKUP_RM：auto-run-1、docs-lessons-to-everos、nightly-xinyue-site。它们能进名单，只是因为 09:37 到 10:34 之间，有人在 Orca 里把状态改成了 completed。RESULT-R5 写的是「不是我改的」。真跑 `--execute` 之前，最好先查清是谁改的：W11 这道闸是靠状态挡的。
- iMac 工作区里有一份 10:55 跑的 `reports/ws-cleanup-exec-1021/imac/run2-dryrun/`，还没提交，结果同样是 3 个 BACKUP_RM，看起来是在准备第二次真跑。PR 还没合，第二次 `--execute` 要 Zack 本人点卡批准。
