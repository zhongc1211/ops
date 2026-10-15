---
title: 没确认过无副作用的预检命令，按真部署对待
date: 2026-10-13
category: lessons
kind: 验证太糙
seen: 1
seen_dates: [2026-10-13]
---

# 没确认过无副作用的预检命令，按真部署对待

**规则：** 跑 `cf-deploy.sh --check-only` 之前先记下目标 Worker 当前的版本号，跑完核对版本没有变；没核对过就当它会上线。

Seen 1×（2026-10-13）

## 出了什么事

- PER-41 验收时只跑了 `cf-deploy.sh --check-only`，正式部署命令被拦下，但 `xinyue-site-test` 已经变了：PER-43 正在验收的大嘴洞洞 3D（版本 `b8274158`）被只含涨水逃生 3D 的版本 `d02e23a5` 盖掉。来源：Linear PER-41，2026-10-13 10:30 SGT 的评论第 3 点。
- 后果：testing 上少了一款正在验收的游戏，要重新合并部署。生产部署用的是同一个脚本，同一条评论建议查 `cf deploy --dry-run` 会不会真的上线。

## 修复

- testing 重新部署了两款合在一起的版本 `30a9b2c7`（PER-43 `e13bcb3` + PER-41 `c76f0ac`），不是代码提交。
- `--check-only` 为什么会改 testing，当天的 PR 和 Linear 里没有看到后续结论。**未修。**

## Done right

- 验收的人自己在 Linear 里写出了这次覆盖，并指出生产走同一个脚本。
- 重新部署后的评论写了当前版本、回滚版本和各自包含什么。
