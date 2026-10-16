---
title: box 上的重任务要先过阻塞闸门（内存 ≥4G、load <6）
date: 2026-10-14
category: rule
kind: rule
seen: 1
seen_dates: [2026-10-14]
origin: "box auto-memory box-heavy-job-gate.md（FIXSTACK seg3，Zack 定）"
---

# box 上的重任务要先过阻塞闸门（内存 ≥4G、load <6）

**规则：** 在 box 上跑 build、测试、部署、e2e 之前，先在循环里阻塞等待，直到可用内存 ≥4G 且 1 分钟 load <6，每 3 分钟查一次；load ≥16 时绝不启动；同一时间只跑一个重任务。

Seen 1×（2026-10-14）

## 出了什么事

- FIXSTACK 第 3 段：只把 load 打印出来、没有真的拦住，testing 部署在 load 32 时启动了。之后 Zack 定为硬规则。

## 怎么做

- 用一个只有闸门打开才会退出的脚本，再用 `&&` 串起来：`gate.sh && scripts/deploy.sh testing`。不要只 echo 一下 load 就继续往下跑。
