# 第六轮以前的运行与披露原文

以下来自前一位 Claude 在 PR #75 的正文（接手前快照），仅保留历史事实；其中第一人称属于前一位执行者，不能解读为当前 Codex 会话亲历。第六轮的新运行和限制以本轮报告为准。

## 全部运行

全部列在这里，没有挑。时间是 SGT；演练的「结果」只列 FAIL 项。

| 开始时间 | 代码 | 结果 | 产物 |
|---|---|---|---|
| 10-21 19:49 | 未提交的工作区（S6b 还没拆成三项） | FAIL：S6b.parallel，box `remote_runtime_unavailable` | 没进仓库 |
| 10-21 19:58 | 未提交的工作区（内容和 d89045e 相同） | 没有 FAIL | 没进仓库 |
| 10-21 20:00 | `d89045e0acc51b7abd1e27f98b0e44467742b41c` | FAIL：S9.94e4b0bc、S6b.box，box `remote_runtime_unavailable` | `reports/heartbeat-mba-imac-1021-run1-d89045e/`：汇总和两项 FAIL 的原始输出，说明在 `NOTE.md` |
| 10-21 20:05 | `b4a8163bbcdf2b9bb0efdc475bed1290583ded5e` | FAIL：同样两项、同样的报错 | `reports/heartbeat-mba-imac-1021/` |
| 10-21 20:29 | `84e4922ddc0bbe3a2e13f50b46f58c40f7d70bc0` | 没有 FAIL | `reports/heartbeat-mba-imac-1021-run3-84e4922/` |
| 10-21 20:31 | 回退测试：代码 base，测试取自 `84e4922ddc0bbe3a2e13f50b46f58c40f7d70bc0` | 45 项都和期望一致：19 项该挂的挂了，26 项该过的过了 | `reports/heartbeat-mba-imac-1021-rollback-f828d45/` |
| 10-21 21:46（第二轮） | `78c59631acb3a1103a30d037e09d4934a2f62b71` | 没有 FAIL | `reports/heartbeat-mba-imac-1021-run4-78c5963/` |
| 10-21 22:01（第二轮） | 回退测试：代码 base，测试取自 `78c59631acb3a1103a30d037e09d4934a2f62b71` | 47 项都和期望一致：20 项该挂的挂了，27 项该过的过了 | `reports/heartbeat-mba-imac-1021-rollback-f828d45-78c5963/` |
| 10-21 22:44（第三轮） | `a62fa3242b74fbf376be81e465e3871a9efd1c05` | FAIL：S12.old（改代码前写明会挂，`FAILURE-MODES.md` A29） | `reports/heartbeat-mba-imac-1021-run5-a62fa32/` |
| 10-22 00:27（第五轮，试跑） | 未提交的工作区：`d33fe4a` 加上这一轮改的 5 个文件，和 `17116ce` 只差 S13 判断里的一处 | FAIL：S13，判断代码的错（见下面） | 没进仓库 |
| 10-22 00:37:51–00:44:05（第五轮） | `17116ce4991e5ef2e71c4cdbb695c3024aed9393` | 56 项都过 | `reports/heartbeat-mba-imac-1021-run6-17116ce/` |
| 10-22 00:45:11–00:52:44（第五轮） | 回退测试：代码 base，测试取自 `17116ce4991e5ef2e71c4cdbb695c3024aed9393` | 56 项里 55 项和期望一致，退出 1：S6b.box 期望过、实际挂了，iMac 连不上 box（见下面）。另外 S13、S14.MBA.timeout 挂了，但不是因为期望里写的原因（见「第五轮」最后一段） | `reports/heartbeat-mba-imac-1021-rollback-f828d45-17116ce/`，说明在 `NOTE.md` |
| 10-22 01:11:35–01:17:45（第五轮） | `a29addd1f487937e8fbd4169addca9157cea0c7a` | 56 项都过 | `reports/heartbeat-mba-imac-1021-run7-a29addd/` |
| 10-22 01:18:40–01:26:15（第五轮） | 回退测试：代码 base，测试取自 `a29addd1f487937e8fbd4169addca9157cea0c7a` | 56 项都和期望一致（该挂 27、该过 29），新加的 7 项挂的原因都对上 | `reports/heartbeat-mba-imac-1021-rollback-f828d45-a29addd/` |
| 10-22 02:29:58–02:37:51（第五轮补充） | `6fd55573c3b7871509b5b72eae796dba061b89c0` | 66 项都过。S14.MBA.crash 的崩溃报告数只数了一个目录（只记不判），见「第五轮补充」 | `reports/heartbeat-mba-imac-1021-run8-6fd5557/`，说明在 `NOTE.md` |
| 10-22 02:42:39–02:50:51（第五轮补充） | `62a8ec954c8507fb6b9969eab2d18b7a5528b650` | 66 项都过 | `reports/heartbeat-mba-imac-1021-run9-62a8ec9/` |
| 10-22 02:53:12–03:01:05（第五轮补充） | `6e144e163e8f04a367b3e5607a046ea39e8a5c4c` | 66 项都过 | `reports/heartbeat-mba-imac-1021-run10-6e144e1/` |
| 10-22 03:02:51–03:15:21（第五轮补充） | 回退测试：代码 base，测试取自 `6e144e163e8f04a367b3e5607a046ea39e8a5c4c` | 66 项都和期望一致（该挂 33、该过 33），新加的 13 项挂的原因都对上 | `reports/heartbeat-mba-imac-1021-rollback-f828d45-6e144e1/` |

上表的回退测试，代码都是 base `f828d452345f16898d6c9d133984e170d98d9f83`。

- 10-21 20:00、20:05 两次的两项 FAIL，报错都是 iMac 经 environment `grok-bot` 读 box 时连不上。据 ops bot，box 20:00 卡死后 X display :4 没了，box 的 orca serve 一直退出，20:07 修好：

  | 用例 | 位置（b4a8163 的行号） | 报错原文 | base 上的对照 |
  |---|---|---|---|
  | S9.94e4b0bc | `wake/tests/heartbeat-watch-ssh.sh:462` | `orca automations show --id 94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80 --environment grok-bot --json` 试了 3 次，都是 `{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}` | 没对照 base：这一项只读现网配置，不执行本 PR 的代码。同一次运行里 base 版读 box 也是这个报错（下一行） |
  | S6b.box | `wake/tests/heartbeat-watch-ssh.sh:589` | 并行版 precheck 的 box 目标：`运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}），已连续 0 分钟` | 紧接着用 base 版跑现网 5c2d0575 的 precheck，20:06:58 得到同样的报错（`reports/heartbeat-mba-imac-1021/raw/S6b/before-base.*`） |

- `17116ce` 回退测试的 S6b.box：00:46:22–00:47:03 iMac 经 grok-bot 读 box 三次都是 `remote_runtime_unavailable`；现网 `5c2d0575` 00:50 那一轮读 box 也是同样的报错。这一项在 base 上不执行本 PR 的代码。按 `FAILURE-MODES.md` C16，期望不改，没有为这个原因重跑。
- d89045e 跑完发现 `raw/S1/*.env` 被仓库的 `.gitignore`（`*.env`）挡掉，进不了仓库，`SHA256SUMS` 在新检出上会对不上。b4a8163 只把这些文件改名成 `.vars`，场景和断言没改，按规矩在新 commit 上重跑。
- 10-21 20:29 前后，回退报告的生成部分（`ROLLBACK.md` 那段 Python）在 b4a8163 那次的产物上试跑过一次，只看报告格式对不对，不是演练，结果没进仓库。
- 第五轮试跑（10-22 00:27）：56 项里 55 项和期望一致。S13 挂在判断代码上：B 的用时是 0.021 秒，`.orca.json` 里记成 `0.0`，判断写的是 `(bo.get("durationS") or 99) <= 3`，Python 把 0.0 当成没有值，换成了 99。B 本身和期望一致。判断改成先判 `is not None` 再比 `<= 3`，期望没变，改动在 `17116ce` 里。试跑的产物在我的会话临时目录，没进仓库。
- 10-22 01:10 前后，提交 `a29addd` 之前，用造的数据（在会话临时目录里，不进仓库）跑过一次新判断和 `WHY_RE`，只核对写法，不是演练。
- 第五轮补充：`6fd5557` 和 `62a8ec9` 上都没跑回退测试，原因见「偏离和披露」。第二轮、第三轮没有试跑；第四轮没跑演练。


## 偏离和披露

- **演练以外给自己起的进程发过信号**（都在我的会话临时目录里，进程都是我刚起的）：
  - 10-21 23:42（iMac）：手试 lockf，给自己起的 lockf（pid 8918）发 SIGKILL，它起的 `sleep 6` 让它自己结束；给自己起的一个测试进程组（sh、lockf、`sleep 30`）发 SIGTERM；一个子进程 `sh -c 'kill -TERM $$'` 给它自己发 SIGTERM。
  - 10-22 00:01（iMac）：试 `pgrep -P` 的写法时，给自己起的 `sleep 30`（pid 21503）发 SIGTERM。
  - 10-22 01:33（iMac）：手测 F33，给自己起的 lockf 发 SIGTERM、SIGSEGV。SIGSEGV 那次留下 `~/Library/Logs/DiagnosticReports/lockf-2026-10-22-013355.ips`。
  - 10-22 01:54（iMac）：试跑 lock-held-alert（假 curl），一个子进程 `sh -c 'kill -TERM $$'` 给它自己发 SIGTERM，看被信号杀掉时的退出码。
  - 10-22 02:16–02:18（iMac）：在临时目录里先试跑 S15 和 S14 的 iMac 部分，kill、term、crash 各给自己起的 lockf 发一次信号，留下 `lockf-2026-10-22-021802.ips`。这次试跑的 S15 第 5、6 轮和 S14.timeout 第二轮经 Orca 只读了真的 box 和 MBA（带 `--dry-run`），告警只发给假 curl。结果都和期望一致，没进仓库。
  - MBA 上演练以外只跑过只读的命令：`ls`、`shasum`、`sw_vers`、不带参数的 `lockf`（打印用法）、读 Orca 的 app.asar、`defaults read`、`pgrep -l`、`ps -o pid,ppid,rss,etime,comm`。
- **看进程超出了任务书写的两种写法**：10-22 01:2x 核对回退测试时用过 `ps -axo pid,ppid,etime,command | grep -E '[s]leep …'`，另一次用过 `pgrep -lf heartbeat-watch`（两次输出都是空的）；MBA 上查 Orca 版本时用过 `ps -o pid,ppid,rss,etime,comm -ax | grep -i "Orca.app/Contents/MacOS/Orca$"`；查 sleep 是谁起的，用过 `pgrep -lP <pid>` 和 `ps -o ppid= -p <pid>`；查自己的 shell 往上是哪个 claude 进程，用过 `ps -o pid,ppid,etime,comm`。都没杀进程。
- **拿错了替身试跑**：10-22 01:10（iMac，提交 `a29addd` 之前），我想单独试 S13 的新替身，用 awk 从演练脚本里截出来的却是 S12 的替身，在会话临时目录里以 `orca --version`、`ssh -V` 跑了两次。它 exec 了 `/usr/bin/ssh 'sleep 110'`，ssh 把 `sleep 110` 当成主机名，退出 255，没有连出去。改成从 `local d=$R/s13` 以后截，截对了。
- **只记不判的数记错过目录**：F33 写「没有多出崩溃报告」是错的，F36 更正；F36 写的目录对 MBA 不对，F37 更正。`6fd5557` 的演练里 S14.MBA.crash 记的「0 个、0 个」只数了 `~/Library/Logs/DiagnosticReports/`，说明在那次产物目录里手写的 `NOTE.md`（不在 `SHA256SUMS` 里）。
- **崩溃报告留在两台本机**：见「为什么安全」。是 macOS 写的，我没删；它们在用户和系统的日志目录里，不在仓库里。
- **两台的 Orca 自己升级过**：iMac 10-21 23:15 前后、MBA 10-22 00:55 前后，不是本 PR 动的（F28、F35）。
- **「状态记在锁目录旁边」的理解**：状态文件放在锁文件旁边（同一个目录，`<锁文件>.skips.json`），没另建目录。
- **选了告警，没写心跳行**：理由见「第五轮补充」(a) 和 F34。
- **有两个 commit 上没跑回退测试**：`6fd5557` 的演练跑完发现崩溃报告数的目录不对，先改演练；`62a8ec9` 的演练跑完以后改了 README 的两处文字（`6e144e1`）。这两次都在新 commit 上把演练和回退测试一起重跑了。
- **判断代码的错**：第五轮试跑（10-22 00:27）S13 挂在判断代码上（`(bo.get("durationS") or 99) <= 3` 把 0.0 当成没有值），修在 `17116ce`，期望没变，见「全部运行」。
