---
title: 回滚 Worker 版本不会回退 D1 迁移
date: 2026-10-15
category: lessons
kind: lessons
seen: 1
seen_dates: [2026-10-15]
origin: "docs/deploy.md §5（7c1fe2c）"
---

# 回滚 Worker 版本不会回退 D1 迁移

**规则：** 在后台回滚 Worker 版本，或把 staging 重置到上一个 commit，都不会回退 D1 迁移；需要回退的迁移要另写一个迁移。

Seen 1×（2026-10-15）
