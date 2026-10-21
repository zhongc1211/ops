## 真实工作区：R1 127 行，R2 128 行
| 结论 | R1 | R2 | 差 |
|---|---|---|---|
| RM | 19 | 19 | +0 |
| BACKUP_RM | 14 | 13 | -1 |
| SKIP | 93 | 95 | +2 |
| LIST | 1 | 1 | +0 |

逐行有变化的：
- xinyue-site xy-combined-src：SKIP W4 → SKIP W11（Orca 状态是 in-progress，不是 completed）
- deepvision-ads dvads-privacy-facts：BACKUP_RM W13 → SKIP W7（有未提交改动 2 项）
- ops ops-per126-v5-write-1021：（R1 没有） → SKIP W5（agent 在跑（终端里或 Orca 记录里））
- ops ops-stuck-routing-1020：SKIP W9 → SKIP W18（GIT_LOCKED：index.lock）

## 演练仓库：R1 25 行，R2 25 行
| 结论 | R1 | R2 | 差 |
|---|---|---|---|
| RM | 0 | 0 | +0 |
| BACKUP_RM | 0 | 0 | +0 |
| SKIP | 25 | 25 | +0 |
| LIST | 0 | 0 | +0 |

逐行有变化的：
- ws-cleanup-drill d11-locked：SKIP W12 → SKIP W18（GIT_LOCKED：git worktree lock）
- ws-cleanup-drill d11-locked：SKIP W12 → SKIP W18（GIT_LOCKED：git worktree lock）

