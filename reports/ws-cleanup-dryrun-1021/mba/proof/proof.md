| 快照 | 字节完全一样 |
|---|---|
| wt.json | 否 |
| term.json | 否 |
| git.txt | 是 |

wt.json 在 result 之外不同的字段：`id`
term.json 在 result 之外不同的字段：`id`

**worktrees**：before 34 条、after 34 条；只在 before 里 0 条，只在 after 里 0 条。

**terminals**：before 15 条、after 15 条；只在 before 里 0 条，只在 after 里 0 条。
- 变了 `lastOutputAt, preview, title`：◑ PER-126 v3 方案（`term_e69f8401-2fe4-410d-a73c-c57e4b641215`）

**git worktree list**：40 行 / 40 行，不同的行：

**worktrees.tsv**（去掉 idle_h、procs 两列）：run1 34 行、run2 34 行，2 行不同。
- `/Users/jiawenwang/orca/workspaces/deepvision-site/fdv-70-calendar-claim`：mb `1354` → `1344`
- `/Users/jiawenwang/orca/workspaces/deepvision-site/fdv-70-g6-g7-g9`：mb `1907` → `1908`

**terminals.tsv**（去掉 idle_h、procs 两列）：run1 15 行、run2 15 行，完全一样。

