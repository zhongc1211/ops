---
title: cf builds 报 8000008/8000012 时停下报告，不自己建 token
date: 2026-10-15
category: lessons
kind: lessons
seen: 1
seen_dates: [2026-10-15]
origin: "status.md FDV-58（df5412e）"
---

# cf builds 报 8000008/8000012 时停下报告，不自己建 token

**规则：** `cf builds repos connections upsert` 报 8000008（Cloudflare GitHub App 看不到仓库）或 8000012（repository no longer exists），说明 App 没装到仓库所在的 owner，或者仓库转到组织后 owner id 已经失效；这时照 brief 停下报告，不要自己新建 API token 绕过去。

Seen 1×（2026-10-15）

## 出了什么事

- FDV-58：仓库转到 GitHub 组织 futuredeepvision 后，brief 里的 provider-account-id 28890418 失效；用旧 owner 报 8000012，用新 owner 报 8000008。
- 建 trigger 需要 build token，`cf builds tokens list` 返回空；CICD.md 规定不能自己建 token，所以停下，由 Zack 二选一。
