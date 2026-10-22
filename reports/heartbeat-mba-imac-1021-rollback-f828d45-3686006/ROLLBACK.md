# B1 回退测试：旧代码（base f828d45）上跑同一套演练

**结果：71 项里 71 项和期望一致，0 项不一致。期望挂的 40 项挂了 40 项；期望过的 31 项过了 31 项。**

把本 PR 的代码换回 base `f828d452345f16898d6c9d133984e170d98d9f83`，用本分支 `3686006c0cca6dfdef62d36b4f0eeee6bad02328` 的演练脚本和回放数据整轮跑 `wake/tests/heartbeat-watch-ssh.sh`。
期望先写在 `automations/heartbeat-1021/FAILURE-MODES.md`「回退测试的期望」「回退测试的期望（第二轮）」「回退测试的期望（第五轮）」「回退测试的期望（第五轮补）」「回退测试的期望（第五轮补充）」「回退测试的期望（第六轮）」六节，再跑。第五轮新加的 7 项该挂的（S13、S14 的 held、nodir、timeout）和第五轮补充新加的 6 项该挂的（S15、S15 的 .45、.bad），还要在演练的「实际」一栏里对上挂的原因（回退脚本里的 `WHY_RE`），第六轮另有 7 项核对原因，共 20 项；对不上记「不一致（挂了，但原因对不上）」。这个文件由回退脚本生成。

## 怎么重跑

在 iMac 的仓库根目录：

```bash
wake/tests/heartbeat-watch-ssh-rollback.sh
```

要求和 `wake/tests/heartbeat-watch-ssh.sh` 一样。整个目录会被重写（有 `.hb-drill` 标记才清空）。

## 旧代码怎么放回去

- 在临时目录里 `git clone --shared` 本仓库，`checkout --detach` 到 base。base 里没有 `scripts/orca-via-ssh`、`scripts/lock-held-alert` 和 `automations/heartbeat-1021/register.sh`，`scripts/heartbeat-watch.sh` 是 base 那份。
- 放进去的只有测试和定义：HEAD 的 `wake/tests/heartbeat-watch-ssh.sh`、`wake/tests/hb-replay/`，加一份现网版 `automations/heartbeat-1021/defs.json`（`rollback/defs-live.json`）。
- 现网版 defs：MBA 那条的 precheck 是现网 box `94e4b0bc` 的原文 `$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "iMac ops · 01 卡住工作检查|iMac|439cd438-cffe-44dd-bd2b-23b07bfa3d61|20"`（environment `iMac`，不经 ssh）；`5c2d0575` 的并行版、最终版都是它的现网原文 `$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "box ops · 29 卡住检查心跳|grok-bot|94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80|20"`。都没有 lockf 和 lock-held-alert（base 里也没有 `scripts/lock-held-alert`）。
- 这个目录里的 `README.md`、`results.tsv`、`env.txt`、`raw/` 是演练脚本照常生成的：`env.txt` 的 commit 是 base，「未提交的改动」数的是上面放进去的文件。

旧代码检出的情况（`rollback/tree.txt`）：

```
旧代码：f828d452345f16898d6c9d133984e170d98d9f83（git clone --shared 后 checkout --detach）
测试取自：3686006c0cca6dfdef62d36b4f0eeee6bad02328
没有 scripts/orca-via-ssh
没有 scripts/lock-held-alert
没有 automations/heartbeat-1021/register.sh
有 scripts/heartbeat-watch.sh（sha256 a408563a6a3cd0d0）
base 之外放进去的（git status --porcelain --untracked-files=all）：
?? automations/heartbeat-1021/defs.json
?? wake/tests/hb-replay/clock/sitecustomize.py
?? wake/tests/hb-replay/fixtures/list-imac.json
?? wake/tests/hb-replay/fixtures/runs-439cd438.json
?? wake/tests/hb-replay/orca
?? wake/tests/hb-replay/replay.py
?? wake/tests/heartbeat-watch-ssh.sh
```

## 这次运行

- 时间 2026-10-22 09:06:38 SGT
- 命令 wake/tests/heartbeat-watch-ssh.sh
- commit f828d452345f16898d6c9d133984e170d98d9f83（分支 HEAD）
- 代码有没有未提交的改动（scripts automations wake）：3 个文件
- base（和 origin/main 的分叉点）f828d452345f16898d6c9d133984e170d98d9f83
- iMac：iMac，macOS 26.6.2 x86_64，GNU bash, version 3.2.57(1)-release (x86_64-apple-darwin25)，Python 3.9.6，perl v5.34.1，OpenSSH_10.3p1, LibreSSL 3.3.6，orca 1.4.237，shellcheck 0.11.0
- MBA：mba，macOS 26.6.2 arm64，GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)，Python 3.9.6，perl v5.34.1，OpenSSH_10.3p1, LibreSSL 3.3.6，orca 1.4.237

## 期望挂的 40 项（本 PR 会改变结果）

「raw/ 里的输出原文」：冒号前是 `raw/` 下的文件，冒号后是这些文件里不空的前两行（去掉开头的时间戳，⏎ 隔开）。

| 编号 | 为什么该挂 | 实际 | 和期望 | raw/ 里的输出原文（截到 240 字） | 演练的「实际」一栏（截到 160 字；核对原因的 20 项截到 600 字） |
|---|---|---|---|---|---|
| S0.diff | base 和「本分支」是同一份，没有第 7、13、33 行的改动 | FAIL | 一致 | S0/diff-base-new.txt：（raw/S0/diff-base-new.txt 没有内容） |  |
| S0.bot | base 收件人仍是 coding-assistant | FAIL | 一致 | S0/diff-base-new.txt：（raw/S0/diff-base-new.txt 没有内容） | 本分支第 33 行 BOT = "coding-assistant"；base BOT = "coding-assistant"；已装版 BOT = "coding-assistant" |
| S1.bot | 本分支这版是 base，ops-system 待发行数为 0 | FAIL | 一致 | S1/c02.new.out：iMac ops · 01 卡住工作检查：中断：最新心跳在 10-21 19:30，已 30 分钟没有新的（阈值 20 分钟）：Orca 调度器停了或脚本没在跑 ⏎ dry-run，将 POST 给 coding-assistant：{"task": "检查任务没在跑：iMac ops · 01 卡住工作检查", "worktree": "本机", "status": "stuck", "kind": "heartbeat_stale", "machine": "本机", "… | 本分支这版 coding-assistant 出现 6 行，「将 POST 给 ops-system」0 行；base「将 POST 给 coding-assistant」6 行 |
| S5.iMac | 没有 scripts/orca-via-ssh | FAIL | 一致 | S5-imac/edit.err：env: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/scripts/orca-via-ssh: No such file or directory | 0/14 条符合；不符： allow-list(退出 127，ssh 0 次) allow-runs(退出 127，ssh 0 次) create(退出 127，ssh 0 次) edit-id(退出 127，ssh 0 次) edit(退出 127，ssh 0 次) host-empty(退出 127，ssh 0 次… |
| S8.mba | 没有 register.sh | FAIL | 一致 | S8/mba.out、S8/mba.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.imac-noid | 没有 register.sh | FAIL | 一致 | S8/imac.out、S8/imac.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.parallel | 没有 register.sh | FAIL | 一致 | S8/imac-parallel.out、S8/imac-parallel.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.final | 没有 register.sh | FAIL | 一致 | S8/imac-final.out、S8/imac-final.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.rollback | 没有 register.sh | FAIL | 一致 | S8/imac-rollback.out、S8/imac-rollback.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.refuse | 没有 register.sh | FAIL | 一致 | S8/bad-id.out、S8/bad-id.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/automations/heartbeat-1021/register.sh: No such file or directory | 退出码不是 2 的： bad-id mba-stage box stage-novalue unknown-flag；假 orca 被调用 0 次；--apply 没跑（任务书禁止） |
| S6b.parallel | 现网 5c2d0575 只有 box 目标，没有 MBA 目标 | FAIL | 一致 | S6b/parallel.out、S6b/parallel.err：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，1.8 分钟前，rc 0，上次扫描 2 分钟前） | ；退出 1；box 那行：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，1.8 分钟前，rc 0，上次扫描 2 分钟前）；顺序不对（box） |
| S6b.final | 现网 5c2d0575 只有 box 目标，没有 MBA 目标 | FAIL | 一致 | S6b/final.out、S6b/final.err：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，2.2 分钟前，rc 0，上次扫描 2 分钟前） | ；退出 1 |
| S14.iMac.held | 现网版 precheck 没套 lockf：heartbeat-watch 照常起来，建出了那个不存在的目录，退出不是 75 | FAIL | 一致 | S14-imac/held.out、S14-imac/held.err：box ops · 29 卡住检查心跳：运行记录查不到（JSONDecodeError），已连续 0 分钟 | 退出 1，stdout 123 字节，stderr：空；目录有；替身 3 次（orca-ide 3 次）；持锁的 lockf 起的 sleep：50994，lockf 退出 0；stdout：2026-10-22 09:08:11 SGT box ops · 29 卡住检查心跳：运行记录查不到（JSONDecodeError），已连续 0 分钟；状态文件：没有 |
| S14.iMac.nodir | 现网版 precheck 没有锁文件这一步，照常跑，建出了那个不存在的目录，退出不是 73 | FAIL | 一致 | S14-imac/nodir.out、S14-imac/nodir.err：box ops · 29 卡住检查心跳：运行记录查不到（JSONDecodeError），已连续 0 分钟 | 退出 1，stdout 123 字节，stderr：空；目录有；替身 3 次（orca-ide 3 次）；stdout：2026-10-22 09:08:27 SGT box ops · 29 卡住检查心跳：运行记录查不到（JSONDecodeError），已连续 0 分钟；状态文件：没有 |
| S14.iMac.timeout | 现网版 precheck 没套 lockf：第一轮还在跑的时候探锁，退出 0；替身起了至少 1 次；第一轮到 12 秒被杀 | FAIL | 一致 | S14-imac/timeout.probe.rc、S14-imac/timeout.probe.err：0 | 探锁退出 0（空），探锁在第一轮开始后 5.6–5.7 秒（第一轮还在跑）；第一轮超时被杀，用时 12.0 秒；替身起了 1 次（orca-ide 1 次），被杀以后都没了；第二轮没超时，用时 9.1 秒，退出 1，stderr 没有 already locked；box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，3.6 分钟前，rc 0，上次扫描 4 分钟前） |
| S15.iMac | 现网版 precheck 没套 lockf 和 lock-held-alert：外部拿着的锁没人用，第 1 轮照常起 heartbeat-watch，退出不是 75，状态目录被建出来；4 轮都没跳过，假 curl 0 次（没有告警，也没有恢复） | FAIL | 一致 | S15-imac/r1.out、S15-imac/r1.err：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，3.7 分钟前，rc 0，上次扫描 4 分钟前） | 第 1–4 轮退出 1、1、1、1（跳过 0 轮），开始于第 1 轮后 0.4、10.1、21.3、30.7 秒，第 1 轮后状态目录有；第 1–4 轮 stdout：1「box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，3.7 分钟前，rc 0，上次扫描 4 分钟前）…」 / 2「box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，3.9 分钟前，rc 0，上次扫描 4 分钟前）…」 / 3「box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，4.1 分钟前，rc 0，上次扫描 4 分钟前）…」 / 4「box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，4.2 分钟前，rc 0，上次扫描 4 分钟前）…」；第 3 轮后状态文件没记报过（null）；第 1 条告警：没有，note 里没有主机名「iMac」、没有锁文件名、目标名缺了；持锁的 sleep 在第 1 轮后 40.5 秒结束（lockf 退出 0）；第 5 轮：退出 1，没有 already locked，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，4.4 分钟前，rc 0，上次扫描 4 分钟前）；lock-held-alert：没有它的行；第 2 条：没有；第 5 轮后状… |
| S15.iMac.45 | 现网版 precheck 没有 lock-held-alert：两轮都照常跑，退出不是 75，假 curl 0 次 | FAIL | 一致 | S15-imac/45a.out、S15-imac/45a.err：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，4.7 分钟前，rc 0，上次扫描 5 分钟前） | 44 分钟：退出 1，stdout：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，4.7 分钟前，rc 0，上次扫描 5 分钟前）…，假 curl 0 次；46 分钟：退出 1，stdout：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，4.9 分钟前，rc 0，上次扫描 5 分钟前）…，假 curl 0 次（没有），之后状态文件没记报过；演练写的状态文件：{"first": 1792628777.214058, "last": 1792631117.214058, "skips": 9} / {"first": 1792628666.595715, "last": 1792631126.595715, "skips": 9} |
| S15.iMac.bad | 现网版 precheck 没有 lock-held-alert：照常跑，退出不是 75 | FAIL | 一致 | S15-imac/bad-a.out、S15-imac/bad-a.err：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，0.1 分钟前，rc 0，上次扫描 0 分钟前） | 乱码：退出 1，stdout：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，0.1 分钟前，rc 0，上次扫描 0 分钟前）…，之后状态文件 没有；目录：退出 1，stdout：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，0.3 分钟前，rc 0，上次扫描 0 分钟前）…，stderr：（stderr 没有 lock-held-alert 的行）；假 curl 0 次 |
| S15.iMac.rf | 现网版没有 lockf 和 lock-held-alert，每轮照常跑，假 curl 0 次 | FAIL | 一致 | S15-imac/rf-a.out、S15-imac/rf-a.err：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，0.5 分钟前，rc 0，上次扫描 0 分钟前） | rf-a：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，0.5 分钟前，rc 0，上次扫描 0 分钟前）…，之后状态文件 {first、last、skips 9}；rf-b：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，0.6 分钟前，rc 0，上次扫描 1 分钟前）…，之后状态文件 {first、last、skips 9}；rf-c：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，0.8 分钟前，rc 0，上次扫描 1 分钟前）…，之后状态文件 {first、last、skips 9}；rf-d：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，1.0 分钟前，rc 0，上次扫描 1 分钟前）…，之后状态文件 {first、last、skips 9}；rf-e：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，1.1 分钟前，rc 0，上次扫描 1 分钟前）…，之后状态文件 {alerted、recovered}；rf-f：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，1.3 分钟前，rc 0，上次扫描 1 分钟前）…，之后状态文… |
| S15.iMac.old | 现网版没有 lockf 和 lock-held-alert，每轮照常跑，假 curl 0 次 | FAIL | 一致 | S15-imac/old-a.out、S15-imac/old-a.err：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，1.5 分钟前，rc 0，上次扫描 1 分钟前） | old-a：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，1.5 分钟前，rc 0，上次扫描 1 分钟前）…，之后状态文件 {first、last、skips 1}；old-b：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，1.6 分钟前，rc 0，上次扫描 2 分钟前）…，之后状态文件 {first、last、skips 7}；old-c：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，1.8 分钟前，rc 0，上次扫描 2 分钟前）…，之后状态文件 {first、last、skips 7}；old-d：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，1.9 分钟前，rc 0，上次扫描 2 分钟前）…，之后状态文件 {alerted（演练写的 3 天前）、first、last、skips 9}；old-e：退出 1，box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:10，2.1 分钟前，rc 0，上次扫描 2 分钟前）…，之后状态文件 {alerted（演练写的 3 天前）、first、last、skips 9}；old-f：退出 1，box ops · 29 卡住检查心跳：正常（最新心… |
| S2.sh | 现网版 precheck 在 MBA 上读不到 iMac ops · 01：MBA 的 Orca 没有 environment iMac | FAIL | 一致 | mba/S2-sh.out、mba/S2-sh.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 | ；退出 1 |
| S2.zsh | 现网版 precheck 在 MBA 上读不到 iMac ops · 01：MBA 的 Orca 没有 environment iMac | FAIL | 一致 | mba/S2-zsh.out、mba/S2-zsh.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 | ；退出 1 |
| S3 | base 的待发告警发给 coding-assistant | FAIL | 一致 | mba/S3.out、mba/S3.err：iMac ops · 01 卡住工作检查：中断：最新心跳在 10-22 08:43，已 30 分钟没有新的（阈值 20 分钟）：Orca 调度器停了或脚本没在跑 ⏎ dry-run，将 POST 给 coding-assistant：{"task": "检查任务没在跑：iMac ops · 01 卡住工作检查", "worktree": "本机", "status": "stuck", "kind": "heartbeat_stale", "machine": "本机", "… | dry-run，将 POST 给 coding-assistant：{"task": "检查任务没在跑：iMac ops · 01 卡住工作检查", "worktree": "本机", "status": "stuck", "kind": "heartbeat_stale", "machine": "本机", "source": "heartbeat-watch", "note": "最新心跳在 10-22 08:43，已 30 分钟没有新的（阈值 20 分钟）：Orca 调…；退出 1 |
| S4 | 没有包装，heartbeat-watch 报的是 FileNotFoundError，不是 ssh 连不上的 JSONDecodeError | FAIL | 一致 | mba/S4.out、mba/S4.err：iMac ops · 01 卡住工作检查：运行记录查不到（FileNotFoundError），已连续 0 分钟 | ；退出 1；用时 16 秒 |
| S4.wrapper | 没有 scripts/orca-via-ssh | FAIL | 一致 | mba/S4-wrapper.out、mba/S4-wrapper.err：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.yh9fWOciTw/orca-via-ssh: No such file or directory | 退出 127，stdout 0 字节，stderr：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.yh9fWOciTw/orca-via-ssh: No such file or directory |
| S4b | 没有包装，heartbeat-watch 报的是 FileNotFoundError，不是 ssh 连不上的 JSONDecodeError | FAIL | 一致 | mba/S4b.out、mba/S4b.err：iMac ops · 01 卡住工作检查：运行记录查不到（FileNotFoundError），已连续 50 分钟 ⏎ iMac ops · 01 卡住工作检查：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（FileNotFoundError），心跳没法确认 | ；退出 1；state.json 没被改 |
| S5.MBA | 没有 scripts/orca-via-ssh | FAIL | 一致 | mba/S5/edit.out、mba/S5/edit.err：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.yh9fWOciTw/orca-via-ssh: No such file or directory | 0/14 条符合；不符： allow-list(退出 127，ssh 0 次) allow-runs(退出 127，ssh 0 次) create(退出 127，ssh 0 次) edit-id(退出 127，ssh 0 次) edit(退出 127，ssh 0 次) host-empty(退出 127，ssh 0 次… |
| S5b | 没有 scripts/orca-via-ssh | FAIL | 一致 | mba/S5b.out、mba/S5b.err：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.yh9fWOciTw/orca-via-ssh: No such file or directory | stdout 不是 JSON；ok=-；orca 收到的值不是原样；error.message：；退出 127 |
| S7 | 没有 scripts/orca-via-ssh | FAIL | 一致 | mba/S7-runs.err：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.yh9fWOciTw/orca-via-ssh: No such file or directory | runs 退出 127、None 条运行记录、None 行 @@HB，最新心跳 None 分钟前（rc None）；list 退出 127、None 个自动任务，439cd438「None」createdAt None |
| S12 | 现网版 precheck 不经 ssh：MBA 的 Orca 没有 environment iMac，几秒内就查不到（invalid_argument），ssh 替身一次都没起 | FAIL | 一致 | mba/S12.out、mba/S12.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 … | 没超时，用时 17.1 秒，退出 1；iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is nam… |
| S13 | 现网版 precheck 没套 lockf：B 在 A 跑的期间照常跑完一轮（没超时、退出 1、调了 orca），B 前后状态目录不一样 | FAIL | 一致 | mba/S13-B.out、mba/S13-B.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 … | A：没超时，用时 107.9 秒，退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no pair，@@HB rc 0，ssh 0 次、orca 3 次；B：A 开始后 4.2 秒开始、A 结束前 86.9 秒结束（在 A 跑的期间），没超时，用时 16.7 秒，退出 1，stdout 394 字节，stderr：空，ssh 0 次、orca 3 次，状态目录前后不一样；C：A 结束后 0.1 秒开始，没超时，用时 16.6 秒，退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no pair，@@HB rc 0，ssh 0 次、orca 3 次；假 curl 0 次；状态文件：./heartbeat.json ./state.json ./watch.log；lock-held-alert：A 的 stdout 里没有它的行；B 的 stdout：iMac ops · 01 卡住工作检查：运行记录查不到（{"cod… |
| S14.MBA.held | 现网版 precheck 没套 lockf：heartbeat-watch 照常起来，建出了那个不存在的目录，退出不是 75 | FAIL | 一致 | mba/S14/held.out、mba/S14/held.err：iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟 | 退出 1，stdout 124 字节，stderr：空；目录有；替身 3 次（orca 3 次）；持锁的 lockf 起的 sleep：23008，lockf 退出 0；stdout：2026-10-22 09:16:42 SGT iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；状态文件：没有 |
| S14.MBA.nodir | 现网版 precheck 没有锁文件这一步，照常跑，建出了那个不存在的目录，退出不是 73 | FAIL | 一致 | mba/S14/nodir.out、mba/S14/nodir.err：iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟 | 退出 1，stdout 124 字节，stderr：空；目录有；替身 3 次（orca 3 次）；stdout：2026-10-22 09:16:58 SGT iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；状态文件：没有 |
| S14.MBA.timeout | 现网版 precheck 没套 lockf：第一轮还在跑的时候探锁，退出 0；替身起了至少 1 次；第一轮到 12 秒被杀 | FAIL | 一致 | mba/S14/timeout.probe.rc、mba/S14/timeout.probe.err：0 | 探锁退出 0（空），探锁在第一轮开始后 3.7–3.7 秒（第一轮还在跑）；第一轮超时被杀，用时 12.0 秒；替身起了 1 次（orca 1 次），被杀以后都没了；第二轮没超时，用时 16.6 秒，退出 1，stderr 没有 already locked；iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac." |
| S15.MBA | 现网版 precheck 没套 lockf 和 lock-held-alert：外部拿着的锁没人用，第 1 轮照常起 heartbeat-watch，退出不是 75，状态目录被建出来；4 轮都没跳过，假 curl 0 次（没有告警，也没有恢复） | FAIL | 一致 | mba/S15/r1.out、mba/S15/r1.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 | 第 1–4 轮退出 1、1、1、1（跳过 0 轮），开始于第 1 轮后 0.1、16.8、33.5、50.2 秒，第 1 轮后状态目录有；第 1–4 轮 stdout：1「iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…」 / 2「iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…」 / 3「iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…」 / 4「iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…」；第 3 轮后状态文件没记报过（null）；第 1 条告警：没有，note 里没有主机名「mba」、没有锁文件名、目标名缺了；持锁的 sleep 在第 1 轮后 66.9 秒结束（lockf 退出 0）；第 5 轮：退出 1，没有 already locked，（没有「iMac ops · 01 卡住工作检查：正常（最新心跳」那行）；loc… |
| S15.MBA.45 | 现网版 precheck 没有 lock-held-alert：两轮都照常跑，退出不是 75，假 curl 0 次 | FAIL | 一致 | mba/S15/45a.out、mba/S15/45a.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 | 44 分钟：退出 1，stdout：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，假 curl 0 次；46 分钟：退出 1，stdout：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，假 curl 0 次（没有），之后状态文件没记报过；演练写的状态文件：{"first": 1792629336.130228, "last": 1792631676.130228, "skips": 9} / {"first": 1792629233.000695, "last": 1792631693.000695, "skips": 9} |
| S15.MBA.bad | 现网版 precheck 没有 lock-held-alert：照常跑，退出不是 75 | FAIL | 一致 | mba/S15/bad-a.out、mba/S15/bad-a.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 | 乱码：退出 1，stdout：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 没有；目录：退出 1，stdout：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，stderr：（stderr 没有 lock-held-alert 的行）；假 curl 0 次 |
| S15.MBA.rf | 现网版没有 lockf 和 lock-held-alert，每轮照常跑，假 curl 0 次 | FAIL | 一致 | mba/S15/rf-a.out、mba/S15/rf-a.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 | rf-a：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {first、last、skips 9}；rf-b：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {first、last、skips 9}；rf-c：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {first、last、skips 9}；rf-d：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {first、last、skips 9}；rf-e：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {alerted、recovered}；r… |
| S15.MBA.old | 现网版没有 lockf 和 lock-held-alert，每轮照常跑，假 curl 0 次 | FAIL | 一致 | mba/S15/old-a.out、mba/S15/old-a.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [{"id": "ssh-1），已连续 0 分钟 | old-a：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {first、last、skips 1}；old-b：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {first、last、skips 7}；old-c：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {first、last、skips 7}；old-d：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态文件 {alerted（演练写的 3 天前）、first、last、skips 9}；old-e：退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Or…，之后状态… |
| S11 | orca-via-ssh、register.sh 不存在 | FAIL | 一致 | S11/bash-n.txt：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/scripts/orca-via-ssh: No such file or directory ⏎ /bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.GNaRn2DxAI/tree/scripts/lock-h… | bash -n 429 字节输出；lint 4 行；shellcheck 3 行；最后一步：… … |

## 期望过的 31 项（本 PR 不改变结果，用来排除「是环境坏了才挂」）

| 编号 | 实际 | 和期望 | 实际原文（截到 200 字） |
|---|---|---|---|
| S0.same | PASS | 一致 | base=fc59716e01d2 installed=fc59716e01d2 new=fc59716e01d2  |
| S1.c01 | PASS | 一致 | iMac ops · 01 卡住工作检查：正常（最新心跳 10-21 19:58，2.0 分钟前，rc 1，上次扫描 11 分钟前）；退出 1；三版一致 |
| S1.c02 | PASS | 一致 | iMac ops · 01 卡住工作检查：中断：最新心跳在 10-21 19:30，已 30 分钟没有新的（阈值 20 分钟）：Orca 调度器停了或脚本没在跑；退出 1；三版一致 |
| S1.c03 | PASS | 一致 | iMac ops · 01 卡住工作检查：中断：心跳还在（10-21 19:59），但上次跑完的扫描在 10-21 19:20，已 40 分钟没跑完：扫描每次超时被杀或每次出错；退出 1；三版一致 |
| S1.c04 | PASS | 一致 | iMac ops · 01 卡住工作检查：中断：最近 101 次运行记录里没有心跳行（@@HB），最新一次运行在 10-21 19:57；退出 1；三版一致 |
| S1.c05 | PASS | 一致 | iMac ops · 01 卡住工作检查：已恢复，报过一次；退出 1；三版一致 |
| S1.c06 | PASS | 一致 | iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；退出 1；三版一致 |
| S1.c07 | PASS | 一致 | iMac ops · 01 卡住工作检查：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（JSONDecodeError），心跳没法确认；退出 1；三版一致 |
| S1.c08 | PASS | 一致 | iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；退出 1；三版一致 |
| S1.c09 | PASS | 一致 | iMac ops · 01 卡住工作检查：自动任务建好 5 分钟（不到 20 分钟），还没有心跳，这次不判断；退出 1；三版一致 |
| S1.c10 | PASS | 一致 | iMac ops · 01 卡住工作检查：还在中断（10-21 19:50 起已报过，不重复报）：最新心跳在 10-21 19:30，已 30 分钟没有新的（阈值 20 分钟）：Orca 调度器停了或脚本没在跑；退出 1；三版一致 |
| S1.c11 | PASS | 一致 | 用法：heartbeat-watch.sh --target "名字\|environment\|自动任务 id\|N 分钟" [--target ...] [--precheck] [--dry-run]；退出 2；三版一致 |
| S1.c12 | PASS | 一致 | iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "automation_not_found", "message": "Automation not found: 439cd438-cffe-44dd-bd2b-23b07bfa3d61"}），已连续 0 分钟；退出 1；三版一致 |
| S1.c13 | PASS | 一致 | MBA ops · 29 心跳互查：中断：最新心跳在 10-21 19:30，已 30 分钟没有新的（阈值 20 分钟）：Orca 调度器停了或脚本没在跑；退出 1；三版一致 |
| S1.c14 | PASS | 一致 | iMac ops · 01 卡住工作检查：正常（最新心跳 10-21 19:58，2.0 分钟前，rc 1，上次扫描 11 分钟前）；退出 0；三版一致 |
| S1.curl | PASS | 一致 | 假 curl 被调用 0 次 |
| S9.5c2d0575 | PASS | 一致 | 名字「ops · 29 心跳互查（盯 box ops · 29）」、超时 240、启用 True、precheck 等于 defs |
| S9.94e4b0bc | PASS | 一致 | 名字「ops · 29 卡住检查心跳（盯 iMac ops · 01）」、rrule */5 * * * *、超时 240、grace 720、启用 True、precheck 等于 defs |
| S9.439cd438 | PASS | 一致 | 名字「ops · 01 卡住工作检查」、超时 600、启用 True、rrule * * * * * |
| S9.mba | PASS | 一致 | 9 个自动任务，同名的 0 个，ops · 09：ops · 09 内存与 CPU 负载清理 MBA |
| S6 | PASS | 一致 | MBA ops · 09 内存与 CPU 负载清理：中断：最近 101 次运行记录里没有心跳行（@@HB），最新一次运行在 10-22 08:37；退出 0 |
| S6b.box | PASS | 一致 | box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，1.8 分钟前，rc 0，上次扫描 2 分钟前）；退出 1；紧接着用 base 版跑现网 precheck（raw/S6b/before-base.*）：box ops · 29 卡住检查心跳：正常（最新心跳 10-22 09:05，2.0 分钟前，rc 0，上次扫描 2 分钟前）；现网 5c2d0575 最近几次对 … |
| S14.iMac.kill | PASS | 一致 | 第一次探退出 75（lockf: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-drill.RiCBQCQg9g/s14/…）；kill -KILL 51845（pid 51845、ppid 47449 是演练的 shell、命令名 /usr/bin/lockf）；它退出 137；第二次探退出 0；锁文件有；发信号以后它起的 sleep：5… |
| S14.iMac.term | PASS | 一致 | 第一次探退出 75（lockf: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-drill.RiCBQCQg9g/s14/…）；kill -TERM 52216（pid 52216、ppid 47449 是演练的 shell、命令名 /usr/bin/lockf）；它退出 143；第二次探退出 0；锁文件有；发信号以后它起的 sleep：5… |
| S14.iMac.crash | PASS | 一致 | 第一次探退出 75（lockf: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-drill.RiCBQCQg9g/s14/…）；kill -SEGV 52778（pid 52778、ppid 47449 是演练的 shell、命令名 /usr/bin/lockf）；它退出 139；第二次探退出 0；锁文件有；发信号以后它起的 sleep：5… |
| S12.old | PASS | 一致 | 超时 240 秒，超时被杀（timedOut），用时 240.1 秒；@@HB 没有；状态目录里什么都没有；ssh 起了 3 次，相邻开始隔 97、99 秒；第二次起来后 0 秒查，第一次的 ssh 已经没了；跑完时都没了 |
| S14.MBA.kill | PASS | 一致 | 第一次探退出 75（lockf: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.yh9fWOciTw/s14/…）；kill -KILL 23160（pid 23160、ppid 21756 是演练的 shell、命令名 /usr/bin/lockf）；它退出 137；第二次探退出 0；锁文件有；发信号以后它起的 sleep：2… |
| S14.MBA.term | PASS | 一致 | 第一次探退出 75（lockf: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.yh9fWOciTw/s14/…）；kill -TERM 23336（pid 23336、ppid 21756 是演练的 shell、命令名 /usr/bin/lockf）；它退出 143；第二次探退出 0；锁文件有；发信号以后它起的 sleep：2… |
| S14.MBA.crash | PASS | 一致 | 第一次探退出 75（lockf: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.yh9fWOciTw/s14/…）；kill -SEGV 23505（pid 23505、ppid 21756 是演练的 shell、命令名 /usr/bin/lockf）；它退出 139；第二次探退出 0；锁文件有；发信号以后它起的 sleep：2… |
| S10.MBA | PASS | 一致 | 没有 ~/.orca-state/bin/heartbeat-watch.sh 没有 ~/.orca-state/bin/orca-via-ssh 没有 ~/.orca-state/bin/lock-held-alert 没有 ~/.orca-state/heartbeat-watch 没有 ~/.orca-state/heartbeat-watch/mba-hb-watch.lock 没有 ~/… |
| S10.iMac | PASS | 一致 | 已装版 a36d3dc8a88702a8 → a36d3dc8a88702a8；有 ~/.orca-state/bin/heartbeat-watch.sh 没有 ~/.orca-state/bin/orca-via-ssh 没有 ~/.orca-state/bin/lock-held-alert 有 ~/.orca-state/heartbeat-watch 没有 ~/.orca-state/h… |

## 文件

- `rollback.tsv`：每项一行：编号、回退后期望、实际、和期望一不一致、为什么该挂、演练的「实际」一栏、raw/ 里的输出原文。
- `rollback/tree.txt`：旧代码检出的情况。`rollback/defs-live.json`：现网版 defs。`rollback/drill.log`：演练的屏幕输出。
- `README.md`、`results.tsv`、`env.txt`、`raw/`：演练脚本在旧代码上生成的，格式同 `reports/heartbeat-mba-imac-1021/`。
- `SHA256SUMS`：除它自己以外所有文件的 sha256（`shasum -a 256 -c SHA256SUMS` 校验）。
