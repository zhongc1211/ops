---
title: 租户数据的查询必须带 workspace_id 或 org_id 过滤
date: 2026-10-12
category: rule
kind: rule
seen: 1
seen_dates: [2026-10-12]
origin: "AGENTS.md Conventions（7bbf786）"
---

# 租户数据的查询必须带 workspace_id 或 org_id 过滤

**规则：** D1 一律通过 `getDb()` 用 prepared statement 访问；查询租户数据时必须按 `workspace_id` 或 `org_id` 过滤；工作区页面先调用 `requireWorkspace(org, ws)`，组织页面先调用 `requireOrg`。

Seen 1×（2026-10-12）
