---
name: wake-tla-verify
description: 叫醒系统（notify-run、orca-wake、orca-agent-launch、stuck-check 卡住检查、heartbeat-watch 心跳互查）的 TLA+ 模型检查。改了 wake/bin/*、wake/pi/dispatch-wake.ts、scripts/stuck-check.sh、scripts/heartbeat-watch.sh 里和「发 webhook / 判断成功 / 重试 / 记已通知 / 补叫醒 / 心跳」有关的代码，或者改了这些自动任务的 precheck、超时、频率时用：跑一条命令，看改动有没有让「停下的 agent 一定有人收到」「发送失败不记成功」「卡住检查停了一定告警」这些性质变好或变坏。
---

# 叫醒系统 TLA+ 检查

模型在 `wake/tla/`：`Wake.tla`（叫醒链路，P1/P1h/P2/P4/P5）、`Heartbeat.tla`（卡住检查自告警，P3）、`Launch.tla`（agent 没起来，P6）、`MC.tla`（cfg 用的组合）、`cfg/*.cfg`（每个检查一份）、`check.sh`（全部跑并对照期望）、`SOURCES.sha256`（建模时代码的 sha256）。性质、界限、假设、每个动作对应的代码行见 `wake/tla/README.md`。

## 1. 这次改动要不要跑

跑，如果 diff 碰到下面任何一处（行号是建模时的，代码变了以 `SOURCES.sha256` 不一致为准）：

| 代码 | 模型里的位置 |
|---|---|
| `wake/bin/notify-run` 的 `send_webhook`（重试次数、`case "$http" in 2??)`、`log_send`） | `Wake.tla` `NrAttempt` |
| `wake/bin/orca-wake` 的 `dispatch_send`、`_send_now`（`ok = ...`、重试、`_mark_sent`、`mark_woken`）、`cmd_claude_hook` 的 Stop / idle_prompt、`cmd_recheck` / `candidate` / `_recheck_idle` | `AgentPause`、`OwAttempt`、`IdlePrompt`、`RecheckOW`/`RecheckKnown` |
| `wake/bin/wake-prefilter` 的规则 a（notify-run done ↔ orca-wake idle 互相覆盖）、e（完成后提醒）、`NEVER` 集合、`record` 账本；notify-run / orca-wake / stuck-check 里调它的地方（PER-88） | `AgentExit` 的 drop（`NrDropOK`）、`OwDrop`、`PfDropRem`、`Scan` 的 rep0/rep/escDrop；性质 P1pf / P1hpf / P2_OW（w17～w19） |
| `wake/pi/dispatch-wake.ts` 什么时候调 `orca-wake send` | `AgentPause`（同一条 idle 去重路径） |
| `wake/bin/orca-agent-launch` 是否还强制 `notify-run --tty` | 模型前提：每个任务都经 notify-run 起 |
| `wake/bin/orca-agent-launch` 的 `wake_reject`、`wake/bin/notify-run` 的 `start_watch` / `agent_started`（agent 没起来时叫醒） | `Launch.tla` 的 `RejectWake`、`WatchWake`（P6） |
| `scripts/stuck-check.sh`：`post`、`send_all`（`broken`）、`check_agents` 里 agent_gone / agent_idle / 主目录 `main_seen`、`wake_recheck` 结果处理（`known[key]`）、`check_reported`（1 小时、放行干净工作区）、`gate`、`heartbeat`、`take_lock`、`main()` 的异常处理 | `Gone`、`IdleCand`、`RepCand`、`Scan`；`Heartbeat.tla` 的 `GateOpen`/`PrintsHB`/`nScan` |
| `scripts/heartbeat-watch.sh` 的阈值和判断（`age > max`、`scan_age`、`UNREACH_MIN`、`alerted`） | `Heartbeat.tla` `Down`、`WatchNow` |
| 自动任务 ops · 01（439cd438）/ ops · 29（94e4b0bc、5c2d0575）的 precheck、`timeoutSeconds`、rrule | `Heartbeat.tla` 常量 `PRE_TIMEOUT`、`WATCH_EVERY`、`HB_MAX` |

只改日志文案、注释、`agent-stop`、`orca-wake-hooks`（只要 hook 列表没变）、payload 里不影响判断的字段，不用跑。

## 2. 跑

```bash
cd <仓库根>
wake/tla/check.sh                 # 全部（约 1～25 分钟，大头是 w15/w16 两个 2 任务的检查）
wake/tla/check.sh w0 h0           # 只跑名字以 w0、h0 开头的（P2、P3，一分钟内）
```

要先装好 Java 17 和 tla2tools.jar v1.7.4（README「安装」，装在 `~/.local/opt/`，不用 sudo）。脚本自己守资源：每次 `-workers 2 -Xmx1500m`、`timeout 1200`，可用内存 < 2G 或 load > 8 先等 5 分钟。TLC 原文在 `wake/tla/out/<名字>.out`，汇总 `wake/tla/out/summary.tsv`。

退出码 0 = 每个检查都和 `check.sh` 表里的「期望」一致。注意「期望 violated」有两种：`*_mutant` 是故意改坏的变体（证明这条性质查得出问题），其余是**现有代码的已知发现**（README「发现」）。所以 0 不等于「叫醒系统没问题」，只等于「和上次记录的一样」。

## 3. 结果变了怎么办

先看开头有没有「模型对应的代码和建模时不一样了」：有就先做第 4 步，否则结果没意义。

- **期望 pass、变成 violated**：TLC 输出里 `Error: Invariant ... is violated` 或 `Temporal properties were violated` 下面是反例，一串 `State n: <动作名 ...>`。逐步对着 README「动作 ↔ 代码」表翻成代码的话（哪个进程、哪一行、webhook 当时通不通）。
  - 每一步都能在改过的代码里真的发生 → 真 bug，报出来（反例按「1. agent 停下 2. hook 发三次都 500 ……」写），不要改模型让它通过。
  - 有一步代码里不可能发生（比如模型允许的顺序代码里有锁挡着）→ 是模型错，改模型并在 README 写清为什么。
- **期望 violated、变成 pass**：
  - `*_mutant` 变 pass：模型里那条判断被改没了，检查失去了查错能力——修模型。
  - 发现类（w07 w09 w11 w13 w15；h03 h04 已随 F7/F8、w13c 已随 F3、w07 w13a 已随 F1、w11a w15 已随 F4/F5、w09 w11 w13 已随 F2/F6 修好改成期望 pass）变 pass：可能是代码修好了。确认修法真的在代码里（不是只改了模型），然后把 `check.sh` 表里的期望改成 pass，README「发现」里标已修和 commit。
- `timeout` / `error`：看 `.out` 末尾。`error` 多半是 cfg 和模块常量对不上；`timeout` 是状态空间太大，先缩小界限，不要把 timeout 当 pass。

## 4. 代码改了，更新模型

1. `git diff` 看改动落在第 1 节表里哪个动作。
2. 改 `Wake.tla` / `Heartbeat.tla` 对应动作，动作上方注释里的 `文件:行号` 一起改对（用 `grep -n` 找新行号）。一个动作只能是代码里一步不可分的事；新加的重试、分支、状态文件要有对应变量。
3. 新的判断要能失败：给它加一个 `Mutant` 分支（模拟删掉这行检查），在 `cfg/` 加一份 `*_mutant.cfg`、在 `check.sh` 表里加一行「期望 violated」，跑一次看到它失败。
4. `sha256sum <9 个文件> > wake/tla/SOURCES.sha256`（文件列表就是现在那份的第二列），再跑 `wake/tla/check.sh` 到退出码 0。
5. 结果和 README「结果」表不同的，更新 README。

## 5. 预过滤的真进程演练（PER-88）

模型只管「被覆盖」的挡法（README「界限」）。改了 `wake/bin/wake-prefilter` 的任何规则，或改了三个调用点，除了跑 w17～w19，还要在 PR head 上跑真进程演练：

```bash
wake/tests/prefilter-drill.sh <产物目录>        # 当前分支；全部用临时 HOME、本机假接收端 wake/tests/mock_webhook.py、假 key
WAKE_DRILL_CODE=<main 的 git archive 导出> WAKE_DRILL_EXPECT=send WAKE_DRILL_PORT=18822 \
    wake/tests/prefilter-drill.sh <产物目录>   # 回退测试：同一套输入跑 main 的代码，该挡的都会发出
```

| 演练 | 期望（开关 on） |
|---|---|
| a1 a2 b1 b2 b3 c1 d1 d3 e1 e2 f1 | 挡掉：假接收端 0 条，prefilter.log 一行（规则字母对得上） |
| r1～r11 | 照发：假接收端条数和 main 一样，prefilter.log 没有这一条 |
| d2 | 照发（ops-system 的「[演练 叫醒通路]」内置放行），prefilter.log 一行「放行：」 |
| s1 off / s2 shadow | 全部照发；off 的 payload 和 main 逐字节相同；shadow 的 prefilter.log 记「shadow 会挡」 |

逐条输入和判定写在脚本里，说明在 `wake/docs/TESTS.md`「叫醒前预过滤演练」。只在两次线上卡住检查扫描之间跑，不发真叫醒、不读真 env。

## 6. 不要做

- 不要为了让检查通过去放宽性质、删 cfg、把期望改成实际结果却不解释。
- 不要在检查时发真实叫醒；这些模型不碰网络和线上状态。要在真环境演练叫醒，只发 test bot（`--bot test` / `STUCK_FORCE_BOT=test`）。
