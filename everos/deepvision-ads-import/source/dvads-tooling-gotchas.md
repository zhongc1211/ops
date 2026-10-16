---
title: deepvision-ads 在 box 上的工具坑：gh pr edit、node_modules 软链、cf d1 cwd
date: 2026-10-14
category: lessons
kind: lessons
seen: 1
seen_dates: [2026-10-14]
origin: "box auto-memory dv-ads-tooling-gotchas.md"
---

# deepvision-ads 在 box 上的工具坑：gh pr edit、node_modules 软链、cf d1 cwd

**规则：** `gh pr edit --body-file` 在本仓库会失败，改用 `gh api -X PATCH repos/<owner>/deepvision-ads/pulls/N -F body=@file`；不要软链 node_modules（typecheck 和测试能过，但 OpenNext 部署会失败），要用 `cp -al`；`npx cf d1 query` 必须在一个含 node_modules 的目录里跑。

Seen 1×（2026-10-14）

## 细节

- gh pr edit 失败的原因是 Projects classic 的 GraphQL 已弃用。
- 软链 node_modules 时，OpenNext 会按解析后的路径去打包 sharp 的 `.node` 文件。
- `cf d1 query` 在没有 node_modules 的目录下会报 `EACCES mkdir /node_modules/.cache`。
