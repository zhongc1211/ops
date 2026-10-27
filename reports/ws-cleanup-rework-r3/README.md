# ws-cleanup R3（Zack 10-21 08:44）

脚本 `scripts/ws-cleanup.sh` 在 3fdf19a（blob 6feb047）。iMac 上跑。

## 假 orca / 假 gh 用例（测试替身，不算 E2E）

`WS_TEST_BASH=<bash> /bin/bash scripts/tests/ws-cleanup-test.sh`

| 被测脚本 | bash | 结果 | 输出 |
|---|---|---|---|
| 3fdf19a | 3.2.57 | 168/168 通过 | `tests/ws-cleanup-test-bash3.2.out` |
| 3fdf19a | 5.3 | 168/168 通过 | `tests/ws-cleanup-test-bash5.3.out` |
| d1602db（R2） | 3.2.57 | 160/168，8 个失败，都是新加的 N 用例 | `tests/ws-cleanup-test-old-d1602db.out` |

R2 是 159 个，这次加了 9 个（N1–N8；N1–N5 是 5 个工作区判 W19，N6 是 `--execute` 复查）。原有的 RM / BACKUP_RM 用例都挂上了已关的 Linear issue（N7），在 R2 代码上照样通过。

## iMac 全量 dry-run（只读）

`/bin/bash scripts/ws-cleanup.sh --out imac/run1-bash3.2`（08:55），`/usr/local/bin/bash … --out imac/run2-bash5.3`（08:57）。
两次退出码 0，stderr 为空；worktrees.tsv（96 行）逐行一样；terminals.tsv（20 行）只有本任务所在终端的进程顺序不同（都是 SKIP T3）。

和 R2（d1602db，07:59）逐行对比：`imac/compare-r2.md`，脚本 `compare_r2.py`。
