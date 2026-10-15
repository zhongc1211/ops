---
title: PR 正文引用的验证结果，发 PR 时就要在
date: 2026-10-13
category: lessons
kind: 验证太糙
seen: 1
seen_dates: [2026-10-13]
---

# PR 正文引用的验证结果，发 PR 时就要在

**规则：** PR 正文说「结果写在下面的评论里」时，那条评论要已经发出；CI 出红后在 PR 里写明是哪条用例、与改动有没有关系。

Seen 1×（2026-10-13）

## 出了什么事

- #75（PER-46，泡泡砰砰）22:28 SGT 开出，正文写「旧页面的回归和完整 `npm test` 的结果写在下面的评论里」。到 23:30 夜审时，PR 下只有 Linear 的自动回链，没有这条评论。
- 同一个 head `43c8706` 上 CI 的 Playwright (mobile) 失败（run 38413685844）：`tests/browser/site-change.spec.mjs:394`「the owner tries the eraser of a draft in the preview」1 条失败，197 条通过。PR 里没有提到。这条用例不在 #75 改动的范围内；`feat/xinyue-site` 的 `a8cac8a` 上同一个 job 是通过的。是偶发还是被改动影响，没有查。
- 后果：现在读 PR 的人看不到旧页面有没有被影响。PR 还开着、没有合并，所以没有实际损失。

## 修复

还没有。#75 仍是 open。

## Done right

- #75 正文写了测试跑在哪个提交、什么机器、什么命令，并分开写了真实时钟和假时钟的用例，以及 2D 画面「帧率没测」。
- #74 的验证记录和 PR 同一小时内发出，包含一节「没跑的」。
