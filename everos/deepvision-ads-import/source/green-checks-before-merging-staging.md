---
title: 合进 staging 前先确认 PR 检查是绿的
date: 2026-10-15
category: lessons
kind: lessons
seen: 1
seen_dates: [2026-10-15]
origin: "docs/deploy.md §1（8b5001c）"
---

# 合进 staging 前先确认 PR 检查是绿的

**规则：** Workers Builds 只看 Cloudflare 那边配置的分支，不等 GitHub Actions 的结果；staging 上的检查失败了，testing 也照样部署，所以合进 staging 之前要先确认 PR 上的检查是绿的。

Seen 1×（2026-10-15）
