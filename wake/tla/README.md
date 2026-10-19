# 叫醒系统 TLA+ 模型检查（PER-67）

用 TLC 把叫醒系统的几条承诺在小模型里**所有交错顺序**都查一遍：agent 做完或卡住会不会有人收到、发送失败会不会被记成成功、卡住检查自己停了会不会告警。模型来自代码（不是文档），每个动作上方注释写了 `文件:行号`。

下一个 agent 改相关代码时用项目内 skill：[`.claude/skills/wake-tla-verify/SKILL.md`](../../.claude/skills/wake-tla-verify/SKILL.md)。

## 复跑

```bash
wake/tla/check.sh            # 全部检查（数目见 check.sh 的表），约 10 分钟（不含等资源的时间）；退出码 0 = 和期望一致
wake/tla/check.sh w0 h0      # 只跑 P2、P3（一分钟内）
wake/tla/trace.py wake/tla/out/w13a_p1h_only_recheck.out   # 把反例翻成「第几步、哪个动作、对应代码、变了什么」
```

每次 TLC：`-workers 2`、`-Xmx1500m`、`timeout 1200`；开跑前可用内存 < 2G 或 load > 8 就等 5 分钟。原文在 `wake/tla/out/`（不进 git）。

## 安装（用户目录，不用 sudo，不装系统包）

| 东西 | 位置 | 来源 | sha256 |
|---|---|---|---|
| Temurin JRE 17.0.12+7 | `~/.local/opt/jdk-17.0.12+7-jre/` | https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12%2B7/OpenJDK17U-jre_x64_linux_hotspot_17.0.12_7.tar.gz | `0e8088d7a3a7496faba7ac8787db09dc0264c2bc6f568ea8024fd775a783e13c`（和官方 .sha256.txt 一致） |
| tla2tools.jar v1.7.4（TLC 2.19，2024-08-08） | `~/.local/opt/tla/tla2tools.jar` | https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar | `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88` |

```bash
mkdir -p ~/.local/opt/tla ~/.local/opt/dl && cd ~/.local/opt/dl
curl -sSfLO "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12%2B7/OpenJDK17U-jre_x64_linux_hotspot_17.0.12_7.tar.gz"
curl -sSfL -o ~/.local/opt/tla/tla2tools.jar https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
sha256sum OpenJDK17U-jre_*.tar.gz ~/.local/opt/tla/tla2tools.jar   # 对上表
tar -C ~/.local/opt -xzf OpenJDK17U-jre_x64_linux_hotspot_17.0.12_7.tar.gz
```

删除：`rm -rf ~/.local/opt/jdk-17.0.12+7-jre ~/.local/opt/tla ~/.local/opt/dl`（没改 PATH、没写别的文件）。macOS / arm 机器换对应的 Temurin 包，用 `TLA_JAVA=<java 路径>` 指给 check.sh。

## 为什么用 TLA+ / TLC

问题是「几个独立进程（notify-run、orca-wake 的 hook 和 detached 发送进程、每 15 分钟的卡住检查、每 5 分钟的心跳互查）按什么顺序发生、webhook 什么时候通不通，会不会有一种顺序让停下的 agent 永远没人收到」。这是交错顺序和活性的问题，测试只能碰到想到的那几种顺序；TLC 在给定界限里把所有顺序穷举，活性性质（「最终会……」）还能给出无限循环的反例。工具就一个 jar 加 JRE，装在用户目录。

## 模型对应的代码（建模时，已核对线上一致）

`SOURCES.sha256` 记着下面 8 个文件建模时的 sha256；check.sh 每次比对，变了就提示先对模型。

| 文件 | sha256（前 16 位） | box `~/.local/bin` | iMac | MBA |
|---|---|---|---|---|
| wake/bin/notify-run | cc7d25e99ed2d8ce（F2 加了 pane、agent 字段，第 6 组加了起没起来的检查；建模时 72e01f954dc624ee） | 一致 | 一致 | 一致 |
| wake/bin/orca-agent-launch | 20a441762a069921（第 6 组加了拒绝时叫醒；建模时 4355bc557b4876d0） | 一致 | 一致 | 一致 |
| wake/bin/orca-wake | ab75137c97142a40 | 一致 | 一致 | 一致 |
| wake/bin/orca-wake-hooks | 1a5e66d777618c76 | 一致 | 一致 | 一致 |
| wake/bin/agent-stop | 7cc0ebefd5b5c53a | 一致 | 一致 | 一致 |
| scripts/agent-probe | af95da54bf99000a（F2/F6 加了 wake；建模时 0fb882eb340a8004） | 一致 | 一致 | 一致 |
| scripts/stuck-check.sh | f7c44d4b864c3170（F7/F8、F3、F1、F5/F4、F2/F6 修过；建模时 c0bf9c6dad8c4a09） | — | `~/orca/workspaces/ops/scripts/`（ops · 01/02 跑的）一致 | **不一致**（d743f664…，MBA 上没有自动任务跑它） |
| scripts/heartbeat-watch.sh | a36d3dc8a88702a8（F8 同类修过；建模时 682dfa079840cf2e） | `~/.orca-state/bin/`（box ops · 29 跑的）一致 | `~/.orca-state/bin/`（iMac ops · 29 跑的）一致 | — |
| wake/pi/dispatch-wake.ts | 350c898595552ed6 | 没核对（Pi 扩展装在各 agent 的扩展目录） | | |

自动任务（`orca automations show`，只读）：iMac ops · 01 `439cd438` precheck `stuck-check.sh --scan`、rrule 每分钟、**precheck timeoutSeconds 300**；iMac ops · 02 `c7692ae9` codex 备用（`orca-fallback.sh stuck-check 25 60`，8–23 点每小时 53 分）；box ops · 29 `94e4b0bc` `heartbeat-watch.sh --precheck --target "iMac ops · 01 …|iMac|439cd438…|20"` 每 5 分钟；iMac ops · 29 `5c2d0575` 盯 box ops · 29。enabled-bots 三台都含全部真实 bot（coding-assistant、deepvision-ops、vllm-omni、xinyue、deepvision-ads、deepvision-marketing），所以模型里不建影子模式。

## 动作 ↔ 代码

| 模型动作 | 代码 | 一步不可分的理由 |
|---|---|---|
| `AgentPause` | orca-wake `cmd_claude_hook` Stop 分支 724-739 → `dispatch_send` 370-423（`hookFired=FALSE` = 731-736 的 background_work / queued_followup，或 hook 没跑） | Session 文件锁内完成；发送交给 detached 进程 |
| `IdlePrompt` | orca-wake 764-779 → `dispatch_send` 378-397 去重 | 同上 |
| `OwAttempt` | orca-wake `_send_now` 一次 urlopen 501-554；ok 判断 518；`_mark_sent` 450-453 写 sent/ 和 woken | 一次 HTTP 请求的结果 |
| `AgentExit` | notify-run wait 循环 196-205 → `finish` 144-158 | |
| `NrAttempt` | notify-run 122-130（一次 curl），成功判断 127，日志 126 | 一次 curl |
| `MarkCompleted` | agent 把 Orca 工作区标 completed | |
| `Scan` | stuck-check `main()` 一次扫描：`check_agents` 844-1179（agent_gone 1057-1071、主目录退出 959-987、idle → `wake_recheck` 1073-1097/553-609、结果处理 1124-1177）、第二类 1739-1757 / `check_reported` 1374-1468、`send_all` 1544-1627 | 一次扫描是一个进程顺序执行（run.lock 保证同时只有一个），别的进程在扫描中途的交错对这些性质没有影响（见「假设」） |
| `Tick` | 15 分钟（`INTERVAL_MIN` 138，闸门 1694） | |
| `WebhookUp/Down` | 环境：bot 的 webhook 服务通不通 | |
| Heartbeat `Step` | 每分钟一次 precheck（stuck-check 1908-1948：闸门关 1911-1915 打 `@@HB`，闸门开先写 gate.last 1930 再 `main()` 1935，异常 1936-1944，跑完才写 gate.done 1945-1946；@@HB 的 last_scan = done 1885）+ 每 5 分钟 heartbeat-watch `main()` 188-257 | |
| Heartbeat `Fail` | 卡住检查出故障并一直坏：dead（自动任务不跑 / Orca 挂了）、crash（`main()` 每次抛异常）、hang（每次超过 300 秒被杀） | |

## 性质

| 名字 | 一句话 | 坏了的后果 | 公平性 / 前提 |
|---|---|---|---|
| P1 | 每个停下（退出或停在输入框）的任务，最终有一个 bot 收到（2xx），或者升级到 Coding助手 | agent 做完或卡住没人知道，任务一直挂着 | 扫描和时间一直往前走、在途的发送进程会跑完（WF）；前提：Coding助手 的 webhook 最终一直可用；派活 bot 可以一直坏 |
| P1h | 同上，前提弱化成所有 bot 的 webhook 最终都一直可用（中断有限长） | 同上 | 同上 |
| P2 | webhook 发送失败（非 2xx、超时、连不上）绝不被记成成功：notify-run 的 exit 0 / 日志（P2_NR）、orca-wake 的 sent/ 和 woken（P2_OW）、stuck-check 自己 POST 后的 agents.json notified（P2_SC_POST）、stuck-check 交给 orca-wake 后的 notified（P2_SC_RECHECK） | 以为叫醒了其实没有，之后也不会补 | 安全性，无前提 |
| P3 | 卡住检查自己停了（自动任务不跑 / Orca 挂了 / 每次超时 / 每次出错），最终一定告警 Coding助手；P3_BOUND：最后一次跑完的扫描后 75 分钟内 | 兜底没了，没人知道 | Step 的 WF；假设 box 上的 heartbeat-watch 自己在跑、Coding助手 webhook 可用 |
| P4 | 没有任务停下超过 1 小时、没有任何 bot 收到、也没叫醒 Coding助手 | 同 P1，且时间有上限 | 安全性；前提 Coding助手 webhook 一直可用（`CA_ALWAYS_UP`） |
| P5（代码里找到的） | 一个 bot 的 webhook 坏了，不挡派给 Coding助手 的任务被收到 | 一个坏掉的 bot 让所有卡住告警（含给 Coding助手 的）都发不出去 | 前提 Coding助手 webhook 最终一直可用 |
| P6（第 6 组） | agent 没起来（orca-agent-launch 拒绝，或 notify-run 起了 claude 却一直没有第 1 个回合），最终有 bot 收到「没起来」（或者它后来起来了）；P6_BOUND：一直没起来的 START+1 分钟内 | 派活 bot 以为 agent 在干活，其实一个都没起（10-19 07:24 iMac term_b8179e9b） | `Launch.tla`；前提 Coding助手 webhook 一直可用 |

## 界限和简化

- 时间：Wake 一步 15 分钟（一次扫描）；停下后的计数封顶 5（≥ 60 分钟），P4 的「超过 1 小时」= 第 5 个 Tick 起（60～75 分钟）。Heartbeat 一步 1 分钟，计数封顶 76。
- 任务数：P1/P1h/P2/P4 用 **1 个任务**，派活 bot ∈ {ops-bot, Coding助手}、task/main、有没有要验收的东西、第二类检查的相位都穷举；P5 用 **2 个任务**（任务 1 派给 ops-bot、只会退出；任务 2 派给 Coding助手、可以停顿 / 标完成 / 退出；两个都是任务工作区）。2 个任务、所有组合一起的状态空间在 20 分钟内跑不完（试过：20 分钟仍在增长），所以缩成这个场景，只查 P5 关心的「一个 bot 挡另一个」。
- bot 数：2（ops-bot 代表任意一个派活 bot，coding-assistant）。
- 重试：notify-run 3 次、orca-wake 3 次（真实值）；P5 的两个检查折成 1 次（brief 允许更小；一次 POST 的成败由那一刻 webhook 通不通决定，3 次重试都在约 65 秒内，折叠后能出现的结局一样）。stuck-check 的 `post` 4 次重试（约 65 秒）折叠成「这一刻 up 决定」。
- 失败码：P2 检查用 {0（curl 000/超时/连不上）, 500}；其余用 {500}（成败判断对两者一样）。
- 只建模 idle（停在输入框）和退出；needs_input（对话框）、blocked、error、限流 429 的长重试（60/300/900 秒）没建模。
- 每个任务只停一次（一次停顿 / 一次退出，停顿后可以再退出）；之后的新回合不建模。
- 主动停止标记（agent-stop）、mute 文件、影子模式、没经 notify-run 起的 agent、ws_broken、due 对账、box/MBA 连不上告警没建模。
- 卡住检查的人工复核（Claude 读屏幕后 `--dismiss`）按「不误排除」算。

## 假设（模型外的事实，错了结论就要重看）

1. 每个任务都经 `orca-agent-launch` → `notify-run --tty` 起，hook 已装（`orca-wake-hooks check` 全 ok）。
2. 「bot 收到」= webhook 返回 2xx；收到的 bot 一小时内会处理（review / 评论 / 归档），所以第二类不再报（模型里用 ghost 变量 `accepted` 代替「PR 有人看过」）。
3. 一次扫描内别的进程的交错不影响结论（扫描对 orca-wake 的影响只经 recheck 的 detached 发送，这个发送在模型里是独立动作）。
4. Orca 不会让同一个自动任务的 precheck 重叠运行（假设成重叠只会多出心跳，不改变 P3 的结论）。
5. P3 里 box 上的 heartbeat-watch 在跑（它自己由 iMac ops · 29 盯）。

## 结果（commit 和原文见产物目录 /workspace/ops/reports/wake-tla-20261019/）

| 检查 | 期望 | 说明 |
|---|---|---|
| w01 / w03 / w05 P2_NR / P2_OW / P2_SC_POST | pass（界限内成立） | 三处自己的成功判断都只认 2xx |
| w02 / w04 / w06 改坏变体 | violated | 证明这三条查得出：把判断改成「任何 http」后立刻违反 |
| w07 P2_SC_RECHECK | pass（F1 已修） | |
| w08 改坏：recheck 看到 send 就记 notified（F1 修之前的代码） | violated | |
| w09 / w09a P4 | pass（F6 已修：改报从停下算；completed 的没送达停下每次扫描都查） | |
| w09b 改坏：改报从第一次失败算、completed 不查（F6 修之前，第 4 组的代码） | violated | |
| w10 P4（以前的假设修法 ca_escalate 已在代码里，和 w09 同一份配置） | pass | |
| w11 P1 | pass（F2、F4 已修） | |
| w11a P1 + 假设修法 main_gone | pass（F4 已修：派活 bot 一直坏时 45 分钟改报 Coding助手） | |
| w11b 改坏：没有改报（F4 修之前的代码） | violated | |
| w12 P1（以前的假设修法都已在代码里，和 w11 同一份配置） | pass | |
| w13 / w13b P1h | pass（F2 已修：主目录 agent 退出、notify-run 发送明确失败的照报） | |
| w13f 改坏：主目录里包了 notify-run 的退出一律不报（F2 修之前的代码） | violated | |
| w13a P1h 只剩 F1 | pass（F1 已修） | |
| w13e 改坏：recheck 发送失败后不再补（F1 修之前的代码） | violated | |
| w13c P1h 只剩 F3 | pass（F3 已修） | |
| w13d 改坏：干净工作区一律放行（F3 修之前的代码），同时去掉 F6 的 completed 没送达检查（两层都兜这个场景） | violated | |
| w14 P1h（以前的假设修法都已在代码里，和 w13 同一份配置） | pass | |
| w15 P5 | pass（F5 已修：send_all 只挡发给同一个目标的） | |
| w15b 改坏：一条失败其余全停、没有改报（F5、F4 修之前的 send_all） | violated | |
| w16 P5 + 修法 no_hol | pass | |
| h01 P3（dead）+ P3_BOUND + NoFalseAlarm | pass | 自动任务停 / Orca 挂了会告警，75 分钟内 |
| h02 改坏：查不到运行记录不报 | violated | |
| h03 P3（hang） / h04 P3（crash） | pass（F7、F8 已修） | 加了 P3_BOUND：75 分钟内告警 |
| l01 P6 + P6_BOUND | pass | 第 6 组：orca-agent-launch 拒绝时、notify-run 起的 claude 5 分钟没有第 1 个回合时叫醒派活 bot，发不出去改发 Coding助手 |
| l02 改坏：两处都不叫醒（修之前的代码） / l03 改坏：不改发 Coding助手 | violated | |
| h05 / h06 改坏：last_scan 取扫描开始时间（修之前的代码） | violated | |

「修法」只在模型里（`Fixes` 常量），用来证明性质不是空的、模型不是怎么都失败；没有改任何产品代码。

## 发现

见产物目录 `findings.md`（问题、触发步骤、影响、代码行、建议修法）。一句话版：

- **F1**（已修，PER-67 F1 PR：交给 orca-wake 只记已交出，下次再 recheck，already_woken 才算送达）卡住检查把 orca-wake 补叫醒记成「已通知」时还没发出去；发送失败后这次停顿永远不再补（stuck-check.sh:1045-1052）。
- **F2**（已修，PER-67 F2+F6 PR：notify-run.log 记 pane 和 agent 层，agent-probe 带回来，主目录 agent 退出时这次发送明确失败就报 agent_gone）ops 主目录里 agent 退出、notify-run 三次都发不出去（约 65 秒的中断）就没人知道：卡住检查对包了 notify-run 的退出一律不报（stuck-check.sh:889-894）。
- **F3**（已修，PER-67 F3 PR：放行前看最后一次停下有没有送达过叫醒，没有就照报）工作区标 completed、停顿时 hook 没发（有后台 shell 时按设计不发）、工作区干净没 PR → 第二类放行，永远没人知道（stuck-check.sh:1294-1300 + orca-wake:731-732,769-771）。
- **F4**（已修，PER-67 F5+F4 PR：stuck-check 发给派活 bot 的从第一次失败起 45 分钟改发 Coding助手；交给 orca-wake 的补叫醒交出 45 分钟还没送达就转报 Coding助手；`STUCK_ESCALATE_MIN`）派活 bot 的 webhook 一直坏时，没有任何路径升级到 Coding助手（`bot_cfg` 只在没有 env 文件时转，stuck-check.sh:1347-1354）。
- **F5**（已修，同上 PR：`broken` 改成按目标记，只挡发给同一个 bot 的）`send_all` 一条失败就停（`broken`，stuck-check.sh:1381-1382,1415-1416）：一个坏掉的 bot 每次扫描都排在前面，挡住给 Coding助手 的告警；挡路的还可能是 notify-run 已经送达过的重复 agent_gone。
- **F6**（已修，同上 PR：改报从停下算；completed / in-review 工作区最后一次停下没送达的，每次扫描都查，45 分钟直接报 Coding助手）第二类「报了没人验收」最早 1 小时、按约每小时一次查，completed 任务最坏接近 2 小时才到 Coding助手，P4 的 1 小时在设计上就达不到。
- **F7**（已修，PER-67 F7+F8 PR：`last_scan` 改成上次跑完的扫描 gate.done）扫描每次超过 300 秒被杀时心跳照样新鲜：`last_scan` 取的是扫描**开始**时写的 gate.last（stuck-check.sh:1720 在 1725 `main()` 之前），heartbeat-watch 不会报。iMac 日志 10-16～10-19 最长一次扫描 253 秒，10-16 03:03:55 有一次开始没结束。
- **F8**（已修，同上；heartbeat-watch 自己出错时 last_scan 也不再前进）扫描每次出错时（`main()` 抛异常）`--scan` 返回 0、照打新心跳，只会起一个 Claude 复核 agent（它的报告只进 Orca 运行记录），codex 备用失败后只写 `~/orca-alerts/stuck-check.flag`，没有任何 webhook 告警。

## 代码变了怎么办 / 结果变了怎么办

见 skill 的第 3、4 节。
