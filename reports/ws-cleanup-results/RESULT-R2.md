# PER-139 R2 结果（Zack 10-21 07:34 的两处小改）

## 结论

两处都改好了，已推到 `zhongc1211/ops-ws-cleanup-script`，PR #73 仍是 draft，head `0d321658cbf18c337666a8382eb677f43bca6606`。
- 脚本改动在 d1602db，0d32165 只加了报告。
- 真实工作区没跑 `--execute`，也没跑 `--close-terminals`。
- 这一轮没在 PR 上发评论（R2 派活没要求）。要发的话，内容可以直接用下面「测试」和「iMac 全量 dry-run」两节。

## 改了什么

1. **git 锁在 dry-run 就判 SKIP，规则 W18，原因以 `GIT_LOCKED：` 开头。**
   - 看的是 worktree 自己的 gitdir：linked worktree 是 main 的 `.git/worktrees/<名>`；目录已不在的，按里面的 gitdir 文件反查。
   - 算作锁的有：
     - `index.lock`
     - `MERGE_HEAD`（merge）
     - `rebase-merge/`、`rebase-apply/`（rebase / am）
     - `CHERRY_PICK_HEAD`（cherry-pick）
     - `BISECT_LOG`（bisect）
     - 另外加了两项：`REVERT_HEAD`（revert 没做完）、`locked`（`git worktree lock`，即 R1 演练 d11 的情况）。不想要这两项的话，各删一行就行。
   - 顺序：排在 W5（agent 在跑）、W6（终端开着）之后，W4 / W7 之前。所以 agent 正在跑、顺带有 index.lock 的工作区，记为 W5，不算 GIT_LOCKED。
   - `--execute` 复查时也会挡住：dry-run 之后才加锁的，结果是「跳过：重新判定变成 SKIP W18」，不备份，也不调 rm。
   - summary.md 多一行「GIT_LOCKED（W18）：n 个」。
2. **邮箱打码**：TSV、summary.md、journal.tsv 和 stdout 里，邮箱一律写成「首字母***@域名」，例如 `B***@example.com`。
   - comment 列先打码再截断到 60 字，所以 R1 里那种截断后剩下的半个邮箱不会再出现。现在打码后，那条显示成 `a***@de…`：域名本身也被截断了。
   - 第一次真实 dry-run 发现了误伤：Playwright 录像文件名 `page@<hash>.webm` 被当成邮箱，backup-files.tsv 里 16 个文件名被改了。现在以常见文件扩展名结尾的不算邮箱。另外 `pkg@1.2.3`、`node@20` 这类版本号也原样保留。
   - `--execute` 对名单时，id 和备份清单两边都先过同一个打码再比，有邮箱的那行不会因此永远对不上。
3. 失败方式先写进 `reports/ws-cleanup-rework-r1/FAILURE-MODES.md` 最后一节（G1–G11、M1–M6），再写用例和代码。

## 测试（假 orca / 假 gh，测试替身，不算 E2E）

命令：`WS_TEST_BASH=<bash> /bin/bash scripts/tests/ws-cleanup-test.sh`，iMac 上跑。

| 被测脚本 | bash | 结果 |
|---|---|---|
| d1602db | 3.2.57 | 159/159 通过 |
| d1602db | 5.3 | 159/159 通过 |
| 5a6b8f8（R1 的代码） | 3.2.57 | 142/159，17 个失败 |

- R1 是 140 个，这次加了 19 个：
  - G1–G9：8 个锁住的工作区判 W18，外加原因、summary 计数各一个检查。
  - G10：dry-run 之后才加锁，`--execute` 跳过。
  - G11：main 仓库的 index.lock 不连累它的 linked worktree。
  - M1–M5：邮箱打码，包括 terminals.tsv、journal 和文件名误伤。
- 旧代码上失败的 17 个，都是新加的 G / M 用例。G11 和 M5 在旧代码上本来就过：旧代码不查锁，也不打码。
- 第一次跑 M3 失败，是我的用例写错了：备注写得太长，`node@20` 被 60 字截断吃掉了。我缩短了备注，断言没改。
- 产物：`reports/ws-cleanup-rework-r2/tests/`。

## iMac 全量 dry-run（真实环境，只读）

- 07:59 用 `/bin/bash`（3.2）、08:02 用 `/usr/local/bin/bash`（5.3），各跑一次。脚本 blob 505e0a0，和 d1602db 里的一样。
  - 两次退出码 0，stderr 为空。
  - worktrees.tsv 153 行、terminals.tsv 21 行、backup-files.tsv 2010 行，除 idle_h 外逐行一样。
- 产物：`reports/ws-cleanup-rework-r2/imac/`；和 R1 的逐行对比在 `imac/compare-r1.md`。
- 输出里查过：除了 `page@<hash>.webm` 文件名，没有未打码的邮箱。

**合计**（R1 是 4165ac2 在 04:45 的那次；ws-cleanup-drill 演练仓库单独算）：

| 真实工作区 | R1 | R2 | 差 |
|---|---|---|---|
| RM | 19 | 19 | 0 |
| BACKUP_RM | 14 | 13 | −1 |
| SKIP | 93 | 95 | +2 |
| LIST | 1 | 1 | 0 |
| 合计 | 127 | 128 | +1 |

- 演练仓库：R1、R2 都是 25 个，全部 SKIP。
- 终端：R1 SKIP 19，R2 SKIP 21，都不关。多出来的 2 个是别的会话新开的。
- 状态冲突仍是 14 个；Linear 查不到的仍是 2 个。

**进了 GIT_LOCKED 的：3 个**（真实工作区 1 个、演练仓库 2 个）
- ops-stuck-routing-1020：`index.lock`。0 字节，10-20 19:14 留下的，现在没有 git 进程在用，是上次异常退出留下的陈旧锁。R1 里它已是 SKIP W9（PR 还开着），所以这次不影响删不删。
- 演练仓库两个 d11-locked（第 1、2 轮各一个）：`git worktree lock`。R1 是 SKIP W12。

**和 R1 比，有变化的 4 行（真实工作区）**：
- ops-stuck-routing-1020：SKIP W9 → SKIP W18 GIT_LOCKED。这是这次改动带来的。
- xy-combined-src：SKIP W4 → SKIP W11。原因是远端现在有 `origin/backup/xy-combined-src-36c6f4b`，它的 HEAD 36c6f4b 已经在远端，W4 不再拦，往下判到 W11（状态 in-progress）。这个分支不是我推的。仍然不删。
- dvads-privacy-facts：BACKUP_RM W13 → SKIP W7。现在有 2 项未提交改动，是别人在里面改的。
- ops-per126-v5-write-1021：R1 时还没有，这次是 SKIP W5（agent 在跑）。

除 ops-stuck-routing-1020 外，其余 3 行都是工作区本身的变化，不是这次改动造成的。新代码只多了一个 SKIP 出口 W18，没法把一行改判到别的规则。

## 没跑的

- 真实工作区的 `--execute`、`--close-terminals`：按规矩没跑。
- MBA list-only：这次派活没要求，没跑。
- 真 Orca 演练：这次没重跑。G10 只有假 orca 用例。R1 的演练数据显示，d11-locked 现在 dry-run 就会被挡住。
- PR 证据评论：没发，见「结论」。

## 还要 Zack 定的（R1 那些照旧，这次新增一条）

- ops-stuck-routing-1020 的陈旧 `index.lock`：要不要手动删掉？我没动。它的 PR 还开着，删不删都不影响这次清理。
