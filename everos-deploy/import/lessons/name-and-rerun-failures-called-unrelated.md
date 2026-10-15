---
title: 说「失败与本次改动无关」时，附用例名和在 base 上的重跑结果
date: 2026-10-13
category: lessons
kind: 验证太糙
seen: 1
seen_dates: [2026-10-13]
---

# 说「失败与本次改动无关」时，附用例名和在 base 上的重跑结果

**规则：** 把失败归为「与本次改动无关」时，写出用例名和在 base 上重跑的结果；同一批失败第二次出现就开单查，不再照抄。

Seen 1×（2026-10-13）

## 出了什么事

- 10-13 的记录里「4 条失败」有三种说法：#66 写 `npm test` 596/600，2 条是中文路径下 `playcheck-workerd` 找不到 `migrations`，2 条是负载高超时；#67、#73 的上线评论写 650/654，失败在 `playcheck-workerd` 和 `studio-pages`（后台打包失败），「干净检出上同样失败」；PER-44 的派活说明写的是「`npm test` 在干净检出上失败的 4 条」。
- #74 查的结果：`5ce215b` 上 `npm test` 在本机 worktree、全新 clone、含中文字符的路径和 GitHub runner 上都是 654 条全过。一直红着的 4 条在 Playwright 的 `runtime-embedders.spec.mjs`。
- 后果：几个 PR 带着「已知失败」合并，其中真正一直失败的那 4 条没有人查了两天；`npm test` 那几条到底在什么条件下失败，记录里互相对不上。

## 修复的提交

`85719cc`（#74）修了 Playwright 的 4 条。`npm test` 的失败没有复现，没有改动。

## Done right

- #66 把同一个提交放到纯英文路径下重跑失败的文件，全部通过后才写「无关」。
- #72 写了失败的文件名（`playcheck-clock`）和单独重跑的结果（4/4）。
- #74 没有复现就写「没有复现」，没有为了让 CI 变绿去标记或跳过 `npm test` 的用例。
