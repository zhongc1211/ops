# ws-cleanup.sh：失败方式清单 + dry-run 结果（2026-10-21）

派活：`.orca-task/DRYRUN-BRIEF.md`（Zack 01:43「可以，dryrun 吧」）。规则以 `.orca-task/RULES-DRAFT.md` 为准，改动：D1=24h，D2 备份到
`~/ops-archive/ws-cleanup/<日期>/<repo>/<目录名>/` + `MANIFEST.sha256`，D3 保留 30 天、到期只列出，D4 加 evidence/、artifacts/、analysis/、
`*.local.*`，D5 取消（不设上限），D6 改成目录已不在的 Orca 记录直接 rm。执行者：Claude Code（iMac，本工作区）。本轮没有任何一次调用带 `--execute`。

## 1. 失败方式（写代码之前写的）

每条对应 `scripts/tests/ws-cleanup-test.sh` 里的一个用例：用假的 orca / gh（脚本读 fixture JSON，并把每次调用记进日志）、假的 `ps` 输出，
加上在临时目录里真建的 git 仓库（bare origin + 主 clone + `git worktree add`）。这些用例用了测试替身，不算 E2E；E2E 是第 3 节在 iMac / MBA 上的真实 dry-run。

动手前查到的、会影响设计的事实：

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F1 | `orca diagnostics memory` 给的 pid 是 `login`，shell（zsh）是它的子进程 | 本机 13 个终端逐个对 `ps -A -o pid,ppid,comm` | 「空 shell」= login 下只有一个 shell，shell 下面没有子进程；不能把 login 的子进程当成「活进程」 |
| F2 | 终端 `ptyId` = diagnostics 的 `sessionId`；`ORCA_TERMINAL_HANDLE` 是本终端 | 同上；`env` | T3 用这个环境变量认自己 |
| F3 | `linkedPR` 是数字；vllm-omni 的 linkedPR 可能是上游仓库的号（PER-56 → #8746） | `orca worktree list --json`；审计 4b-3 | 先在 fork 的 PR 列表里找，找不到再查上游；都找不到 = 查询失败 = 跳过 |
| F4 | `orca linear list-issues --team PER/FDV --json` 能拿到全部 issue（truncated=false），52 个 linkedLinearIssue 都在里面；状态 type 有 completed / canceled / duplicate | 只读跑了一次 | 「已关」= 这三种 type；按 issue 前缀分 team 查，某个 team 查不到 → 关联到它的工作区全部跳过 |
| F5 | MBA 上没有 PATH 里的 orca，在 `/Applications/Orca.app/Contents/Resources/bin/orca`（1.4.229）；bash 3.2、python 3.13 | `ssh mba` | 脚本自己找 orca（照 automation-reaper.sh）；MBA 用 `ssh mba 'bash -s -- --list-only …' < scripts/ws-cleanup.sh`，不往 MBA 拷脚本 |
| F6 | `orca worktree rm` 会顺手删检出的本地分支（证明不了已合并的保留）；不加 `--force` 时有未跟踪文件会拒绝 | `orca worktree rm --help` | 不加 `--force`；git 忽略的文件不会挡住 rm，所以要先按 W13 备份 |
| F7 | dry-run 不 fetch（fetch 会写 `.git`）。远端 ref 是旧的时，未推送只会多算、不会少算 | — | W8 偏保守，可接受 |

| # | 失败方式 | 用例 | 期望 |
|---|---|---|---|
| A1 | 删掉 main 工作区或 bare 仓库 | c_main | SKIP W1 |
| A2 | 删掉本任务自己所在的工作区 | c_self | SKIP W2 |
| A3 | 处理别的机器的工作区（hostId 不是 local） | c_remote_host | LIST W3 |
| A4 | 删有 agent 在跑的工作区（agentIdentity 非空，或进程树里有 claude/pi/codex 但 agentIdentity 是空的） | c_agent、c_agent_noid | SKIP W5 |
| A5 | 删终端里还有活进程的工作区 | c_proc | SKIP W6 |
| A6 | 终端查不到 pid（diagnostics 里没有）被当成「没进程」 | c_diag_missing、G6 | SKIP W6 |
| A7 | 删有未提交改动的工作区（含未跟踪文件） | c_dirty、c_untracked | SKIP W7 |
| A8 | 删有未推送提交的工作区 | c_unpushed | SKIP W8 |
| A9 | 删分支 PR 还开着的工作区（按分支名，或按 linkedPR，含上游号） | c_open_pr、c_linked_open_pr | SKIP W9 |
| A10 | gh 查不到（网络、权限）被当成「没有 open PR」 | c_gh_fail | SKIP W9（查询失败） |
| A11 | Linear 还没关的工作区被删 | c_linear_open | SKIP W10 |
| A12 | Linear 查不到被当成「已关」 | c_linear_fail | SKIP W10（查询失败） |
| A13 | 没有任何「做完」证据也删 | c_not_done | SKIP W11；in-review 但 PR 已合并的 c_merged_inreview → RM |
| A14 | 24 小时内有活动的被删；`lastActivityAt=0` 被当成「很久没动」 | c_recent、c_zero_recent_commit | SKIP W12 |
| A15 | 带 TASK.md / .orca-task / briefs / .dev.vars / evidence / artifacts / analysis / `*.local.*` 的没备份就删；藏在别的被忽略目录里面的也要找到 | c_backup、c_backup_evidence、c_nested | BACKUP_RM W13 |
| A16 | 把 node_modules/.next/.wrangler/dist 里的东西当成要备份的（或者反过来，因为有缓存目录就不删） | c_cache_only | RM W14 |
| A17 | ops 项目的普通工作区还被当常驻 | c_ops_common | RM W14 |
| A18 | 中文、空格路径处理错，TSV 列错位 | c_chinese | RM W14，TSV 每行列数一致 |
| A19 | 目录不是 git 仓库（git 命令失败）被当成「干净」 | c_not_git | SKIP（查询失败） |
| A20 | 目录不在的 Orca 记录没处理，或者被误加 `--force` | c_missing | RM W4，计划命令里没有 `--force` |
| A21 | git 里登记、Orca 里没有的 worktree 被删 | git_only | LIST W16 |
| A22 | 关了 agent 的终端 / 带 resume id 的终端 / 本任务的终端 / 有活进程的终端 | t_agent、t_resume、t_self、t_proc | SKIP T1 / T2 / T3 / T6 |
| A23 | 读终端屏幕失败被当成「没有 resume id」 | t_read_fail | SKIP T2（查询失败） |
| A24 | 用 `--tab` 关掉整个 tab，连带关掉同一 tab 里还在跑的窗格 | t_tab_sibling | 计划命令不带 `--tab` |
| A25 | 空 shell、已断开的终端没被列为可关 | t_empty、t_dead | CLOSE T4 / T5 |
| A26 | dry-run 实际动了东西：调用了 rm/close，建了备份目录，改了 git 状态 | G1 | 假 orca 日志里没有 rm/close；备份根目录不存在；git 快照前后一致 |
| A27 | `--list-only` 还给出 RM/CLOSE 动作 | G2 | 动作列全部是 LIST |
| A28 | 输出不可重复（顺序随机） | G3 | 连续两次，去掉时间列后 TSV 一样 |
| A29 | `orca worktree list` / `terminal list` 失败还照样出结论 | G4、G5 | 退出码 4，不写结果文件 |
| A30 | 报告里出现 .dev.vars 内容或终端屏幕内容 | G7 | 输出目录和 stdout 里都找不到 fixture 里的假密钥 |
| A31 | 备份的 sha 对不上还继续 rm | E1 | 不 rm，记 BACKUP_FAIL（只在 `--execute` 下才会走到，见下） |
| A32 | rm 被 Orca 拒绝后加 `--force` 重试 | E2 | 记失败原文，不重试 |
| A33 | .dev.vars 被复制（多一份明文）而不是移动，或者权限不是 600 | E3 | 原位置没了，新位置 600，目录 700 |
| A34 | 判定和 rm 之间工作区又有了改动（先判后删的时间差） | E4 | rm 前对这一个工作区重新判一次，结论变了就不删 |

E1–E4 只在 `--execute` 下才会走到。本轮禁止带 `--execute`，即使对假数据也不行，所以这四条**没写成可运行的用例、也没跑**。
代码里有对应的处理（备份后逐个文件 sha 核对，对不上不 rm；rm 不加 `--force`、失败不重试；.dev.vars 核对一致后才删原位置，
新位置 600、目录 700；动手前重新收数据再判一次），但都没验证过。打开 `--execute` 之前要先补这四条。

（以上第 1 节在写代码之前提交，commit 0b11d67。后面几节是跑完以后写的。）

## 2. 失败方式用例的结果

命令：`bash scripts/tests/ws-cleanup-test.sh`（iMac，macOS，/bin/bash 3.2.57，python 3.13.13）。

| 跑的是什么 | 结果 | 产物 |
|---|---|---|
| 本分支的 `scripts/ws-cleanup.sh`（aeb576b） | **55/55 通过**，E1–E4 没跑 | `tests/ws-cleanup-test.out` |
| 空实现（`WS_CLEANUP=/dev/null`，用来确认这些用例能挂） | 7/55 通过，48 条挂 | `tests/ws-cleanup-test-empty-stub.out` |

空实现过的 7 条都是「没做坏事」类的检查（没调 rm/close、没建备份目录、git 状态没变、输出里没有假密钥、没有 `--tab`），什么都不做自然会过。
写用例时测试脚本自己错了三处（`eval` 里引用了错误的 `$3`；含空格的分支名 git 不收；awk 跨文件用了 NR 而不是 FNR），都改的是测试脚本，被测脚本没为此改动。

## 3. dry-run（E2E：真实机器、真实 Orca/git/gh/Linear 数据，只读）

| | iMac | MBA |
|---|---|---|
| 命令 | `bash scripts/ws-cleanup.sh --out reports/ws-cleanup-dryrun-1021/imac/run{1,2}` | `ssh mba 'bash -s -- --list-only --out /tmp/wscd/run{1,2}' < scripts/ws-cleanup.sh`（脚本走 stdin，没拷到 MBA；结果 scp 回来） |
| 时间（SGT） | run1 02:06:05，run2 02:07:05 | run1 02:09:14，run2 02:09:57 |
| 脚本版本 | aeb576b（`scripts/ws-cleanup.sh` sha256 a7fd2070…75a7，和提交里的一致） | 同左 |
| 环境 | iMac，Orca 1.4.224，123 个工作区，13 个终端 | MBA，Orca 1.4.229，34 个工作区，15 个终端 |
| 退出码 | 0 / 0 | 0 / 0 |

**iMac 结果**：RM 41、BACKUP_RM 9、SKIP 73、LIST 1（共 124 行 = 123 个 Orca 工作区 + 1 个 git-only）。RM 约 10.4 GB，BACKUP_RM 约 5.0 GB。
终端 CLOSE 5、SKIP 8。
**MBA 结果**：全部 LIST 34。如果在 MBA 上清，结论会是 BACKUP_RM 2、SKIP 32。终端 15 个全部 LIST（结论会是 CLOSE 4、SKIP 11）。
逐行明细：`imac/run1/worktrees.tsv`、`imac/run1/terminals.tsv`、`mba/run1/…`；规则计数在各自的 `summary.md`。

### 3a. 只读证明（`imac/proof/proof.md`、`mba/proof/proof.md`）

跑之前和跑之后各存一份 `orca worktree list --json`、`orca terminal list --json`、每个仓库的 `git worktree list`（`imac/proof/snap.sh`）。
原始快照里有终端屏幕的 preview，所以没放进仓库，只放 sha256（`proof/snapshots.sha256`），原件留在 iMac 的会话临时目录里。

| 比较 | iMac | MBA |
|---|---|---|
| `git worktree list` | 字节完全一样 | 字节完全一样 |
| `orca worktree list` | 字节不一样。唯一不同的是响应顶层的 `id`（每次请求都不同），123 个工作区的所有字段都没变 | 同左，34 个工作区都没变 |
| `orca terminal list` | 字节不一样。顶层 `id` 不同；13 个终端里只有本任务自己的终端（`term_5deddc53`）的 `lastOutputAt`/`preview` 变了 | 顶层 `id` 不同；只有 PER-126 agent 的终端（`term_e69f8401`，T1）的 `lastOutputAt`/`preview`/`title` 变了 |
| 两次 TSV（去掉 `idle_h`、`procs` 两列） | worktrees 124 行、terminals 13 行都完全一样 | terminals 一样；worktrees 2 行的 `mb` 不同（1354→1344、1907→1908），两个都是 agent 正在跑的工作区（W5） |

所以「完全一样」这一条按字面没有做到：快照字节不同，MBA 第二次的 TSV 有 2 行不同。逐项看，所有不同都来自响应 id、本任务自己的终端，或者别的正在跑的 agent。
去掉的两列：`idle_h` 是拿当前时间算出来的；`procs` 是 agent 终端下面的子进程名，agent 在跑就会变。
另外：第一轮（02:00，那版脚本后来改过）的 before/after 之间，`sortOrder` 在 120 个工作区上一起后移了 173.7 秒。
我又在不跑脚本的情况下每隔 60 秒存一次 `sortOrder`，它照样在变，说明是 Orca 自己在重排，和脚本无关。
那一轮的结果没有采用，全部在最终版脚本上重跑了。

### 3b. 和审计报告逐条对照（`audit-compare.md`，脚本 `compare_audit.py`）

审计数据：box `/workspace/ops/reports/worktree-cleanup-audit-1021/raw/` 里的 `worktrees-classified.json`、`ignored-*.json`、`safe-summary.json`、
`git-worktrees-not-in-orca.json`（10-21 01:07 SGT），只读 scp 下来。按路径关联，并把审计的分类换算成新规则下应有的结论：
4b-1→RM，4b-2→BACKUP_RM，4b-3→SKIP，4c→RM/BACKUP_RM，目录已删→RM（D6），其余→SKIP。

| | 一致 | 不一致 | 新规则带来的 | 审计后状态变了 | 真不一致 |
|---|---|---|---|---|---|
| iMac | 91 | 33 | 28 | 5 | 0 |
| MBA | 27 | 7 | 5 | 2 | 0 |
| 合计 | 118 | **40** | 33 | 7 | 0 |

- 新规则带来的 33 条分三种：
  - Linear 现在会查，issue 还开着，所以从「可清」变成 SKIP W10：iMac 10、MBA 5；
  - 备份清单按 D4，审计算 4b-2 的变成直接 RM：iMac 16；
  - 做完的证据只有 Linear 已关，变成 RM：iMac 2（FDV-39 状态 sleep，PER-75 状态 in-review）。
- 审计后状态变了的 7 条：都是 01:07 之后新建的工作区，包括本任务自己的工作区。此外，审计里 MBA 的 3 个 git-only worktree（/private/tmp 下的 scratchpad）现在已经不在了。
- 第一次对照时有 2 条归到了「真不一致」，就是上面 Linear 已关的那 2 条。原因是对照脚本没有考虑「审计没查 Linear」，改了对照脚本以后归到「新规则带来的」。

## 4. 发现的改进点（给 Zack 评估，本轮没改规则）

1. **rm 会删掉 D4 清单以外的 git 忽略文件。** iMac 有 16 个 RM 工作区带这类文件。大部分是构建产物（next-env.d.ts、.open-next、.cloudflare、studio-public/base.css、runtime-public/），但有两处像是不能丢的：
   - `dvads-privacy-facts` 的 `docs/e2e/legal/*/report.md`：FDV-76 的 E2E 报告；
   - `ops/everos-vps-deploy` 的 `xinyue-lessons-import.tgz`。

   建议：备份清单加上 `docs/e2e/` 和 `*.tgz`/`*.tar.gz`/`*.zip`；或者反过来，「非缓存的忽略文件默认都备份，只排除一张构建产物清单」，这是审计用的口径。
2. **W10（Linear 没关）挡住了 iMac 17 个、MBA 8 个。** 其中 iMac 10 个状态已经是 completed（2 个 PR 已合并），多数挂在 FDV-70、PER-56 这类总 issue 下面，issue 要等全部子任务做完才会关。
   建议：第一次执行先保持现状（最保守）；之后可以考虑「状态 completed 且 PR 已合并」时不再看 Linear。
3. **终端：iMac 5 个 CLOSE 全是有 agent 在跑的工作区里那个配套的空 shell，其中一个是本任务工作区的 shell（`term_e34518f4`）。**
   按现在的 T1/T3 字面，它们该关；但它们在 bot 的工作区里，按「属于哪个 bot 的就由那个 bot 关」的意思，应该不算无主终端。
   建议：T1 扩到「工作区里有 agent 在跑，就整个工作区的终端都不关」；T3 扩到本任务所在工作区的所有终端。
4. 只有 Linear 已关、状态没到 completed 的工作区会被 RM（FDV-39 sleep、PER-75 in-review）。这符合规则，但要不要再加一条「状态是 in-progress / in-review 时不靠 Linear 判定做完」，请 Zack 定。
5. agent 只能通过 Orca 终端认出来。在工作区目录里、但不在 Orca 终端下跑的进程（比如从别处 `cd` 进去的 shell），按「进程只用 ps -o pid,ppid,comm」这条限制看不到 cwd，所以认不出来。

## 5. 没做 / 没跑

- `--execute`：本轮任何一次调用都没有带它。E1–E4 没写成用例，也没跑（见第 1 节末尾）。
- box：不在范围，没跑。
- 没挂到 ops·11，没改任何 automation。今晚 02:17 三台的 ops·11 还会按旧提示词跑。
- 没有 `git fetch`，远端 ref 用的是本地已有的（只会多算未推送，不会少算）。
- MBA 上 `/tmp/wscd/`（快照和两次输出）留在原处，没删。

## 产物

本目录：`RESULT.md`（本文件）、`tests/`、`imac/run{1,2}/`、`mba/run{1,2}/`、`*/proof/`、`audit-compare.md`、`compare_proof.py`、`compare_audit.py`。
box 副本：`/workspace/ops/reports/ws-cleanup-dryrun-1021/`。
重跑对照：`python3 -I compare_audit.py <审计 raw 目录> iMac=imac/run1/worktrees.tsv MBA=mba/run1/worktrees.tsv`。
