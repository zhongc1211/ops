---
title: 一个模块对应一个 issue、一个 worktree、一个 PR，不超过 2000 行
date: 2026-10-12
category: rule
kind: rule
seen: 1
seen_dates: [2026-10-12]
origin: "AGENTS.md Hard rules（7bbf786）"
---

# 一个模块对应一个 issue、一个 worktree、一个 PR，不超过 2000 行

**规则：** 一个功能模块对应一个 Linear issue、一个 Orca worktree、一个 PR；每个 PR 不超过 2000 行改动（不计 package-lock.json），按 docs/features.md 表格的顺序叠加。

Seen 1×（2026-10-12）

## 怎么做

- 开 PR 前跑 `git diff --stat <base>`，确认行数，并确认只改了本模块的文件。
- PR 正文写：改了什么、没碰什么、验证命令、回滚方式，并链接 Linear issue。
