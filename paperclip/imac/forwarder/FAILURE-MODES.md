# S12 ② 触发转发程序：失败方式清单（先写清单，再写代码）

写于 2026-10-25 03:14 +08，在写 `forwarder.js` 和脚本之前。依据：派活 `BRIEF-s12-fwd-1.md`；Zack 选的 D；
Paperclip v2026.1012.0 源码（路径相对 Paperclip 仓库根目录，和 iMac 上 `git show v2026.1012.0:` 的 sha256 逐个核对过）；
发送方 `wake/bin/notify-run`、`wake/bin/orca-wake`；iMac 上的只读检查。

转发程序（下称「程序」）只做一件事：在 iMac tailnet IPv4 的 8110 端口收 `POST /api/routine-triggers/public/<publicId>/fire`，
转给 `http://127.0.0.1:3110`。其余一律 404。
**第 2 轮改动（2026-10-25 06:00 +08，派活 `BRIEF-s12-fwd-2.md`）**：不设 `PAPERCLIP_PUBLIC_URL`，不为此重启 Paperclip，
只把两个 `.url` 文件里的 origin 换成转发地址（Zack 第 76 条，主会话按第 1 轮验收第 11 项收窄）。G6、G7、F4、F21、F22、F32、B4 跟着改了，
新增 F34–F40；第 1 轮验收提的小问题在 D 节。

读回脚本（`readback-from-mba.sh`）和本地自查（`selfcheck-mba.sh`）的每一项对应下表的一条或几条。结果不符就记 FAIL，
不放宽判断、不挑着重跑。

## 动手前查到的、会影响设计的事实

| # | 事实 | 依据 | 影响 |
|---|---|---|---|
| G1 | publicId 由 `crypto.randomBytes(12).toString("hex")` 生成：24 位、小写十六进制 | `server/src/services/routines.ts:2480`、`:2744` | 程序的路径规则写成 `[0-9a-f]{24}`，只认小写。派活给的格式和源码一致，不用改 |
| G2 | Paperclip 鉴权中间件的免身份规则是 `/^\/api\/routine-triggers\/public\/[a-f0-9]{24}\/fire\/?$/i`：不分大小写，允许结尾斜杠 | `server/src/middleware/auth.ts:223`、`:243-247` | 程序比它更窄：只认小写，不许结尾斜杠，不许查询串。发送方用的地址来自 `routineWebhookUrl`，本来就是小写、没有结尾斜杠 |
| G3 | 触发路由要求 `Content-Type: application/json`，正文必须是 JSON 对象；读的头有 authorization、x-paperclip-signature、x-hub-signature-256、x-hub-signature、x-paperclip-timestamp、idempotency-key、x-github-delivery | `server/src/routes/routines.ts:656-673` | 我们的触发器是 bearer 模式，只用得到 Authorization；另外按派活放 Content-Type 和 Idempotency-Key。签名类的头不转 |
| G4 | bearer 检查：`Bearer <密钥>` 用 timingSafeEqual 比，长度不同直接失败；setupPending 时验过也只记测试回执 | `server/src/services/routines.ts:2985-2999` | Authorization 原样转，不改大小写、不去空格 |
| G5 | private 模式的 Host 检查先读 `X-Forwarded-Host`，没有才读 `Host`；只认 allowedHostnames、绑定地址、localhost 和回环地址 | `server/src/middleware/private-hostname-guard.ts:8-12`；`server/src/app.ts:274-282` | 程序把 Host 改成 `127.0.0.1:3110`，不转 X-Forwarded-Host，所以不用往 allowedHostnames 登记 tailnet 地址，也挡住了请求方伪造 |
| G6 | `routineWebhookUrl` 在读的时候算：先取 `PAPERCLIP_PUBLIC_URL`，再取 `PAPERCLIP_AUTH_PUBLIC_BASE_URL`，再取 `PAPERCLIP_API_URL`。`GET /api/routines/:id` 返回的每个触发器都带这样算出的 `webhookUrl` | `server/src/services/cloud-runtime-identity.ts:202-213`；`server/src/services/routines.ts:109-113`、`:2198-2201` | 不设 PUBLIC_URL 时，读回的 webhookUrl 是本机地址（#79 的 plist 设了 `PAPERCLIP_API_URL=http://127.0.0.1:3110`）。安装脚本从 GET 读 webhookUrl，核对 origin 是本机、路径符合规则，只把 origin 换成转发地址写进 `.url`，不自己拼 publicId |
| G7 | 设了 PUBLIC_URL 以后：它的主机名自动并进 allowedHostnames；`auth.baseUrlMode` 推成 explicit；`PAPERCLIP_RUNTIME_API_URL` 变成转发地址；CSRF 检查多信任这个源；MCP、Slack、chat webhook 生成的对外地址都用它 | `server/src/config.ts:203-247`；`server/src/index.ts:942-961`；`server/src/runtime-api.ts:50-62`；`server/src/middleware/board-mutation-guard.ts:49-56`；`server/src/app.ts:578`、`:616`、`:629`、`:871` | 第 2 轮起不设 PUBLIC_URL，这些变化都不会发生；万一发现设了，安装脚本停下（F21）。agent 拿到的 `PAPERCLIP_API_URL` 仍是本机：`packages/adapter-utils/src/server-utils.ts:3216-3223` 先取显式的 `PAPERCLIP_API_URL`，#79 的 plist 显式设了 |
| G8 | 发送方：notify-run 用 curl `--max-time 20`，只带 Authorization 和 Content-Type，正文 `--data-binary @文件`（有 Content-Length），非 2xx 重试，共 3 次（间隔 20、45 秒）；orca-wake 用 urllib，`timeout=20`，同样两个头，非 2xx 和连不上都按退避重试 | `wake/bin/notify-run:126-138`；`wake/bin/orca-wake:500-555` | 等上游的超时定 15 秒，小于 20 秒。两边都不发 Idempotency-Key，也不用分块编码 |
| G9 | 正文大小：notify-run 的 log_tail 最多 4000 字符，加其它字段，JSON 转义后最坏几十 KB（中文按 `\uXXXX` 转义是 6 倍） | `wake/bin/notify-run:69` | 上限 64 KiB 够用；超了 413 |
| G10 | iMac 的 `/usr/local/bin/tailscale` 是一个 shell 包装，调 `/Applications/Tailscale.app/Contents/MacOS/tailscale`；`tailscale ip -4` 返回一个 100.64.0.0/10 里的地址，挂在 utun 网卡上 | `ssh imac` 只读查看 | 地址的取法见 F1 |
| G11 | Node 的 http 服务：`req.url` 是原样的请求目标（不解码、不规范化，`#` 也原样保留，绝对形式就是 `http://x/...`）；同时带 Transfer-Encoding 和 Content-Length 时解析器直接报 `HPE_INVALID_TRANSFER_ENCODING`；HTTP/1.1 不带 Host 时 Node 自己回 400 | MBA 上 node v22.23.2 用 nc 发原始请求实测（临时目录，测完关掉） | 路径只对 `req.url` 做整串匹配；解析错误统一回固定的 404；`requireHostHeader:false`，缺 Host 由程序自己判 404 |
| G12 | MBA 上只有 node v22.23.2，没有 v24.22.1 | `ls ~/.nvm/versions/node/` | 本地自查用 v22 跑，只用 v22 和 v24 都有的 API；iMac 上正式运行用 v24.22.1。结果里写明 |

## A. 要防的失败方式

| # | 失败方式 | 怎么发现 | 怎么防 |
|---|---|---|---|
| F1 | 监听到 0.0.0.0、`::`、局域网地址或所有 IPv6 地址 | iMac 上 `lsof -nP -iTCP:8110 -sTCP:LISTEN` 只许一行，地址是 tailnet IPv4；读回从 iMac 打 127.0.0.1:8110、`[::1]:8110`、局域网地址:8110 都要连不上 | 地址只从 `tailscale ip -4` 取（它知道哪个是 tailnet 地址；只扫网卡分不清别的 100.64/10 地址）；再核对三件事：是合法 IPv4、在 100.64.0.0/10 里、确实挂在本机某个网卡上。三件有一件不成立就退出（非 0）。`listen()` 只传这个地址，代码里没有任何 0.0.0.0、`::` 或「取不到就用默认」的分支 |
| F2 | 开机时 tailnet 地址还没就绪，程序退回去听别的地址 | 同 F1；日志里有「取不到 tailnet 地址，退出」 | 取不到就以退出码 1 退出，没有退回分支（同 F1） |
| F3 | 开机时一直崩溃重启、占着 CPU | `launchctl print` 的 runs 计数；日志里退出的频率 | LaunchAgent 设 `ThrottleInterval 30`：两次启动至少隔 30 秒。程序启动到退出只做一次 `tailscale ip -4`（5 秒超时），CPU 很少。tailnet 就绪以后下一次启动就能起来 |
| F4 | tailnet 地址变了，程序还在听旧地址 | 日志「tailnet 地址变了，退出」；`lsof` 看监听地址 | 程序每 30 秒重查一次：网卡上已经没有这个地址，或者 `tailscale ip -4` 给出了别的合法地址，就退出（非 0），由 launchd 隔 30 秒用新地址重起。`tailscale ip -4` 暂时失败但网卡上还有原地址时不退出，免得 tailscaled 重启时来回抖。**地址变了以后 `.url` 文件和两台的 wake env 都是旧地址**，见 F38。headscale 给节点的地址一般不变，这种情况少见，写进 README |
| F5 | 路径绕过：`..`、`%2e%2e`、`%2F`、双斜杠、大小写、结尾多一个斜杠、少一段、带查询串、带 `#`、绝对形式的请求目标、超长路径 | 读回和自查逐个发，期望 404 | 只对原样的 `req.url` 做整串匹配 `^/api/routine-triggers/public/[0-9a-f]{24}/fire$`，不解码、不规范化。查询串和 `#` 里的 `?`、`#` 不在规则里，自然不匹配。超长路径先被请求头大小上限（8 KiB）挡掉，解析错误一样回 404 |
| F6 | 方法绕过：OPTIONS、GET、PUT、PATCH、DELETE、HEAD | 同上 | 方法必须严格等于 `POST`，否则 404 |
| F7 | HTTP/1.0 | 同上 | `req.httpVersion` 必须是 `1.1`，否则 404。两个发送方都用 1.1 |
| F8 | 请求走私：同时带 Transfer-Encoding 和 Content-Length | 自查发原始请求，期望 404，连接关掉 | Node 解析器本身就拒（G11），`clientError` 统一回 404 并关连接；程序另外规定：带任何 Transfer-Encoding 都 404 |
| F9 | 分块编码 | 同上 | 带 Transfer-Encoding 一律 404；必须带 Content-Length（发送方都带）。转发时 Content-Length 按读到的字节数重算，上游请求不分块 |
| F10 | `Expect: 100-continue` | 自查带这个头发一次合法请求（应转发）和一次非法路径（应 404，不回 100） | 处理 `checkContinue`：方法、路径、版本、头都过了才回 100，再读正文；过不了直接 404 不读正文。Expect 的其它值回 404。Expect 不转给上游（正文是读完再转的） |
| F11 | 连接复用：一个连接里塞第二个请求，第二个请求绕过检查或被当成第一个的正文 | 自查在一个连接里连发两个请求，第二个不应得到响应 | 每个响应都带 `Connection: close`，`maxRequestsPerSocket = 1`，响应写完就关连接。到上游每次新建连接（`agent:false`），也带 `Connection: close` |
| F12 | 转发了请求方带的 X-Forwarded-*、Forwarded、Host、Connection、Cookie 等头 | 自查用替身上游记下收到的全部头，逐个核对只有 Host、Authorization、Content-Type、Idempotency-Key、Content-Length、Connection 六个 | 白名单：只拷 Authorization、Content-Type、Idempotency-Key 三个（有才拷），其余一律不拷。同名头出现两次直接 404（Node 对重复头的合并规则各不相同，不靠它） |
| F13 | Host 没改成本机地址，被 Paperclip 的主机名检查挡掉（403） | 读回：伪造 Host、伪造 X-Forwarded-Host 再带错 bearer，期望 401 而不是 403 | 上游请求的 Host 固定写 `127.0.0.1:3110` |
| F14 | 慢速连接（慢慢发头、慢慢发正文） | 自查开一个只发半个请求头的连接，看几秒后被关 | 读头 5 秒（`headersTimeout`），整个请求 10 秒（`requestTimeout`），Node 检查超时的间隔设成 1 秒（默认 30 秒会让上面两个值不准）；空闲 socket 20 秒关（必须比等上游的 15 秒长，见 C1） |
| F15 | 超大请求体 | 读回、自查发 70 KiB，期望 413 | Content-Length 大于 64 KiB 直接 413，不读正文；边读边数，超了也 413 并关连接 |
| F16 | 并发连接打满（内存、文件句柄） | 自查同时开 20 个慢连接，再发一个合法请求，看是否在超时后恢复 | `maxConnections = 16`，超出的新连接直接关掉；每个连接最多 64 KiB 正文加 8 KiB 头，16 个合计约 1.2 MiB。被占满时发送方会重试（G8），慢连接最多占 10 秒 |
| F17 | 日志里出现 bearer、请求体、publicId 或对方的 IP | 读回在 iMac 上对日志 grep `Bearer`、24 位十六进制、IPv4 形状（只出计数，不出内容） | 每行只写时间、方法（不在已知列表里的写 `OTHER`）、是否放行、状态码、耗时毫秒。错误只写固定的错误种类（例如 `upstream_refused`），不写异常原文。程序里没有任何地方把 `req.url`、头、正文、`remoteAddress` 写进日志 |
| F18 | Paperclip 没起来或很慢 | 自查：上游端口没人听 → 502；替身上游故意 20 秒不回 → 504（在 15 秒左右） | 上游连不上 502，15 秒没回完 504，正文固定。15 秒小于发送方的 20 秒，发送方能收到 504 而不是自己超时 |
| F19 | 发送方会不会重试；重试会不会重复叫醒 | 读 G8 | 502、504 时发送方会重试。504 时上游可能已经收下了，重试会再投一次。两个触发器的 routine 是 `coalesce_if_active`，同一 routine 正在跑时后来的会合并；不在跑时会多一次叫醒。发送方都不带 Idempotency-Key，要去重得改发送方，留给 S12 ③，写进 README 待办 |
| F20 | 超过发送方的 20 秒 | 自查计时 | 上游 15 秒 + 读请求最多 10 秒，最坏 25 秒；但发送方是一次发完的（curl、urllib 都不慢发），实际读请求只要几毫秒，总时间约等于上游时间。写明这个前提 |
| F21 | Paperclip 意外带着 `PAPERCLIP_PUBLIC_URL` 在跑（plist 里有，或者实例目录里有 `public-url`，下次 `launchagent.sh --apply` 就会设上），G7 的变化会出现，读回的 webhookUrl 也不再是本机地址 | `install.sh` 计划和 `--apply` 都用 PlistBuddy 读 Paperclip plist 的 `PAPERCLIP_PUBLIC_URL`，并看实例目录里有没有 `public-url`；`readback-imac.sh checks` 再查一遍，两样都没有才 PASS | 发现任何一样就打印（打码）并停下，什么都不写：那不是这一轮预期的状态，要人看是谁设的。`install.sh` 自己不再写 `public-url`、不再调 `launchagent.sh`。`launchagent.sh` 不往 `config.json` 登记 allowedHostnames（第 1 轮已改） |
| F22 | 触发器的 `.url` 文件没更新，还是本机地址 | `readback-imac.sh checks`：`.url` 的路径和 Paperclip 读回的 webhookUrl 的路径相同，origin 是 `http://<当前 tailnet-ip>:8110`（只比较，不打印内容） | `install.sh --apply` 在转发程序起好、核对过监听以后才写 `.url`（F34–F37、F40）。两台 wake env 里的 URL 才是发送方真正用的，这次不改（要 Zack 批，派活不许改） |
| F23 | LaunchAgent 环境里有 `ORCA_*` | iMac 读回：`launchctl print` 的 environment 段键名、运行中进程环境里 `ORCA_` 开头的键数 | ProgramArguments 用 `/usr/bin/env -i HOME=… PATH=… LANG=…` 起 node，清掉所有继承来的变量，不只是 #79 清掉的 4 个；plist 的 EnvironmentVariables 不写 ORCA 键，渲染后检查；程序启动时再查一次环境，有 `ORCA_` 键就退出 |
| F24 | PATH 或 node 用错了 | plist 读回 ProgramArguments；`ps -axo comm=` 里的 node 路径 | node 写绝对路径 `~/.nvm/versions/node/v24.22.1/bin/node`，安装脚本核对 `-v` 是 v24.22.1；tailscale 也写绝对路径（`/usr/local/bin/tailscale`），不靠 PATH。PATH 只放系统目录 |
| F25 | 正式运行时用了改过的监听或上游地址（自查参数被带进正式环境） | iMac 读回 plist 的 ProgramArguments 和期望逐项相等 | 正式运行不带任何参数：不带参数时监听地址只能是 tailnet IPv4:8110，上游只能是 127.0.0.1:3110。自查参数 `--dev-listen`、`--dev-upstream` 只接受 `127.0.0.1:<端口>`，所以就算被误带进正式环境也只会更窄。安装脚本渲染 plist 后核对参数里没有 `--dev` |
| F26 | 内存：iMac 只有 8 GiB，memorystatus 22–28 | 装前、装后读 `kern.memorystatus_level`；`ps -axo rss=,comm=` 记程序 RSS | 程序只用 node 自带模块，常驻约 40 MB；node 加 `--max-old-space-size=32` 限制堆；正文和连接数有上限（F15、F16）。memorystatus 低于 20 安装脚本不装 |
| F27 | 端口 8110 被别的程序占了 | 安装前 `lsof -iTCP:8110 -sTCP:LISTEN` | 被占就不装、退出；程序 `listen` 失败就退出（非 0），不换端口 |
| F28 | 日志无限增长 | 读回看日志大小 | 程序自己写日志文件，超过 1 MiB 就改名成 `.1`（只留一份旧的）；launchd 的 stdout/stderr 只接启动错误 |
| F29 | 上游的响应头带出 Set-Cookie 之类，或响应体过大 | 自查替身上游回 Set-Cookie，看客户端收不到 | 只回传状态码、Content-Type 和正文；正文超过 256 KiB 算上游异常，回 502 |
| F30 | 头里带非法字符、头数量过多 | 自查 | Node 解析器拒绝非法字符（`clientError` → 404）；`maxHeadersCount = 50`，头总大小 8 KiB |
| F31 | 程序自身异常（未捕获错误）把进程打崩 | 日志、`launchctl print` 的 last exit code | 每个请求的处理都在 try 里，出错回 502 并记固定错误种类；真崩了由 KeepAlive 隔 30 秒重起 |
| F32 | `--off` 没撤干净：转发程序还在、8110 还有人听，或者 `.url` 没还原，发送方拿到的还是转发地址 | `--off` 自己最后核对：8110 没人听；每个 `.url` 的 origin 是 Paperclip 读回的本机 origin、路径和 webhookUrl 相同、权限 600；不对就以非 0 退出 | `--off` 先 bootout、删 plist 和程序，再从 `<slug>.url.before-forwarder` 还原（600），还原后才删备份；没有备份时不动 `.url`，但照样核对，`.url` 还是转发地址就报错。`--off` 不碰 Paperclip 的 LaunchAgent、`public-url`、Paperclip 进程 |
| F33 | 安装时把 bearer、publicId、IP 打到屏幕或 ssh 输出 | 安装脚本的输出过打码 | `.url` 文件由 iMac 上的 python 直接写，屏幕只出「已更新」和打码后的前缀；IPv4 一律打码 |
| F34 | `.url` 写错：origin 不是转发地址，或者路径不是那个触发器的 | 写完马上读回：内容必须等于「转发 origin + webhookUrl 的路径」；`readback-imac.sh checks` 再比一次 | 新内容只由脚本算：`http://<tailnet-ip>:8110` 加上 Paperclip 读回的 webhookUrl 的路径，路径整串符合 `^/api/routine-triggers/public/[0-9a-f]{24}/fire$`，不带查询串和 `#`；tailnet 地址用的是刚核对过、转发程序正在听的那个 |
| F35 | `.url` 只写了一半：写到一半出错、磁盘满，或者两个里只写了一个 | 同 F34 的读回；`readback-imac.sh` 两个都要 PASS | 先把两个触发器都读回、核对完，有一个不对就一个都不写；每个文件先写到同目录的临时文件（600，`O_EXCL`），`fsync` 后 `os.replace` 换过去，换名是原子的，不会留下半个文件。脚本中途停下时，已经换好的那个是完整的新地址，另一个是完整的旧地址，重跑 `--apply` 能补齐 |
| F36 | `.url` 或备份的权限不是 600 | 写完读回 `stat`；`readback-imac.sh` 打印权限，不是 600 就 FAIL | 临时文件用 `os.open(..., 0o600)` 建，换过去以后再 `chmod 600`；备份同样 600 |
| F37 | 读回的 webhookUrl 不是本机地址（比如 PUBLIC_URL 被设了），或者路径不合规则、带查询串，或者找不到某个触发器 | 脚本打印哪个触发器哪一项不对（不打印内容） | origin 必须正好是 `http://127.0.0.1:3110`（`API_URL`），路径整串匹配规则，没有查询串和 `#`；两个触发器 `ops-system`、`s12-drill` 都要找到，并且每个只有一个。有一项不对就停下，不写任何文件 |
| F38 | tailnet 地址变了，`.url` 里还是旧地址 | `readback-imac.sh checks` 用当前的 `tailscale ip -4` 比 origin，对不上就 FAIL；转发程序日志 `reason=tailnet_address_changed` | 转发程序自己会用新地址重起（F4），但 `.url` 不会自己变：重跑 `install.sh --apply`，它会按当前地址重写 `.url`（备份已存在就不再备份）。两台 wake env 要 Zack 批了再改。headscale 给节点的地址一般不变，写进 README |
| F39 | `install.sh` 意外动了 Paperclip（重启、改 LaunchAgent、写 `public-url`） | 装前装后读 `launchctl print` 里 Paperclip 的 runs，必须不变；plist 里没有 `PAPERCLIP_PUBLIC_URL` | `install.sh` 里已经没有调 `launchagent.sh`、写 `public-url`、对 Paperclip bootout 或 kickstart 的代码；只对 Paperclip 发 GET |
| F40 | 重跑或备份丢了时，把已经是转发地址的 `.url` 当成「装之前」备份下来，`--off` 就还原不回本机地址 | `--off` 的核对（F32） | 只在没有备份时才备份，并且要求现在的 `.url` 内容正好等于 Paperclip 读回的本机 webhookUrl；不等就停下，不备份也不写 |

## B. 已知但这次不解决的

| # | 内容 | 原因、交给谁 |
|---|---|---|
| B1 | tailnet 里任何能到 iMac 8110 的节点都能打触发路径，靠 bearer 挡 | 和原计划的 Serve 一样（34A）。headscale ACL 不在这次范围 |
| B2 | 发送方不带 Idempotency-Key，504 后的重试可能重复叫醒（F19） | 改发送方，S12 ③ |
| B3 | log_tail、note 里一行 `~~~~` 能关掉模板的代码围栏（S12 ② 验收新风险第 2 条） | 改发送端，S12 ③ |
| B4 | ~~`PAPERCLIP_RUNTIME_API_URL` 指向转发地址对 agent 的实际影响~~ | 第 2 轮起不设 PUBLIC_URL，不再有这个问题 |
| B7 | 请求声明的 Content-Length 比实际发的字节少：前一个请求转给了 Paperclip，客户端却收到 404，发送方会重试（第 1 轮验收新风险第 4 条） | 两个发送方都按实际长度发，碰不到。和 B2 一起留给 S12 ③ |
| B8 | CONNECT 请求直接断开，不回 404（node 没有 `connect` 监听时的默认行为；第 1 轮验收新风险第 5 条） | 没转发，不算绕过。留给 S12 ③ |
| B5 | 重启 iMac 以后程序能不能在 tailnet 就绪后自己起来 | 这一轮不装；装的那一轮也不许重启，写进 README 的读回步骤 |
| B6 | 程序跑在 HTTP 上，bearer 在 tailnet 里明文传（tailnet 本身是 WireGuard 加密的） | 和原计划 Serve 走 HTTP 一样（34A 照 24A） |

## C. 写完代码以后本地自查发现的（2026-10-25 03:23–03:25 +08，MBA，替身上游，不是 E2E）

| # | 发现 | 对应、改了什么 |
|---|---|---|
| C1 | 第一版 socket 空闲超时 15 秒，和等上游的 15 秒一样长：上游不回时，客户端连接先被关，发送方收不到 504，只会看到连接断开 | F18。空闲超时改成等上游的时间加 5 秒（20 秒），重跑自查 504 在 15.0 秒收到 |
| C2 | 自查第一次起转发程序时，程序因为本会话环境里有 `ORCA_*` 拒绝启动（`reason=orca_env_present`），F23 的检查生效了 | 自查脚本改成和 LaunchAgent 一样用 `env -i` 起，另加一项「环境里有 ORCA_* 时拒绝启动」的检查 |

## D. 第 1 轮验收提的小问题（2026-10-25 第 2 轮处理）

| # | 问题 | 处理 |
|---|---|---|
| D1 | launchd 的 `launchd.err.log`、`launchd.out.log` 不转存，反复崩溃时一直变大（新风险第 6 条） | `forwarder.js` 正式模式启动时，这两个文件超过 1 MiB 就改名成 `.1`（只留一份旧的）。launchd 每次起进程时重新打开这两个文件，所以改名以后下一次启动写新文件 |
| D2 | `serve.sh --apply` 不检查转发程序在不在跑，两者都占 8110（新风险第 8 条） | `serve.sh --apply` 在转发程序已加载或 8110 有人听时停下 |
| D3 | `readback-from-mba.sh` 的打码会把 commit sha 里的 24 位截掉（第 14 项） | 打码只换前后都不是十六进制字符的 24 位串，40 位的 sha 不再被截 |
| D4 | install 的屏幕输出里有 `gui/<数字>` 和带用户名的家目录（新风险第 7 条） | 装的那一轮抄进结果时手工打码（派活要求） |
