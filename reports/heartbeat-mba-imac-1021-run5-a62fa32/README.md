# heartbeat-watch 跨机看守挪到 MBA↔iMac：演练结果

B1（ops 审计）。代码和上线步骤见 [`automations/heartbeat-1021/`](../../automations/heartbeat-1021/README.md)，失败方式清单见 [`FAILURE-MODES.md`](../../automations/heartbeat-1021/FAILURE-MODES.md)。这个文件由演练脚本生成。

**结果：46 项 PASS，1 项 FAIL。**

## 怎么重跑

在 iMac 的仓库根目录：

```bash
wake/tests/heartbeat-watch-ssh.sh
```

要求本机 Orca 有 environment `mba`、`grok-bot`，能 `ssh mba`，MBA 能 `ssh imac`。整个目录会被重写（有 `.hb-drill` 标记才清空）。回放数据要重录时先跑 `wake/tests/heartbeat-watch-ssh.sh --record`。

heartbeat-watch 都用临时 `HB_STATE_DIR`；除 S12 外都带 `--dry-run`、用假 webhook 目录（`127.0.0.1:9` 的假地址），不发叫醒、不读真凭据。S12 不带 `--dry-run`（要看它写下的 state.json 和 `@@HB`）：webhook 目录是空的，PATH 里放了只记录调用的假 curl，第一次查不到时 heartbeat-watch 走 `continue`，到不了发告警那步。S12.old 到超时时，演练脚本照 Orca 的做法给它自己起的预检进程组发 SIGTERM、2 秒后 SIGKILL；没有给演练以外的进程发过信号。orca 只用 `automations list / show / runs`；不往 `~/.orca-state/bin/` 装文件；MBA 上只用 `mktemp -d` 的临时目录，跑完删掉。

## 这次运行

- 时间 2026-10-21 22:44:06 SGT
- 命令 wake/tests/heartbeat-watch-ssh.sh
- commit a62fa3242b74fbf376be81e465e3871a9efd1c05（分支 zhongc1211/ops-heartbeat-mba-imac-1021）
- 代码有没有未提交的改动（scripts automations wake）：0 个文件
- base（和 origin/main 的分叉点）f828d452345f16898d6c9d133984e170d98d9f83
- iMac：iMac，macOS 26.6.2 arm64，GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)，Python 3.9.6，perl v5.34.1，OpenSSH_10.3p1, LibreSSL 3.3.6，orca 1.4.224，shellcheck 0.11.0
- MBA：mba，macOS 26.6.2 arm64，GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)，Python 3.9.6，perl v5.34.1，OpenSSH_10.3p1, LibreSSL 3.3.6，orca 1.4.229

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
| S12 | ssh 连上了、iMac 那边不回：照 defs 原文跑 MBA 的 precheck，看超时以前有没有写下 fail_since 和 @@HB；S12.old 换成 7ac1220 的包装（ssh 没有上限）对照 | MBA → ssh iMac | 替身：ssh 替身把远端命令换成 sleep 110；ssh 客户端、包装、heartbeat-watch 和 iMac 是真的。预检进程照 Orca 的做法起，不是 Orca 起的 |

S1、S3、S5、S8、S12 用了测试替身，不算 E2E。S2 是从 iMac `ssh mba` 起的进程，不是 Orca 在 MBA 上跑的预检；Orca 预检环境里能不能连 ssh，要到上线卡 ② 第一次真实运行才算证实。

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
| S5.iMac | iMac：edit / run / create / remove / show、别的命令组、参数不全、ORCA_SSH_HOST 没设 / 空 / 以 - 开头，共 12 条都退出 2、假 ssh 0 次；放行的 runs、list 两条对照假 ssh 各记到 1 次，参数开头是 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 imac zsh -lc；输出里没有标记环境变量 | 14/14 条符合；edit 那条：orca-via-ssh: 只放行 automations runs 和 automations list，拒绝：automations edit | PASS |
| S9.5c2d0575 | iMac 5c2d0575 现网的名字、precheck、超时和 defs.json 的 before 一样（回滚就还原成这个），启用中 | 名字「ops · 29 心跳互查（盯 box ops · 29）」、超时 240、启用 True、precheck 等于 defs | PASS |
| S9.94e4b0bc | box 94e4b0bc（经 grok-bot）现网的名字、precheck、超时 240 和 defs.json 一样，启用中；每 5 分钟、grace 720（MBA 新任务照抄） | 名字「ops · 29 卡住检查心跳（盯 iMac ops · 01）」、rrule */5 * * * *、超时 240、grace 720、启用 True、precheck 等于 defs | PASS |
| S9.439cd438 | iMac ops · 01 439cd438 启用中，名字和 precheck 超时（600）和 defs.json 一样 | 名字「ops · 01 卡住工作检查」、超时 600、启用 True、rrule * * * * * | PASS |
| S9.mba | MBA 上还没有「ops · 29 心跳互查 MBA（盯 iMac ops · 01）」（本 PR 没建任务）；S6 用的 ops · 09 62d18b16 在 | 9 个自动任务，同名的 0 个，ops · 09：ops · 09 内存与 CPU 负载清理 MBA | PASS |
| S8.mba | mba：create 带 --disabled、--fresh-session、每 5 分钟、超时 330、grace 720，precheck 是 defs 原文；退出 0 | orca automations create --name 'ops · 29 心跳互查 MBA（盯 iMac ops · 01）' --trigger '*/5 * * * *' --timezone Asia/Singapore --provider claude '--extra-agent-args=--model haiku --effort low' --workspace path:/Users/jiawenwang/orca/workspaces/ops -…；退出 0 | PASS |
| S8.imac-noid | imac 没给 --mba-id：命令里是占位，并提示不能照抄；退出 0 | # 没给 --mba-id：下面的命令里是占位「<MBA 新任务 id>」，不能照抄执行；退出 0 | PASS |
| S8.parallel | parallel：保留 box 目标在前、加 MBA 目标，不改名，超时 600（两个目标最坏 572 秒）；退出 0 | orca automations edit 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --precheck '$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "box ops · 29 卡住检查心跳\|grok-bot\|94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80\|20" --target "MBA ops · 29 心跳互查\|mba\|11111…；退出 0 | PASS |
| S8.final | final：只剩 MBA 目标，改名「盯 MBA ops · 29」，超时 300（一个目标最坏 286 秒）；退出 0 | orca automations edit 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --name 'ops · 29 心跳互查（盯 MBA ops · 29）' --precheck '$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "MBA ops · 29 心跳互查\|mba\|11111111-2222-3333-4444-555555555555\|20"' --pr…；退出 0 | PASS |
| S8.rollback | rollback：还原成现网 5c2d0575 的名字和 precheck（S9 读到的原文）；退出 0 | orca automations edit 5c2d0575-dddc-4d5c-8f73-e47b26ea9a11 --name 'ops · 29 心跳互查（盯 box ops · 29）' --precheck '$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "box ops · 29 卡住检查心跳\|grok-bot\|94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80\|20…；退出 0 | PASS |
| S8.refuse | 参数错（id 不完整、mba 带 --stage、机器名不对、--stage 没值、不认识的参数）都退出 2；整个 S8 假 orca 0 次调用（dry-run 不调 orca） | 退出码不是 2 的：没有；假 orca 被调用 0 次；--apply 没跑（任务书禁止） | PASS |
| S6 | iMac 经 environment mba 读到 MBA ops · 09 的运行记录：不是「查不到」，有运行记录和最新一次运行时间（它不打 @@HB，所以结论是没有心跳行）；退出 0 | MBA ops · 09 内存与 CPU 负载清理：中断：最近 101 次运行记录里没有心跳行（@@HB），最新一次运行在 10-21 22:37；退出 0 | PASS |
| S6b.parallel | 5c2d0575 并行版 precheck（defs 原文，MBA 新任务 id 用 ops · 09 代替）：box 目标在前、出一行结论，MBA 目标读到运行记录，没有脚本出错；退出 1 | MBA ops · 29 心跳互查：中断：最近 101 次运行记录里没有心跳行（@@HB），最新一次运行在 10-21 22:37；退出 1；box 那行：box ops · 29 卡住检查心跳：正常（最新心跳 10-21 22:40，3.6 分钟前，rc 0，上次扫描 4 分钟前） | PASS |
| S6b.box | 并行版里的 box 目标正常。要 iMac 到 box 的 grok-bot 隧道当时是通的；没过时对照同一时刻 base 版跑现网 precheck 的结论和现网 5c2d0575 的运行记录（都在实际一栏）；退出 1 | box ops · 29 卡住检查心跳：正常（最新心跳 10-21 22:40，3.6 分钟前，rc 0，上次扫描 4 分钟前）；退出 1；紧接着用 base 版跑现网 precheck（raw/S6b/before-base.*）：box ops · 29 卡住检查心跳：正常（最新心跳 10-21 22:40，3.7 分钟前，rc 0，上次扫描 4 分钟前）；现网 5c2d0575 最近几次对 box 的结论：22:40 box ops · 29 卡住检查心跳：正常（最新心跳 10-21 22:35，4.3 分钟前，rc 0，上次扫描 4 分钟前） 22:35 box ops · 29 卡住检查心跳：运行记录查不到（{"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runt 22:30 box ops · 29 卡住检查心跳：正常（最新心跳 10-21 22:30，0.0 分钟前，rc 0，上次扫描 0 分钟前） 22:25 box ops · 29 卡住检查心跳：正常（最新心跳 10-21 22:25，0.1 分钟前，rc 0，上次扫描 0 分钟前）  | PASS |
| S6b.final | 5c2d0575 最终版 precheck：只查 MBA 目标，读到运行记录；退出 1 | MBA ops · 29 心跳互查：中断：最近 101 次运行记录里没有心跳行（@@HB），最新一次运行在 10-21 22:37；退出 1 | PASS |
| S2.sh | MBA 上经 /bin/sh 跑 defs 原文（env -i 最少环境，只换两个脚本路径，加 --dry-run）：经 ssh 读 iMac ops · 01，结果正常；退出 1 | iMac ops · 01 卡住工作检查：正常（最新心跳 10-21 22:44，0.5 分钟前，rc 1，上次扫描 8 分钟前）；退出 1 | PASS |
| S2.zsh | MBA 上经 /bin/zsh 跑 defs 原文（env -i 最少环境，只换两个脚本路径，加 --dry-run）：经 ssh 读 iMac ops · 01，结果正常；退出 1 | iMac ops · 01 卡住工作检查：正常（最新心跳 10-21 22:44，0.5 分钟前，rc 1，上次扫描 8 分钟前）；退出 1 | PASS |
| S3 | MBA 上回放 30 分钟前的心跳：出 heartbeat_stale 待发内容，收件人 coding-assistant（STUCK_FORCE_BOT 没设）；退出 1 | dry-run，将 POST 给 coding-assistant：{"task": "检查任务没在跑：iMac ops · 01 卡住工作检查", "worktree": "本机", "status": "stuck", "kind": "heartbeat_stale", "machine": "本机", "source": "heartbeat-watch", "note": "最新心跳在 10-21 22:14，已 30 分钟没有新的（阈值 20 分钟）：Orca 调…；退出 1 | PASS |
| S4 | ORCA_SSH_HOST=no-such-host.invalid：记「运行记录查不到」、不报、不算脚本出错，--precheck 退出 1；退出 1 | iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；退出 1；用时 16 秒 | PASS |
| S4.wrapper | 包装连不上时退出 255（ssh 的）、stdout 空 | 退出 255，stdout 0 字节，stderr：ssh: Could not resolve hostname no-such-host.invalid: nodename nor servname provided, or not known | PASS |
| S4b | state 里记着 50 分钟前起查不到：报 heartbeat_stale「连不上 本机 的 Orca」给 coding-assistant；dry-run 不改 state；退出 1 | iMac ops · 01 卡住工作检查：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（JSONDecodeError），心跳没法确认；退出 1；state.json 没被改 | PASS |
| S5.MBA | MBA：edit / run / create / remove / show、别的命令组、参数不全、ORCA_SSH_HOST 没设 / 空 / 以 - 开头，共 12 条都退出 2、假 ssh 0 次；放行的 runs、list 两条对照假 ssh 各记到 1 次，参数开头是 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 imac zsh -lc；输出里没有标记环境变量 | 14/14 条符合；edit 那条：orca-via-ssh: 只放行 automations runs 和 automations list，拒绝：automations edit | PASS |
| S5b | MBA 经包装真 ssh 到 iMac：--environment 的值带单双引号、$(…)、反引号、;、&&、*、反斜杠、$HOME 变量、中文、换行，orca 的报错里原样带回（没被展开或执行），stdout 只有一个 JSON | stdout 是一个 JSON；ok=False；orca 收到的值是原样；error.message：Unknown Orca server in --environment hb'drill "q" $(echo HBX) 'echo HBY' ; echo HBZ && echo HBW * \ $HOME 中文 · \|⏎第二行: no paired Orca server is named or has id hb'drill "q" $(echo HBX) 'echo HBY' ; ech；退出 1 | PASS |
| S7 | MBA 上直接跑 orca-via-ssh automations runs / list：ok，读到 ops · 01 的运行记录和 @@HB，list 里有 439cd438 和 createdAt | runs 退出 0、101 条运行记录、101 行 @@HB，最新心跳 0.3 分钟前（rc 1）；list 退出 0、16 个自动任务，439cd438「ops · 01 卡住工作检查」createdAt 1791804522369 | PASS |
| S12 | MBA 上照 defs 原文跑 precheck（只换两个脚本路径，不带 --dry-run），ssh 替身让 iMac 那边不回（sleep 110），照 Orca 的做法起、超时 330 秒：没超时、自己结束、退出 1；有「运行记录查不到（JSONDecodeError），已连续 0 分钟」；@@HB rc 0；state.json 的 fail_since 在这次运行期间；ssh 3 次，相邻开始隔 75–85 秒；第二次起来时第一次的 ssh 已经没了，跑完都没了；假 curl 0 次，输出里没有 POST 和 webhook 配置 | 没超时，用时 227.5 秒，退出 1；iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟；@@HB rc 0；state.json 的 fail_since 在运行期间（开始后 0.3 秒）；ssh 起了 3 次，相邻开始隔 78、78 秒；第二次起来后 0 秒查，第一次的 ssh 已经没了；跑完时都没了；假 curl 0 次 | PASS |
| S12.old | 同样的设置，包装换成 7ac1220 那版（ssh 没有上限）：到 330 秒超时被杀（timedOut，用时在超时到超时加 15 秒之间）；没有 @@HB；状态目录里什么都没写；相邻两次 ssh 开始隔 95–105 秒；第二次起来时第一次的 ssh 已经没了（heartbeat-watch 的 90 秒超时杀的就是 ssh），跑完都没了 | 没超时，退出 1，用时 286.4 秒；@@HB 有；状态目录里：./heartbeat.json、./state.json、./watch.log；ssh 起了 3 次，相邻开始隔 97、98 秒；第二次起来后 1 秒查，第一次的 ssh 已经没了；跑完时都没了 | **FAIL** |
| S10.MBA | MBA 演练前后：~/.orca-state/bin/heartbeat-watch.sh、~/.orca-state/bin/orca-via-ssh、~/.orca-state/heartbeat-watch、主检出的 scripts/orca-via-ssh 都没有，主检出 HEAD 不变；临时状态目录里只有 S4b 种的 state.json（S12 不是 dry-run，它的状态目录不算）；临时目录删掉了 | 没有 ~/.orca-state/bin/heartbeat-watch.sh 没有 ~/.orca-state/bin/orca-via-ssh 没有 ~/.orca-state/heartbeat-watch 没有 ~/orca/workspaces/ops/scripts/orca-via-ssh 主检出 HEAD f828d452345f16898d6c9d133984e170d98d9f83 ；状态文件：s4b/state/state.json ；临时目录删掉了 | PASS |
| S10.iMac | iMac 演练前后：~/.orca-state/bin/heartbeat-watch.sh 的 sha256 不变，主检出没有 scripts/orca-via-ssh、HEAD 不变；所有临时状态目录里只有种进去的 state.json，内容没变（dry-run 不写 state.json、watch.log、heartbeat.json） | 已装版 a36d3dc8a88702a8 → a36d3dc8a88702a8；有 ~/.orca-state/bin/heartbeat-watch.sh 没有 ~/.orca-state/bin/orca-via-ssh 有 ~/.orca-state/heartbeat-watch 没有 ~/orca/workspaces/ops/scripts/orca-via-ssh 主检出 HEAD f828d452345f16898d6c9d133984e170d98d9f83 ；状态文件 9 个 | PASS |
| S11 | 4 个 shell 文件 /bin/bash 3.2 -n、lint-bash32-utf8、shellcheck -S warning 都过；2 个 Python 文件能解析；orca-via-ssh 最后一步是 exec /usr/bin/perl -e 'alarm shift; exec …' 70 ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2（每次 ssh 最多 70 秒；heartbeat-watch 超时杀的也是 ssh 本身） | bash -n 0 字节输出；lint 1 行；shellcheck 0 行；最后一步：exec /usr/bin/perl -e 'alarm shift; exec { $ARGV[0] } @ARGV …     ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 "$h… | PASS |

## 没跑的

- `register.sh --apply`：任务书禁止。主机名检查、备份文件检查和真正调用 orca 的部分都没演练过。
- 任何 `orca automations create / edit / run`：任务书禁止。MBA 新任务还没建，S6、S6b 用 MBA ops · 09 代替它。
- TLC（`wake/tla/check.sh`）：本批只改了 `wake/tla/README.md` 的文字，模型和 `SOURCES.sha256` 留给后续 wake-tla 批次。
- iMac 上真的 orca 卡住时什么样：没演练。S12 的「iMac 那边不回」是 ssh 替身把远端命令换成 `sleep 110`；真 orca 可能自己 60 秒超时、先回一个报错，那样不用等 70 秒上限。
- Orca 自己起这条预检：要到上线卡 ② 才有。S12 的预检进程是演练脚本照 Orca 的做法起的（`/bin/sh -c`、新进程组、到时先 TERM 后 KILL）。
- ssh 连接半路断了（ServerAlive 起作用）：没演练。
- MBA 那条的少见情况：还没见过心跳、心跳又过期，而且 runs 前两次各卡满 70 秒，再加一次 list，最坏 296 秒，加起动约 4 秒，在 330 秒的超时以内。没演练。

## 文件

- `results.tsv`：每项一行（编号、结果、期望、实际），`README.md` 由它生成。
- `env.txt`：时间、commit、两台机器的系统和工具版本。
- `raw/S0/`：三版的 sha256 和 diff。`raw/S1/`：每个例子的参数（`.cmd`）、回放设置（`.vars`，不用 `.env`：仓库的 .gitignore 不收 `*.env`）、种的状态（`.seed.json`），三版各自的 stdout、stderr、退出码和假 orca 收到的调用。
- `raw/S5-imac/`：iMac 上包装每条用例的命令、退出码、stderr、假 ssh 收到的参数。
- `raw/S6/`、`raw/S6b/`：iMac 上的命令和原始输出。`raw/S8/`：register.sh 每次的参数和输出。`raw/S9/`：只读 show / list 摘下来的字段。
- `raw/mba/`：MBA 那边的原始输出（S2、S3、S4、S4b、S5、S5b、S7 摘要、S10、S12）。S7 只留摘要，不留运行记录原文。
- `raw/mba/S12.*`、`raw/mba/S12-old.*`：precheck（`.cmd`）、stdout、stderr、预检结果（`.orca.json`：超时、是否超时、退出码、用时、起止时间）、每次 ssh 的 pid 和开始时间（`.ssh-starts`）、ssh 收到的参数（`.ssh-args`）、进程检查（`.first-alive-at-second`、`.alive-after`，是 `ps -o pid,ppid,rss,etime,comm` 的输出，空 = 进程已经没了）、假 curl 的调用（`.curl-calls`）、状态目录里的文件和内容。
- `raw/S11/`：静态检查的输出。
- `SHA256SUMS`：除它自己以外所有文件的 sha256（`shasum -a 256 -c SHA256SUMS` 校验）。
