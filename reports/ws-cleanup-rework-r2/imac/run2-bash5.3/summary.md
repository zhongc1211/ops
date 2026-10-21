# ws-cleanup dry-run（iMac，2026-10-21 08:02:03 SGT）

orca：`/Applications/Orca.app/Contents/Resources/bin/orca`；gh：`/usr/local/bin/gh`；工作区空闲门槛 24 小时，终端 24 小时；备份根目录 `/Users/jiawenwang/ops-archive/ws-cleanup`。

| 动作 | 工作区 |
|---|---|
| RM | 19 |
| BACKUP_RM | 13 |
| SKIP | 120 |
| LIST | 1 |

RM 合计约 1550 MB，BACKUP_RM 合计约 7337 MB（du）。

| 规则 | 个数 |
|---|---|
| W1 | 10 |
| W2 | 1 |
| W4 | 2 |
| W5 | 17 |
| W6 | 1 |
| W7 | 7 |
| W8 | 4 |
| W9 | 11 |
| W10 | 16 |
| W11 | 24 |
| W12 | 19 |
| W13 | 13 |
| W14 | 19 |
| W16 | 1 |
| W17 | 5 |
| W18 | 3 |

状态冲突、这次不删、等 Zack 定的：14 个（worktrees.tsv 里 W11 且原因写「状态冲突」）

GIT_LOCKED（W18）：3 个（gitdir 里有锁或没做完的 git 操作，这次不删）

Linear 查不到的：2 个（都当作没关）

终端：SKIP 21（T1 12，T3 2，T7 6，T8 1）

超过 30 天的备份（只列出，删除另外批准）：无
