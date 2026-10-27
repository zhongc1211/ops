# ws-cleanup dry-run（iMac，2026-10-21 10:55:20 SGT）

orca：`/usr/local/bin/orca`；gh：`/usr/local/bin/gh`；工作区空闲门槛 24 小时，终端 24 小时；备份根目录 `/Users/jiawenwang/ops-archive/ws-cleanup`。

| 动作 | 工作区 |
|---|---|
| BACKUP_RM | 3 |
| SKIP | 92 |
| LIST | 1 |

RM 合计约 0 MB，BACKUP_RM 合计约 10 MB（du）。

| 规则 | 个数 |
|---|---|
| W1 | 9 |
| W2 | 1 |
| W5 | 17 |
| W7 | 3 |
| W9 | 16 |
| W10 | 11 |
| W11 | 12 |
| W12 | 12 |
| W16 | 1 |
| W17 | 6 |
| W19 | 8 |

状态冲突、这次不删、等 Zack 定的：12 个（worktrees.tsv 里 W11 且原因写「状态冲突」）

NO_LINEAR_ISSUE（W19）：5 个（没挂 Linear issue，这次不删）

没挂 Linear、审查记录 DELETE_OK 且 HEAD 对得上、走 BACKUP_RM 的：3 个（记录目录 `/Users/jiawenwang/orca/workspaces/ops/ops-cleanup-rules-draft-1021/reports/no-issue-review`）

终端：SKIP 20（T1 12，T3 2，T7 5，T8 1）

超过 30 天的备份（只列出，删除另外批准）：无
