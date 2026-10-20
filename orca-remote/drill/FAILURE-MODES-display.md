# serve 显示问题：失败方式清单（先写清单，再写代码）

写于 2026-10-20，改 watchdog.sh 和收 e2e 脚本之前。依据：box `/workspace/ops/reports/orca-serve-1020/` 的材料
（orca-remote.diff、e2e 产物）和 box 上 10-20 的 serve.log（只读）。时间均为 SGT。

背景：`orca-remote serve-loop` 把 DISPLAY 钉在 :4。:4 是宿主管的某个 Grok agent 桌面（pod-daemon → start-desktop.sh），
会被拆掉重建。10-20 每次 :4 被拆，serve 就以 `X connection error` 退出，之后每 6 秒以 `DISPLAY=:4 is not verifiably live`
崩一次，本地 6768 合计挂了约 5 小时；watchdog 21 次整套重启都没用，16:48:43 :4 重建后才恢复。

## E. orca-remote 启动 serve（`e2e-serve-display.sh`）

A = 假 orca-ide（记录收到的环境后退出 1），任何机器都能跑；B = 真 orca-ide 1.4.224 serve，只在 Linux 容器里跑。

| # | 失败方式 | 测试 | 修后期望 | 旧 orca-remote |
|---|---|---|---|---|
| E1 | serve 借用的桌面被拆，serve 崩溃循环直到桌面重建（10-20 的事故） | B0：真 serve + 死 DISPLAY；B-loop：`orca-remote serve-loop`，:4 上没有 X | B0 复现 exit 1 和 `not verifiably live`；B-loop 默认模式 120 秒内 `orca_server_ready` | B-loop 一直崩、不 ready（回退测试） |
| E2 | own 模式下 Orca 没有真的自起 Xvfb（没装 xvfb、`env -i` 的 PATH 里找不到 Xvfb） | B1、B-loop | 有 Xvfb :99 子进程，ready | — |
| E3 | serve 退出后自起的 Xvfb 留下来（:99 锁残留），下一次 serve 起不来或越积越多 | B1 停掉后查；B-loop 杀掉 serve，等 serve-loop 自己重启 | 停掉后 Xvfb 退出；重启后再次 ready，且只有 1 个 Xvfb | — |
| E4 | serve-loop 仍把调用方的 DISPLAY 传给 serve | A own（调用方 DISPLAY=:77） | 假 orca-ide 收不到 DISPLAY | 收到 :77 |
| E5 | 回滚开关失效：`ORCA_SERVE_DISPLAY=:4` 或 `$STATE/serve-display` 里的 `:4` 不再恢复旧行为 | A rollback、A rollback file | 传入 DISPLAY=:77 | — |
| E6 | 快崩时刷屏重启（旧版每 5 秒一次） | A own 退避 | 40 秒内 ≤ 5 次启动，间隔涨过 5 秒 | 约 7 次 |
| E7 | `ORCA_SERVE_RUNTIME=electron` 没传，或私有 XDG_RUNTIME_DIR 没给 | A own | 都有 | — |
| E8 | 回滚开关只在手动那一次有效：watchdog 用自己的环境 `orca-remote restart`/`start`，`ORCA_SERVE_DISPLAY=:4` 丢失，serve 悄悄回到 own（代码审查发现） | B-start：真 `orca-remote start`/`restart`（tmux），开关写在 `$STATE/serve-display` 或环境变量里 | 文件 `:77` → `display=:77`；环境变量优先于文件；两者都没有 → `display=own`；stop 后不留 Xvfb | 没有 `display=`（FAIL） |

已知取舍（不是失败，写明）：own 模式下 serve 不再连 :4 桌面的 D-Bus，Orca 的 Computer Use 看到的是自起的空白 Xvfb :99，
不再是 :4 桌面。要 Computer Use 用那个桌面时设 `ORCA_SERVE_DISPLAY=:4`，代价是回到 10-20 的风险。

box 上的只读前提检查（2026-10-20 17:10）：`/usr/bin/Xvfb` 存在；`/tmp/.X11-unix` 里没有 X99，`/tmp/.X99-lock` 不存在。

## W. watchdog 对「显示类失败」的判据（`run-drill.sh`，场景 X1–X5）

显示类失败 = serve.log 里出现 `not verifiably live` 或 `X connection error`。判据只看最近的日志段，不看整个文件：

- own 模式：上一次 `orca_server_ready` 之后出现过显示错误（serve-loop 正在自愈，新的一次 serve 还在起）。
- 非 own 模式：最后一次 `starting orca-ide serve` 之后出现过显示错误（这一次 serve 就是死在显示上）。
- 模式取最后一行 `starting orca-ide serve ... display=<mode>`；没有 `display=` 的旧格式行按非 own（旧版钉 :4）处理。
- serve.log 超过 WATCHDOG_SLOG_STALE 秒（默认 180）没写入，说明 serve-loop 不在了，不算显示类失败。
- 离开 display_dead 后的第 1 轮不健康不计 strike（显示回来后 serve 还在起）。

| # | 失败方式 | 场景 | 修前（origin/main 的 watchdog）预期 | 修后预期 |
|---|---|---|---|---|
| W1 | own 模式显示失败后 serve-loop 正在自愈，watchdog 2 次 strike 就整套重启，打断正在起的 serve | X1：写入 X connection error → 重启 → starting（display=own），本地 000；watchdog 记到第 2 条不健康后 serve ready | 第 2 条就是 strike 2，整套重启：FAIL | 第 1 轮不计 strike，第 2 轮才是 strike 1；serve 好了，不重启 |
| W2 | own 模式多给的一轮变成永远不重启（显示失败自愈不了，比如 Xvfb 起不来） | X2：同 X1，但一直不 ready | 照常重启 | 多给一轮后照常 strike，60 秒内整套重启 |
| W3 | 非 own 模式显示已死，watchdog 反复整套重启（10-20 的 21 次） | X3：display=:4，每次 serve 都 `not verifiably live`，持续 60 秒 | 重启（FAIL） | 不整套重启，state=display_dead，日志写明 |
| W4 | 显示恢复后状态卡在 display_dead | X3 后半：显示回来，serve ready，本地 200 | — | state 回到 ok |
| W5 | 旧版 orca-remote 的 serve.log 行没有 `display=`，被当成 own 模式多给一轮或照常重启 | X3b：同 X3，starting 行是旧格式 | 重启（FAIL） | 按非 own：不重启，display_dead |
| W6 | 判据看得太宽：serve.log 里以前的显示错误，让现在跟显示无关的故障（Orca 挂住）不再重启 | X4（own）：显示错误之后已经 ready 过，现在 Orca 挂住；X5（非 own）：较早一次 serve 死于显示，最后一次 serve 没有显示错误但挂住 | 照常重启 | 照常重启（2 次 strike） |
| W7 | serve.log 不存在或读不到时判据出错，影响原有场景 | S1–S6b 不设 serve.log | 原样通过 | 原样通过 |
| W8 | 非 own 模式显示恢复后，serve-loop 新起的 serve 要 60–75 秒才 ready；离开 display_dead 后马上照常计 strike，2 轮就整套重启，打断正在起的 serve（代码审查发现） | X6：display_dead 之后显示回来，写入新的 starting 行，serve 再过 2 轮才 ready | 显示死的时候就重启（FAIL） | 离开 display_dead 的第 1 轮不计 strike；serve ready，不重启 |
| W9 | serve.log 停止更新（serve-loop 窗口没了，但 tmux 会话还在），最后一段永远是显示错误，watchdog 永远停在 display_dead 不重启（代码审查发现） | X7：显示错误之后 serve.log 不再写入 | 照常重启 | serve.log 超过 WATCHDOG_SLOG_STALE（默认 180 秒，演练 20 秒）没更新就不算显示类失败，照常 strike、重启 |
| W2b | own 模式多给的不是一轮而是多轮 | X2 加查：第一次整套重启前只有 1 条「display failure in own mode」 | — | 恰好 1 条 |

演练本身的限制（沿用 FAILURE-MODES.md 的 C 节）：X 场景里的 serve.log、6768、orca-remote 都是本地替身，serve.log 的
行由场景脚本按 box 上真实日志的格式写入，所以这部分只能叫「scratch 演练（本地替身）」。真实 serve 的行为由
`e2e-serve-display.sh` 的 B 部分在容器里用真 orca-ide 1.4.224 覆盖。watchdog 在 box 上的线上表现要等上线后才能看，
本次不碰 box 线上文件和进程，没跑。

修前对照用 origin/main 的 watchdog.sh（`PRE_REF=origin/main`），不是 run-drill.sh 默认的 10b4975：显示判据要和最近的
watchdog 比。origin/main 的 watchdog 已经带演练用的环境变量，不需要 prefix-shim。
