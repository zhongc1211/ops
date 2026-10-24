# iMac 上的 Paperclip（实例 ops）

S12 ②：在 iMac 上装 Paperclip 2026.1012.0，做 ops 系统叫醒的接收端。本目录是安装、配置、读回、回退用的脚本。
先读 `FAILURE-MODES.md`：每个脚本和读回对应其中哪几条失败方式。

所有脚本在 iMac 上跑。不带参数只打印计划，加 `--apply` 才动手；可以重跑，已做好的步骤会跳过。
脚本放到 iMac 上的位置是 `~/.local/share/paperclip-ops/scripts/`（从本目录复制过去，含 `forwarder/` 子目录：`scp -r paperclip/imac/* imac:.local/share/paperclip-ops/scripts/`）。

## 装了什么、在哪

| 东西 | 位置 |
|---|---|
| paperclipai 2026.1012.0（钉死版本，`npm install --save-exact`） | `~/.local/share/paperclip-ops/app-2026.1012.0/` |
| node | `~/.nvm/versions/node/v24.22.1/bin/node`（绝对路径，不用默认的 v22） |
| 实例 `ops`（`PAPERCLIP_INSTANCE_ID=ops`） | `~/.paperclip/instances/ops/`（配置 `config.json`、数据库 `db/`、日志 `logs/`、本地密钥 `secrets/`） |
| 服务 | `127.0.0.1:3110`，local_trusted、private、只听本机；内嵌 postgres `127.0.0.1:54339`（另有 `[::1]`） |
| 触发转发程序（代替 Serve） | `~/.local/share/paperclip-ops/forwarder/forwarder.js`，只听 tailnet IPv4 的 8110，只放行触发路径，转给 `127.0.0.1:3110`。LaunchAgent `com.zhongc1211.paperclip-ops-forwarder`。日志 `~/Library/Logs/paperclip-ops-forwarder/forwarder.log`。详见下面「对外怎么开」 |
| LaunchAgent | label `com.zhongc1211.paperclip-ops`，`~/Library/LaunchAgents/com.zhongc1211.paperclip-ops.plist`，`launchctl bootstrap gui/<uid>` 加载，开机自启 |
| company / agent | company「ops 系统」；agent `ops-system`（claude_local，暂停） |
| routine | 「ops 系统叫醒」（正式）、「S12 演练叫醒（测试）」（S12 ④ 用） |
| 触发器 | 每个 routine 一个 bearer webhook，label `ops-system-bearer`、`s12-drill-bearer`，都在 setupPending |
| 触发器 bearer、地址 | `~/.config/paperclip-ops/triggers/{ops-system,s12-drill}.{bearer,url}`（目录 700，文件 600） |
| agent 工作目录、设置文件 | `~/.paperclip/instances/ops/agent-work/ops-system/`；`.claude/ops-system-settings.json`（600，最小默认拒绝） |

不碰：`~/.paperclip/instances/default`（试装）、`~/.paperclip/cli`、`~/paperclip` 克隆、`~/.claude/settings.json`。

## 步骤

1. `install.sh [--apply]`：装 paperclipai、写 `config.json`、跑 `doctor --repair`。不起服务。
2. 对外：`forwarder/install.sh [--apply | --off]`，见下面「对外怎么开」。`serve.sh` **现在不用**（headscale 下 Serve 用不了），留着备用。
3. `launchagent.sh [--apply | --bootout]`：有 `~/.paperclip/instances/ops/public-url` 时设 `PAPERCLIP_PUBLIC_URL`；渲染 plist（环境里没有 `ORCA_*`，`PAPERCLIP_API_URL` 固定本机），bootstrap。内存 `kern.memorystatus_level` 低于 20 不起。
   不再往 `config.json` 登记 allowedHostnames：转发程序把 Host 改成本机地址，PUBLIC_URL 的主机名运行时也会自动并进去（1012.0 `server/src/config.ts:231-246`）。
4. `provision.sh [--apply | --check]`：建 company、agent（建完就暂停）、设置文件、两条 routine、两个触发器（密钥直接写 600 文件，屏幕只出长度）；
   再收紧：company 的 `requireBoardApprovalForNewAgents` 设 true，ops-system 的 `canCreateAgents` 设 false。`--check` 是只读的读回：
   company 下只有 ops-system 一个 agent、`canCreateAgents=false`、4 个授权（`agents:configure`、`skills:create`、`tools:manage_runtime`、
   `tools:manage_connections`）都不在。4 个授权在 1012.0 删不掉，见「要 Zack 定」，所以那一项在 Zack 定之前会是 FAIL。
5. `key-fill.sh --fill`：Zack 填 Console API key，见 `KEY-FILL.md`。不带参数只打印用法。

## 读回

- iMac：`~/.local/share/paperclip-ops/scripts/readback-imac.sh`。版本、实例、配置、监听、LaunchAgent 环境键名、PATH、主机名检查、agent/routine/触发器配置、本机不带 bearer 和带错 bearer 的 401、heartbeat runs 条数、密钥文件权限和长度、Serve 状态。不打印密钥、IP、ID、PID。
  注意：它会对两个触发器各发两次被拒的 POST，Paperclip 会记 `routine.webhook_test_rejected` 活动，不起运行。
- MBA：`paperclip/imac/forwarder/readback-from-mba.sh`（在仓库里直接跑），转发程序装好以后用，见「对外怎么开」。
  `paperclip/imac/readback-from-mba.sh` 是 S12 ② 时没有对外入口时的读回（所有端口都应连不上），装了转发程序以后 8110 的那几项不再适用。
- key：`key-fill.sh --check`，只打印 有/没有。
- 内存：`sysctl -n kern.memorystatus_level`；`ps -axo rss=,comm= | grep -E 'paperclip-ops|postgres|v24.22.1'`。低于 15 就 `launchagent.sh --bootout`。

### ID 怎么查

仓库和结果里不写 ID。要用时在 iMac 上查（只在本机，不要贴到别处）：

```bash
curl -s http://127.0.0.1:3110/api/companies | python3 -c 'import json,sys; [print(c["name"], c["id"]) for c in json.load(sys.stdin)]'
curl -s http://127.0.0.1:3110/api/companies/<company id>/agents   | python3 -c 'import json,sys; [print(a["name"], a["id"]) for a in json.load(sys.stdin)]'
curl -s http://127.0.0.1:3110/api/companies/<company id>/routines | python3 -c 'import json,sys; [print(r["title"], r["id"]) for r in json.load(sys.stdin)]'
curl -s http://127.0.0.1:3110/api/routines/<routine id> | python3 -c 'import json,sys; [print(t["label"], t["id"]) for t in json.load(sys.stdin)["triggers"]]'
```

触发器的公开地址（含 publicId）在 `~/.config/paperclip-ops/triggers/<slug>.url`。装转发程序之前里面是本机地址（`http://127.0.0.1:3110/...`）；
`forwarder/install.sh --apply` 把它换成 Paperclip 读回的新 webhookUrl（`http://<tailnet-ip>:8110/...`），旧的备份成 `<slug>.url.before-forwarder`。

## 回退

按顺序，在 iMac 上：

```bash
S=~/.local/share/paperclip-ops/scripts
$S/forwarder/install.sh --off                                 # 撤掉转发程序，PUBLIC_URL 和 .url 恢复原样（会重启 Paperclip）
$S/launchagent.sh --bootout                                   # 停服务、卸载 LaunchAgent
rm ~/Library/LaunchAgents/com.zhongc1211.paperclip-ops.plist
$S/serve.sh --off                                             # 撤掉本目录加的 serve（现在本来就没有）
# 删实例目录之前，确认 Paperclip 和它的内嵌 postgres 都已经退出：下面两行都必须没有输出，有输出就停下，不要删
lsof -nP -iTCP:3110 -sTCP:LISTEN
lsof -nP -iTCP:54339 -sTCP:LISTEN
rm -rf ~/.paperclip/instances/ops                             # 只删新实例，绝不碰 instances/default
rm -rf ~/.local/share/paperclip-ops ~/.config/paperclip-ops   # 程序、脚本、触发器密钥
rm -rf ~/Library/Logs/paperclip-ops-forwarder                 # 转发程序的日志
```

回退后读回：`launchctl print gui/$(id -u)/com.zhongc1211.paperclip-ops` 应报找不到；`lsof -nP -iTCP:3110 -sTCP:LISTEN` 应为空；
`lsof -nP -iTCP:54339 -sTCP:LISTEN`、`lsof -nP -iTCP:8110 -sTCP:LISTEN` 也为空；`launchctl print gui/$(id -u)/com.zhongc1211.paperclip-ops-forwarder` 应报找不到；
`ls ~/.paperclip/instances` 只剩 `default`；`tailscale serve status` 不含 `/api/routine-triggers/public/`。

## 对外怎么开：触发转发程序（代替 Serve）

背景：headscale 下 Serve 用不了（`FAILURE-MODES.md` C1、C2：HTTPS 501；HTTP 能配上，但 tailscale 1.104.1 按「Host + MagicDNS 后缀」
查处理器，在这个 headscale 的命名下永远查不到，一律 404）。Zack 选了 D：在 iMac 上跑一个小转发程序代替 Serve。

转发程序在 `forwarder/`，失败方式清单先写在 `forwarder/FAILURE-MODES.md`：

- `forwarder.js`：只用 node 自带模块，一个文件。只听 tailnet IPv4 的 8110（地址运行时由 `tailscale ip -4` 取，再核对在 100.64.0.0/10 里、
  挂在本机网卡上，取不到就以非 0 退出，不退回别的地址）。只放行 `POST /api/routine-triggers/public/<24 位小写十六进制>/fire`
  （原样路径整串匹配，HTTP/1.1，没有查询串），转给 `127.0.0.1:3110`，只带 Authorization、Content-Type、Idempotency-Key，Host 写本机。
  其余一律 404，正文固定。正文上限 64 KiB（超了 413），读头 5 秒、整个请求 10 秒、等上游 15 秒（超时 504，连不上 502），最多 16 个连接。
  每 30 秒核对一次地址，变了就退出，由 launchd 用新地址重起。
- 日志：`~/Library/Logs/paperclip-ops-forwarder/forwarder.log`（在实例目录以外），每行只有时间、方法、是否放行、状态码、耗时；
  超过 1 MiB 改名成 `.1`。launchd 的 stdout/stderr 在同一目录的 `launchd.out.log`、`launchd.err.log`。
- LaunchAgent：`com.zhongc1211.paperclip-ops-forwarder`，模板 `forwarder/com.zhongc1211.paperclip-ops-forwarder.plist.template`。
  用 `/usr/bin/env -i` 起 node，环境里只有 HOME、PATH、LANG，没有任何 `ORCA_*`；不带参数，所以只能是 tailnet IPv4:8110 和 127.0.0.1:3110；
  RunAtLoad、KeepAlive、ThrottleInterval 30。
- `forwarder/install.sh [--apply | --off]`：默认只打印计划和检查结果。`--apply`：装程序、渲染并核对 plist、`launchctl bootstrap gui/<uid>`、
  核对 8110 只听 tailnet IPv4、把 `public-url` 写成转发地址、跑 `launchagent.sh --apply` 重启 Paperclip（设 `PAPERCLIP_PUBLIC_URL`）、
  从 Paperclip 读回新的 webhookUrl 更新两个 `.url` 文件。`--off`：撤掉程序和 LaunchAgent，`public-url` 和 `.url` 恢复成装之前的样子，重启 Paperclip。
- 读回：MBA 上 `paperclip/imac/forwarder/readback-from-mba.sh [输出文件]`。只用错的 bearer 或不带 bearer；前后各数一次 heartbeat runs，必须都是 0。
  内容：不带 bearer、错 bearer、伪造 X-Forwarded-Host 或 Host 再带错 bearer → 401；`/`、`/api/health`、`/api/companies`、各种路径和方法变体、
  HTTP/1.0、分块编码、走私 → 404；70 KiB → 413；iMac 的 127.0.0.1、`[::1]`、局域网地址打 8110 连不上；LaunchAgent、日志、`.url` 文件的核对。
- 本地自查（开发自查，替身上游，不是 E2E）：MBA 上 `paperclip/imac/forwarder/selfcheck-mba.sh <输出目录>`，只用 127.0.0.1。

装的那一轮在 iMac 上跑（先把脚本复制过去，见本文件开头）：

```bash
S=~/.local/share/paperclip-ops/scripts
$S/forwarder/install.sh            # 先看计划
$S/forwarder/install.sh --apply
$S/provision.sh --apply            # 收紧 company 和 agent（建好的部分会跳过）
$S/provision.sh --check
```

然后在 MBA 上跑 `paperclip/imac/forwarder/readback-from-mba.sh`。

tailnet 地址变了的话（少见）：转发程序会自己退出、用新地址重起，但 `public-url`、`.url` 文件和两台 wake env 里还是旧地址。
重跑 `forwarder/install.sh --apply` 更新前两样；wake env 要 Zack 批了再改。

## 要 Zack 定：ops-system 的 4 个授权删不掉

S12 ② 验收方要求去掉 ops-system 的 `agents:configure`、`skills:create`、`tools:manage_runtime`、`tools:manage_connections`。
1012.0 没有能删 agent 授权的 REST 接口：成员授权接口只认人类成员（`server/src/routes/access.ts:1301`），
`PATCH /agents/:id/permissions` 只会动 `tasks:assign`（`server/src/routes/agents.ts:5116-5126`）。`provision.sh` 这次只列出来，不删。

- A.（推荐）把 ops-system 设成低信任：`PATCH /agents/:id/permissions` 带 `trustPreset: "low_trust_review"`。低信任时
  `agents:create`、`agent_config:update`、`skill_config:update`、`runtime:manage`、`secrets:read` 等一律拒绝（`server/src/services/authorization.ts:1029-1049`），
  不管有没有那几个授权（读源码推的，没实测）。走的是正式接口，能读回。缺点：它还会拒掉 `company_scope:read`、`inbox:manage` 等，ops 系统实际要用哪些，
  得 S12 ④ 真跑一次才知道。
- B. 直接在内嵌 postgres 里删 `principal_permission_grants` 表里这 4 行。精确，但绕过 Paperclip，没有活动记录，升级后会不会被补回来没查实。
- C. 先不删，只靠 `canCreateAgents=false`、`requireBoardApprovalForNewAgents=true` 和设置文件 deny Bash、WebFetch。
  缺点：`agents:configure` 还在，ops-system 仍可能改别的 agent 的 `dangerouslySkipPermissions`（S12 ② 验收第 9 项）。

可以直接回复「A」「B」或「C」。

## 待办

- S12 ③：log_tail、note 里有一行 `~~~~` 就能把模板的代码围栏关掉（S12 ② 验收新风险第 2 条）。要改发送端（notify-run、orca-wake），这次没改。
- S12 ③：发送方不带 Idempotency-Key，转发程序回 504 后发送方重试，可能重复叫醒（`forwarder/FAILURE-MODES.md` F19）。
- 两台 wake env 里的 URL 换成转发地址：是切换，要 Zack 批。
- S12 ④：`PAPERCLIP_RUNTIME_API_URL` 会指向转发地址，看 agent 真跑时有没有用到它（`forwarder/FAILURE-MODES.md` F21）。

## 已知限制

- 只钉了顶层包版本，依赖跟着包自己的版本范围走。重装后用 `npm ls` 再读回（`FAILURE-MODES.md` C4 是这次的读回）。
- npm 11 默认不跑依赖的安装脚本（C3），这次核对过 postgres 的符号链接都在。
- `--bare` 下用户级 `~/.claude/settings.json` 的权限设置会不会被读到，`claude --help` 没写清楚，留给 S12 ③（A24）。
- 重启 iMac 后 LaunchAgent 是否自己起来，这次没重启验证（B5）。
