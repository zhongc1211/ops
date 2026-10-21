# 真 Orca 演练（Zack 10-21 03:40 批）

## 怎么跑的

- 演练仓库：iMac 本地 `~/ops-drill/ws-cleanup-drill`，origin 是本地 bare 仓库 `~/ops-drill/origin.git`，没有用 GitHub。
  - 注册成单独的 Orca repo：`aa123560-8996-445e-9798-58252049e7e5`。
- 演练工作区：
  - 用 `git worktree add` 建在 `~/ops-drill/wt`（第 1 轮）和 `~/ops-drill/wt-r2`（第 2 轮）下。
  - 用 `orca repo set --external-worktree-visibility show` 让 Orca 看见它们。
  - 用 `orca worktree set --workspace-status` 设状态。
  - 只有 d01-clean 是用 `orca worktree create` 建的。Orca 会在里面自动开一个终端。
- 每次调用 `ws-cleanup.sh` 都带 `--repo aa123560-…`。环境变量：
  - `WS_ARCHIVE=~/ops-drill/archive[-r2]`：备份不和真的混在一起。
  - `WS_IDLE_H=0`：演练工作区才建了几分钟。其余规则不变。
- 脚本：`scripts/tests/ws-cleanup-drill.sh setup|dry|execute|post <输出目录>`，第 2 轮加 `DRILL_TAG=r2`。
- 两轮：
  - 第 1 轮在 5a280d7 上跑（`drill-r1-5a280d7/`），看到 3 个问题（D1–D3，见 FAILURE-MODES.md 最后一节）。
  - 修好后在 4165ac2 上重跑第 2 轮（`drill-r2-4165ac2/`）。下面的结果都是第 2 轮的。
- 真实工作区：`--execute` 只在演练仓库上跑过，`orca terminal close` 一次都没调过。
  - 前后快照对比见 `drill-r*/proof.md`。
  - 原始 JSON 不进仓库（里面有别的会话的终端预览和 agent 消息），放在 iMac `~/ops-archive/ws-cleanup-rework-r1-snapshots/`，sha256 见各目录的 `snapshots.sha256`。

## 真实工作区没变（第 2 轮 `proof.md`）

- `orca worktree list`：演练仓库外前后都是 126 个，没有多也没有少。变过的字段只有 `sortOrder`，是 Orca 自己重新排序。
- `orca worktree ps`：演练仓库外前后都是 127 个。另外变过的有 `lastOutputAt`、`preview`、`agents`、`status`，是别的会话在跑。
- `orca terminal list`：演练仓库外前后都是 18 个，没有多也没有少。
- `git worktree list --porcelain`：10 个主仓库里，9 个前后字节一样；不一样的那个是演练仓库。
- 演练仓库自己的工作区从 30 个变成 25 个，删掉的正好是 d02、d03、d07、d12、d14。

## 逐项结果（第 2 轮，`dry-new-bash3.2/` → `execute-1/` → `execute-2-same-day/`）

dry-run 在 bash 3.2 和 5.3 下各跑一次，结论逐行一样。`--execute` 用 bash 3.2 跑。

| 用例 | 怎么造 | dry-run | --execute 结果 | 对应 |
|---|---|---|---|---|
| d02-probe | 干净、已推送、completed | RM W14 | 已 rm | 基线 |
| d03-backup | 被忽略的 notes.local、假 .dev.vars，加 node_modules/ | BACKUP_RM W13 | 已备份再 rm。备份只有 .dev.vars 和 notes.local，没有 node_modules；目录 700，文件 600；MANIFEST 校验通过 | F2、E3 |
| d04-unpushed | 本地提交没推 | SKIP W8 | 不在名单 | — |
| d05-dirty | 未跟踪文件 | SKIP W7 | 不在名单 | — |
| d06-gone-local | detached HEAD 上的本地提交，然后删掉目录 | SKIP W4，报告里写了 commit 8d2b96a 和建议的备份分支名 | 不在名单；git 里那条 worktree 记录还在（prunable），提交没丢 | F1、E9 |
| d07-gone-pushed | 目录删掉，HEAD 在 origin/main | RM W4「rm 会删 Orca 记录和 git worktree 记录」 | 已 rm。Orca 记录没了，git worktree 记录没了，本地分支 drill-r2/d07-gone-pushed 也被删了（HEAD 已在 origin/main） | E13 |
| d08-inreview | 状态 in-review | SKIP W11 | 不在名单 | M1 |
| d09-late-commit | dry-run 后提交一次 | RM W14 | 跳过：名单里是 RM，这次判定 SKIP W8 | F5、E4b、D1 |
| d10-late-dirty | dry-run 后新建文件 | RM W14 | 跳过：名单里是 RM，这次判定 SKIP W7 | F5、E4a、D1 |
| d11-locked | 假 .dev.vars；dry-run 后 `git worktree lock` | BACKUP_RM W13 | 已备份；rm 失败，result 是 Orca 原话「Worktree is locked by Git…」；只调了一次 rm，没加 --force；原位置的 .dev.vars 还在。第二次跑：BACKUP_FAIL「备份目录已存在，不覆盖」 | E2、E3、E12、D2 |
| d12-sha | 32 MB 的被忽略文件，execute 期间后台一直往里追加 | BACKUP_RM W13 | BACKUP_FAIL「sha 对不上」，没 rm；拷了一半的目录改名成 `d12-sha.failed-044306`。第二次跑时没有追加：备份成功，MANIFEST 校验通过，然后 rm | E1、D3 |
| d13-noperm | 被忽略的文件 chmod 000 | BACKUP_RM W13 | ERROR：PermissionError，这一行没删，后面的照常处理；TSV、summary、journal 都写出来了；半个目录改名成 .failed-* | F4、E8、D3 |
| d14-fifo | 工作区根目录下有个被忽略的 FIFO | RM W14 | 已 rm | 见下面「新发现」 |
| d15-nested | 被忽略的目录里有嵌套 git 仓库 | SKIP W13 | 不在名单 | F2 |
| d16-linear-missing | 挂一个不存在的 Linear issue PER-999999 | SKIP W10「Linear 查不到（当作没关）」 | 不在名单 | Zack 03:37 |
| d17-branch-only | 提交已推到 origin 分支，没进 main，没有 PR | SKIP W17 | 不在名单 | Zack 03:33 |
| d01-clean | Orca 建的工作区，里面有 Orca 自动开的终端 | SKIP W6；终端 SKIP T7 | 不在名单；终端没关 | F3 |
| 名单里有、Orca 里已经没有的 | 第二次跑时 d02、d03、d07、d14 已删 | — | journal 记 not-found，不动 | D1 |
| W40 | 名单里混进 ops 仓库 id 的一行 | — | 退出码 2「白名单外有 1 个候选…整轮中止」；演练工作区数量不变 | Zack 03:40 |
| E14 | `--execute` 不带 `--only-from` | — | 退出码 2 | E14 |
| E10 | `WS_GH` 指向不存在的文件 | — | 退出码 5，summary 第一行写「环境不对：找不到 gh」 | E10 |
| E11 | 锁目录里是活的 pid | — | 退出码 6，什么都没做 | E11 |

## 旧代码 d3efbf0 对照（第 1 轮 `dry-old-d3efbf0/`，只跑 dry-run）

旧代码没有 `--repo`，所以没在演练仓库上跑旧代码的 `--execute`：它会顾不上白名单去动真实工作区。只跑了全量 dry-run（只读），再挑出演练仓库的行。

| 用例 | 旧代码 | 新代码 | 说明 |
|---|---|---|---|
| d06-gone-local | RM W4「目录已不在，只删 Orca 记录」 | SKIP W4 | F1：旧代码会把只在本地的提交连同 worktree 记录删掉 |
| d03-backup | BACKUP_RM，只备份 .dev.vars；notes.local 放在 other_ignored 里，不备份 | 备份 .dev.vars 和 notes.local | F2 |
| d13-noperm | RM W14；secret-notes 放在 other_ignored 里，直接删 | BACKUP_RM（读不了 → ERROR，不删） | F2、F4 |
| d15-nested | RM W14：嵌套的 git 仓库会被删 | SKIP W13 | F2 |
| d17-branch-only | RM W14 | SKIP W17 | Zack 03:33 |
| d01-clean 的终端 | CLOSE T4「空 shell」；同一次全量 dry-run 里旧代码一共会关 9 个终端 | SKIP T7；新代码 0 个 CLOSE | F3 |
| F5（判定后变化） | 旧代码 `--execute` 不复查 git，也不支持 `--only-from` | 第 2 轮的 d09、d10 | 旧代码的 execute 没法在演练里安全地跑，所以这一项没有真跑的旧代码对照；假 orca 用例里有（E4a/E4b 在旧代码上失败） |
| F6（PR 查询） | 演练仓库在本地 bare origin 上，没有 PR | — | 没跑：要建 GitHub 仓库才有 PR。旧代码的毛病出在换过 owner 和超过 1000 个 PR 的仓库上，新建的私有仓库复现不了，所以没建 |

## 新发现（没改代码）

- **FIFO 不在 git 的忽略列表里**：`git ls-files --others --ignored` 不会列出 FIFO，所以 d14 判成 RM。FIFO 本身不存数据，删了不丢东西。被忽略目录里的 FIFO 会被看到，判成 W13 SKIP（假 orca 用例覆盖了）。
- **被 git lock 的工作区 dry-run 照样判 RM / BACKUP_RM**：rm 时 Orca 会拒绝，脚本记失败、不加 --force，不会丢东西；但会先做一次备份。可以让 dry-run 读 `git worktree list --porcelain` 的 locked，直接 SKIP。这轮没改，写进 RESULT-R1 的待定项。

## 演练留下的东西

都在 iMac `~/ops-drill/` 下：
- 演练仓库和 bare origin。
- 第 1 轮、第 2 轮没删的工作区（SKIP 的那些，加上 d11-locked、d13-noperm）。
- 备份目录 `archive`、`archive-r2`。

d01-clean 里有一个 Orca 自动开的终端（term_fe39422a）。按规矩我没关它，也没手动 rm 任何工作区。需要清掉时，由 Zack 在 Orca 里删 ws-cleanup-drill 这个项目，再 `rm -rf ~/ops-drill`。
