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
