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

## D. 代码审查后补的（2026-10-19 15:30 改的，演练 2026-10-19 晚补上）

修改见 ff5a147。下面先写失败方式和预期，再写场景（D1、D1b、D2、D3、D4）。三个被测版本：

- 修前 = 10b4975（box 线上版本，经 prefix-shim），brief 指定的对照。它没有卡顿判据、cf_fresh、推迟、翻倍，所以 D 项上的失败原因和 D 修改无关。
- 审查修正前 = 791c033（ff5a147 的上一个 commit，有 rev 2026-10-19 的全部逻辑，只差 D1–D4 的修正）。这是 D1–D4 真正的「修前」，作为补充对照单独跑一轮（见 RERUN.md），不改 run-drill.sh 的 pre/post 定义。
- 修后 = origin/main（ff5a147 合并后）。

| # | 失败方式 | 场景 | 修前 10b4975 预期 | 审查修正前 791c033 预期 | 修后预期 |
|---|---|---|---|---|---|
| D1 | 生产间隔下（INT=45、STALL_SLACK=30）一次 31–45 秒的 VM 暂停被判成 guest 内卡顿，不走 cloudflared 快速路径，公网多断约 90 秒 | D1：生产 INT/STALL_SLACK，45 秒 sleep 走到第 43.5 秒时暂停 37 秒（uptime 冻结），tunnel 卡在旧连接 | 墙钟间隔约 80 秒 < GAP=135，不认暂停；靠 2 次 strike 才重启 cloudflared（约 +45 秒），没有状态文件。FAIL | 旧判据「guest 时钟走了不到一半」：43 < 80/2 不成立，判成卡顿，不走快速路径。FAIL | 判成暂停，15 秒内只重启 cloudflared，状态 paused |
| D1b | 新判据放得太宽：同样长度的 guest 内卡顿（guest 时钟照走）被判成 VM 暂停，走快速路径杀掉会自愈的 cloudflared（A4 回归） | D1b：同 D1 的时机，冻结 37 秒但 uptime 照走；cloudflared 解冻后 3 秒自己重新注册，6 秒后公网恢复 | 不认暂停，不杀 cloudflared；没有状态文件。状态检查 FAIL | 判成卡顿。PASS | 判成卡顿（stalled），不杀 cloudflared |
| D2 | VM 暂停后快速路径因 cloudflared 刚注册而放弃（返回 2），之后不再重试；tunnel 其实没好，要等宽限期结束再攒 2 次 strike | D2：VM 暂停 40 秒，恢复前 1 秒 cloudflared 写了一条注册，但 tunnel 仍然 530、不自愈。这一项 GRACE=30、CF_FRESH=15（和生产 120/60 同比例） | 没有 cf_fresh，恢复后立刻杀掉刚注册的 cloudflared（约 +1 秒）。「注册未满 CF_FRESH 不杀」FAIL；「宽限期内修好」PASS | 第一次放弃时已把 resumed 清零，之后等宽限期结束（+30 秒）再 2 次 strike，约 +35 秒才杀。「宽限期内修好」FAIL | 注册未满 15 秒不杀；之后每轮重试，约 +16 秒杀掉并修好，在 30 秒宽限期内 |
| D3 | 两次重启相隔已超过 MAXGAP，间隔仍然翻倍，下一次真故障要多等 | D3：这一项 MAXGAP=120（其他沿用演练值，MINGAP=40）。重启 #1 修好 Orca，健康 125 秒后 Orca 再挂且重启修不好，看 #2→#3、#3→#4（最多等 240 秒，#4 必须出现） | 没有翻倍，间隔一直约 40 秒：「#2→#3 回到 MINGAP」PASS（本来就没有翻倍）；「回落后 #3→#4 重新翻倍到 ≥ 2×MINGAP」FAIL。修前和修后在第一条断言上相同，靠第二条区分 | #2 时照样翻倍到 80：「#2→#3 < 1.5×MINGAP」FAIL；#3→#4 约 120 秒（翻到 160 封顶 120），第三条 PASS | #2→#3 约 40 秒，#3→#4 ≥ 80 秒且 #4 确实发生 |
| D4 | 内存压力高、整套重启正在推迟时发生卡顿；卡顿后沿用旧的 defer_since，宽限期一过立刻整套重启，推迟形同虚设 | D4：Orca 挂、PSI full 70% 一直不降，推迟开始约 12 秒后冻结 40 秒（guest 时钟照走） | 没有推迟逻辑：冻结前就已重启，之后按 MINGAP 一直重启。「冻结后 STALL_GRACE+DEFER_MAX 内不整套重启」FAIL；「推迟进行中被冻结」前提不成立，FAIL | 恢复后约 +35 秒（宽限期 30 + 2 次 strike）就重启：FAIL | 卡顿后重新推迟 30 秒，约 +65 秒才重启；之后照样会重启（不变成永不重启） |
| D5 | box-load-gate 读不到 PSI 时当成 0，放行 | — | — | — | 在 box 上手动跑过，见 PR #40；本轮不演练 |

D 项新增的演练风险：

| # | 风险 | 处理 |
|---|---|---|
| C6 | 容器里 SIGSTOP 不会让 sleep 变长（sleep 的截止时间按单调时钟，暂停期间照走），所以「45 秒 sleep 里暂停 37 秒」不能在 sleep 一开始就暂停，否则墙钟间隔只有约 37 秒、guest 时钟只走 0 秒，和生产不像 | D1、D1b 从 /proc/<sleep pid>/stat 读出 sleep 的起始时刻，在第 INT−1.5 秒才暂停：墙钟间隔约 80 秒、guest 时钟走约 43 秒，和生产里「sleep 45 秒 + 暂停 37 秒」一致。实际的 wd/ud 记在 watchdog.log，summary 里列出 |
| C7 | 场景单独调参（D1 用生产 INT/STALL_SLACK，D2 用 GRACE=30，D3 用 MAXGAP=120），修前修后用的不是同一组值 | 每个场景的参数对修前、审查修正前、修后三个版本相同；参数在 in-container.sh 的场景函数里写明，跑完由 teardown 恢复演练默认值，不影响其他场景 |
| C8 | 断言为了让修后通过而放宽 | 断言和界值先写在本表（上表「修后预期」一列），代码照抄；跑出来不符就记 FAIL 并保留，不改界值重跑 |
| C9 | 断言太松，坏的 watchdog 也能过 | 代码审查（Codex 对抗审查）发现 D3 第三条原来在只有 3 次重启时按「已过 80 秒」也算过，#3 之后不再重启的 watchdog 会被放过。已改严：#4 必须出现。改动在第一轮全套跑完之前，第一轮（旧断言）结果照样保留 |
