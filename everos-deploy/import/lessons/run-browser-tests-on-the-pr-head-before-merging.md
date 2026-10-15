---
title: 合并前在 PR 的 head 上跑过受影响的浏览器用例
date: 2026-10-13
category: lessons
kind: 不该合的
seen: 1
seen_dates: [2026-10-13]
---

# 合并前在 PR 的 head 上跑过受影响的浏览器用例

**规则：** 合并前等 CI 的四个 check 在 PR 的 head 上出结果；改了哪个模块，就确认对应的 Playwright spec 跑过。

Seen 1×（2026-10-13）

## 出了什么事

- #54（PER-35，10-11）把 `https://xy.deepvision.sg` 加进运行器的嵌入方名单，开 PR 后 24 秒合并，正文里的验证只有 `npm test`。`tests/browser/runtime-embedders.spec.mjs` 里写死的名单没有跟着改。
- 后果：这个 spec 的 2 个用例在 desktop 和 mobile 各失败一次，共 4 条，在 `feat/xinyue-site` 上红了两天，直到 10-13 #74 第一次在 CI 上跑全量浏览器测试才发现。
- 10-13 当天 #66（开 PR 后 11 分钟合并）、#73（8 分钟）、#68–#71 合并时仓库还没有 CI，依据都是本地结果。

## 修复的提交

`85719cc`（#74）：补齐 spec 的名单，新域名加进「可以嵌入运行器」的循环。

## Done right

- #74 自己等四个 check 在 `85719cc` 上全绿才合，合并记录写了合并的 head。
- #74 的验证记录给了改动前（run 38352175784，7 条失败）和改动后（run 38355103445，0 条失败）两次 CI。
