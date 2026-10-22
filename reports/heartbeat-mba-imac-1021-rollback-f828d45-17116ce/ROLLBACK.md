# B1 回退测试：旧代码（base f828d45）上跑同一套演练

**结果：56 项里 55 项和期望一致，1 项不一致。期望挂的 27 项挂了 27 项；期望过的 29 项过了 28 项。**

把本 PR 的代码换回 base `f828d452345f16898d6c9d133984e170d98d9f83`，用本分支 `17116ce4991e5ef2e71c4cdbb695c3024aed9393` 的演练脚本和回放数据整轮跑 `wake/tests/heartbeat-watch-ssh.sh`。
期望先写在 `automations/heartbeat-1021/FAILURE-MODES.md`「回退测试的期望」「回退测试的期望（第二轮）」「回退测试的期望（第五轮）」三节，再跑。这个文件由回退脚本生成。

## 怎么重跑

在 iMac 的仓库根目录：

```bash
wake/tests/heartbeat-watch-ssh-rollback.sh
```

要求和 `wake/tests/heartbeat-watch-ssh.sh` 一样。整个目录会被重写（有 `.hb-drill` 标记才清空）。

## 旧代码怎么放回去

- 在临时目录里 `git clone --shared` 本仓库，`checkout --detach` 到 base。base 里没有 `scripts/orca-via-ssh` 和 `automations/heartbeat-1021/register.sh`，`scripts/heartbeat-watch.sh` 是 base 那份。
- 放进去的只有测试和定义：HEAD 的 `wake/tests/heartbeat-watch-ssh.sh`、`wake/tests/hb-replay/`，加一份现网版 `automations/heartbeat-1021/defs.json`（`rollback/defs-live.json`）。
- 现网版 defs：MBA 那条的 precheck 是现网 box `94e4b0bc` 的原文 `$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "iMac ops · 01 卡住工作检查|iMac|439cd438-cffe-44dd-bd2b-23b07bfa3d61|20"`（environment `iMac`，不经 ssh）；`5c2d0575` 的并行版、最终版都是它的现网原文 `$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "box ops · 29 卡住检查心跳|grok-bot|94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80|20"`。都没有 lockf。
- 这个目录里的 `README.md`、`results.tsv`、`env.txt`、`raw/` 是演练脚本照常生成的：`env.txt` 的 commit 是 base，「未提交的改动」数的是上面放进去的文件。

旧代码检出的情况（`rollback/tree.txt`）：

```
旧代码：f828d452345f16898d6c9d133984e170d98d9f83（git clone --shared 后 checkout --detach）
测试取自：17116ce4991e5ef2e71c4cdbb695c3024aed9393
没有 scripts/orca-via-ssh
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

- 时间 2026-10-22 00:45:13 SGT
- 命令 wake/tests/heartbeat-watch-ssh.sh
- commit f828d452345f16898d6c9d133984e170d98d9f83（分支 HEAD）
- 代码有没有未提交的改动（scripts automations wake）：3 个文件
- base（和 origin/main 的分叉点）f828d452345f16898d6c9d133984e170d98d9f83
- iMac：iMac，macOS 26.6.2 arm64，GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)，Python 3.9.6，perl v5.34.1，OpenSSH_10.3p1, LibreSSL 3.3.6，orca 1.4.235，shellcheck 0.11.0
- MBA：mba，macOS 26.6.2 arm64，GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)，Python 3.9.6，perl v5.34.1，OpenSSH_10.3p1, LibreSSL 3.3.6，orca 1.4.229

## 期望挂的 27 项（本 PR 会改变结果）

「raw/ 里的输出原文」：冒号前是 `raw/` 下的文件，冒号后是这些文件里不空的前两行（去掉开头的时间戳，⏎ 隔开）。

| 编号 | 为什么该挂 | 实际 | 和期望 | raw/ 里的输出原文（截到 240 字） | 演练的「实际」一栏（截到 160 字） |
|---|---|---|---|---|---|
| S0.diff | base 和「本分支」是同一份，没有第 13 行的改动 | FAIL | 一致 | S0/diff-base-new.txt：（raw/S0/diff-base-new.txt 没有内容） |  |
| S5.iMac | 没有 scripts/orca-via-ssh | FAIL | 一致 | S5-imac/edit.err：env: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/scripts/orca-via-ssh: No such file or directory | 0/14 条符合；不符： allow-list(退出 127，ssh 0 次) allow-runs(退出 127，ssh 0 次) create(退出 127，ssh 0 次) edit-id(退出 127，ssh 0 次) edit(退出 127，ssh 0 次) host-empty(退出 127，ssh 0 次… |
| S8.mba | 没有 register.sh | FAIL | 一致 | S8/mba.out、S8/mba.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.imac-noid | 没有 register.sh | FAIL | 一致 | S8/imac.out、S8/imac.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.parallel | 没有 register.sh | FAIL | 一致 | S8/imac-parallel.out、S8/imac-parallel.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.final | 没有 register.sh | FAIL | 一致 | S8/imac-final.out、S8/imac-final.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.rollback | 没有 register.sh | FAIL | 一致 | S8/imac-rollback.out、S8/imac-rollback.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/automations/heartbeat-1021/register.sh: No such file or directory | ；退出 127 |
| S8.refuse | 没有 register.sh | FAIL | 一致 | S8/bad-id.out、S8/bad-id.err：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/automations/heartbeat-1021/register.sh: No such file or directory | 退出码不是 2 的： bad-id mba-stage box stage-novalue unknown-flag；假 orca 被调用 0 次；--apply 没跑（任务书禁止） |
| S6b.parallel | 现网 5c2d0575 只有 box 目标，没有 MBA 目标 | FAIL | 一致 | S6b/parallel.out、S6b/parallel.err：box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}），已连续 0 分钟 | ；退出 1；box 那行：box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}），已连续 0 分钟；顺序不对（box） |
| S6b.final | 现网 5c2d0575 只有 box 目标，没有 MBA 目标 | FAIL | 一致 | S6b/final.out、S6b/final.err：box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}），已连续 0 分钟 | ；退出 1 |
| S14.iMac.held | 现网版 precheck 没套 lockf：heartbeat-watch 照常起来，建出了那个不存在的目录，退出不是 75 | FAIL | 一致 | S14-imac/held.out、S14-imac/held.err：box ops · 29 卡住检查心跳：运行记录查不到（JSONDecodeError），已连续 0 分钟 | 退出 1，stdout 123 字节，stderr：空；目录有；替身 3 次；持锁的 lockf 起的 sleep：86329，lockf 退出 0 |
| S14.iMac.nodir | 现网版 precheck 没有锁文件这一步，照常跑，退出不是 73 | FAIL | 一致 | S14-imac/nodir.out、S14-imac/nodir.err：box ops · 29 卡住检查心跳：运行记录查不到（JSONDecodeError），已连续 0 分钟 | 退出 1，stdout 123 字节，stderr：空；目录有；替身 3 次 |
| S14.iMac.timeout | 现网版 precheck 没套 lockf：第一轮跑的时候探针拿得到锁（退出 0） | FAIL | 一致 | S14-imac/timeout.probe.rc、S14-imac/timeout.probe.err：0 | 探锁退出 0（空）；第一轮超时被杀，用时 12.0 秒；替身起了 1 次，被杀以后都没了；第二轮没超时，用时 19.1 秒，退出 1，stderr 没有 already locked；box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "… |
| S2.sh | 现网版 precheck 在 MBA 上读不到 iMac ops · 01：MBA 的 Orca 没有 environment iMac | FAIL | 一致 | mba/S2-sh.out、mba/S2-sh.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [], "nextSteps），已连续 0 分钟 | ；退出 1 |
| S2.zsh | 现网版 precheck 在 MBA 上读不到 iMac ops · 01：MBA 的 Orca 没有 environment iMac | FAIL | 一致 | mba/S2-zsh.out、mba/S2-zsh.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [], "nextSteps），已连续 0 分钟 | ；退出 1 |
| S4 | 没有包装，heartbeat-watch 报的是 FileNotFoundError，不是 ssh 连不上的 JSONDecodeError | FAIL | 一致 | mba/S4.out、mba/S4.err：iMac ops · 01 卡住工作检查：运行记录查不到（FileNotFoundError），已连续 0 分钟 | ；退出 1；用时 16 秒 |
| S4.wrapper | 没有 scripts/orca-via-ssh | FAIL | 一致 | mba/S4-wrapper.out、mba/S4-wrapper.err：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.YAxAnUI2w3/orca-via-ssh: No such file or directory | 退出 127，stdout 0 字节，stderr：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.YAxAnUI2w3/orca-via-ssh: No such file or directory |
| S4b | 没有包装，heartbeat-watch 报的是 FileNotFoundError，不是 ssh 连不上的 JSONDecodeError | FAIL | 一致 | mba/S4b.out、mba/S4b.err：iMac ops · 01 卡住工作检查：运行记录查不到（FileNotFoundError），已连续 50 分钟 ⏎ iMac ops · 01 卡住工作检查：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（FileNotFoundError），心跳没法确认 | ；退出 1；state.json 没被改 |
| S5.MBA | 没有 scripts/orca-via-ssh | FAIL | 一致 | mba/S5/edit.out、mba/S5/edit.err：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.YAxAnUI2w3/orca-via-ssh: No such file or directory | 0/14 条符合；不符： allow-list(退出 127，ssh 0 次) allow-runs(退出 127，ssh 0 次) create(退出 127，ssh 0 次) edit-id(退出 127，ssh 0 次) edit(退出 127，ssh 0 次) host-empty(退出 127，ssh 0 次… |
| S5b | 没有 scripts/orca-via-ssh | FAIL | 一致 | mba/S5b.out、mba/S5b.err：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.YAxAnUI2w3/orca-via-ssh: No such file or directory | stdout 不是 JSON；ok=-；orca 收到的值不是原样；error.message：；退出 127 |
| S7 | 没有 scripts/orca-via-ssh | FAIL | 一致 | mba/S7-runs.err：env: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.YAxAnUI2w3/orca-via-ssh: No such file or directory | runs 退出 127、None 条运行记录、None 行 @@HB，最新心跳 None 分钟前（rc None）；list 退出 127、None 个自动任务，439cd438「None」createdAt None |
| S12 | 现网版 precheck 不经 ssh：MBA 的 Orca 没有 environment iMac，几秒内就查不到（invalid_argument），ssh 替身一次都没起 | FAIL | 一致 | mba/S12.out、mba/S12.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [], "nextSteps），已连续 0 分钟 … | 没超时，用时 18.1 秒，退出 1；iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is nam… |
| S13 | 现网版 precheck 没套 lockf：B 照常跑，退出不是 75 | FAIL | 一致 | mba/S13-B.out、mba/S13-B.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [], "nextSteps），已连续 0 分钟 … | A：没超时，用时 18.3 秒，退出 1，iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no pair，@@HB rc 0，ssh 0 次；… |
| S14.MBA.held | 现网版 precheck 没套 lockf：heartbeat-watch 照常起来，建出了那个不存在的目录，退出不是 75 | FAIL | 一致 | mba/S14/held.out、mba/S14/held.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [], "nextSteps），已连续 0 分钟 | 退出 1，stdout 309 字节，stderr：空；目录有；替身 0 次；持锁的 lockf 起的 sleep：16046，lockf 退出 0 |
| S14.MBA.nodir | 现网版 precheck 没有锁文件这一步，照常跑，退出不是 73 | FAIL | 一致 | mba/S14/nodir.out、mba/S14/nodir.err：iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message": "Unknown Orca server in --environment iMac: no paired Orca server is named or has id iMac.", "data": {"knownEnvironments": [], "knownSshTargets": [], "nextSteps），已连续 0 分钟 | 退出 1，stdout 309 字节，stderr：空；目录有；替身 0 次 |
| S14.MBA.timeout | 现网版 precheck 没套 lockf：第一轮跑的时候探针拿得到锁（退出 0） | FAIL | 一致 | mba/S14/timeout.probe.rc、mba/S14/timeout.probe.err：0 | 探锁退出 0（空）；第一轮超时被杀，用时 12.0 秒；替身起了 0 次，被杀以后都没了；第二轮没超时，用时 17.0 秒，退出 1，stderr 没有 already locked；iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "invalid_argument", "message":… |
| S11 | orca-via-ssh、register.sh 不存在 | FAIL | 一致 | S11/bash-n.txt：/bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/scripts/orca-via-ssh: No such file or directory ⏎ /bin/bash: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-rollback.gkjsnzaAsJ/tree/automations/he… | bash -n 290 字节输出；lint 3 行；shellcheck 2 行；最后一步：… … |

## 期望过的 29 项（本 PR 不改变结果，用来排除「是环境坏了才挂」）

| 编号 | 实际 | 和期望 | 实际原文（截到 200 字） |
|---|---|---|---|
| S0.same | PASS | 一致 | base=0748576996d2 installed=0748576996d2 new=0748576996d2  |
| S0.bot | PASS | 一致 | BOT = "coding-assistant" |
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
| S6 | PASS | 一致 | MBA ops · 09 内存与 CPU 负载清理：中断：最近 101 次运行记录里没有心跳行（@@HB），最新一次运行在 10-22 00:37；退出 0 |
| S6b.box | FAIL | 不一致 | ；退出 1；本次 box 那行：box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}），已连续 0 分钟；紧接着用 base 版跑现网 precheck（raw/S6b/before-base.*）：… |
| S14.iMac.kill | PASS | 一致 | 第一次探退出 75（lockf: /var/folders/rz/c67l5p1d6rg2ldhm5459tv180000gn/T/hb-drill.t7fnBMTtGK/s14/…）；kill -KILL 87177（pid 87177、ppid 82955 是演练的 shell、命令名 /usr/bin/lockf）；它退出 137；第二次探退出 0；kill 以后它起的 sleep：8718… |
| S3 | PASS | 一致 | dry-run，将 POST 给 coding-assistant：{"task": "检查任务没在跑：iMac ops · 01 卡住工作检查", "worktree": "本机", "status": "stuck", "kind": "heartbeat_stale", "machine": "本机", "source": "heartbeat-watch", "note": "最新心跳在 … |
| S12.old | PASS | 一致 | 超时 240 秒，超时被杀（timedOut），用时 240.1 秒；@@HB 没有；状态目录里什么都没有；ssh 起了 3 次，相邻开始隔 98、98 秒；第二次起来后 1 秒查，第一次的 ssh 已经没了；跑完时都没了 |
| S14.MBA.kill | PASS | 一致 | 第一次探退出 75（lockf: /var/folders/6j/tz0s2v611hj_c04dtspxg8vw0000gn/T/hb-drill.YAxAnUI2w3/s14/…）；kill -KILL 17767（pid 17767、ppid 13147 是演练的 shell、命令名 /usr/bin/lockf）；它退出 137；第二次探退出 0；kill 以后它起的 sleep：1777… |
| S10.MBA | PASS | 一致 | 没有 ~/.orca-state/bin/heartbeat-watch.sh 没有 ~/.orca-state/bin/orca-via-ssh 没有 ~/.orca-state/heartbeat-watch 没有 ~/.orca-state/heartbeat-watch/mba-hb-watch.lock 没有 ~/.orca-state/heartbeat-watch/5c2d0575.… |
| S10.iMac | PASS | 一致 | 已装版 a36d3dc8a88702a8 → a36d3dc8a88702a8；有 ~/.orca-state/bin/heartbeat-watch.sh 没有 ~/.orca-state/bin/orca-via-ssh 有 ~/.orca-state/heartbeat-watch 没有 ~/.orca-state/heartbeat-watch/mba-hb-watch.lock 没有 ~… |

## 文件

- `rollback.tsv`：每项一行：编号、回退后期望、实际、和期望一不一致、为什么该挂、演练的「实际」一栏、raw/ 里的输出原文。
- `rollback/tree.txt`：旧代码检出的情况。`rollback/defs-live.json`：现网版 defs。`rollback/drill.log`：演练的屏幕输出。
- `README.md`、`results.tsv`、`env.txt`、`raw/`：演练脚本在旧代码上生成的，格式同 `reports/heartbeat-mba-imac-1021/`。
- `SHA256SUMS`：除它自己以外所有文件的 sha256（`shasum -a 256 -c SHA256SUMS` 校验）。
