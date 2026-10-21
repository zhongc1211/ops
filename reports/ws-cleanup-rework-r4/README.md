# PER-139 R4：没挂 Linear 的工作区，有审查记录才放行（Zack 10-21 09:18）

- `tests/`：`scripts/tests/ws-cleanup-test.sh` 的输出，用的是假 orca 和假 gh（测试替身，不算 E2E）。
  - `ws-cleanup-test-bash3.2.out`、`ws-cleanup-test-bash5.3.out`：新代码，185/185。
  - `ws-cleanup-test-old-3fdf19a.out`：R3 的代码，134/185。旧代码不认 `--no-issue-reviews`，带这个参数的 dry-run 和 `--execute` 都是退出码 2。所以挂掉的 51 个是 R 用例，加上整个 `--execute` 段。
  - 命令：`WS_TEST_BASH=<bash> /bin/bash scripts/tests/ws-cleanup-test.sh`；跑旧代码时，前面加 `WS_CLEANUP=<3fdf19a 的 ws-cleanup.sh>`。
- `imac/`：iMac 全量 dry-run（真实环境，只读），带 `--no-issue-reviews reports/no-issue-review`。
  - bash 3.2 和 5.3 各跑一次。脚本 blob 记在 `script-blob.txt`。
  - 和 R3 的逐行对比在 `imac/compare-r3.md`。
- 审查记录：`reports/no-issue-review/<repo>/<工作区目录名>.md`，共 18 份，由 Claude 只读查看后写的。
