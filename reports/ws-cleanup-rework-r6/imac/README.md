# R6 iMac 全量 dry-run（真实环境，只读）

- 命令：`<bash> scripts/ws-cleanup.sh --out <dir> --no-issue-reviews reports/no-issue-review`，脚本 blob 见 `script-blob.txt`（b9c46ae，commit 9ce6a53）。
- `run1-bash3.2/`：11:38 用 `/bin/bash` 跑；`run2-bash5.3/`：11:43 用 `/usr/local/bin/bash` 跑。两次退出码 0，stderr 为空。
- 计数：3.2 是 SKIP 96、LIST 2；5.3 是 SKIP 97、LIST 1；RM 和 BACKUP_RM 都是 0。
  - 差的那一个是 ops-PER126-p2-sampler：11:40 别的会话新建，3.2 时还只在 git 里（W16），5.3 时已进 Orca、agent 在跑（W5）。
  - 其余行除随时间变的列（idle_h、mb、last_activity、unread）外一样。
- 和 R5 的逐行对比：`compare-r5.md`。
