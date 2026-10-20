# ws-cleanup list-only（MBA，2026-10-21 02:09:14 SGT）

orca：`/Applications/Orca.app/Contents/Resources/bin/orca`；空闲门槛 24 小时；备份根目录 `/Users/jiawenwang/ops-archive/ws-cleanup`。

| 动作 | 工作区 |
|---|---|
| LIST | 34 |

只列出；如果在这台机器上清理，结论会是：BACKUP_RM 2，SKIP 32

RM 合计约 0 MB，BACKUP_RM 合计约 1952 MB（du）。

| 规则 | 个数 |
|---|---|
| W1 | 6 |
| W5 | 7 |
| W7 | 1 |
| W9 | 5 |
| W10 | 8 |
| W12 | 5 |
| W13 | 2 |

终端：LIST 15（T1 8，T2 3，T4 4）

超过 30 天的备份（只列出，删除另外批准）：无
