| 快照 | 字节完全一样 |
|---|---|
| wt.json | 否 |
| term.json | 否 |
| wps.json | 否 |
| git.txt | 是 |

wt.json 在 result 之外不同的字段：`id`
term.json 在 result 之外不同的字段：`id`
wps.json 在 result 之外不同的字段：`id`
本任务自己的终端：`term_5deddc53-8ba6-4ea7-a986-f5615e70952a`

**wt.json worktrees**：before 126 条、after 126 条；只在 before 里 0 条，只在 after 里 0 条。
- 变了 `sortOrder`：125 条（全部只变了这些字段）

**wps.json worktrees**：before 127 条、after 127 条；只在 before 里 0 条，只在 after 里 0 条。
- 变了 `sortOrder`：121 条（全部只变了这些字段）
- 变了 `lastOutputAt, sortOrder`：ops-PER-134-dryrun-fix、ops · PER-94 pstack 新版监测设计
- 变了 `agents, lastOutputAt, liveTerminalCount, preview, sortOrder, status`：ops · ops bot 定位草稿评审 B（pi Astra max，只读）
- 变了 `lastOutputAt, preview, sortOrder`：ops-cleanup-rules-draft-1021
- 变了 `agents, lastActivityAt, lastOutputAt, preview`：本机管理

**term.json terminals**：before 20 条、after 21 条；只在 before 里 0 条，只在 after 里 1 条。
- 变了 `lastOutputAt`：✳ PER-94 PR #55 iMac 任务交接（`term_bf077c75-4d1d-4d81-8e8c-068ff8c5c645`）、✳ PER-134 任务简报（`term_fa68ec24-8ff3-46d7-9661-cba2877e16d9`）
- 变了 `lastOutputAt, preview`：✳ Orca CLI 多 Linear 账号支持（`term_4045de0c-0618-4ffe-b806-84692cfc4741`）
- 变了 `lastOutputAt, preview, title`：◑ RULES-DRAFT 文件撰写（`term_5deddc53-8ba6-4ea7-a986-f5615e70952a`）

**git worktree list**：518 行 / 518 行，不同的行：

**worktrees.tsv**（去掉 idle_h、procs 两列）：run1 127 行、run2 127 行，完全一样。

**terminals.tsv**（去掉 idle_h、procs 两列）：run1 20 行、run2 20 行，完全一样。

