新增 `scripts/ws-cleanup.sh`：Orca 工作区和终端的夜间清理，纯脚本，不起模型。默认 dry-run，只读；只有加 `--execute --only-from <dry-run 名单>` 才会备份、`orca worktree rm`（不加 `--force`）。终端默认不关，要另加 `--close-terminals`。这个 PR 没挂任何 automation，没改 ops·11。

## 规则版本

- 底稿是 Zack 10-21 01:43 定的规则（`reports/ws-cleanup-dryrun-1021/RESULT.md`）。之后按评审返工了 R1–R6：
  - R1–R2：备份清单、git 锁（W18）、`--only-from`、动手前复查、锁、rm 失败不重试；
  - R3：没挂 Linear 的一律 SKIP（W19，Zack 08:44）；
  - R4：带 `--no-issue-reviews DIR` 时，有 DELETE_OK 审查记录且 HEAD 对得上才放行（Zack 09:18）；
  - R5：fork 上换了分支名开的 PR 也算开着；查 PR 失败一律当作开着；10:57 定稿「按 R5，不开例外」；
  - R6：备份后、rm 前再复查一次；W17 只认主分支（Zack 11:15）。
- **W17 现在的口径**：HEAD 要在远端主分支上，或者在一个合进主分支的已合并 PR 里（PR head 就是 HEAD，或者 PR head 包含 HEAD）。合进 staging 等其他 base 的 PR 一律不算，sha 或别的分支名查到的 PR 也只用来挡，不用来放行。
  - 「主分支」是 main、master，加上 Orca 里主工作区所在的分支（xinyue-site 是 `feat/xinyue-site`）。
  - Zack 11:15 的原话还有「或 HEAD 在工作区自己已推送的分支上」。这一条没有实现：照字面做，没合并、只推送过的工作区也能删，比改之前还松。要不要加，等 Zack 定。
- 失败方式清单都是写代码前先写的：`reports/ws-cleanup-rework-r1/FAILURE-MODES.md`。

## 已经真跑过的 `--execute`

这个分支上的脚本在 iMac 上真跑过两次 `--execute`，日志在 `reports/ws-cleanup-exec-1021/imac/`：

- run1，10-21 08:23 SGT：删了 32 个工作区，其中 13 个先备份。
  - 有 12 个没挂 Linear issue，所以 R3 加了 W19。
  - 当时的 W17 还认合进 staging 的 PR。按现在的口径，其中 4 个不会因为那个 PR 放行：site #60、#61、#75，xinyue-site #89。#60、#61 的 HEAD 现在也在 origin/main 上，#75、#89 的只在 origin/staging 上。
- run2，10-21 11:07 SGT：删了 3 个，auto-run-1、docs-lessons-to-everos、nightly-xinyue-site。Zack 10:53 卡片批准，3 个都先备份了审查记录。

## 现在的 dry-run（R6，iMac，只读）

10-21 11:38 用 bash 3.2、11:43 用 bash 5.3 各跑一次，带 `--no-issue-reviews reports/no-issue-review`，脚本 blob b9c46ae（commit 9ce6a53）。两次退出码都是 0，stderr 为空。

| | bash 3.2（11:38） | bash 5.3（11:43） |
|---|---|---|
| RM / BACKUP_RM | 0 / 0 | 0 / 0 |
| SKIP | 96 | 97 |
| LIST | 2 | 1 |
| 合计 | 98 | 98 |

- 现在没有可删的工作区。
- 两次只差一个 ops-PER126-p2-sampler：11:40 别的会话刚建的，第一次还只在 git 里（LIST W16），第二次进了 Orca、有 agent 在跑（SKIP W5）。
- 98 行里有 4 行是演练仓库的（见下面「验证」）。
- 和 R5（10:34）比：run2 删掉的 3 个不在了；6 个 W17 只是原因文字换了，结论没变；没有工作区因为新的 W17 改判。逐行对比在 `reports/ws-cleanup-rework-r6/imac/compare-r5.md`。

## 为什么安全

- `--execute` 只在 hostname 是 iMac 的机器上允许；别的机器的工作区只列出（W3）。
- `--execute` 必须带 `--only-from` 一份 dry-run 名单，只动名单里的；带 `--repo` 时名单里混进别的仓库的行，整轮中止。
- 同一时间只能有一个 `--execute`：有锁，锁里的 pid 还活着就退出；锁目录里除了 pid 还有别的东西，也不删、直接退出。
- 动手前对每个工作区重新取数据、重新判定，结论或备份清单和名单不一样就跳过。
- 备份后、rm 前再复查一次（R6）：HEAD、未提交、未推送、Linear、Orca 状态、lastActivityAt、终端、agent 有任何变化就不 rm，备份留着。
- 被忽略的文件除了可重建的，一律先备份；备份逐个核对 sha256，对不上就不 rm。
- `orca worktree rm` 不加 `--force`，失败不重试。
- 查不到就跳过：gh、Linear、git、Orca 任何一项查询失败，这个工作区就不删；gh、Orca 诊断这类环境问题，整轮什么都不做。`gh pr list` 正好拿到 `--limit` 条也当作查不到。

## 验证

E2E（真实环境）：

- iMac 全量 dry-run，只读，bash 3.2 和 5.3 各一次：`reports/ws-cleanup-rework-r6/imac/`。
- 真 Orca 演练：单独的 Orca 项目 `ws-cleanup-drill`（`~/ops-drill`），只动演练工作区，跑了 4 个用例的真 `--execute`：`reports/ws-cleanup-rework-r6/drill/`。
  - 没挂 Linear、审查 DELETE_OK、HEAD 对得上：先备份（备份里有 NO-ISSUE-REVIEW.md）再 rm。
  - dry-run 后 HEAD 变了：跳过，没 rm。
  - gh 一直失败：SKIP W9，没 rm；连 `gh auth status` 都失败时，退出码 5，什么都没做。
  - 备份期间工作区被改：备份留着，没 rm。
  - 演练仓库以外的 92 个工作区，前后 id 列表一样。
- run1、run2 两次真 `--execute` 的日志：`reports/ws-cleanup-exec-1021/imac/`。

另外用假 orca、假 gh 数据跑了 213 个检查，bash 3.2 和 5.3 都全过，产物在 `reports/ws-cleanup-rework-r6/tests/`。这些用了替身，不算 E2E。

每一轮的结果和评审意见在 `reports/ws-cleanup-results/`（RESULT-R1 到 R6、dr eggbot 的评审）。

## 要 Zack 定的

- W17 要不要加「HEAD 在工作区自己已推送的分支上」这一条（见上面「规则版本」）。
- 演练项目 `ws-cleanup-drill` 和 `~/ops-drill` 还留着，清理要卡片。

🤖 Generated with [Claude Code](https://claude.com/claude-code)
