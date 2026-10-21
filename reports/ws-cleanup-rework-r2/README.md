# ws-cleanup R2（Zack 10-21 07:34）

脚本 `scripts/ws-cleanup.sh` 在 d1602db（blob 505e0a0）。iMac 上跑。

## 假 orca / 假 gh 用例（测试替身，不算 E2E）

`WS_TEST_BASH=<bash> /bin/bash scripts/tests/ws-cleanup-test.sh`

| 被测脚本 | bash | 结果 | 输出 |
|---|---|---|---|
| d1602db | 3.2.57 | 159/159 通过 | `tests/ws-cleanup-test-bash3.2.out` |
| d1602db | 5.3 | 159/159 通过 | `tests/ws-cleanup-test-bash5.3.out` |
| 5a6b8f8（R1） | 3.2.57 | 142/159，17 个失败，都是新加的 G / M 用例 | `tests/ws-cleanup-test-old-5a6b8f8.out` |

R1 是 140 个，这次加了 19 个：G1–G11（8 个锁的工作区、原因、summary 计数、main 的 index.lock 不连累 linked worktree、dry-run 后才加锁的 --execute 复查）和 M1–M5（邮箱打码）。

## iMac 全量 dry-run（只读）

`/bin/bash scripts/ws-cleanup.sh --out imac/run1-bash3.2`（07:59），`/usr/local/bin/bash … --out imac/run2-bash5.3`（08:02）。
两次退出码 0，stderr 为空；worktrees.tsv（153 行）、terminals.tsv（21 行）、backup-files.tsv（2010 行）除 idle_h 外逐行一样。

和 R1（4165ac2，04:45）逐行对比：`imac/compare-r1.md`，脚本 `compare_r1.py`。演练仓库 ws-cleanup-drill 单独算。
