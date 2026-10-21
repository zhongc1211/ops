# B1 心跳看守挪到 MBA↔iMac：失败方式清单（先写清单，再写代码）

写于 2026-10-21 19:2x SGT，写 `scripts/orca-via-ssh`、`register.sh` 和演练脚本之前。依据：`.orca-task/BRIEF.md`、
iMac / MBA / box 上 `orca automations list|show|runs --json` 的只读结果、`scripts/heartbeat-watch.sh` 和 Orca 1.4.224 CLI 源码
（`/Applications/Orca.app/Contents/Resources/app.asar.unpacked/out/`）。

每一条对应 `wake/tests/heartbeat-watch-ssh.sh` 里的一个场景（S 编号）。断言照本表写进脚本；跑出来不符就记 FAIL 并保留原始输出，
不放宽断言、不挑重跑。

## 动手前查到的、会影响设计的事实

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F1 | iMac 的 Orca 有 environment `grok-bot`（box）和 `mba`；MBA 的 Orca 没有任何 environment | `orca environment list` | MBA 读不到 iMac 的运行记录，要经 ssh 在 iMac 上跑 orca（`orca-via-ssh`） |
| F2 | 现网：iMac `439cd438-cffe-44dd-bd2b-23b07bfa3d61`「ops · 01 卡住工作检查」每分钟，precheck 超时 **600 秒**（wake/tla/README.md 写的是 300）；box `94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80`「ops · 29 卡住检查心跳（盯 iMac ops · 01）」每 5 分钟、超时 240、grace 720，目标 environment 叫 `iMac`；iMac `5c2d0575-dddc-4d5c-8f73-e47b26ea9a11`「ops · 29 心跳互查（盯 box ops · 29）」每 5 分钟、超时 240、grace 720，目标 `box ops · 29 卡住检查心跳\|grok-bot\|94e4b0bc…\|20` | `orca automations show --id … --json`（box 那条用 `--environment grok-bot`） | defs.json 的「改之前」照抄这几条；MBA 新任务照 box 那条的频率、超时、grace |
| F3 | MBA 的 9 个自动任务都在 `~/orca/workspaces/ops`（MBA 上这是 git 主检出，f828d45），多数 `--model haiku --effort low`、grace 720；MBA 的 `~/.orca-state/bin/` 没有 heartbeat-watch.sh，也没有 `~/.orca-state/heartbeat-watch/` | iMac 上 `orca automations list --environment mba --json`；`ssh mba ls` | 上线第 1 步要在 MBA 装 heartbeat-watch.sh；新任务用同一个工作区和模型参数 |
| F4 | MBA 上 `ssh -o BatchMode=yes imac` 不靠 ssh-agent（ssh 会话里 SSH_AUTH_SOCK 没设），`env -i` 下也能连；iMac 上 `zsh -lc 'command -v orca'` 是 `/usr/local/bin/orca`（指向 Orca.app，1.4.224），登录脚本不往 stdout 打字 | `ssh mba '…'` | 包装用 `zsh -lc` 找 orca；Orca 预检的环境变量少也能连 |
| F5 | iMac 的登录 shell 是 /bin/zsh；ssh 把命令参数用空格拼成一串交给远端登录 shell | `dscl . -read … UserShell`；ssh 的行为 | 参数要转义两层：远端登录 shell 一层，`zsh -lc` 一层 |
| F6 | orca CLI：`edit` 接受位置参数 id 或 `--id`，有 `--name`、`--precheck`、`--precheck-timeout`、`--enabled`、`--disabled`；`--environment` 是全局参数。解析时每个不以 `--` 开头的词都算命令路径，`runs`、`list` 不收位置参数，多出来的词只会报 Unknown command，拼不成别的子命令 | `out/cli/specs/automations.js`、`out/cli/args.js` | 包装只要卡住前两个词是 `automations runs|list` |
| F7 | orca 对不认识的 `--environment` 值，会在 `error.message` 里原样带回这个值 | `orca automations list --environment "<含引号和 \$() 的串>" --json` | 可以用真 ssh、真 orca 验证转义：值原样回来就说明没被展开，全程只读 |
| F8 | Orca 预检：退出 0 才起模型，其余退出码、超时、出错都记 skipped；超时上限 600 秒；stdout 只存 4000 字符 | `out/shared/automation-precheck.js` | heartbeat-watch `--precheck` 永不退出 0，模型不会起 |
| F9 | heartbeat-watch 查一次运行记录：3 次 × 90 秒超时，中间等 2 × 8 秒，最坏 286 秒，超过 240 秒的预检超时（只在连上了但远端卡住时）；Python 超时只杀直接子进程 | 读 `runs_of` | 包装用 `exec ssh`，被杀的就是 ssh 本身，不留孤儿 ssh；超时写进 README 的已知限制 |
| F10 | heartbeat-watch 在 `--dry-run` 下也会先读 `<STUCK_WEBHOOK_DIR>/coding-assistant.env` 再判断 dry-run | 读 `post()` | 演练一律把 STUCK_WEBHOOK_DIR 指到临时目录里的假文件（地址 127.0.0.1:9），不读真的凭据 |
| F11 | environment 写空串时，告警里的 machine / worktree 写「本机」，连不上时写「连不上 本机 的 Orca」。用了 orca-via-ssh 后「本机」其实是 ssh 过去的 iMac | 读 `main()` | 任务书要求逻辑不动，写进 README 的已知限制；目标名里带「iMac」 |
| F12 | iMac 已装的 `~/.orca-state/bin/heartbeat-watch.sh` sha256 `a36d3dc8…`（等于 wake/tla/SOURCES.sha256），main 的 `a408563a…` 只差第 17 行注释 | `shasum`、`diff` | 新旧对比要把已装版本一起比 |
| F13 | MBA 是笔记本，box 一直开着。MBA 睡着超过 20 分钟，iMac 会报「MBA ops · 29 心跳互查」中断，这段时间 ops · 01 没人盯 | migration-1020 README（SleepDisabled 1、接电源）；设计推出来的 | 写进 README 的已知限制，上线前要 Zack 知道 |

## A. 要防的失败方式

| # | 失败方式 | 场景 | 期望 |
|---|---|---|---|
| A1 | heartbeat-watch 除了注释还改了别的，告警行为变了 | S0、S1 | S0：base、iMac 已装版、本分支三版去掉 `#` 注释行后逐字节一致，Python 部分 sha256 相同。S1：11 个回放用例（正常、心跳过期、扫描没跑完、没有 @@HB、已恢复、查不到 45 分钟内 / 超过 45 分钟、输出不是 JSON、新建不到 N 分钟、已报过不重复、用法错）三版的输出和退出码逐字节一致 |
| A2 | 包装放行了会写东西的子命令（edit / run / create / remove），可能改到现网任务 | S5 | edit、run、create、remove、show、别的命令组、只给 `automations`、不给参数：都退出 2，假 ssh 记录的调用数 0 |
| A3 | 包装没转义，参数里的 `$()`、反引号、`;`、引号在 iMac 上被展开或执行 | S5b | 真 ssh 到 iMac：含单引号、双引号、`$(…)`、反引号、`;`、`&&`、`*`、反斜杠、中文、换行的 `--environment` 值，在 orca 的 error.message 里原样回来，没有多出的输出 |
| A4 | 没设 ORCA_SSH_HOST，或者它以 `-` 开头（变成 ssh 的选项，如 `-oProxyCommand=…`） | S5 | 退出 2，不调 ssh |
| A5 | 包装把环境变量打出来（可能带密钥） | S5、S5b | 演练设一个只有本次知道的标记环境变量，所有输出里都找不到它 |
| A6 | 远端连不上时 heartbeat-watch 报错退出（rc 4）或者马上告警 | S4、S4b | S4：不存在的主机，日志「运行记录查不到（…），已连续 0 分钟」，没有「脚本出错」，`--precheck` 退出 1；包装自己退出 255、stdout 为空。S4b：state 里记着 50 分钟前起就查不到，出 heartbeat_stale 待发内容「连不上 本机 的 Orca」 |
| A7 | heartbeat-watch 90 秒超时杀掉包装后，ssh 还挂着 | S11 | 静态检查：包装最后一步是 `exec ssh`（没法在不杀进程的前提下实测，写明） |
| A8 | defs.json 里 MBA 的 precheck 原文解析不对（目标里有空格、`·`、`\|\|`），或者依赖 Orca 预检环境里没有的 PATH / agent | S2 | 在 MBA 上用 `env -i`（只给 HOME、PATH=/usr/bin:/bin:/usr/sbin:/sbin、LANG），分别经 /bin/sh 和 /bin/zsh 跑 defs 原文（只换两个脚本路径，加 `--dry-run` 和临时状态目录）：「iMac ops · 01 卡住工作检查：正常」，退出 1 |
| A9 | MBA 经 ssh 实际读不到 iMac ops · 01 的心跳 | S2、S7 | S7：MBA 上直接跑 `orca-via-ssh automations runs --id 439cd438… --json`，ok 为 true、有运行记录、最新一条带 `@@HB`；`automations list --json` 里有 439cd438 和 createdAt |
| A10 | 心跳过期时，经新路径不出 heartbeat_stale，或者收件人变了 | S3 | MBA 上回放 30 分钟前的心跳：有「dry-run，将 POST 给 coding-assistant」，kind 是 heartbeat_stale，bot 是 coding-assistant（STUCK_FORCE_BOT 没设） |
| A11 | iMac 经 environment mba 读不到 MBA 的运行记录 | S6 | iMac 上 `--dry-run` 读 MBA 一条现有任务（ops · 09 `62d18b16…`）：没有「运行记录查不到」，读到的运行记录数 ≥ 1、有最新一次运行时间 |
| A12 | iMac 5c2d0575 改后的 precheck（并行版、最终版）跑不通 | S6b | iMac 上照 defs 原文跑（MBA 新任务 id 用 ops · 09 代替，加 `--dry-run` 和临时状态目录）：并行版 box 目标「正常」、MBA 目标读到运行记录；最终版只有 MBA 目标 |
| A13 | register.sh 在 dry-run 时调用了 orca；create 没带 `--disabled`；在别的机器上 apply | S8 | PATH 里放一个只记录调用的假 orca，dry-run 调用数 0；create 带 `--disabled`、`--fresh-session`、`--precheck-timeout 240`、每 5 分钟；没给 `--mba-id` 时打印占位、给了不合法的 id 退出 2。`--apply` 本 PR 不许跑，主机名和备份文件两道检查只做代码审阅 |
| A14 | defs.json 记的「改之前」和现网不一样，回滚还原不回去 | S9 | 只读 `orca automations show`：5c2d0575 的名字、precheck、超时和 defs 的 before 一致；box 94e4b0bc 和 439cd438 的 id、名字、启用状态对得上；MBA 上还没有同名任务 |
| A15 | 上线顺序里某一步让 ops · 01 一个看守都没有 | 文档检查 | README 顺序：MBA 新任务先启用，再改 5c2d0575，最后先去掉 5c2d0575 的 box 目标、再停 box 94e4b0bc；回滚先启用 box 再停 MBA。没法在本 PR 里实跑 |
| A16 | 演练写了真状态（`~/.orca-state/heartbeat-watch`、`~/.orca-state/bin`）或发了真叫醒 | S10、全部 | 每次运行都带 `--dry-run`、临时 HB_STATE_DIR、假 webhook 目录；MBA 上真路径演练前后都不存在 |
| A17 | 新脚本在 macOS 自带 /bin/bash 3.2 下出错 | S11、全部 | `wake/tests/lint-bash32-utf8.sh` 和 `/bin/bash -n` 通过；演练在两台 Mac 上都用 /bin/bash 3.2 跑脚本 |

## B. 演练本身可能骗人的地方

| # | 风险 | 处理 |
|---|---|---|
| C1 | S1 回放用假 HB_ORCA 和固定时钟 | 是替身，不叫 E2E。数据是 10-21 从 iMac 真实录的 439cd438 运行记录（只留 `@@HB` 行，别的日志行去掉，免得把工作区名进仓库）；时钟用 `wake/tests/hb-replay/clock/sitecustomize.py` 固定，`time.sleep` 不等，三版输出才能逐字节比 |
| C2 | S3 的「心跳过期」是把录的数据整体往前挪 30 分钟 | 是回放。不能为了演练去停现网的 ops · 01 |
| C3 | S5 用假 ssh 证明「没连 ssh」 | 是替身，只用在拒绝的用例上；转义（S5b）和正常读取（S2、S7）是真 ssh、真 orca |
| C4 | MBA 上的运行是从 iMac `ssh mba` 起的，不是 Orca 的预检进程 | `env -i` 只给最少的环境变量来近似。Orca 预检环境在 MBA 上能不能连 ssh，要到上线第 3 步第一次真实运行才算证实 |
| C5 | defs 原文里两个脚本路径换成了临时副本 | 不许往 `~/.orca-state/bin/` 装文件，MBA 主检出也还没有 orca-via-ssh。只换路径，别的照原文 |
| C6 | S6 / S6b 的「MBA 新任务」是拿 ops · 09 代替的 | 它不打 `@@HB`，结论会是「没有心跳行」；这两个场景只证明 iMac 读得到 MBA 的运行记录，不看正常 / 中断 |
| C7 | register.sh 的 `--apply` 没跑 | 任务书禁止。主机名检查、备份检查和真正调用 orca 的部分都没演练过 |

## 写完代码、第一次试跑以后补的（2026-10-21 19:5x；上面两张表没改）

- A1 / S1：回放用例从 11 个加到 14 个，多了 orca 回 `ok: false`（找不到自动任务）、两个目标（一个正常、一个过期）、不带
  `--precheck`（退出 0）。
- A12 / S6b：第一次试跑（19:49，产物没进仓库）只有这一项 FAIL：并行版里 box 目标的结论是 `remote_runtime_unavailable`，
  那几分钟 iMac 到 box 的 grok-bot 隧道不通（现网 5c2d0575 19:30 那次运行也报了 box 查不到）。断言没有放宽，只是拆成三条：
  S6b.parallel（box 目标在前、出一行结论，MBA 目标读到运行记录）、S6b.box（box 目标「正常」，原来的断言）、S6b.final。
  S6b.box 的实际一栏附两样对照：紧接着用 base 版 heartbeat-watch 跑现网 5c2d0575 的 precheck（defs 里 before 的原文）
  得到的 box 结论，和现网 5c2d0575 最近 4 次运行对 box 的结论。
- F4 补充：MBA 上的 orca 是 1.4.229，iMac 是 1.4.224。

## 回退测试的期望（2026-10-21 20:2x，写回退脚本、跑之前；ops bot 验收要求）

回退测试 `wake/tests/heartbeat-watch-ssh-rollback.sh` 把代码换回 base `f828d452`：没有 `scripts/orca-via-ssh`、`register.sh`，
heartbeat-watch.sh 是 base 那份。defs.json 换成现网版：MBA 那条的 precheck 用现网 box `94e4b0bc` 的原文（environment `iMac`，
不经 ssh），`5c2d0575` 的并行版、最终版都用它的现网原文（只有 box 目标）。演练脚本和回放数据用本分支的，整轮跑一次。

本 PR 会改变结果的场景，回退后应该挂（19 项）：

| 编号 | 回退后为什么挂 |
|---|---|
| S0.diff | base 和「本分支」是同一份，没有第 13 行的改动 |
| S2.sh、S2.zsh | 现网版 precheck 在 MBA 上读不到 iMac ops · 01：MBA 的 Orca 没有 environment `iMac` |
| S4、S4b | 没有包装，heartbeat-watch 报的是 FileNotFoundError，不是 ssh 连不上的 JSONDecodeError |
| S4.wrapper、S5.iMac、S5.MBA、S5b、S7 | 没有 `scripts/orca-via-ssh`，退出 127，不是 2 / 255 / 0 |
| S6b.parallel、S6b.final | 现网 5c2d0575 只有 box 目标，没有 MBA 目标 |
| S8.mba、S8.imac-noid、S8.parallel、S8.final、S8.rollback、S8.refuse | 没有 `register.sh` |
| S11 | `orca-via-ssh`、`register.sh` 不存在，`bash -n`、shellcheck 报错，最后一步不是 `exec ssh` |

本 PR 不改变结果的场景，回退后应该照样过（26 项），用来排除「是环境坏了才挂」：S0.same、S0.bot、S1 全部 15 项（heartbeat-watch
行为本来就没变）、S3（回放）、S6（environment `mba` 本来就能读）、S6b.box、S9 四项（defs 现网版的 before 就是现网）、
S10.MBA、S10.iMac。其中 S6b.box、S9.94e4b0bc 要 iMac 到 box 的 grok-bot 隧道当时是通的。

为了让旧 defs 也能照原文跑，演练脚本里拼 precheck 的两处检查放宽成「最多出现一次」：S2 的包装路径、S6b 的 MBA 新任务 id 占位。
各场景的断言没改。

## 第二轮：dr eggbot 审查 7ac1220 以后（2026-10-21 21:2x，写代码之前）

依据：`.orca-task/REVIEW-dreggbot-7ac1220.md` 的必改 1–4、建议 1–5，和下面新查到的事实。上面几张表不改，新的写在这里。

### 新查到的事实

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F14 | Orca 起预检用 `spawn(命令, {shell: true, detached: true})`：`/bin/sh -c`，自成一个进程组。到 timeoutSeconds 先给整个进程组发 SIGTERM，2 秒后发 SIGKILL，这一轮记 timedOut、exitCode 为空；stdout、stderr 都关了才算结束（close 事件）。iMac 1.4.224 和 MBA 1.4.229 这段一样 | 两台 `/Applications/Orca.app/Contents/Resources/app.asar` 里预检那段代码 | 被杀的这一轮，heartbeat-watch 来不及写 state.json、打 `@@HB`（审查 R6）。S12 照这个做法起预检 |
| F15 | iMac 上 orca CLI 的请求默认 60 秒超时，前面还有一次 status.get。Orca 卡住时，一次调用就可能顶到 heartbeat-watch 的 90 秒 | 审查（box 上 Orca 源码 `cli/runtime/client.js:37`） | 一次查询最坏 3×90+2×8=286 秒，超过 240。ssh 连得上、iMac 的 Orca 卡住时，MBA 那条每轮都被杀，fail_since 记不上，永远不报（必改 1） |
| F16 | MBA 的 ssh 设置没有 ServerAlive，ConnectTimeout 没设（包装自己加了 10 秒），不复用连接 | 审查（MBA 上 `ssh -G imac`） | 连上以后对面不回，ssh 不会自己退；连接半路断了，客户端要等 TCP 超时 |
| F17 | 两台都是 macOS 26.6.2，都有 `/usr/bin/perl`（5.34.1）、`/usr/bin/ssh`（OpenSSH_10.3p1）、`/usr/bin/python3`（3.9.6） | `sw_vers`、`perl -e 'print $^V'`、`ssh -V` | 包装用 perl 的 `alarm` 给每次 ssh 加 70 秒上限：先 `alarm 70` 再 exec ssh，计时在 exec 以后还在，到时 SIGALRM 发给 ssh 本身。ssh 会不会自己处理或清掉 SIGALRM，要用真 ssh 实测（A20） |
| F18 | 5c2d0575 的目标经 iMac 本机 orca 的 environment（`grok-bot`、`mba`）读，不经包装，每个目标最坏还是 286 秒 | defs.json、heartbeat-watch 的 `runs_of` | 并行版两个目标最坏 572 秒，precheckTimeout 改 600（Orca 的上限，F8）；最终版一个目标，改 300；回滚版照旧还原成现网的 240 |
| F19 | 还没见过目标的心跳（state 里没有 last_hb）、心跳又没有或过期时，heartbeat-watch 还要查一次 `automations list`（createdAt），只查 1 次，也经包装 | 读 `main()` 第 207–210 行、`created_at` | 加上限后 MBA 那条最坏：runs 3 次 226 秒；碰上这种情况再加 list 70 秒，共 296 秒。要超过 240，得是还没见过心跳、心跳又过期，而且 runs 前两次各卡满 70 秒、第三次才成功。写进 README 已知限制 |

### 要防的失败方式

| # | 失败方式 | 场景 | 期望 |
|---|---|---|---|
| A18 | ssh 连上了、iMac 的 orca 不回：MBA 这条每轮被 Orca 杀掉，不写 fail_since、不打 `@@HB`，永远不报（必改 1） | S12 | MBA 上照 defs 原文跑 precheck：只换两个脚本路径；不加 `--dry-run`；临时状态目录、空的 webhook 目录、PATH 里放只记录调用的假 curl。PATH 最前面的 ssh 替身把远端命令换成 `sleep 110`，别的参数原样 exec 真 ssh。照 Orca 的做法起（F14），超时取 defs 的 precheckTimeout，真时间。期望：没超时、自己结束、退出 1；有「iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟」；有 `@@HB`，rc 0；state.json 里这个目标有 fail_since，在这次运行的起止时间之间；ssh 起了 3 次，相邻两次开始隔 75–85 秒（70 秒上限加 8 秒等待）；第二次 ssh 起来时第一次的 ssh 进程已经没了，跑完 3 个都没了；假 curl 0 次，输出里没有「POST」和「webhook 配置」（第一次查不到时走 `continue`，到不了发告警那步） |
| A19 | S12 分不出好坏：没有上限的包装也能过 | S12.old | 同样的设置，包装换成 7ac1220 那版（没有上限），precheck 直接写（不取 defs），超时取 defs 的 precheckTimeout。期望：到超时被杀（timedOut，用时在超时和超时加 15 秒之间）；没有 `@@HB`；状态目录里什么都没写；相邻两次 ssh 开始隔 95–105 秒（heartbeat-watch 的 90 秒超时加 8 秒）；第二次 ssh 起来时第一次的已经没了，跑完都没了 |
| A20 | ssh 自己处理或清掉 SIGALRM，70 秒上限不起作用 | S12 | S12 用的是真 ssh，只换了远端命令。上限不起作用的话，每次要等 heartbeat-watch 的 90 秒，两次开始隔 98 秒左右，最后被杀，S12 挂 |
| A7（补） | heartbeat-watch 90 秒超时杀掉包装后，ssh 还挂着 | S12.old | 原来只做了静态检查（S11）。S12.old 里第二次 ssh 起来时（第一次被 90 秒超时杀掉之后、Orca 杀整个进程组之前）看第一次的 pid，期望已经没了 |
| A21 | 包装加的 ServerAlive 选项让正常读取出错 | S2、S5b、S7 | 这三个走真 ssh 和新包装，期望照旧 |
| A22 | 包装里 ssh 的参数变了，或者被放行的调用没走 perl 的上限 | S5、S11 | S5：放行的两条，假 ssh 收到的参数开头是 `-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 imac zsh -lc …`。S11：包装最后一步是 `exec /usr/bin/perl -e 'alarm shift; …' 70 ssh …` |
| A23 | 没有 perl，或者 perl exec ssh 失败 | 不演练 | 包装退出非 0、stdout 空，heartbeat-watch 走「运行记录查不到」，45 分钟后报。两台都有 `/usr/bin/perl`（F17） |
| A24 | 预检超时没放够：并行版不到 572 秒、最终版不到 286 秒 | S8 | register.sh 打印的 `--precheck-timeout`：MBA 新任务 240，parallel 600，final 300，rollback 240 |
| A25 | MBA 用的包装跟着主检出变：主检出切了分支或者删了文件，要 45 分钟后才报（建议 2） | S2、S12 | defs 的 `HB_ORCA` 改成 `$HOME/.orca-state/bin/orca-via-ssh`，和 heartbeat-watch.sh 一样装到 `~/.orca-state/bin/`，装后比 sha（README 第 1 步）。S2、S12 拼 precheck 时换的是这个路径。本 PR 不装 |
| A26 | 演练写了真状态 | S10 | MBA 上多查一个真路径 `~/.orca-state/bin/orca-via-ssh`，4 个都没有。S12 不是 dry-run，状态写在临时目录；S10 数状态文件时不算 S12 的目录 |

### 演练本身可能骗人的地方

| # | 风险 | 处理 |
|---|---|---|
| C8 | S12 的「iMac 的 orca 不回」是 ssh 替身把远端命令换成 `sleep 110` | 是替身，不叫 E2E。ssh 客户端、包装、heartbeat-watch 是真的，连的是真 iMac。iMac 上真 orca 卡住时什么样没演练：比如 orca 自己 60 秒超时后可能先回一个报错 JSON，那样不用等 70 秒上限。远端的 `sleep 110` 最多活 110 秒，自己结束 |
| C9 | S12 的预检进程是演练脚本照 Orca 的做法起的，不是 Orca | 照两台 app.asar 的代码写（F14）：`/bin/sh -c`、新进程组、超时先 TERM 再 KILL、等 stdout 和 stderr 都关。Orca 自己起这条预检，要到上线卡 ② 才有 |
| C10 | S12 不带 `--dry-run` | dry-run 不写 state.json、不打 `@@HB`，看不到要证明的东西。状态目录是临时的，webhook 目录是空的，PATH 里有假 curl；第一次查不到时 heartbeat-watch 走 `continue`，到不了发告警那步 |

### 回退测试的期望（第二轮）

base 还是 `f828d452`，回退的做法不变。新加的两项：

- S12 该挂（该挂的变成 20 项）：现网版 precheck 不经 ssh，MBA 的 Orca 没有 environment `iMac`，几秒内就「运行记录查不到（invalid_argument）」。ssh 替身一次都没起，不是 JSONDecodeError，也没有 3 次 70 秒。
- S12.old 照样过（该过的变成 27 项）：它用的是钉死的 7ac1220 包装，heartbeat-watch 的行为本来就没变。

## 第三轮：dr eggbot 复审 99358b0 以后（2026-10-21 22:4x，写代码之前）

复审签了，条件是 MBA 新任务的预检超时从 240 改成 330：最坏 296 秒（F19），加约 4 秒起动（S12 里第一次 ssh 在开始后约 4 秒才起），再留余量。这一轮只改这个值，和跟着它变的期望、说明。上面几张表不改，新的写在这里。

### 新查到的事实

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F20 | 超时 240 时，F19 的少见情况（3 × 70 + 2 × 8 + 70 = 296 秒）这一轮会被杀 | F19 | MBA 新任务 precheckTimeout 改成 330：296 秒加起动约 4 秒，还剩约 30 秒 |
| F21 | 330 比 5 分钟的间隔长。Orca 建运行只按计划时间去重；调度把每次运行发给界面进程就往下走，不等预检；界面进程每个请求各自处理，没看到「上一轮没完就不起下一轮」的判断。heartbeat-watch 写 state 用 `os.replace`，不加锁 | iMac 上 Orca 1.4.224 的 app.asar（`createAutomationRun`、`evaluateDueRuns`、界面进程处理 `automations:dispatchRequested` 的代码）；`scripts/heartbeat-watch.sh` 第 96 行。MBA 的 1.4.229 没核对，没在真机上验证 | 一轮预检超过 300 秒时，下一轮的预检会和它同时跑一小段，最坏是同一时刻发两条告警。常见最坏 226 秒碰不到；少见情况 296 秒加起动约 4 秒，正好在边上。`5c2d0575` 并行版超时 600，第二轮起就是这样。不改，写进 README 已知限制 |
| F22 | 超时 330 时，S12 的情况（ssh 连上了、远端不回）没有 70 秒上限也放得下：3 × 90 + 2 × 8 = 286 秒，加起动约 4 秒 | F9、F15 | 70 秒上限只在 F19 的少见情况里还有用：没有上限时 3 × 90 + 2 × 8 + 90 = 376 秒，超过 330 |

### 要防的失败方式

| # | 失败方式 | 场景 | 期望 |
|---|---|---|---|
| A27 | register.sh 打印的超时没跟着 defs 变 | S8 | MBA 新任务 `--precheck-timeout 330`（A13、A24 里 MBA 新任务的 240 改成 330）；parallel 600、final 300、rollback 240 不变 |
| A28 | 超时改成 330 后 S12 变了 | S12 | 同 A18，超时取 defs，变成 330 |
| A29 | S12.old 的期望是按 240 写的 | S12.old | 超时也取 defs，变成 330。照 F22，7ac1220 的包装约 290 秒自己结束、不被杀，会写下 fail_since 和 `@@HB`，和 A19 的期望（到超时被杀、什么都没写）不符：**这一轮 S12.old 预期 FAIL**，除它以外各项期望都过。任务说其他不动，S12.old 不改；要不要改、怎么改（钉在 7ac1220 那版 defs 的 240，按 330 改期望，或者去掉）由 Zack 定 |

### 回退测试（第三轮）

不重跑。这次改动不影响它，理由：

- 回退测试的现网版 defs 把 MBA 那条的 precheck 和超时都换成 box `94e4b0bc` 的原文（`wake/tests/heartbeat-watch-ssh-rollback.sh` 第 39 行），超时还是 240，S12、S12.old 的期望不变。
- S8 在旧代码上该挂，原因是 base 没有 register.sh；期望值从 240 改成 330 不影响。要再核一遍第二轮回退报告里 S8 六项的实际输出，确认挂的原因是这个。

## 第五轮：precheck 外面套 lockf（2026-10-21 23:5x，写代码之前）

第四轮读 `scripts/heartbeat-watch.sh` 发现，两轮预检重叠时会同时写状态文件（F27），停下来报给 Zack。Zack 选了方案 1：MBA 新任务和
`5c2d0575` 并行版的 precheck 外面套 `/usr/bin/lockf -k -t 0 <锁文件>`，锁文件放在 `~/.orca-state/heartbeat-watch/` 下，每个任务一个。
heartbeat-watch.sh 本身不改，它内部加锁、临时文件按进程取名留作后续。S12.old 按第四轮的方案 1：超时钉在 7ac1220 那版 defs 的 240。
上面几张表不改，新的写在这里。

### 新查到的事实

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F23 | 两台的 `/usr/bin/lockf` 是同一个文件（sha256 `e15de85e…`）。用法 `lockf [-knsw] [-t 秒] 文件 命令 [参数…]`：先拿锁，拿到了再起命令、等它结束；`-t 0` 拿不到锁时不起命令，退出 75（EX_TEMPFAIL），stderr 是 `lockf: <文件>: already locked`；锁文件打不开（比如目录不存在）退出 73（EX_CANTCREAT）；命令自己退出时原样返回它的退出码，命令被信号杀掉时退出 70；`-k` 跑完不删锁文件。锁是 flock(2)，持锁的进程退出或被杀，锁就放开 | `man lockf`；iMac 上在临时目录里试过：拿不到锁退出 75、stdout 空；目录不存在退出 73；命令 `exit 3` 时返回 3；命令被 SIGTERM 杀掉时返回 70 | 上一轮还在跑时，这一轮立刻退出 75：heartbeat-watch 不起，不读也不写状态，也不打 `@@HB`。正常的一轮 heartbeat-watch 退出 1，lockf 原样返回 1 |
| F24 | MBA 上还没有 `~/.orca-state/heartbeat-watch/`（F3）。heartbeat-watch 第一次跑时会自己建这个目录（第 63 行），但 lockf 在它起来之前就要打开锁文件 | `ssh mba ls`；F23 | README 第 1 步先 `mkdir -p ~/.orca-state/heartbeat-watch`。漏了这一步，每轮退出 73、没有 `@@HB`：卡 ② 第 3 步的核对（exitCode 1、有 `@@HB`）过不了；到卡 ③ 以后，iMac 20 分钟后报 MBA 那条中断。iMac 上这个目录已经有了（现网 `5c2d0575` 一直在写） |
| F25 | 预检退出码不是 0，Orca 就记 `skipped_precheck`，不起模型。iMac 的 Orca 1.4.235 和 MBA 的 1.4.229 判断预检通过的代码一样：有结果、没超时、没出错、退出码是 0，四条都满足才算过；不过就记 `skipped_precheck`，错误文字是「Precheck exited with code N.」。只读的运行记录里，iMac 755 条（10-11 到 10-21）、MBA 200 条（10-18 到 10-21），退出码 1、2、255 和超时都记成了 `skipped_precheck`。没有退出码 75 的记录 | 两台 app.asar 里预检那段代码；`orca automations runs --json`（只读） | 75 会记成 `skipped_precheck`，依据是代码和别的退出码的记录，没在真机上验证：要让 Orca 真跑一轮带锁的预检，就得建任务或者改现网任务，任务书禁止。卡 ② 启用以后，可以手动拿住锁一轮来看（README 卡 ②） |
| F26 | 锁只在 lockf 进程手里，它起的命令不持锁。Orca 超时时给整个进程组发信号（F14），lockf、heartbeat-watch、ssh 一起没了，锁跟着放开。只杀 lockf 一个进程时，锁也放开，但它起的命令还在跑（ppid 变成 1），下一轮拿到锁，会和它同时跑 | iMac 上在临时目录里试过：`kill -KILL` lockf 以后马上能拿到锁，它起的 sleep 还在；给整个进程组发 SIGTERM 以后也马上能拿到锁 | Orca 自己不会只杀 lockf，有人手动只杀 lockf 才会这样。写进已知限制 |
| F27 | 第四轮读代码的结论：两轮重叠时，两个进程各读一份旧状态（第 189 行），各写回整份（第 256 行）；`save_json` 不加锁，临时文件名固定是 `state.json.tmp`（第 90–96 行）。后存的一轮盖掉先存的：同一次中断报两次、漏报一次中断、「已恢复」不发、45 分钟的计时偏；两轮恰好同时写时，state.json 可能被写坏，下一轮按空状态从头算，所有目标的记录一起丢 | `scripts/heartbeat-watch.sh`；第四轮的 RESULT.md | F21 写的「最坏是同一时刻发两条告警」不全，README 和 PR 描述的已知限制按这一条改。套上 lockf 以后，同一个任务的两轮不会同时进到 heartbeat-watch |
| F28 | 在两台现装的 Orca 上重读了两轮会不会重叠。iMac 上的 Orca 10-21 23:15 前后自己升级到了 1.4.235（前几轮记的是 1.4.224），MBA 还是 1.4.229。调度每 60 秒看一次哪些运行到点了，建好运行、发给界面进程就往下走，不等预检；界面进程每收到一个就跑一次预检，不排队，也没有「上一轮没完就不起下一轮」。1.4.235 加了按任务排队（`runInAutomationLane`），排的只是「发给界面进程」这一步，不包括预检；1.4.229 没有这个队列 | 两台 app.asar 里的 `evaluateDueRuns`、界面进程处理 `automations:dispatchRequested` 的代码、`runInAutomationLane` | 结论和 F21 一样：一轮预检超过 300 秒时，下一轮会和它同时跑。没在真机上验证。Orca 升级不是本 PR 动的 |
| F29 | wake-tla 这次跑不了：两台都没有 Java 17 和 tla2tools（iMac 只有 Java 8，MBA 没有 Java）；`wake/tla/check.sh` 用 `free` 和 `/proc/loadavg`，只能在 Linux 上跑；`SOURCES.sha256` 里 `scripts/stuck-check.sh`、`scripts/heartbeat-watch.sh` 两项和现在的代码对不上，按 skill 第 3 步要先更新模型，结果才有意义；模型里还是 box 盯 iMac，没有 lockf，`wake/tla/README.md` 的假设 4（Orca 不会让同一个自动任务的 precheck 重叠运行）和 F21、F28 不符。TLC 只读 `wake/tla/` 下的文件，本 PR 在那里只改了 README 的文字 | `/usr/libexec/java_home -V`；`check.sh`；`shasum -a 256 -c wake/tla/SOURCES.sha256`；`.claude/skills/wake-tla-verify` | 不跑，PR 里写没跑和原因。被 lockf 跳过的那一轮没有 `@@HB`，盯它的一方看到的心跳间隔最长 10 分钟，后续 wake-tla 批次建模时要算进去 |

### 要防的失败方式

| # | 失败方式 | 场景 | 期望 |
|---|---|---|---|
| A30 | 锁没起作用：上一轮还在跑，下一轮照常进到 heartbeat-watch，两轮同时读写状态 | S13 | MBA 上照 defs 原文跑 MBA 新任务的 precheck（只换两个脚本路径和锁文件目录；不带 `--dry-run`；临时状态目录、空的 webhook 目录、PATH 里放假 curl），照 Orca 的做法起三轮，共用状态目录和锁文件。PATH 最前面的 ssh 替身记下每次调用，再 exec 真 ssh；A 的替身先等 30 秒。A 的 ssh 起来 3 秒后起 B，A 结束后起 C。期望：A 退出 1，有「iMac ops · 01 卡住工作检查：正常（最新心跳」，`@@HB` rc 0；B 在 A 跑的期间开始、也在这期间结束，3 秒内退出 75，stdout 空，stderr 有 `already locked`，B 的 ssh 0 次，B 前后状态目录一样；C 在 A 结束以后开始，退出 1，正常，`@@HB` rc 0；假 curl 0 次，输出里没有「POST」和「webhook 配置」 |
| A31 | 拿不到锁的那一轮还是起了 heartbeat-watch，读写了状态 | S14.MBA.held、S14.iMac.held | 先用 `lockf -k -t 0 <锁文件> sleep 6` 拿住锁（等到它起的 sleep 出现），再照 defs 原文跑 precheck：MBA 用 MBA 新任务的，iMac 用 `5c2d0575` 并行版的（MBA 新任务 id 用 ops · 09 代替）；锁文件换到临时目录，加 `--dry-run`；HB_STATE_DIR 指向一个不存在的目录，heartbeat-watch 一起来就会建它（第 63 行，在读 state 之前）；PATH 最前面放只记录调用、退出 1 的替身（MBA 替 ssh，iMac 替 orca 和 orca-ide）。期望：退出 75，stdout 空，stderr 有 `already locked`，那个目录没被建出来，替身 0 次 |
| A32 | 拿不到锁时的退出码不是 75 | S13、S14.MBA.held、S14.iMac.held | 75 |
| A33 | 持锁的进程被杀以后锁不放开 | S14.MBA.kill、S14.iMac.kill | 只用 lockf：`lockf -k -t 0 <锁文件> sleep 8` 拿住锁；探一次（`lockf -k -t 0 <锁文件> true`），退出 75；核对这个 lockf 的 pid 是演练刚起的、ppid 是演练的 shell、命令名是 lockf，只给它一个发 SIGKILL；它退出 137；再探一次，退出 0；它起的 sleep 还在、ppid 1（F26），之后自己结束 |
| A34 | 被超时杀掉以后锁不放开，下一轮拿不到 | S14.MBA.timeout、S14.iMac.timeout | 第一轮照 Orca 的做法起，超时 12 秒，加 `--dry-run`，PATH 最前面的替身（MBA 替 ssh，iMac 替 orca 和 orca-ide）记下 pid 后 exec `sleep 60`。替身起来 3 秒后探一次锁：退出 75。第一轮到 12 秒被杀（timedOut，用时 12–27 秒），替身的进程没了。紧接着照 Orca 的做法起第二轮：用真的 ssh / orca，超时取 defs（330、600），加 `--dry-run`。期望：没超时，退出 1，没有 `already locked`，有第一个目标的结论行（MBA「iMac ops · 01 卡住工作检查：」，iMac「box ops · 29 卡住检查心跳：」） |
| A35 | 锁目录不存在（MBA 漏了第 1 步的 mkdir） | S14.MBA.nodir、S14.iMac.nodir | 锁文件放在不存在的目录里，其余同 held：退出 73，stdout 空，stderr 有 `cannot open`，那个目录没被建出来，替身 0 次。这就是 F24：每轮 73、没有 `@@HB` |
| A36 | 演练在真目录里建了锁文件，或者拿了真的锁 | S10 | 真路径多查两个：`~/.orca-state/heartbeat-watch/mba-hb-watch.lock`、`~/.orca-state/heartbeat-watch/5c2d0575.lock`。MBA 上 6 个真路径演练前后都没有；iMac 上这两个演练后没有，其余照旧。演练里拼 precheck 时，`$HOME/.orca-state/heartbeat-watch/` 最多出现一次，换成临时目录 |
| A37 | 套了 lockf 以后，正常的一轮变了（输出、退出码、用时） | S2、S6b、S12、S13 | 期望不变：S2 两项正常、退出 1；S6b 三项照旧；S12 照 A18、A28（ssh 3 次、自己结束、退出 1、写下 fail_since 和 `@@HB`）；S13 的 A、C 退出 1 |
| A38 | register.sh 打印的 precheck 没带 lockf，或者 final、rollback 也被套上了 | S8 | S8.mba 的 `--precheck` 是 `'HB_ORCA=$HOME/.orca-state/bin/orca-via-ssh ORCA_SSH_HOST=imac /usr/bin/lockf -k -t 0 $HOME/.orca-state/heartbeat-watch/mba-hb-watch.lock $HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target "…"'`，超时 330；S8.parallel 是 `'/usr/bin/lockf -k -t 0 $HOME/.orca-state/heartbeat-watch/5c2d0575.lock $HOME/.orca-state/bin/heartbeat-watch.sh --precheck …'`，超时 600；S8.final、S8.rollback 和上一轮一样，没有 lockf |
| A39 | S12.old 的超时跟着 defs 变，就不再是旧包装的对照了 | S12.old | 第四轮的方案 1：超时取 7ac1220 那版 defs.json 里 MBA 新任务的 precheckTimeout，判断时核对它是 240。期望同 A19：到 240 秒被杀，没有 `@@HB`，状态目录是空的，ssh 相邻两次开始隔 95–105 秒 |
| A40 | 这一轮挡不住、也不演练的 | 不演练 | 写进 README 已知限制：final（超时 300）和 rollback（240）没套 lockf，这次只要求套 MBA 新任务和并行版；锁按任务分，两个任务用同一个状态目录时互相挡不住（现在每台只有一个任务用 heartbeat-watch：iMac 的 `5c2d0575`，MBA 上还没有）；只杀 lockf 一个进程时，它起的 heartbeat-watch 不受锁保护（F26）。heartbeat-watch 自己加锁、临时文件按进程取名留作后续，这次不改 heartbeat-watch.sh |

### 演练本身可能骗人的地方

| # | 风险 | 处理 |
|---|---|---|
| C11 | S13 的三轮是演练脚本照 Orca 的做法起的，A 用 ssh 替身拖慢了 30 秒 | Orca 自己会不会让两轮重叠，只读了代码（F28），没在真机上看到。拖慢 A 是为了让 B 一定落在 A 跑的期间；ssh 客户端、包装、lockf、heartbeat-watch 和 iMac 都是真的。用了替身，不叫 E2E |
| C12 | S14 的 held、kill 用 `lockf … sleep` 拿锁，不是一轮真的 heartbeat-watch；kill 要给演练自己起的 lockf 发 SIGKILL | held、kill 看的是锁本身。一轮真的 heartbeat-watch 拿着锁的情况在 S13（A 拿着锁时 B 被挡）和 S14.timeout（第一轮拿着锁时探针被挡）。kill 之前核对 pid、ppid 和命令名，只给这一个进程发信号；它起的 sleep 不发信号，让它自己结束 |
| C13 | S14.timeout 的超时是 12 秒，替身把 ssh / orca 换成 `sleep 60` | 真的超时是 330、600 秒，等不起。被杀的方式和 Orca 一样（给整个进程组先发 TERM，2 秒后发 KILL），和超时多长无关。用了替身，不叫 E2E |
| C14 | Orca 把 75 记成 `skipped_precheck` 没验证 | 见 F25。卡 ② 启用以后可以手动验证一次 |

### 回退测试的期望（第五轮）

base 还是 `f828d452`，回退的做法不变：现网版 defs 里，MBA 那条用现网 box `94e4b0bc` 的 precheck，`5c2d0575` 各阶段用它自己的现网
precheck，都没有 lockf。新加的 9 项：

- 该挂的 7 项（该挂的从 20 项变成 27 项）：
  - S13：现网版 precheck 没套 lockf，B 照常跑，退出不是 75。
  - S14.MBA.held、S14.iMac.held：heartbeat-watch 照常起来，建出了那个不存在的目录，退出不是 75。
  - S14.MBA.nodir、S14.iMac.nodir：没有锁文件这一步，照常跑，退出不是 73。
  - S14.MBA.timeout、S14.iMac.timeout：第一轮跑的时候，探针拿得到锁（退出 0）。
- 照样过的 2 项（该过的从 27 项变成 29 项）：S14.MBA.kill、S14.iMac.kill。它们只用 lockf 本身，和 defs、代码都无关。
- S12.old 照样过：超时取 7ac1220 那版 defs 的 240，和以前一样。

共 56 项。新代码上 56 项都该过。

### 第五轮回退测试以后补的（2026-10-22 01:0x，改演练之前）

`17116ce` 上的回退测试（`reports/heartbeat-mba-imac-1021-rollback-f828d45-17116ce/`）56 项里 55 项和期望一致。逐项核对挂的原因时发现，
S13 和 S14.MBA.timeout 在 base 上没测到要测的情况：挂是挂了，原因不是上面写的那条。上面几张表不改，补的写在这里，写完再改演练。

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F30 | base 上 MBA 那条 precheck（现网 box `94e4b0bc` 的原文）没有 `HB_ORCA`，heartbeat-watch 直接调本机的 orca：先在 PATH 里找 `orca-ide`、`orca`，都找不到就用 `/Applications/Orca.app/Contents/Resources/bin/orca`（第 39–40 行，和 base 一样）。演练在 MBA 上用最少环境，PATH 是 `替身目录:/usr/bin:/bin:/usr/sbin:/sbin`；MBA 的 `orca` 在 `/usr/local/bin`（链接到上面那个路径），不在 PATH 里，所以用的是那个路径。S13、S14 在 MBA 上只替了 ssh，base 上这些替身一次都没被调用 | 回退测试的 `raw/mba/S13-A.ssh-calls`、`S13-B.ssh-calls`、`raw/mba/S14/timeout.stub-calls` 都是空的；`raw/mba/S13-*.orca.json` 的起止时间；`scripts/heartbeat-watch.sh` 第 39–40 行；在 MBA 上 `ls -l` 看了这两个路径 | S13：A 没被拖慢，18.3 秒就结束了，B 在 A 结束 3.3 秒后才开始，两轮没有同时跑。B 照常跑完、退出 1，S13 因此挂了，但证明不了「两轮同时跑时，没有锁 B 就会进到 heartbeat-watch」。S14.MBA.timeout：第一轮调的是真 orca，替身没起来；演练等满 10 秒、又等 3 秒才探锁，第一轮 12.0 秒时已经被杀，探锁退出 0 证明不了「第一轮跑的时候拿得到锁」。S14.MBA.held、nodir 在 base 上调的也是真 orca（只读），它们挂的原因（目录被建出来、退出不是 75 / 73）不受影响。iMac 上 base 的 heartbeat-watch 在 PATH 里找到了 orca-ide 替身，S14.iMac.timeout 的替身起来了（`raw/S14-imac/timeout.stub-calls` 有一行），探锁在替身起来 3 秒后 |

### 演练本身可能骗人的地方（补）

| # | 风险 | 处理 |
|---|---|---|
| C15 | 替身只替 ssh：base 上 MBA 那条 precheck 不经 ssh（F30），替身没起作用，项目照样挂。只看「过 / 挂」看不出来 | MBA 上 S13、S14 的替身同时替 ssh 和 orca，每次调用记一行：pid、时间、替身名。S13 A 那轮每次调用先等 30 秒，再 exec 真的 `/usr/bin/ssh` 或 `/Applications/Orca.app/Contents/Resources/bin/orca`（PATH 里找不到 orca 时 heartbeat-watch 用的就是它）。S14.timeout 探锁前后各记一次时间（精确到毫秒），和第一轮的起止时间比。回退测试对第五轮新加的 7 项该挂的，除了核对挂没挂，还按下面「回退测试的期望（第五轮补）」核对演练「实际」一栏里挂的原因，对不上算不一致 |
| C16 | S6b.box 读的是 iMac 经 environment `grok-bot` 连 box 的运行记录，box 连不上时会挂。`17116ce` 的回退测试就是这样：00:46:22–00:47:03 三次都是 `remote_runtime_unavailable`，现网 `5c2d0575` 00:50 那一轮也一样（回退测试目录里手写的 `NOTE.md`） | 期望不改。挂了照实写报错原文和同一时间现网 `5c2d0575` 读 box 的结果，不为这个原因重跑 |

### 新代码上的期望（第五轮补）

A30–A35 之外：

- S13：A、B、C 各自的 ssh、orca 调用分开数。B 的 ssh、orca 都是 0 次。「实际」一栏写明 B 在不在 A 跑的期间。
- S14.MBA.held、S14.MBA.nodir：替身 0 次，ssh、orca 都算。
- S14.MBA.timeout、S14.iMac.timeout：探锁在第一轮开始以后、结束以前（第一轮还在跑），「实际」一栏写明；替身各起了几次分开写。

共 56 项，新代码上 56 项都该过。

### 回退测试的期望（第五轮补）

该挂 27 项、该过 29 项不变。第五轮新加的 7 项该挂的，演练「实际」一栏要对得上下面的原因，对不上算不一致：

- S13：B 在 A 跑的期间开始和结束，没超时，退出 1（照常跑完一轮），B 调了 orca（至少 1 次），B 前后状态目录不一样。
- S14.MBA.held、S14.iMac.held：退出不是 75，那个目录被建出来了。
- S14.MBA.nodir、S14.iMac.nodir：退出不是 73，那个目录被建出来了。
- S14.MBA.timeout、S14.iMac.timeout：第一轮还在跑的时候探锁，退出 0；替身起了至少 1 次；第一轮到 12 秒被杀。

## 第五轮补充：锁一直被占着（dr eggbot，2026-10-22 01:4x，写代码之前）

dr eggbot 补的要求：锁一直被占着时，每一轮都退出 75 跳过，这本身就是漏报。要 (a) 连续跳过超过 45 分钟（约 9 轮）就告警或写一条心跳行，
状态记在锁目录旁边；(b) 在两台机器上实测 `-k` 的锁在持锁进程崩溃或被 kill 以后不会残留；再加一条「锁一直被占着」的演练：外部持锁超过阈值时
必须看到告警，锁放开以后要能恢复。两样都做。heartbeat-watch.sh 还是不改（和 base 比只差第 13 行），所以 (a) 放在一个新脚本
`scripts/lock-held-alert` 里，precheck 里写在 lockf 前面。「状态记在锁目录旁边」理解成状态文件和锁文件放在同一个目录。
上面几张表不改，新的写在这里。

### 新查到的事实

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F31 | 现在锁一直被占着时谁会发现：MBA 新任务每轮退出 75、没有 `@@HB`，卡 ③ 以后 iMac `5c2d0575` 盯着它，20 分钟后报「MBA ops · 29 心跳互查」中断；卡 ③ 之前没人盯它（这时 box 还在盯 ops · 01）。`5c2d0575` 并行版没人盯（README 已知限制「`5c2d0575` 本身没人盯」），它每轮跳过时 box、MBA 两个目标都没人查，也没人报 | README「谁盯谁」；defs.json | (a) 主要补的是 `5c2d0575` 并行版。MBA 新任务从卡 ③ 起会被报两次（A53） |
| F32 | 锁能一直被占着的情况：lockf 拿着锁，直到它起的命令结束。heartbeat-watch 一轮有上限（MBA 新任务最坏约 296 秒，并行版最坏 572 秒），Orca 到超时会杀整个进程组（F14）。所以要么有人手动拿着锁（README 卡 ② 后面的可选验证就是 `lockf … sleep 360`），要么持锁的进程卡住了、又不在 Orca 会杀的那个进程组里。Orca 退出、崩溃或升级时正在跑的那一轮会怎样，没查 | F14、F23、F26；README | 平时碰不到；碰到了就是 A41 |
| F33 | 持锁的 lockf 被信号杀掉时，锁马上放开，`-k` 留下的锁文件不挡下一次拿锁。iMac 上在临时目录里手测（10-22 01:3x）：SIGTERM 退出 143，SIGSEGV 退出 139；信号发出后马上探锁，都退出 0；锁文件还在；它起的 sleep ppid 变成 1，自己结束；~~`~/Library/Logs/DiagnosticReports/` 没有多出 lockf 的崩溃报告~~（这句错了，见 F36）。SIGKILL（退出 137）见 S14.kill | 手测；F23 | (b) 放进演练，两台各做 SIGKILL、SIGTERM、SIGSEGV 三项。崩溃用 `kill -SEGV` 模拟 |
| F34 | 对面的 heartbeat-watch 读 `@@HB` 时只看 `ts` 和 `last_scan`，不看 `rc`（第 117–125、220–228 行）。跳过的那一轮如果打一行 `@@HB`，`ts` 是新的，对面就当这边还活着；`last_scan` 沿用旧值时，要过 N + 15 = 35 分钟才报「扫描每次超时被杀或每次出错」。不打 `@@HB`，对面 20 分钟就报「已 N 分钟没有新的」 | `scripts/heartbeat-watch.sh` | (a) 选告警，不写 `@@HB`。跳过时只在 stdout 打一行普通文字（进 Orca 的运行记录，对面不读）。告警的发法照抄 heartbeat-watch 的 `post`：同一个 bot、同样的 webhook 文件和环境变量 |
| F35 | MBA 的 Orca 自己升级了：10-22 00:37 的演练记的是 1.4.229，01:11 的记的是 1.4.237，MBA 上 Orca 进程约 00:55 起来，不是本 PR 动的。重读 1.4.237：调度起的运行，有预检就先跑预检，结果不算通过就记 `skipped_precheck`（和 iMac 1.4.235 那段代码一样，只是压缩后的名字不同）；预检进程正常退出时把数字退出码交上去。判断通过的 `didAutomationPrecheckPass`（有结果、没超时、没出错、退出码 0）在 `app.asar.unpacked/out/shared/automation-precheck.js`，两台这个文件逐字节一样（sha256 `957c4853…`）。主进程里调用处压缩成了 `f.vw`，它是不是就是这个函数，没追到。另外，只有调度起的运行（`trigger` 是 `scheduled`）才跑预检，手动 `orca automations run` 不跑 | 两台 `app.asar` 和 `automation-precheck.js` 的只读查看 | F25 的结论对 1.4.237 也成立，同样没在真机上验证；手动 run 也验证不了 75 |
| F36 | 更正 F33（10-22 02:2x 查到）：`kill -SEGV` 打在 lockf 上，macOS 会给它写一份崩溃报告 `~/Library/Logs/DiagnosticReports/lockf-<日期>-<时间>.ips`，有时晚几秒才写。iMac 上现在有两份：`lockf-2026-10-22-013355.ips` 是 F33 的手测留下的，01:34:04 才写，比发信号晚约 9 秒，当时查得太早，没看到；`lockf-2026-10-22-021802.ips` 是 02:18 在临时目录里试跑 S14 时留下的。MBA 上还没有。两台「共享 Mac 分析」都关着（`DiagnosticMessagesHistory.plist` 里 `AutoSubmit`、`ThirdPartyDataSubmit` 都是 0），报告只留在本机 | `ls -l ~/Library/Logs/DiagnosticReports/`、`defaults read`，都是只读查看 | S14.crash 每跑一次，那台机器就多一份 lockf 的崩溃报告：演练和回退测试各跑一次，两台各多两份。报告是系统写的，演练不删，写进已知限制和 PR。A52 的「crash 后数一次」是等它起的 sleep 结束以后才数，报告写得更晚时会数漏，所以只记不判 |

### 要防的失败方式

| # | 失败方式 | 场景 | 期望 |
|---|---|---|---|
| A41 | 锁一直被占着，每轮都退出 75，没人知道 | S15.MBA、S15.iMac | `scripts/lock-held-alert`（装到 `~/.orca-state/bin/`）。两个 precheck 写成 `… $HOME/.orca-state/bin/lock-held-alert /usr/bin/lockf -k -t 0 <锁文件> $HOME/.orca-state/bin/heartbeat-watch.sh …`。它照原样跑后面的 lockf 命令；lockf 退出 75 时，在锁文件旁边的 `<锁文件>.skips.json` 记下这一串跳过的第一次时间和次数，从第一次跳过起满 45 分钟（环境变量 `HB_LOCK_ALERT_MIN`，默认 45）的那一轮发一条告警：发给 heartbeat-watch 发的那个 bot（`coding-assistant`；`STUCK_FORCE_BOT`、`STUCK_WEBHOOK_DIR` 照样生效），`kind` `heartbeat_stale`，`status` `stuck`，`source` `lock-held-alert`；写明主机、锁文件、第一次跳过的时间、跳过了几轮、这段时间没在查的目标（取后面命令里 `--target` 的名字）。按 5 分钟一轮，是第 10 或第 11 次跳过。演练：外部用 `lockf -k -t 0 <锁> sleep 32` 拿住锁，阈值用环境变量改成 0.25 分钟（15 秒），照 Orca 的做法起 4 轮（第 1 轮开始后约 0、6、18、24 秒），加 `--dry-run`。4 轮都退出 75，stderr 有 `already locked`，stdout 只有一行「…已连续跳过 N 轮…」（N 依次是 1–4），`HB_STATE_DIR` 没被建出来；第 1、2 轮假 curl 0 次；第 3 轮假 curl 1 次，请求体 `kind` `heartbeat_stale`、`status` `stuck`、`source` `lock-held-alert`、`bot` `ops-system`，`note` 里有主机名、锁文件名和目标名（MBA「iMac ops · 01 卡住工作检查」；iMac「box ops · 29 卡住检查心跳」「MBA ops · 29 心跳互查」）；状态文件里记了报过的时间 |
| A42 | 锁放开以后不恢复：状态一直留着，或者恢复了没人知道 | S15.MBA、S15.iMac | 持锁的 sleep 结束以后起第 5 轮（真的 ssh / orca，加 `--dry-run`）：退出 1，没有 `already locked`，有第一个目标的「正常」，stdout 有一行「…锁拿到了，之前连续跳过 4 轮…」；假 curl 变成 2 次，第 2 次 `kind` `heartbeat_recovered`、`status` `recovered`；状态文件没了。第 6 轮：退出 1，假 curl 还是 2 次，stdout 没有 lock-held-alert 的行 |
| A43 | 跳过的每一轮都告警 | S15.MBA、S15.iMac | 第 4 轮还是跳过，假 curl 还是 1 次，stdout 那一行写「已报过」 |
| A44 | 偶尔一轮重叠（上一轮跑过 300 秒）就报 | S13、S15（第 1、2 轮） | 没到阈值不发；拿到锁的一轮把这一串清掉。S13：B 跳过一次，锁文件旁边的状态文件记 1 次、没有报过；C 拿到锁，stdout 有「之前连续跳过 1 轮」，C 之后状态文件没了；假 curl 0 次 |
| A45 | 默认阈值不是 45 分钟 | S15.MBA.45、S15.iMac.45 | 不设 `HB_LOCK_ALERT_MIN`，外部拿住锁。先把状态文件写成「第一次跳过在 44 分钟前、已跳过 9 轮」，跑一轮：退出 75，「已连续跳过 10 轮」，假 curl 0 次；再写成「46 分钟前」，跑一轮：退出 75，假 curl 1 次，`kind` `heartbeat_stale` |
| A46 | 加了这一层以后，正常的一轮变了（输出、退出码） | S2、S6b、S12、S13（A）、S15（第 6 轮） | 锁空着、旁边没有状态文件时，lock-held-alert 什么都不打，退出码就是 lockf 的。S2、S6b、S12 和 S13 的 A 期望不变 |
| A47 | 退出码被改了：非 0 变成 0（Orca 会起模型），或者 75 变成别的 | S13、S14、S15、S15.MBA.bad、S15.iMac.bad | 退出码一律照 lockf 的：75、73、1 原样交出去；lockf 被信号杀掉时是 128 + 信号；lock-held-alert 自己出错（状态文件读写失败、发告警出错）时在 stderr 写一行，退出码还是 lockf 的；起不了 lockf 时退出 71。S15.*.bad：状态文件内容是乱码时当成没有状态，这一轮算第 1 次跳过，退出 75；状态文件的路径是个目录、写不进去时，退出还是 75，stderr 有 lock-held-alert 的报错，假 curl 0 次 |
| A48 | lock-held-alert 没装或者路径写错：每轮退出 127（sh 找不到命令），并行版两个目标都没人查，也没人报 | S8；上线核对 | defs 里两个 precheck 都用 `$HOME/.orca-state/bin/lock-held-alert`（S8 核对）。README 卡 ② 第 1 步在 MBA 装它；卡 ③ 第 4 步先在 iMac 装它、比 sha256、照 precheck 原文经它跑一次 `--dry-run`，再 `register.sh --apply`；改完看下一次运行退出 1、两个目标都有结论行。演练不了，靠上线时核对 |
| A49 | 演练在真目录里留下状态文件，或者把 lock-held-alert 装进了 `~/.orca-state/bin/` | S10 | 两台都多查三个真路径：`~/.orca-state/bin/lock-held-alert`、`~/.orca-state/heartbeat-watch/mba-hb-watch.lock.skips.json`、`~/.orca-state/heartbeat-watch/5c2d0575.lock.skips.json`，演练前后都没有 |
| A50 | 两个 lock-held-alert 同时写状态文件：拿着锁的那一轮结束时清掉，同时有一轮跳过、记一次 | 不演练 | 临时文件按进程取名，再用 `os.replace` 换上去，文件不会写坏；谁后写算谁的。清掉的被盖回成「跳过 1 次」：下一轮拿到锁就清掉；跳过的一次被清掉：告警晚一轮。写进已知限制 |
| A51 | 告警发不出去（没有 webhook 配置、POST 失败） | 不演练 | 和 heartbeat-watch 一样：stdout 写「没发」，不记报过，下一轮跳过时再发；「已恢复」发不出去时留着报过的记录，下一次拿到锁再发。演练只走了发成功的路（假 curl 回 200）。写进已知限制 |
| A52 | (b) 持锁的进程崩溃或被杀以后，锁还在 | S14.MBA.kill、S14.MBA.term、S14.MBA.crash、S14.iMac.kill、S14.iMac.term、S14.iMac.crash | 做法同 A33，只用 lockf：`lockf -k -t 0 <锁> sleep 8` 拿住锁，探一次，退出 75；核对 pid、ppid、命令名以后，只给这个 lockf 发信号：kill 发 SIGKILL（退出 137），term 发 SIGTERM（退出 143），crash 发 SIGSEGV 模拟崩溃（退出 139）；马上再探，退出 0；锁文件还在（`-k`）；它起的 sleep ppid 1，自己结束。crash 前后各数一次 `~/Library/Logs/DiagnosticReports/` 里 lockf 开头的文件，记下来 |
| A53 | 从卡 ③ 起，MBA 的锁一直被占着时报两次 | 不演练 | iMac `5c2d0575` 20 分钟时报「MBA ops · 29 心跳互查」中断（没有 `@@HB`），MBA 上 lock-held-alert 45 分钟时再报一次锁被占着；恢复时也是两条。两条说的不是一回事（对面看到的现象、这边的原因），不合并。写进已知限制 |
| A54 | 每轮退出 73（锁文件的目录没了）不算跳过 | S14.MBA.nodir、S14.iMac.nodir | 73 时目录不在，状态文件也写不了：lock-held-alert 不计数、不告警、不打字，stdout 空（A35 不变）。MBA 上从卡 ③ 起 iMac 会报（F24）；iMac 上这个目录一直有。写进已知限制 |

另外，A30、A31 跟着改：S13 的 B 和 S14 的 held，stdout 不再是空的，只有 lock-held-alert 的一行「…已连续跳过 1 轮…」，没有 `@@HB`；
锁文件旁边多一个状态文件，记 1 次、没有报过。A38（S8）里 MBA 新任务和并行版的 precheck 前面多 `$HOME/.orca-state/bin/lock-held-alert `。其他不变。

### 演练本身可能骗人的地方

| # | 风险 | 处理 |
|---|---|---|
| C17 | S15 的阈值用环境变量 `HB_LOCK_ALERT_MIN` 改成 0.25 分钟；precheck 原文不设它，默认 45 | 默认值由 S15.*.45 看：状态文件是演练写的，假装第一次跳过在 44、46 分钟前，不是真等 45 分钟。用了伪造的状态，不叫 E2E |
| C18 | S15 的告警发给假 webhook 配置（`127.0.0.1:9`）和 PATH 里的假 curl：假 curl 记下请求体、回 200 | 真的 webhook 和收消息的 Coding助手 都没碰；收件方怎么处理 `source` 是 `lock-held-alert` 的 `heartbeat_stale`，没验证。用了替身，不叫 E2E |
| C19 | S15 外部持锁用的是 `lockf … sleep 32`，不是一轮卡住的 heartbeat-watch | 要看的是「锁一直被占着」本身，谁拿着都一样（F32） |
| C20 | S14.crash 用 `kill -SEGV` 从外面发信号模拟崩溃，不是 lockf 自己出错 | 真的段错误也是进程收到 SIGSEGV 后终止；演练只能从外面发这个信号。照实写成模拟 |

### 回退测试的期望（第五轮补充）

base 还是 `f828d452`，回退的做法不变。base 的 precheck 没有 lockf，也没有 lock-held-alert。新加 10 项：

- 该挂的 6 项（该挂的从 27 项变成 33 项）：
  - S15.MBA、S15.iMac：外部拿着的锁没人用，第 1 轮照常起 heartbeat-watch，退出不是 75，状态目录被建出来；4 轮都没跳过，假 curl 0 次（没有告警，也没有恢复）。
  - S15.MBA.45、S15.iMac.45：两轮都照常跑，退出不是 75，假 curl 0 次。
  - S15.MBA.bad、S15.iMac.bad：照常跑，退出不是 75。
- 照样过的 4 项（该过的从 29 项变成 33 项）：S14.MBA.term、S14.MBA.crash、S14.iMac.term、S14.iMac.crash，只用 lockf 本身。
- 已有的 56 项期望不变。S13 B 的 stdout 现在有 lock-held-alert 的一行，base 上没有这一层，S13 照样按「回退测试的期望（第五轮补）」挂。

共 66 项，新代码上 66 项都该过。新加的 6 项该挂的，演练「实际」一栏要对得上上面的原因，对不上算不一致。
