# iMac 上的 Paperclip（实例 ops）

S12 ②：在 iMac 上装 Paperclip 2026.1012.0，做 ops 系统叫醒的接收端。本目录是安装、配置、读回、回退用的脚本。
先读 `FAILURE-MODES.md`：每个脚本和读回对应其中哪几条失败方式。

所有脚本在 iMac 上跑。不带参数只打印计划，加 `--apply` 才动手；可以重跑，已做好的步骤会跳过。
脚本放到 iMac 上的位置是 `~/.local/share/paperclip-ops/scripts/`（从本目录复制过去：`scp paperclip/imac/* imac:.local/share/paperclip-ops/scripts/`）。

## 装了什么、在哪

| 东西 | 位置 |
|---|---|
| paperclipai 2026.1012.0（钉死版本，`npm install --save-exact`） | `~/.local/share/paperclip-ops/app-2026.1012.0/` |
| node | `~/.nvm/versions/node/v24.22.1/bin/node`（绝对路径，不用默认的 v22） |
| 实例 `ops`（`PAPERCLIP_INSTANCE_ID=ops`） | `~/.paperclip/instances/ops/`（配置 `config.json`、数据库 `db/`、日志 `logs/`、本地密钥 `secrets/`） |
| 服务 | `127.0.0.1:3110`，local_trusted、private、只听本机；内嵌 postgres `127.0.0.1:54339`（另有 `[::1]`） |
| LaunchAgent | label `com.zhongc1211.paperclip-ops`，`~/Library/LaunchAgents/com.zhongc1211.paperclip-ops.plist`，`launchctl bootstrap gui/<uid>` 加载，开机自启 |
| company / agent | company「ops 系统」；agent `ops-system`（claude_local，暂停） |
| routine | 「ops 系统叫醒」（正式）、「S12 演练叫醒（测试）」（S12 ④ 用） |
| 触发器 | 每个 routine 一个 bearer webhook，label `ops-system-bearer`、`s12-drill-bearer`，都在 setupPending |
| 触发器 bearer、地址 | `~/.config/paperclip-ops/triggers/{ops-system,s12-drill}.{bearer,url}`（目录 700，文件 600） |
| agent 工作目录、设置文件 | `~/.paperclip/instances/ops/agent-work/ops-system/`；`.claude/ops-system-settings.json`（600，最小默认拒绝） |

不碰：`~/.paperclip/instances/default`（试装）、`~/.paperclip/cli`、`~/paperclip` 克隆、`~/.claude/settings.json`。

## 步骤

1. `install.sh [--apply]`：装 paperclipai、写 `config.json`、跑 `doctor --repair`。不起服务。
2. `serve.sh [--apply | --off]`：`tailscale serve --bg` 只挂 `/api/routine-triggers/public/`。先试 HTTPS，不行走 HTTP，地址写进 `~/.paperclip/instances/ops/serve-url`。
   **现在用不了**，见下面「要 Zack 定」。命令本身：
   - `tailscale serve --bg --https=443 --set-path /api/routine-triggers/public/ http://127.0.0.1:3110/api/routine-triggers/public/`
   - `tailscale serve --bg --http=8110 --set-path /api/routine-triggers/public/ http://127.0.0.1:3110/api/routine-triggers/public/`
   - 关：同样的参数把目标换成 `off`
3. `launchagent.sh [--apply | --bootout]`：有 serve-url 时登记 allowedHostnames、设 `PAPERCLIP_PUBLIC_URL`；渲染 plist（环境里没有 `ORCA_*`，`PAPERCLIP_API_URL` 固定本机），bootstrap。内存 `kern.memorystatus_level` 低于 20 不起。
4. `provision.sh [--apply]`：建 company、agent（建完就暂停）、设置文件、两条 routine、两个触发器（密钥直接写 600 文件，屏幕只出长度）。
5. `key-fill.sh`：Zack 填 Console API key，见 `KEY-FILL.md`。

## 读回

- iMac：`~/.local/share/paperclip-ops/scripts/readback-imac.sh`。版本、实例、配置、监听、LaunchAgent 环境键名、PATH、主机名检查、agent/routine/触发器配置、本机不带 bearer 和带错 bearer 的 401、heartbeat runs 条数、密钥文件权限和长度、Serve 状态。不打印密钥、IP、ID、PID。
  注意：它会对两个触发器各发两次被拒的 POST，Paperclip 会记 `routine.webhook_test_rejected` 活动，不起运行。
- MBA：`paperclip/imac/readback-from-mba.sh`（在仓库里直接跑）。从 tailnet 打 iMac 的 8110、443、3110、54339，看 `/`、`/api/health`、`/api/companies`、触发路径、路径穿越各回什么。
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

触发器的公开地址（含 publicId）在 `~/.config/paperclip-ops/triggers/<slug>.url`。现在里面是本机地址（`http://127.0.0.1:3110/...`），因为建触发器时还没有 Serve 地址；Serve 定了以后，对外地址 = Serve 地址 + 同样的路径。

## 回退

按顺序，在 iMac 上：

```bash
S=~/.local/share/paperclip-ops/scripts
$S/launchagent.sh --bootout                                   # 停服务、卸载 LaunchAgent
rm ~/Library/LaunchAgents/com.zhongc1211.paperclip-ops.plist
$S/serve.sh --off                                             # 撤掉本目录加的 serve（现在本来就没有）
rm -rf ~/.paperclip/instances/ops                             # 只删新实例，绝不碰 instances/default
rm -rf ~/.local/share/paperclip-ops ~/.config/paperclip-ops   # 程序、脚本、触发器密钥
```

回退后读回：`launchctl print gui/$(id -u)/com.zhongc1211.paperclip-ops` 应报找不到；`lsof -nP -iTCP:3110 -sTCP:LISTEN` 应为空；
`ls ~/.paperclip/instances` 只剩 `default`；`tailscale serve status` 不含 `/api/routine-triggers/public/`。

## 要 Zack 定：headscale 下 Serve 用不了

实测（`FAILURE-MODES.md` C1、C2）：HTTPS 被 headscale 拒（501）；HTTP 能配上，但 tailscale 1.104.1 按「Host + MagicDNS 后缀」查处理器，
在这个 headscale 的命名下永远查不到，所有请求都是 404。所以现在没开 Serve，服务只在 iMac 本机可达，MBA 的叫醒到不了。

选项：

- A. 改 headscale 的 DNS 配置（MagicDNS、base_domain），让节点有完整域名，Serve 就能按名字匹配。影响整个 tailnet 的名字解析，要在 headscale 上动手。
- B. 34B：Paperclip 改 authenticated 模式、bind 到 tailnet 地址。整个 API 和界面都对 tailnet 开放，靠登录挡。改动面大。
- C. 34C：只在 iMac 本机用，MBA 的叫醒不进 Paperclip，维持现在的叫醒方式。
- D.（推荐）在 iMac 上写一个很小的转发程序，只听 tailnet 地址的一个端口，只放行 `POST /api/routine-triggers/public/<24 位十六进制>/fire`，原样转给 `127.0.0.1:3110`，其它一律 404。效果和原计划的 Serve 一样，但是新代码，要单独派活、单独审。

定了以后：A 选完重跑 `serve.sh --apply`，再跑 `launchagent.sh --apply`（会设 `PAPERCLIP_PUBLIC_URL`、登记主机名、重启服务）；D 要另写转发程序和它的 LaunchAgent，Paperclip 这边同样用它的地址重跑 `launchagent.sh --apply`。

## 已知限制

- 只钉了顶层包版本，依赖跟着包自己的版本范围走。重装后用 `npm ls` 再读回（`FAILURE-MODES.md` C4 是这次的读回）。
- npm 11 默认不跑依赖的安装脚本（C3），这次核对过 postgres 的符号链接都在。
- `--bare` 下用户级 `~/.claude/settings.json` 的权限设置会不会被读到，`claude --help` 没写清楚，留给 S12 ③（A24）。
- 重启 iMac 后 LaunchAgent 是否自己起来，这次没重启验证（B5）。
