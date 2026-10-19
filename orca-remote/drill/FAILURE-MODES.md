# watchdog.sh 演练：失败方式清单（先写清单，再写代码）

写于 2026-10-19，改 watchdog.sh 之前。依据：box 侧中期证据
`/workspace/ops/reports/orca-bot-tunnel-1019/interim.md` 和 box 上 10-19 的 watchdog.log。时间均为 SGT。

每一条都对应 `run-drill.sh` 里的一个场景（S1–S6b）。「修前」= base 上的 watchdog.sh（rev 2026-10-18），
「修后」= 本分支的 watchdog.sh。

## A. 已经在 10-19 线上发生过的（修前应复现，修后应通过）

| # | 失败方式 | 10-19 线上实例 | 场景 | 修后期望 |
|---|---|---|---|---|
| A1 | 卡顿前记的 strike 和卡顿后的 strike 拼成「连续 2 次」 | 13:02:09 strike 1，13:22:54 strike 2，中间卡了 20 分钟 | S1 | 跨卡顿不累计 |
| A2 | 杀掉刚自己重新注册的 cloudflared | 13:22:53 注册，13:22:54 被杀 | S1、S6 | tunnel.log 60 秒内有 `Registered tunnel connection` 就不杀 |
| A3 | 卡在 `curl-local` 里的卡顿只记一条 slow step，不开宽限期，卡顿期间拿到的探测结果照常计 strike | 13:22:53 slow step 1142s | S1 | 探测阶段超过 curl 超时 + 余量 = 卡顿，丢弃这一轮结果，开宽限期 |
| A4 | guest 内卡顿（guest 时钟照走）被当成 VM 恢复，走快速路径立刻杀 cloudflared | 13:49:26 「guest clock ran」仍杀 | S2 | guest 时钟照走 = 卡顿：不走快速路径，宽限期内不杀 |
| A5 | 卡顿刚结束、Orca 还在恢复（local 000），2 次 strike 就整套重启 Orca | 11:55:59 restart unhealthy x2，11:56:45 Orca 自己好了 | S4 | 卡顿后宽限期 + 内存压力高（PSI full）时推迟整套重启 |
| A6 | 卡顿/恢复状态没有地方可读，叫醒方不知道 watchdog 正在处理 | 每次自愈的断线都叫醒值班 | S1、S3 | 写状态文件 `watchdog.state`（stalled / paused / ok …） |

## B. 修的时候可能弄坏的（修前修后都应通过 = 防回归）

| # | 失败方式 | 场景 | 期望 |
|---|---|---|---|
| B1 | 真的 VM 暂停（guest 时钟停）后 tunnel 卡在旧连接（CF 1033），快速路径不再立刻修 | S3 | 恢复后 15 秒内只重启 cloudflared，60 秒内公网 200，Orca 不重启 |
| B2 | Orca 真的挂了（本地 6768 不响应，curl 挂住），不再重启 | S5 | 每轮探测有硬超时；连续失败后整套重启 |
| B3 | Orca 真的挂了且内存压力一直高，推迟变成永远不重启 | S5b | 推迟最多 DEFER_MAX 秒，到点照样重启 |
| B4 | 一直重启不好时重启风暴 | S5 | 两次重启间隔逐次翻倍（MINGAP → MAXGAP） |
| B5 | cloudflared 真坏了（没卡顿、不自愈），stale tunnel 不再修 | S6b | 连续 2 次 stale strike 后只重启 cloudflared，Orca 不动 |
| B6 | 探测没有硬超时，watchdog 被一个挂住的 curl 卡死 | S5 | 本地挂住时每轮仍在 curl 超时内结束，strike 照常推进 |

## C. 演练本身可能骗人的地方

| # | 风险 | 处理 |
|---|---|---|
| C1 | 修前脚本没法在容器里跑（路径写死），为了跑它改了逻辑 | 只用 sed 把写死的路径、URL、间隔换成同名环境变量（`prefix-shim.sh`，逐条列出），逻辑一行不改；shim 后的文件和 base 的 diff 存进产物 |
| C2 | 「卡顿」不是真卡顿 | guest 内卡顿用 SIGSTOP 冻住 watchdog 进程（墙钟照走、uptime 照走，和线上一致）；VM 暂停用 SIGSTOP 加冻结 uptime 文件（容器里没法停 guest 时钟，这是替身，写明） |
| C3 | cloudflared、Orca、公网入口是替身 | 是。演练里的 cloudflared / orca-remote / 6768 / 公网都是本地替身进程，所以这份结果只能叫「scratch 演练（本地替身）」，不能叫线上 E2E。线上 E2E 要在 box 上替换 watchdog 之后跑，brief 不允许，没跑 |
| C4 | 只挑跑通的那次 | 修前、修后各跑一轮全量，原始日志全部保留，不重跑挑结果 |
| C5 | 时间常数缩小后行为变了 | 所有阈值由同一组环境变量给出，修前修后用同一组值；生产默认值写在脚本头 |

## D. 代码审查后补的（2026-10-19 15:30，修改在先，演练没有覆盖）

| # | 失败方式 | 修改 | 演练 |
|---|---|---|---|
| D1 | 生产间隔下（INT=45、STALL_SLACK=30）31–45 秒的 VM 暂停被判成 guest 内卡顿，不走 cloudflared 快速路径 | 按「guest 时钟少走的时间超过超时部分的一半」判暂停 | 没覆盖：演练间隔 INT=5 < STALL_SLACK=10，新旧判据结果相同 |
| D2 | VM 暂停后快速路径因 cloudflared 刚注册而放弃，之后不再重试 | 返回 2 时保留 resumed=1，宽限期内下一轮重试 | 没覆盖 |
| D3 | 两次重启相隔已超过 MAXGAP，间隔仍然翻倍 | 相隔 >= MAXGAP 时间隔回到 MINGAP | 没覆盖（S5 只覆盖翻倍） |
| D4 | 推迟期间发生卡顿，卡顿后沿用旧的 defer_since，立刻重启 | 卡顿时 defer_since 清零 | 没覆盖 |
| D5 | box-load-gate 读不到 PSI 时当成 0，放行 | 读不到 PSI 退出 2（按 DENY 处理） | 在 box 上手动跑过，见 PR |
