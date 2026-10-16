---
title: cf 部署自定义域名会直接覆盖已有 DNS 记录
date: 2026-10-15
category: lessons
kind: lessons
seen: 1
seen_dates: [2026-10-15]
origin: "docs/deploy.md §2（7c1fe2c）"
---

# cf 部署自定义域名会直接覆盖已有 DNS 记录

**规则：** cf 在非交互环境里部署自定义域名时，会直接覆盖该子域名（例如 ads.deepvision.sg）已有的 DNS 记录，不会询问；部署前先查清这个子域名现在有没有别的用途。

Seen 1×（2026-10-15）
