# S6b.box 和期望不一致的说明

这个文件是回退测试跑完以后手写的，不在 `SHA256SUMS` 里。

这次回退测试 56 项里 55 项和期望一致，S6b.box 不一致：期望过，实际挂了。

- 用例：S6b.box，`wake/tests/heartbeat-watch-ssh.sh:861`（`17116ce`）。
- 报错原文（`raw/S6b/parallel.out`，2026-10-22 00:46:22 SGT）：
  `box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}），已连续 0 分钟`。
  紧接着的 `raw/S6b/before-base.out`（00:46:42）、`raw/S6b/final.out`（00:47:03）是同样的报错。
- 这一项读的是 iMac 经 environment `grok-bot` 连到 box 的运行记录。三方面对照：
  - 这次回退测试跑的就是 base 代码，所以「base 上的结果」就是这一次：挂了。
  - 同一项在新代码上（`reports/heartbeat-mba-imac-1021-run6-17116ce/`，00:38:32）过了，box 那行是「正常」；紧接着用 base 版跑现网 precheck（00:38:49）也是「正常」。
  - 现网 5c2d0575（现网配置、iMac 已装的 heartbeat-watch，本 PR 没动）00:50 那一轮读 box 也是同样的报错。
    下面是 2026-10-22 00:53:43 SGT 在 iMac 上只读查到的：命令是 `orca automations runs --id 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --json`，
    每一轮只摘 precheck stdout 里 box 那行，去掉开头的时间戳。

```
00:50 box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}），已连续 0 分钟
00:45 box ops · 29 卡住检查心跳：正常（最新心跳 10-22 00:41，4.2 分钟前，rc 0，上次扫描 4 分钟前）
00:40 box ops · 29 卡住检查心跳：正常（最新心跳 10-22 00:36，4.3 分钟前，rc 0，上次扫描 4 分钟前）
00:35 box ops · 29 卡住检查心跳：正常（最新心跳 10-22 00:31，4.2 分钟前，rc 0，上次扫描 4 分钟前）
00:30 box ops · 29 卡住检查心跳：正常（最新心跳 10-22 00:25，5.0 分钟前，rc 0，上次扫描 5 分钟前）
00:25 box ops · 29 卡住检查心跳：正常（最新心跳 10-22 00:25，0.0 分钟前，rc 0，上次扫描 0 分钟前）
```

这一项挂的原因是那段时间 iMac 连不上 box（回退测试里 00:46:22–00:47:03 三次，现网 00:50 一次），不是代码的问题。回退测试没有重跑。
