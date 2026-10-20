**环境不对：找不到 gh。--execute 什么都没做**

# ws-cleanup 执行（iMac，2026-10-21 04:26:25 SGT）

orca：`/Applications/Orca.app/Contents/Resources/bin/orca`；gh：`无`；工作区空闲门槛 0 小时，终端 24 小时；备份根目录 `/Users/jiawenwang/ops-drill/archive`；只看 repo aa123560-8996-445e-9798-58252049e7e5。

| 动作 | 工作区 |
|---|---|
| RM | 3 |
| BACKUP_RM | 4 |
| SKIP | 11 |

RM 合计约 0 MB，BACKUP_RM 合计约 32 MB（du）。

| 规则 | 个数 |
|---|---|
| W1 | 1 |
| W4 | 2 |
| W6 | 1 |
| W7 | 2 |
| W8 | 2 |
| W10 | 1 |
| W11 | 1 |
| W13 | 5 |
| W14 | 2 |
| W17 | 1 |

Linear 查不到的：1 个（都当作没关）

终端：SKIP 1（T7 1）

超过 30 天的备份（只列出，删除另外批准）：无

没做成的：0 个（见 worktrees.tsv / terminals.tsv 的 result 列，逐条动作见 journal.tsv）
