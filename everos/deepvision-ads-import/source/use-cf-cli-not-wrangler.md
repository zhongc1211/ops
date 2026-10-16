---
title: 部署和设置 secret 用 Cloudflare CLI（npx cf），不用 wrangler
date: 2026-10-12
category: rule
kind: rule
seen: 1
seen_dates: [2026-10-12]
origin: "AGENTS.md Hard rules（7bbf786）"
---

# 部署和设置 secret 用 Cloudflare CLI（npx cf），不用 wrangler

**规则：** 部署和设置 secret 用 Cloudflare CLI（`npx cf`），不用 `wrangler deploy` / `wrangler secret`；不留常驻的 server 或预览进程。

Seen 1×（2026-10-12）

## 怎么做

- testing 的部署走 Workers Builds（push 到 staging 触发），手工部署用 `scripts/deploy.sh testing`。
- 用完的预览服务器和轮询要关掉。
