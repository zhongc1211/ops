新增 `scripts/ws-cleanup.sh`：Orca 工作区和终端的夜间清理，纯脚本，不起模型。规则按 Zack 10-21 01:43 定的版本。脚本默认 dry-run，只有显式加 `--execute` 才会备份、`orca worktree rm`（不加 `--force`）、关终端。这个 PR 里没有任何一次调用带 `--execute`，也没挂到 ops·11，没改任何 automation。

完整说明在 `reports/ws-cleanup-dryrun-1021/RESULT.md`。第 1 节失败方式清单是写代码之前提交的（0b11d67）。

## dry-run 结果

| | iMac | MBA（`--list-only`） |
|---|---|---|
| 工作区 | RM 41、BACKUP_RM 9、SKIP 73、LIST 1 | LIST 34（如果在 MBA 上清，会是 BACKUP_RM 2、SKIP 32） |
| 终端 | CLOSE 5、SKIP 8 | LIST 15 |
| 和审计报告逐条对照 | 一致 91，不一致 33 | 一致 27，不一致 7 |

不一致的 40 条：新规则带来的 33 条（Linear 现在会查、备份清单按 D4），审计（01:07）之后新建的工作区 7 条，没有找不到原因的。逐条见 `audit-compare.md`。

## 只读证明

跑前跑后各存了一份 `orca worktree list --json`、`orca terminal list --json`、每个仓库的 `git worktree list`：

- `git worktree list`：两台都字节一样。
- 两份 orca JSON：字节不一样。不同的只有响应顶层的请求 `id`，以及正在输出的终端：iMac 是本任务自己的终端，MBA 是一个 agent 的终端。工作区记录没有任何字段变。
- 连续两次的 TSV，去掉 `idle_h`、`procs` 两列（都是随时间变的）之后，iMac 完全一样；MBA 有 2 行的 `mb` 不同，那两个工作区里有 agent 正在跑。

## 跑了什么

- 失败方式复现用例：`bash scripts/tests/ws-cleanup-test.sh`，用假 orca/gh 数据加临时 git 仓库，55/55 通过；对空实现跑是 7/55，用来确认这些用例会挂。
- dry-run：`bash scripts/ws-cleanup.sh --out reports/ws-cleanup-dryrun-1021/imac/run{1,2}`，在 iMac 上跑（macOS，bash 3.2.57，python 3.13.13，Orca 1.4.224），时间 10-21 02:06–02:08 SGT。
- MBA：`ssh mba 'bash -s -- --list-only --out /tmp/wscd/run{1,2}' < scripts/ws-cleanup.sh`（Orca 1.4.229），时间 02:09–02:10 SGT。
- 两边的 dry-run 都跑在 commit `aeb576b960d544d1d4b97e61a5bc43677fcbaf55`。之后的 d3efbf0 只加了报告和对照脚本，`scripts/ws-cleanup.sh` 没变。
- 产物：`reports/ws-cleanup-dryrun-1021/`，box 上有一份副本 `/workspace/ops/reports/ws-cleanup-dryrun-1021/`。

## 没跑

- `--execute` 这条路径：备份 sha 核对、rm 失败不重试、.dev.vars 移动后权限 600、动手前重新判定。本轮禁止带 `--execute`，这四条没写成用例，也没验证过。
- box：不在范围。

## 要 Zack 看的

RESULT.md 第 4 节有 5 条改进建议，这次没改规则。最要紧的两条：

- 现在 rm 会删掉 D4 清单以外的 git 忽略文件。iMac 上有 16 个这样的工作区，其中 FDV-76 的 `docs/e2e/legal/*/report.md` 和 `xinyue-lessons-import.tgz` 看起来不该丢。
- iMac 那 5 个 CLOSE 终端，全是 agent 正在跑的工作区里配套的空 shell。

🤖 Generated with [Claude Code](https://claude.com/claude-code)

（会话链接，存档时已去掉）

