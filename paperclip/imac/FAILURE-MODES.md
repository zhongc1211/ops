# S12 ② iMac 装 Paperclip 2026.1012.0：失败方式清单（先写清单，再写脚本）

写于 2026-10-25 02:0x SGT，在写本目录脚本、动 iMac 之前。依据：派活 `BRIEF-s12-2.md`；调研 `6-paperclip.md`；
v2026.1012.0（提交 bba6a45）源码，路径都相对 Paperclip 仓库根目录；iMac 上的只读检查（`ssh imac`）。

脚本的每个读回（`readback-imac.sh`、`readback-from-mba.sh`）对应下表的一条或几条。读回结果不符就记 FAIL、保留原始输出，
不放宽判断、不挑着重跑。

## 动手前查到的、会影响设计的事实

| # | 事实 | 怎么查到的 | 影响 |
|---|---|---|---|
| F1 | 实例目录 = `$PAPERCLIP_HOME`（默认 `~/.paperclip`）`/instances/$PAPERCLIP_INSTANCE_ID`，不设时是 `default`；实例 ID 只许字母、数字、`_`、`-` | `packages/shared/src/home-paths.ts:4,22-34` | 每个脚本和 LaunchAgent 都显式设 `PAPERCLIP_INSTANCE_ID=ops`，并在执行前核对 |
| F2 | `onboard --yes` 会当场在前台起服务（`shouldRunNow = … opts.yes === true`）；`run` 在没有配置文件时也会走 onboard | `cli/src/commands/onboard.ts:499-512`、`cli/src/commands/run.ts` | 不跑 onboard。安装脚本自己写 `config.json`；服务只经 LaunchAgent 跑 `paperclipai run --instance ops`，这时配置已经在，run 只做 doctor 再起服务 |
| F3 | onboard 快速配置写死嵌入式 postgres 端口 54329、服务端口 3100，和试装的 `default` 一样 | `onboard.ts:259`、`:277` | 新实例用 3110 和 54339，试装就算被人起了也不抢端口 |
| F4 | `heartbeat.maxConcurrentRuns` 不在实例配置里，在每个 agent 的 `runtimeConfig.heartbeat` 里，默认 20 | `server/src/services/heartbeat.ts:16820-16831`、`:3753-3762`；`packages/shared/src/constants.ts:77` | 建 agent 时写 `runtimeConfig.heartbeat.maxConcurrentRuns=1`，读回 agent 配置核对 |
| F5 | 设了 `PAPERCLIP_PUBLIC_URL` 而没设 `PAPERCLIP_API_URL` 时，服务端会把 `PAPERCLIP_API_URL` 推成公开地址，agent 拿到的回调地址就变成 Serve 地址 | `server/src/index.ts:942-961`（`choosePrimaryRuntimeApiUrl` 用 `authPublicBaseUrl`） | LaunchAgent 里显式设 `PAPERCLIP_API_URL=http://127.0.0.1:3110` |
| F6 | `PAPERCLIP_PUBLIC_URL` 的主机名会自动并进 allowedHostnames，也会把 `auth.baseUrlMode` 推成 explicit | `server/src/config.ts:203-247` | 仍按派活显式跑 `allowed-hostname`，读回配置文件 |
| F7 | webhook 触发：routine 是 paused 且触发器不在 setupPending 时，先返回 409，不做 bearer 检查；触发器 `setupPending=true` 时，先查 bearer（错就 401），对就只记一条测试回执（`test_received`），不建运行、不叫醒 agent | `server/src/services/routines.ts:2938-2940`、`:2984-2996`、`:3026-3031`、`:3036` | routine 设 active、触发器建成 `setupPending=true`、agent 暂停。这样不带 bearer 的读回是 401，带对 bearer 也起不了运行。S12 ④ 用 `PATCH {"setupPending":false}` 转正（转正后不能回到 setupPending） |
| F8 | 触发器的密钥由服务端生成，只在建触发器的响应里出现一次（`secretMaterial.webhookSecret`） | `docs/api/routines.md:126-139` | 建触发器的请求在 iMac 上发，响应直接交给 iMac 上的 python 把密钥写进 600 文件，stdout 只出名字、长度和「有/没有」 |
| F9 | 变量不写 `required` 时默认必填；缺值时，没声明 `defaultValue` 的占位符原样留在标题和描述里 | `packages/shared/src/validators/routine.ts:22-29`；`server/src/services/routines.ts:448-484`；`packages/shared/src/routine-variables.ts:132-143` | 每个变量都写 `required:false`、类型 text、`defaultValue:"-"` |
| F10 | `{{date}}`、`{{timestamp}}` 是内置变量，按当前时间取值，会进分发指纹 | `packages/shared/src/routine-variables.ts:18-45`；`routines.ts:1771-1798` | 模板里不用这两个；`provision.sh` 写入前检查模板不含这两个词 |
| F11 | claude_local：engine 不写时是 acp（ACP 默认 `approve-all`）；CLI 引擎 `dangerouslySkipPermissions` 默认 true | `packages/adapters/claude-local/src/server/acp.ts:85-93`、`:133-138`；`packages/adapter-utils/src/acpx-engine/constants.ts:3-4`；`packages/adapters/claude-local/src/server/execute.ts:437` | 建 agent 时显式写 `engine:"cli"`、`dangerouslySkipPermissions:false`，读回核对 |
| F12 | CLI 命令行是 `--print --output-format stream-json --verbose … --add-dir <bundle>`，extraArgs 加在最后 | `execute.ts:848-879` | extraArgs 原样写四组参数，`--settings` 用绝对路径 |
| F13 | 建 company 时若 `requireBoardApprovalForNewAgents` 为真，直接建 agent 返回 409 | `server/src/routes/agents.ts:4931-4935` | provision 先读 company 的这个字段，为真就停下写进结果，不自己改 |
| F14 | iMac 是 arm64、8 GiB；默认 node 是 v22.23.2，nvm 有 v24.22.1；npx 缓存里有 paperclipai 2026.1012.0（engines `>=24.11.0`）；`~/.paperclip/cli` 只有 `update-check.json`；磁盘剩 32 GiB（93% 已用） | `ssh imac` 只读 | 用 `npm install --prefix` 装进单独目录，不碰 `~/.paperclip/cli`（那是 Paperclip 自己的托管安装位置，和试装共用）；备份保留天数改 7 |
| F15 | iMac 的 tailscale 1.104.1，`serve status` 是 No serve config；控制服务器是 headscale，没有证书域名，MagicDNS 关 | `tailscale serve status`；`6-paperclip.md` 第 19 条 | 先试 `--https`，失败就 `--http`，两次的报错都留下 |
| F16 | iMac 上非交互 ssh 的 PATH 里没有 node、orca、claude；登录 shell 里 `timeout` 在 `/usr/local/bin` | `ssh imac 'zsh -lic …'` | 脚本里写绝对路径；LaunchAgent 的 PATH 显式列出 |
| F17 | 本会话（MBA）环境里有 `ORCA_DISPATCH_BOT`；经 ssh 到 iMac 的环境里没有 | `env \| cut -d= -f1` | 任何 Paperclip 进程都只经 iMac 的 LaunchAgent 起，wrapper 里再 `unset` 一次 |

## A. 要防的失败方式

| # | 失败方式 | 怎么发现 | 怎么防 |
|---|---|---|---|
| A1 | 装错版本，或者走了 `@latest` | 读回 `<app>/node_modules/paperclipai/package.json` 的 version；`npm ls paperclipai` | `install.sh` 只接受写死的 `2026.1012.0`（`config.sh` 里一处），命令写 `paperclipai@2026.1012.0`，`--save-exact`；装完版本不对就退出非零 |
| A2 | 内嵌 postgres、server 等依赖版本漂了 | `npm ls @paperclipai/server embedded-postgres` 读回写进结果 | 只能钉顶层包；依赖由包自己的 semver 决定。写进 README 的已知限制，重装后要再读回 |
| A3 | 没设 `PAPERCLIP_INSTANCE_ID`，打开了试装的 `default` | 读回服务写的 `~/.paperclip/instances/ops/runtime-info.json`、日志目录在 ops 下；`default` 的 `config.json` 修改时间和 sha256 装前装后一致 | 所有脚本开头设并核对 `PAPERCLIP_INSTANCE_ID=ops`；CLI 都带 `--instance ops` 或 `-c <ops 的 config.json>`；LaunchAgent 写死；装前记 `default` 的 sha256 |
| A4 | 用错 node（默认的 v22） | LaunchAgent 的 `ProgramArguments[0]` 是 v24.22.1 的绝对路径；`ps -axo comm=` 里 node 路径；服务启动日志 | 脚本和 plist 都写 `~/.nvm/versions/node/v24.22.1/bin/node` 的绝对路径；不依赖 PATH 里的 node；node 版本不是 v24.22.1 就退出 |
| A5 | LaunchAgent 环境里带着 `ORCA_DISPATCH_BOT` | `launchctl print gui/<uid>/<label>` 的 environment 段只看键名；服务进程的环境键名（`ps eww` 只取键名） | plist 的 EnvironmentVariables 不写这个键；wrapper `unset ORCA_DISPATCH_BOT` 等 Orca 派活变量；渲染 plist 后 grep 确认没有 |
| A6 | LaunchAgent 的 PATH 里找不到 `orca`、`notify-run`、`claude` | readback 用 plist 里同一个 PATH 跑 `command -v` | plist 显式写 PATH：`~/.local/bin:/usr/local/bin:/opt/homebrew/bin:<node24>/bin:/usr/bin:/bin:/usr/sbin:/sbin`；渲染时逐个检查能找到，找不到就退出 |
| A7 | 服务监听到 0.0.0.0、`::` 或局域网、tailnet 地址 | `lsof -nP -iTCP:3110 -sTCP:LISTEN` 只许 `127.0.0.1:3110`；嵌入式 postgres 54339 同样核对 | `config.json` 写 `deploymentMode=local_trusted`、`exposure=private`、`bind=loopback`、`host=127.0.0.1`；plist 写 `HOST=127.0.0.1`；不设 `PAPERCLIP_BIND` 为别的值 |
| A8 | Serve 把整个界面或整个 API 暴露出去 | 从 MBA 经 Serve 访问 `/`、`/api/health`、`/api/companies`、`/api/routine-triggers/public`（少结尾斜杠）都不是 Paperclip 的回答 | Serve 只挂 `/api/routine-triggers/public/` 一个路径，目标也是同一路径；不挂 `/` |
| A9 | 带 `..`、编码过的斜杠（`%2F`、`%2e%2e`）、自己伪造 `X-Forwarded-Host` 的请求绕过路径限制 | MBA 用 `curl --path-as-is` 发这些变体，记录状态码和响应头里有没有 Paperclip 的痕迹（JSON 的 `error` 字段） | 只挂一个前缀；Paperclip 自己的鉴权仍在（local_trusted 下本机才是管理员，但从 Serve 进来的请求 Host 是 tailnet 地址，鉴权身份不变——见 B3）；变体有一个能到非触发路由，就停在这一步交 Zack 定 |
| A10 | Serve 重启以后没了 | 用 `--bg` 配置；`tailscale serve status --json` 读回；重启 tailscaled 不在本次做（会断开别的连接），写进「没做」 | 只用 `--bg`（持久写进 tailscaled 的状态）；README 写重启后怎么读回 |
| A11 | headscale 下 Serve 用不了，或者 ACL 不放行 MBA 到 iMac 的这个端口 | `tailscale serve` 的报错；MBA 上 curl 超时或连接被拒 | HTTPS 不行就 HTTP；HTTP 也不行或 MBA 到不了，停下交 Zack 定（选项：34C 只在本机；34B authenticated 加 bind=tailnet；改 headscale ACL） |
| A12 | `PAPERCLIP_PUBLIC_URL` 把 agent 的回调地址也带歪了 | 读回服务进程的 `PAPERCLIP_API_URL`：服务启动日志里的 API 地址；`runtime-info.json` 的 dashboardUrl | 见 F5：显式设 `PAPERCLIP_API_URL`。agent 运行时实际拿到的地址只有真跑一次才看得到，留给 S12 ④ 核 |
| A13 | bearer 进了日志、shell 历史或 ssh 输出 | 结束后在 MBA 的会话输出和 iMac 的 Paperclip 日志里 grep 密钥前缀不现实（不能打印密钥），改为：脚本从不 echo 密钥变量；python 只打印长度 | 建触发器的响应不落盘、不打印，直接在 iMac 的 python 进程里解析；密钥文件先建 600 再写；ssh 命令行里不出现密钥；不用 `set -x` |
| A14 | routine 变量必填导致 422 | 读回 routine 的 variables，逐个看 `required:false` | 见 F9 |
| A15 | agent 被意外触发、起了真运行、花了钱 | 读回 agent `status=paused`、heartbeat `enabled=false`；触发器 `setupPending=true`；`GET /api/companies/<id>/heartbeat-runs` 或 agent 的 runs 为空；没有 API key（还没填） | 三层：agent 暂停；触发器 setupPending；没有 `ANTHROPIC_API_KEY`，加上 `--bare` 时不会退回订阅登录。读回只用不带 bearer 的请求和本机只读 GET |
| A16 | 内存不够，把 iMac 拖慢 | 装前、起服务前、起服务后 1 分钟和 5 分钟读 `kern.memorystatus_level`；`ps -axo rss=,comm=` 记 Paperclip 相关进程 | 低于 20 不起服务；低于 15 bootout LaunchAgent；LaunchAgent 不设 KeepAlive 无限重启（用 `KeepAlive.SuccessfulExit=false` 加 `ThrottleInterval 60`），崩溃时不会每 10 秒重起 |
| A17 | 碰了试装：`~/.paperclip/instances/default`、`~/paperclip` 克隆 | 装前装后 `default/config.json` 的 sha256；`git -C ~/paperclip rev-parse HEAD` 前后一致 | 脚本里没有指向 default 的路径；只用 `git show` 只读看源码 |
| A18 | 嵌入式 postgres 或服务端口被占（试装、别的程序） | `lsof` 先查 3110、54339 | 被占就退出，不换端口硬起 |
| A19 | doctor `--repair` 改了我们写的配置 | 起服务后再读一次 `config.json`，和写入的值比 server、database 两段 | 配置写全（含 `$meta`），让 doctor 不需要修；有差异写进结果 |
| A20 | 遥测、更新检查、公告往外发请求 | 配置读回 `telemetry.enabled=false`、`updates.checkEnabled=false`；plist 设 `PAPERCLIP_ANNOUNCEMENTS_ENABLED=false` | 这几项和这次的任务无关，默认关掉，README 写明 |
| A21 | 脚本重跑时重复建 company、agent、routine、触发器，或者轮换了已有触发器的密钥 | provision 每步先按名字查，有就跳过并打印「已存在」 | 按名字幂等；从不调 rotate-secret；密钥文件已存在且非空就不建新触发器 |
| A22 | 建出来的 agent 配置被服务端改写（默认值、规范化） | 建完 GET 一次，逐项核对 engine、dangerouslySkipPermissions、extraArgs、model、cwd、maxConcurrentRuns、budget | 不符就记 FAIL，不改用别的参数 |
| A23 | iMac 装的 claude 不认 `--bare`、`--permission-mode dontAsk`、`--permission-prompts none`、`--settings` | `claude --help` 里逐个找 | 找不到的写进结果，不换参数 |
| A24 | `--bare` 下用户级 `~/.claude/settings.json` 的 permissions（allow 5 条）仍可能被读到 | `claude --help`：`--bare` 只写了跳过 hooks、插件、CLAUDE.md 等，没写跳过 user settings 的 permissions | 这次只写最小的默认拒绝文件，不改参数；写进结果交 S12 ③ 定（例如加 `--setting-sources` 或核对实际放行） |
| A25 | LaunchAgent 用 `launchctl load` 等旧写法、加载到错误的域 | `launchctl print gui/<uid>/<label>` 读回 | 只用 `launchctl bootstrap gui/<uid> <plist>` 和 `launchctl bootout gui/<uid>/<label>` |
| A26 | 命令卡住超过 15 分钟 | — | MBA 侧每条 ssh 用 `timeout 840`；iMac 侧用 `/usr/local/bin/timeout` |
| A27 | 把 IP、ID、密钥写进仓库或结果 | 提交前 `git diff` 人工看；grep `100\.` 和 UUID 形状 | 脚本运行时取 tailnet 地址；结果里写名字和查法 |

## B. 已知但这次不解决的

| # | 内容 | 原因、交给谁 |
|---|---|---|
| B1 | local_trusted 下 iMac 本机任何不带凭据的请求都按管理员处理（`server/src/middleware/auth.ts:230-240`） | 决定 34A 接受；本机侧靠 S12 ③ 的 agent 权限挡 |
| B2 | Host 检查先读 `X-Forwarded-Host`，不核对是否来自可信代理（`server/src/middleware/private-hostname-guard.ts:8-12`） | 主防线是只听本机加 Serve 只挂一个路径；伪造 XFH 的变体在 A9 里测 |
| B3 | 从 Serve 进来的非触发请求如果真到了 Paperclip，在 local_trusted 下也会被当成管理员 | 所以 A8、A9 任何一项到了 Paperclip 都算 FAIL，停下交 Zack |
| B4 | agent 运行时实际拿到的 `PAPERCLIP_API_URL`、`--bare` 和 Paperclip 自己传的参数能否同时用、`dontAsk` 的确切行为 | 要真跑一次，留给 S12 ④ |
| B5 | 重启 iMac 后 LaunchAgent 和 Serve 是否都在 | 这次不重启 iMac；README 写读回步骤 |

## C. 动手以后实测的（2026-10-25 02:00–02:20 SGT）

| # | 实测 | 对应 |
|---|---|---|
| C1 | `tailscale serve --https=443` 报 `error enabling https feature: error 501 Not Implemented`（headscale 不支持） | A11 |
| C2 | `tailscale serve --http=8110 --set-path …` 配得上，但从 MBA、从 iMac 本机发的请求一律是 Go 的 `404 page not found`。原因在 tailscale v1.104.1 `ipn/ipnlocal/serve.go:821-845`：非 TLS 请求按「Host 去端口 + "." + MagicDNS 后缀」查处理器；这个 headscale 下本机短名和 MagicDNS 后缀都是 `imac`，CLI 存的键是 `imac:8110`，查的键却是 `imac.imac:8110` 或 `<ip>.imac:8110`，永远对不上。临时在 127.0.0.1:3110 起 20 秒 python http.server 对照，结果一样是 404，排除了 Paperclip 本身 | A11。已 `serve.sh --off` 撤掉，Serve 停在「要 Zack 定」 |
| C3 | npm 11 默认不跑依赖的安装脚本，跳过了 `@embedded-postgres/darwin-arm64`（hydrate-symlinks）、ssh2、protobufjs、cpu-features；核对 postgres 需要的 17 个符号链接都在，doctor 12 项通过，服务起来后 postgres 正常 | A2 |
| C4 | 依赖读回：`@paperclipai/server@2026.1012.0`、`embedded-postgres@18.1.0-beta.16`、`@embedded-postgres/darwin-arm64@18.1.0-beta.16` | A2 |
| C5 | 嵌入式 postgres 还听 `[::1]:54339`，仍是本机回环 | A7 |
| C6 | `launchctl print` 的 arguments 段里有 `env -u ORCA_DISPATCH_BOT …`，按整段 grep `ORCA_DISPATCH` 会误报；`readback-imac.sh` 改成只看 environment 段的键名，另用 `ps -E` 只数运行中进程环境里 `ORCA_` 开头的键 | A5 |
