---
title: 迁移文件编号等于 Linear issue 编号，已合并的迁移不改
date: 2026-10-12
category: rule
kind: rule
seen: 1
seen_dates: [2026-10-12]
origin: "AGENTS.md Conventions（7bbf786）"
---

# 迁移文件编号等于 Linear issue 编号，已合并的迁移不改

**规则：** D1 迁移文件命名为 `migrations/00NN_<name>.sql`，NN 是 Linear issue 编号（FDV-37 → `0037_…`），这样叠加的分支之间不会撞号；已经合并的迁移不改。

Seen 1×（2026-10-12）

## 怎么做

- 要撤销一个已合并迁移的效果，另写一个新的迁移。
