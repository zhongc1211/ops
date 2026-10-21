# PER-139 R5：fork 上换了分支名开的 PR，W9 也要认出来

- `tests/`：`scripts/tests/ws-cleanup-test.sh` 的输出，用的是假 orca 和假 gh（测试替身，不算 E2E）。
  - 新代码：bash 3.2 和 5.3 各 199/199。
  - `ws-cleanup-test-old-2a751df.out`：R4 的代码，192/199，挂的 7 个都是新的 P 用例。
- `imac/`：iMac 全量 dry-run（真实环境，只读），带 `--no-issue-reviews reports/no-issue-review`。
  - 脚本 blob 记在 `script-blob.txt`。
  - 和 R4 的逐行对比在 `imac/compare-r4.md`。
