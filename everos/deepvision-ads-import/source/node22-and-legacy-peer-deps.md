---
title: 本项目用 Node 22，装依赖要带 --legacy-peer-deps
date: 2026-10-12
category: rule
kind: rule
seen: 1
seen_dates: [2026-10-12]
origin: "AGENTS.md Hard rules（7bbf786）；docs/deploy.md 构建变量"
---

# 本项目用 Node 22，装依赖要带 --legacy-peer-deps

**规则：** box 上系统自带的是 Node 20，本项目要用 Node 22：先 `export PATH=$HOME/.local/node22/bin:$PATH`，装依赖用 `npm install --legacy-peer-deps`。

Seen 1×（2026-10-12）

## 怎么做

- Workers Builds 的构建变量同样要设：`NODE_VERSION=22.23.2`、`NPM_CONFIG_LEGACY_PEER_DEPS=true`。
