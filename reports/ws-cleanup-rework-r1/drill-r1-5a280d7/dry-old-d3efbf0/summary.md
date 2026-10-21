# ws-cleanup dry-run（iMac，2026-10-21 04:25:10 SGT）

orca：`/Applications/Orca.app/Contents/Resources/bin/orca`；空闲门槛 0 小时；备份根目录 `/Users/jiawenwang/ops-drill/archive`。

| 动作 | 工作区 |
|---|---|
| RM | 65 |
| BACKUP_RM | 16 |
| SKIP | 63 |
| LIST | 1 |

RM 合计约 11742 MB，BACKUP_RM 合计约 6138 MB（du）。

| 规则 | 个数 |
|---|---|
| W1 | 10 |
| W2 | 1 |
| W4 | 4 |
| W5 | 10 |
| W7 | 3 |
| W8 | 1 |
| W9 | 12 |
| W10 | 18 |
| W11 | 8 |
| W13 | 16 |
| W14 | 61 |
| W16 | 1 |

终端：CLOSE 9，SKIP 13（T1 12，T3 1，T4 9）

超过 30 天的备份（只列出，删除另外批准）：无
