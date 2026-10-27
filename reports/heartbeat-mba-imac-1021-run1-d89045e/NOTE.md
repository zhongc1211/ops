# 第一次正式演练（commit d89045e，43 PASS、2 FAIL）

这是 `wake/tests/heartbeat-watch-ssh.sh` 在 commit `d89045e0acc51b7abd1e27f98b0e44467742b41c` 上的运行，2026-10-21 20:00:36 SGT 开始。
完整结果在这里的 `README.md` 和 `results.tsv`（演练脚本生成，没改过）。

## 为什么单独留在这里

跑完才发现 `raw/S1/*.env` 这 14 个文件被仓库的 `.gitignore`（`*.env`）挡掉，进不了仓库，`SHA256SUMS` 在新检出上会对不上。
演练脚本改成写 `.vars` 以后 commit 变了，按规矩在新 commit 上重跑，结果在 `../heartbeat-mba-imac-1021/`。
重跑会清空那个目录，所以把这次的汇总和两项 FAIL 的原始输出放在这里。没留的 raw 文件只在 iMac 的临时目录里，不保证留存。
`SHA256SUMS` 是从这次运行原来的 `SHA256SUMS` 里摘出这 13 个文件的行，`shasum -a 256 -c SHA256SUMS` 可以校验。

## 两项 FAIL

| 编号 | 位置 | 报错原文 | base 上的对照 |
|---|---|---|---|
| S9.94e4b0bc | `wake/tests/heartbeat-watch-ssh.sh` 第 462 行 | `orca automations show --id 94e4b0bc-… --environment grok-bot --json` 试了 3 次都是 `{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}`（`raw/S9/94e4b0bc.json`） | 没对照 base：这一项只读现网配置，不跑本 PR 的代码。同一次运行里 base 版读 box 也失败（下一行） |
| S6b.box | `wake/tests/heartbeat-watch-ssh.sh` 第 589 行 | 并行版 precheck 的 box 目标：`运行记录查不到（{"code": "remote_runtime_unavailable", …}）`（`raw/S6b/parallel.*`） | 紧接着用 base 版跑现网 5c2d0575 的 precheck（defs 里 before 的原文）：同样的 `remote_runtime_unavailable`（`raw/S6b/before-base.*`，20:02:16） |

两项都是 iMac 经 environment `grok-bot` 读 box 失败。现网 5c2d0575 自己的运行记录（`raw/S6b/live-5c2d0575-box.txt`）：
19:45 正常、19:50 同样 `remote_runtime_unavailable`、19:55 正常、20:00 正常。

b4a8163 上的重跑（20:05:37 开始）结果一样：43 PASS、2 FAIL，还是这两项、同样的报错；现网 5c2d0575 20:05 那次读 box
也是 `remote_runtime_unavailable`，base 版 20:06:58 读 box 同样失败（见 `../heartbeat-mba-imac-1021/raw/S6b/`）。

提交前在未提交的工作区上还试跑过两次，产物没进仓库：19:49 那次 43 PASS、1 FAIL（S6b 还没拆开，FAIL 也是 box 的
`remote_runtime_unavailable`）；19:58 那次 45 PASS。
