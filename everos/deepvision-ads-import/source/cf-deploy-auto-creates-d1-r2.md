---
title: cf deploy 会自动创建不存在的 D1/R2
date: 2026-10-15
category: lessons
kind: lessons
seen: 1
seen_dates: [2026-10-15]
origin: "docs/deploy.md §2（7c1fe2c）"
---

# cf deploy 会自动创建不存在的 D1/R2

**规则：** `cf deploy`（1.0.0-beta.14）默认会自动创建配置里引用、但实际不存在的 D1 和 R2；生产资源必须先由人手工建好，把真实 ID 写进配置，然后才把 main 连到生产 Worker。

Seen 1×（2026-10-15）

## 怎么做

- 生产 D1 ID 是占位符 `PRODUCTION_D1_DATABASE_ID`；`scripts/deploy.sh production` 看到占位符会报错退出。不要为了让部署跑通去换掉占位符。
