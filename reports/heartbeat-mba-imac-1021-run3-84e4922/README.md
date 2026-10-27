# heartbeat-watch 跨机看守挪到 MBA↔iMac：演练结果

B1（ops 审计）。代码和上线步骤见 [`automations/heartbeat-1021/`](../../automations/heartbeat-1021/README.md)，失败方式清单见 [`FAILURE-MODES.md`](../../automations/heartbeat-1021/FAILURE-MODES.md)。这个文件由演练脚本生成。

**结果：45 项 PASS，0 项 FAIL。**

## 怎么重跑

在 iMac 的仓库根目录：

```bash
wake/tests/heartbeat-watch-ssh.sh
```

要求本机 Orca 有 environment `mba`、`grok-bot`，能 `ssh mba`，MBA 能 `ssh imac`。整个目录会被重写（有 `.hb-drill` 标记才清空）。回放数据要重录时先跑 `wake/tests/heartbeat-watch-ssh.sh --record`。

全部 heartbeat-watch 都带 `--dry-run`、临时 `HB_STATE_DIR`、假 webhook 目录（`127.0.0.1:9` 的假地址），不发叫醒、不读真凭据；orca 只用 `automations list / show / runs`；不往 `~/.orca-state/bin/` 装文件；MBA 上只用 `mktemp -d` 的临时目录，跑完删掉。

## 这次运行

- 时间 2026-10-21 20:29:39 SGT
- 命令 wake/tests/heartbeat-watch-ssh.sh
- commit 84e4922ddc0bbe3a2e13f50b46f58c40f7d70bc0（分支 zhongc1211/ops-heartbeat-mba-imac-1021）
- 代码有没有未提交的改动（scripts automations wake）：0 个文件
- base（和 origin/main 的分叉点）f828d452345f16898d6c9d133984e170d98d9f83
- iMac：iMac，macOS 26.6.2 arm64，GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)，Python 3.9.6，orca 1.4.224，shellcheck 0.11.0
- MBA：mba，macOS 26.6.2 arm64，GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)，Python 3.9.6，orca 1.4.229

## 场景

| 编号 | 场景 | 在哪跑 | 真机还是替身 |
|---|---|---|---|
| S0 | 三版 heartbeat-watch（base、iMac 已装、本分支）去掉注释后一致，第 33 行收件人不变 | iMac | 静态对比 |
| S1 | 14 个回放例子 × 三版：输出和退出码逐字节一致，且符合期望 | iMac | 替身：假 HB_ORCA 回放录好的数据 + 固定时钟 |
| S2 | MBA 上照 defs 原文跑 precheck（/bin/sh、/bin/zsh 各一次）读真的 iMac ops · 01 | MBA → ssh iMac | 真 |
| S3 | MBA 上 --dry-run，目标换成心跳过期的回放数据 | MBA | 替身：假 HB_ORCA |
| S4 / S4b | ORCA_SSH_HOST 指向不存在的主机 | MBA | 真 ssh（主机名解析失败） |
| S5 | orca-via-ssh 拒绝 edit 等子命令和坏的主机名 | iMac、MBA | 替身：假 ssh |
| S5b | orca-via-ssh 的参数转义 | MBA → ssh iMac | 真（orca 只读的 list，报错里带回参数） |
| S6 | iMac 经 environment mba 读 MBA 一条现有任务（ops · 09） | iMac → mba | 真 |
| S6b | iMac 照 defs 原文跑 5c2d0575 的并行版、最终版 precheck；紧接着用 base 版跑现网 precheck 当对照 | iMac → grok-bot、mba | 真（MBA 新任务还没建，用 ops · 09 代替） |
| S7 | MBA 上直接用 orca-via-ssh 读 iMac 的 runs、list | MBA → ssh iMac | 真 |
| S8 | register.sh 只打印命令，不调用 orca | iMac | 替身：假 orca |
| S9 | 现网配置和 defs.json 对得上（只读 show / list） | iMac → grok-bot、mba | 真（只读） |
| S10 | 真路径没动：没装文件、主检出没动、dry-run 不写状态 | iMac、MBA | 真 |
| S11 | 静态检查 | iMac | — |

S1、S3、S5、S8 用了测试替身，不算 E2E。S2 是从 iMac `ssh mba` 起的进程，不是 Orca 在 MBA 上跑的预检；Orca 预检环境里能不能连 ssh，要到上线第 3 步第一次真实运行才算证实。

## 期望和实际

| 编号 | 期望 | 实际 | 结果 |
|---|---|---|---|
| S0.diff | 和 base 比只改了第 13 行（一处 13c13） | 13c13  | PASS |
| S0.same | base installed new 三版的 Python 部分、去掉 # 注释行后的全文 sha256 都一样 | base=0748576996d2 installed=0748576996d2 new=0748576996d2  | PASS |
| S0.bot | 第 33 行仍是 BOT = "coding-assistant" | BOT = "coding-assistant" | PASS |
| S1.c01 | 正常：心跳 2 分钟前，不发；三版一致；退出 1 | iMac ops · 01 卡住工作检查：正常（最新心跳 10-21 19:58，2.0 分钟前，rc 1，上次扫描 11 分钟前）；退出 1；三版一致 | PASS |
| S1.c02 | 心跳过期 30 分钟：报 heartbeat_stale 给 coding-assistant；三版一致；退出 1 | iMac ops · 01 卡住工作检查：中断：最新心跳在 10-21 19:30，已 30 分钟没有新的（阈值 20 分钟）：Orca 调度器停了或脚本没在跑；退出 1；三版一致 | PASS |
| S1.c03 | 心跳还在、扫描 40 分钟没跑完：报 heartbeat_stale；三版一致；退出 1 | iMac ops · 01 卡住工作检查：中断：心跳还在（10-21 19:59），但上次跑完的扫描在 10-21 19:20，已 40 分钟没跑完：扫描每次超时被杀或每次出错；退出 1；三版一致 | PASS |
| S1.c04 | 运行记录里没有 @@HB：报 heartbeat_stale；三版一致；退出 1 | iMac ops · 01 卡住工作检查：中断：最近 101 次运行记录里没有心跳行（@@HB），最新一次运行在 10-21 19:57；退出 1；三版一致 | PASS |
| S1.c05 | 之前报过中断、现在心跳正常：报一次 heartbeat_recovered；三版一致；退出 1 | iMac ops · 01 卡住工作检查：已恢复，报过一次；退出 1；三版一致 | PASS |
| S1.c06 | 连不上（ssh 退出 255、stdout 空）：记「查不到」，45 分钟内不报；三版一致；退出 1 | iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；退出 1；三版一致 | PASS |
| S1.c07 | 50 分钟前起就查不到：报 heartbeat_stale「连不上 本机 的 Orca」；三版一致；退出 1 | iMac ops · 01 卡住工作检查：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（JSONDecodeError），心跳没法确认；退出 1；三版一致 | PASS |
| S1.c08 | 输出不是 JSON：记「查不到」，不报；三版一致；退出 1 | iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；退出 1；三版一致 | PASS |
| S1.c09 | 新建 5 分钟、还没有运行记录：不判断；三版一致；退出 1 | iMac ops · 01 卡住工作检查：自动任务建好 5 分钟（不到 20 分钟），还没有心跳，这次不判断；退出 1；三版一致 | PASS |
| S1.c10 | 还在中断、已经报过：不重复报；三版一致；退出 1 | iMac ops · 01 卡住工作检查：还在中断（10-21 19:50 起已报过，不重复报）：最新心跳在 10-21 19:30，已 30 分钟没有新的（阈值 20 分钟）：Orca 调度器停了或脚本没在跑；退出 1；三版一致 | PASS |
| S1.c11 | 目标写错：用法错误；三版一致；退出 2 | 用法：heartbeat-watch.sh --target "名字\|environment\|自动任务 id\|N 分钟" [--target ...] [--precheck] [--dry-run]；退出 2；三版一致 | PASS |
| S1.c12 | orca 回 ok:false：记「查不到」，不报；三版一致；退出 1 | iMac ops · 01 卡住工作检查：运行记录查不到（{"code": "automation_not_found", "message": "Automation not found: 439cd438-cffe-44dd-bd2b-23b07bfa3d61"}），已连续 0 分钟；退出 1；三版一致 | PASS |
| S1.c13 | 两个目标（5c2d0575 并行版的样子）：box 正常、MBA 那条过期只报 MBA；三版一致；退出 1 | MBA ops · 29 心跳互查：中断：最新心跳在 10-21 19:30，已 30 分钟没有新的（阈值 20 分钟）：Orca 调度器停了或脚本没在跑；退出 1；三版一致 | PASS |
| S1.c14 | 不带 --precheck、正常：退出 0；三版一致；退出 0 | iMac ops · 01 卡住工作检查：正常（最新心跳 10-21 19:58，2.0 分钟前，rc 1，上次扫描 11 分钟前）；退出 0；三版一致 | PASS |
| S1.curl | S1 全部 --dry-run：PATH 里的假 curl 一次都没被调用 | 假 curl 被调用 0 次 | PASS |
| S5.iMac | iMac：edit / run / create / remove / show、别的命令组、参数不全、ORCA_SSH_HOST 没设 / 空 / 以 - 开头，共 12 条都退出 2、假 ssh 0 次；放行的 runs、list 两条对照假 ssh 各记到 1 次；输出里没有标记环境变量 | 14/14 条符合；edit 那条：orca-via-ssh: 只放行 automations runs 和 automations list，拒绝：automations edit | PASS |
| S9.5c2d0575 | iMac 5c2d0575 现网的名字、precheck、超时和 defs.json 的 before 一样（回滚就还原成这个），启用中 | 名字「ops · 29 心跳互查（盯 box ops · 29）」、超时 240、启用 True、precheck 等于 defs | PASS |
| S9.94e4b0bc | box 94e4b0bc（经 grok-bot）现网的名字、precheck、超时 240 和 defs.json 一样，启用中；每 5 分钟、grace 720（MBA 新任务照抄） | 名字「ops · 29 卡住检查心跳（盯 iMac ops · 01）」、rrule */5 * * * *、超时 240、grace 720、启用 True、precheck 等于 defs | PASS |
| S9.439cd438 | iMac ops · 01 439cd438 启用中，名字和 precheck 超时（600）和 defs.json 一样 | 名字「ops · 01 卡住工作检查」、超时 600、启用 True、rrule * * * * * | PASS |
| S9.mba | MBA 上还没有「ops · 29 心跳互查 MBA（盯 iMac ops · 01）」（本 PR 没建任务）；S6 用的 ops · 09 62d18b16 在 | 9 个自动任务，同名的 0 个，ops · 09：ops · 09 内存与 CPU 负载清理 MBA | PASS |
| S8.mba | mba：create 带 --disabled、--fresh-session、每 5 分钟、超时 240、grace 720，precheck 是 defs 原文；退出 0 | orca automations create --name 'ops · 29 心跳互查 MBA（盯 iMac ops · 01）' --trigger '*/5 * * * *' --timezone Asia/Singapore --provider claude '--extra-agent-args=--model haiku --effort low' --workspace path:/Users/jiawenwang/orca/workspaces/ops -…；退出 0 | PASS |
| S8.imac-noid | imac 没给 --mba-id：命令里是占位，并提示不能照抄；退出 0 | # 没给 --mba-id：下面的命令里是占位「<MBA 新任务 id>」，不能照抄执行；退出 0 | PASS |
| S8.parallel | parallel：保留 box 目标在前、加 MBA 目标，不改名；退出 0 | orca automations edit 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --precheck '$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "box ops · 29 卡住检查心跳\|grok-bot\|94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80\|20" --target "MBA ops · 29 心跳互查\|mba\|11111…；退出 0 | PASS |
| S8.final | final：只剩 MBA 目标，改名「盯 MBA ops · 29」；退出 0 | orca automations edit 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --name 'ops · 29 心跳互查（盯 MBA ops · 29）' --precheck '$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "MBA ops · 29 心跳互查\|mba\|11111111-2222-3333-4444-555555555555\|20"' --pr…；退出 0 | PASS |
| S8.rollback | rollback：还原成现网 5c2d0575 的名字和 precheck（S9 读到的原文）；退出 0 | orca automations edit 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --name 'ops · 29 心跳互查（盯 box ops · 29）' --precheck '$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "box ops · 29 卡住检查心跳\|grok-bot\|94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80\|20…；退出 0 | PASS |
| S8.refuse | 参数错（id 不完整、mba 带 --stage、机器名不对、--stage 没值、不认识的参数）都退出 2；整个 S8 假 orca 0 次调用（dry-run 不调 orca） | 退出码不是 2 的：没有；假 orca 被调用 0 次；--apply 没跑（任务书禁止） | PASS |
| S6 | iMac 经 environment mba 读到 MBA ops · 09 的运行记录：不是「查不到」，有运行记录和最新一次运行时间（它不打 @@HB，所以结论是没有心跳行）；退出 0 | MBA ops · 09 内存与 CPU 负载清理：中断：最近 100 次运行记录里没有心跳行（@@HB），最新一次运行在 10-21 20:07；退出 0 | PASS |
| S6b.parallel | 5c2d0575 并行版 precheck（defs 原文，MBA 新任务 id 用 ops · 09 代替）：box 目标在前、出一行结论，MBA 目标读到运行记录，没有脚本出错；退出 1 | MBA ops · 29 心跳互查：中断：最近 100 次运行记录里没有心跳行（@@HB），最新一次运行在 10-21 20:07；退出 1；box 那行：box ops · 29 卡住检查心跳：正常（最新心跳 10-21 20:26，4.0 分钟前，rc 0，上次扫描 4 分钟前） | PASS |
| S6b.box | 并行版里的 box 目标正常。要 iMac 到 box 的 grok-bot 隧道当时是通的；没过时对照同一时刻 base 版跑现网 precheck 的结论和现网 5c2d0575 的运行记录（都在实际一栏）；退出 1 | box ops · 29 卡住检查心跳：正常（最新心跳 10-21 20:26，4.0 分钟前，rc 0，上次扫描 4 分钟前）；退出 1；紧接着用 base 版跑现网 precheck（raw/S6b/before-base.*）：box ops · 29 卡住检查心跳：正常（最新心跳 10-21 20:26，4.1 分钟前，rc 0，上次扫描 4 分钟前）；现网 5c2d0575 最近几次对 box 的结论：20:25 box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runt 20:20 box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runt 20:15 box ops · 29 卡住检查心跳：正常（最新心跳 10-21 20:10，4.7 分钟前，rc 0，上次扫描 5 分钟前） 20:10 box ops · 29 卡住检查心跳：正常（最新心跳 10-21 20:07，2.7 分钟前，rc 0，上次扫描 3 分钟前）  | PASS |
| S6b.final | 5c2d0575 最终版 precheck：只查 MBA 目标，读到运行记录；退出 1 | MBA ops · 29 心跳互查：中断：最近 100 次运行记录里没有心跳行（@@HB），最新一次运行在 10-21 20:07；退出 1 | PASS |
| S2.sh | MBA 上经 /bin/sh 跑 defs 原文（env -i 最少环境，只换两个脚本路径，加 --dry-run）：经 ssh 读 iMac ops · 01，结果正常；退出 1 | iMac ops · 01 卡住工作检查：正常（最新心跳 10-21 20:30，0.0 分钟前，rc 1，上次扫描 5 分钟前）；退出 1 | PASS |
| S2.zsh | MBA 上经 /bin/zsh 跑 defs 原文（env -i 最少环境，只换两个脚本路径，加 --dry-run）：经 ssh 读 iMac ops · 01，结果正常；退出 1 | iMac ops · 01 卡住工作检查：正常（最新心跳 10-21 20:30，0.1 分钟前，rc 1，上次扫描 5 分钟前）；退出 1 | PASS |
| S3 | MBA 上回放 30 分钟前的心跳：出 heartbeat_stale 待发内容，收件人 coding-assistant（STUCK_FORCE_BOT 没设）；退出 1 | dry-run，将 POST 给 coding-assistant：{"task": "检查任务没在跑：iMac ops · 01 卡住工作检查", "worktree": "本机", "status": "stuck", "kind": "heartbeat_stale", "machine": "本机", "source": "heartbeat-watch", "note": "最新心跳在 10-21 20:00，已 30 分钟没有新的（阈值 20 分钟）：Orca 调…；退出 1 | PASS |
| S4 | ORCA_SSH_HOST=no-such-host.invalid：记「运行记录查不到」、不报、不算脚本出错，--precheck 退出 1；退出 1 | iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；退出 1；用时 16 秒 | PASS |
| S4.wrapper | 包装连不上时退出 255（ssh 的）、stdout 空 | 退出 255，stdout 0 字节，stderr：ssh: Could not resolve hostname no-such-host.invalid: nodename nor servname provided, or not known | PASS |
| S4b | state 里记着 50 分钟前起查不到：报 heartbeat_stale「连不上 本机 的 Orca」给 coding-assistant；dry-run 不改 state；退出 1 | iMac ops · 01 卡住工作检查：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（JSONDecodeError），心跳没法确认；退出 1；state.json 没被改 | PASS |
| S5.MBA | MBA：edit / run / create / remove / show、别的命令组、参数不全、ORCA_SSH_HOST 没设 / 空 / 以 - 开头，共 12 条都退出 2、假 ssh 0 次；放行的 runs、list 两条对照假 ssh 各记到 1 次；输出里没有标记环境变量 | 14/14 条符合；edit 那条：orca-via-ssh: 只放行 automations runs 和 automations list，拒绝：automations edit | PASS |
| S5b | MBA 经包装真 ssh 到 iMac：--environment 的值带单双引号、$(…)、反引号、;、&&、*、反斜杠、$HOME 变量、中文、换行，orca 的报错里原样带回（没被展开或执行），stdout 只有一个 JSON | stdout 是一个 JSON；ok=False；orca 收到的值是原样；error.message：Unknown Orca server in --environment hb'drill "q" $(echo HBX) 'echo HBY' ; echo HBZ && echo HBW * \ $HOME 中文 · \|⏎第二行: no paired Orca server is named or has id hb'drill "q" $(echo HBX) 'echo HBY' ; ech；退出 1 | PASS |
| S7 | MBA 上直接跑 orca-via-ssh automations runs / list：ok，读到 ops · 01 的运行记录和 @@HB，list 里有 439cd438 和 createdAt | runs 退出 0、101 条运行记录、101 行 @@HB，最新心跳 0.8 分钟前（rc 1）；list 退出 0、16 个自动任务，439cd438「ops · 01 卡住工作检查」createdAt 1791804522369 | PASS |
| S10.MBA | MBA 演练前后：~/.orca-state/bin/heartbeat-watch.sh、~/.orca-state/heartbeat-watch、主检出的 scripts/orca-via-ssh 都没有，主检出 HEAD 不变；临时状态目录里只有 S4b 种的 state.json；临时目录删掉了 | 没有 ~/.orca-state/bin/heartbeat-watch.sh 没有 ~/.orca-state/heartbeat-watch 没有 ~/orca/workspaces/ops/scripts/orca-via-ssh 主检出 HEAD f828d452345f16898d6c9d133984e170d98d9f83 ；状态文件：s4b/state/state.json ；临时目录删掉了 | PASS |
| S10.iMac | iMac 演练前后：~/.orca-state/bin/heartbeat-watch.sh 的 sha256 不变，主检出没有 scripts/orca-via-ssh、HEAD 不变；所有临时状态目录里只有种进去的 state.json，内容没变（dry-run 不写 state.json、watch.log、heartbeat.json） | 已装版 a36d3dc8a88702a8 → a36d3dc8a88702a8；有 ~/.orca-state/bin/heartbeat-watch.sh 有 ~/.orca-state/heartbeat-watch 没有 ~/orca/workspaces/ops/scripts/orca-via-ssh 主检出 HEAD f828d452345f16898d6c9d133984e170d98d9f83 ；状态文件 9 个 | PASS |
| S11 | 4 个 shell 文件 /bin/bash 3.2 -n、lint-bash32-utf8、shellcheck -S warning 都过；2 个 Python 文件能解析；orca-via-ssh 最后一步是 exec ssh（heartbeat-watch 超时杀的就是 ssh，不留孤儿） | bash -n 0 字节输出；lint 1 行；shellcheck 0 行；最后一步：exec ssh -o BatchMode=yes -o ConnectTime… | PASS |

## 没跑的

- `register.sh --apply`：任务书禁止。主机名检查、备份文件检查和真正调用 orca 的部分都没演练过。
- 任何 `orca automations create / edit / run`：任务书禁止。MBA 新任务还没建，S6、S6b 用 MBA ops · 09 代替它。
- TLC（`wake/tla/check.sh`）：本批只改了 `wake/tla/README.md` 的文字，模型和 `SOURCES.sha256` 留给后续 wake-tla 批次。
- heartbeat-watch 90 秒超时杀掉包装时 ssh 会不会留下：不杀进程就没法实测，S11 只检查了包装最后一步是 `exec ssh`。

## 文件

- `results.tsv`：每项一行（编号、结果、期望、实际），`README.md` 由它生成。
- `env.txt`：时间、commit、两台机器的系统和工具版本。
- `raw/S0/`：三版的 sha256 和 diff。`raw/S1/`：每个例子的参数（`.cmd`）、回放设置（`.vars`，不用 `.env`：仓库的 .gitignore 不收 `*.env`）、种的状态（`.seed.json`），三版各自的 stdout、stderr、退出码和假 orca 收到的调用。
- `raw/S5-imac/`：iMac 上包装每条用例的命令、退出码、stderr、假 ssh 收到的参数。
- `raw/S6/`、`raw/S6b/`：iMac 上的命令和原始输出。`raw/S8/`：register.sh 每次的参数和输出。`raw/S9/`：只读 show / list 摘下来的字段。
- `raw/mba/`：MBA 那边的原始输出（S2、S3、S4、S4b、S5、S5b、S7 摘要、S10）。S7 只留摘要，不留运行记录原文。
- `raw/S11/`：静态检查的输出。
- `SHA256SUMS`：除它自己以外所有文件的 sha256（`shasum -a 256 -c SHA256SUMS` 校验）。
