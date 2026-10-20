# EverOS MCP 接入标准 v2（待 Zack 批）

- 日期：2026-10-16；起草：eggbot（ops）；取代 `MCP-WIRING-STANDARD.md`（v1 草案）
- 依据：
  - pi 调研：`PI-MCP-FINDINGS.md`；
  - 心月 box 冒烟：`/workspace/xinyue-web/everos/mcp-smoke.md`；
  - 隔离测试：`PROJECT-ISOLATION-142.md`；
  - 本文的实测和审计证据：`mcp-evidence/pi-research-20261016/`（下文简称 `EV/`）。
- 写这份文档时只做了只读核对，没改任何配置。下面的命令都是**上线时**才执行，执行前要先批。
- 范围：心月、官网、广告、vllm-omni 四个项目，各自在 box、iMac 两台机器上，分别接 Claude Code 和 pi，一共 16 格。

## 0. 结论，以及和 v1 草案的不同

| 主题 | v1 草案 | v2（本文） | 依据 |
|---|---|---|---|
| Claude Code 怎么挂 | 在 worktree 的父目录放 `.mcp.json`，user 级设置里放行 `enabledMcpjsonServers:["everos"]`，不在父目录下的 checkout 用 local scope 补 | **只用 local scope，在每个 clone 的主 checkout 登记一次**。它会覆盖这个 clone 的所有 git worktree，包括以后新建的 | box 上 Orca worktree 里运行 `claude mcp get everos` 显示 `Scope: Local config`；iMac 上心月的 cicd、ci、Orca worktree、nightly 目录也一样（`EV/audit/*-pass2.txt`） |
| 父目录 `.mcp.json` 和 `enabledMcpjsonServers` | 用 | **不再用**。现有的在 local scope 验证通过后删掉。唯一可能的例外是 iMac 上 vllm-omni 的 bare 仓库（§4.2） | 同名时 local 优先，父目录这份本来就被盖掉了。user 级的放行对**任何目录**里名叫 `everos` 的 `.mcp.json` 都生效，连不受信任的 clone 也算（Claude Code 文档原话）。iMac 上广告的父目录本身就是仓库根 |
| 只读 | 「写工具不放行」，但没写怎么做到 | Claude 在 user 级 `permissions.deny` 里禁 4 个工具；pi 用 `hidden` 加 3 个只读工具 `direct` | box 上用 bypassPermissions 模式实测：不加 deny 时 7 个工具全在，加了只剩 3 个（`EV/claude-*.stream.jsonl`） |
| 启动脚本 | 照心月脚本复制，只改 ENV_FILE | **一份模板，只有 `N=` 这一行不同**。默认锁定 scope，并校验 BASE_URL 和 scope 是否齐全 | 现有脚本会被调用方的 `EVEROS_*` 环境变量改掉 scope，实测会挂到别的项目（`EV/template-probe.txt` T4） |
| pi | 待查 | **一个全局扩展 `~/.pi/agent/extensions/everos.ts`，里面一张表**，按会话 cwd 挂载，后台子 agent 不挂 | `PI-MCP-FINDINGS.md`，run1–9 |
| 读工具集 | recall、search | 两个客户端统一为 `recall_agent_experience`、`search_memory`、`list_memories`；`get_profile` 也关掉 | 避免每个编码会话一开场就把用户画像拉进来 |
| 子 worker | 「不挂」 | 挂载是按目录自动生效的，所以改成：**派 worker 时用参数关掉**，pi 后台子 agent 自动不挂（§7） | run8、run9；`EV/claude-worker-disallow.stream.jsonl` |
| 验收 | 每个项目 4 格 | 16 格加上每台机器的全局检查，证据格式统一（§11） | — |

### 0.1 本文结论的验证情况
- **已跑（box）**：
  - pi run1–9（会话 jsonl 在 `EV/sessions/`）；
  - 模板 T1–T6（`EV/template-probe.txt`）；
  - Claude 的 deny 规则和 worker 参数，各跑了一次 `claude -p`（haiku，`--settings` 临时加规则，没改设置文件）；
  - API 交叉核对，以及 4×4 查询基线；
  - box 和 iMac 两台的只读审计，共 4 轮（`EV/audit/`）。
- **没跑**：
  1. iMac 上的任何 pi 或 Claude 会话：这次任务要求只读，只查版本和配置；
  2. 模板在 macOS `/bin/bash` 3.2 上运行；
  3. Claude local scope 在**新建** worktree 上的效果：只读任务不建 worktree，已有的 worktree 已经验证过；
  4. iMac 上 bare 仓库的 local scope；
  5. Claude 会话内子 agent 的工具继承；
  6. pi 前台子 agent：只读了源码，没实际运行；
  7. §11 的 16 格验收本身：上线时再做。

## 1. 范围与固定值

### 1.1 项目 ID（不变，Zack 13:07 批）
| 项目 | N | app_id | project_id | sender/agent_id | env 文件 | 启动脚本 |
|---|---|---|---|---|---|---|
| 心月 | `xinyue` | xinyue | xinyue-site | coding-xinyue-site | `~/.config/everos/xinyue.env` | `~/.local/bin/everos-mcp-xinyue` |
| 官网 | `deepvision` | deepvision | deepvision-site | coding-deepvision-site | `~/.config/everos/deepvision.env` | `~/.local/bin/everos-mcp-deepvision` |
| 广告 | `dv-ads` | deepvision | deepvision-ads | coding-deepvision-ads | `~/.config/everos/dv-ads.env` | `~/.local/bin/everos-mcp-dv-ads` |
| vllm | `vllm-omni` | vllm-omni | vllm-omni | coding-vllm-omni | `~/.config/everos/vllm-omni.env` | `~/.local/bin/everos-mcp-vllm-omni` |

**客户端范围（2026-10-17 17:50 Zack 定，经 Coding助手 转达）：** 本标准只覆盖 Claude Code 和 pi 两个客户端。Codex 不接 EverOS：两台机器上都不给 Codex 配 everos MCP，不放 env，也不写进 Codex 的 AGENTS/配置；验收矩阵里没有 Codex 格。以后要接，要 Zack 另外批。

user_id 一律用 `zack`；`EVEROS_BASE_URL=https://everos.deepvision.sg`；MCP 的 server 名在所有项目、所有机器、两个客户端上都叫 `everos`。

### 1.2 机器 × 项目的目录（2026-10-16 审计结果；「主 checkout」就是 Claude local scope 登记的位置）
| 机器 | 项目 | 主 checkout | 它下面的 git worktree（local scope 会自动覆盖） | 其他 clone（不会自动覆盖） | pi 表里的根目录 |
|---|---|---|---|---|---|
| box | 心月 | `/workspace/repos/xinyue-site` | `~/orca/workspaces/xinyue-site/*` | — | `~/orca/workspaces/xinyue-site`、`/workspace/repos/xinyue-site` |
| box | 官网 | `/workspace/repos/deepvision-site` | `~/orca/workspaces/deepvision-site/*` | — | `~/orca/workspaces/deepvision-site`、`/workspace/repos/deepvision-site` |
| box | 广告 | `/workspace/repos/deepvision-ads` | `~/orca/workspaces/deepvision-ads/*` | — | `~/orca/workspaces/deepvision-ads`、`/workspace/repos/deepvision-ads` |
| box | vllm | `/workspace/repos/vllm-omni` | `~/orca/workspaces/vllm-omni/*` | — | `~/orca/workspaces/vllm-omni`、`/workspace/repos/vllm-omni` |
| iMac | 心月 | `~/pi/remote/xinyue-site` | `~/pi/remote/xinyue-site-cicd`、`~/pi/remote/xinyue-ci`、`~/orca/workspaces/xinyue-site/*`、`/private/tmp/nightly-xinyue-site` | `~/claude/firstmate/projects/xinyue-site` 及其 worktree `~/.treehouse/xinyue-site-eb8bcb/*/xinyue-site`（firstmate 用，pi 在这里有 7 个会话目录）→ **待定 D1** | `~/pi/remote/xinyue-site`、`~/pi/remote/xinyue-site-cicd`、`~/pi/remote/xinyue-ci`、`~/orca/workspaces/xinyue-site` |
| iMac | 官网 | `~/claude/site` | `~/orca/workspaces/site/*`（**注意** Orca 目录名叫 `site`）、`/private/tmp/nightly-deepvision-site` | — | `~/claude/site`、`~/orca/workspaces/site` |
| iMac | 广告 | `~/orca/workspaces/deepvision-ads`（Orca 父目录本身就是主 checkout） | 嵌套在它里面的 `dv广告-*`、`fdv-*` | — | `~/orca/workspaces/deepvision-ads` |
| iMac | vllm | bare 仓库 `~/pi/remote/h3-c1-lab/repository.git` | `~/orca/workspaces/repository/*` | `~/pi/remote/vllm-omni`、`~/claude/gpu/vllm-omni`（都不是 Orca 登记的仓库）→ **待定 D2** | `~/orca/workspaces/repository` |

- 不属于这四个项目、不挂的：iMac 的 `~/orca/workspaces/vllm/*` 是上游 vllm 仓库（`vllm-project/vllm`），不是 vllm-omni；两台机器上的 ops 工作区。
- nightly 目录（`/private/tmp/nightly-*`）：它们是 worktree，Claude 的 local scope 会自动覆盖；pi 表里不加。iMac 上的夜审自动化本来就是停用的。

### 1.3 版本基线（审计结果）
| 组件 | box | iMac | 要求 |
|---|---|---|---|
| Claude Code | 2.1.301 | 2.1.301 | 至少 2.1.211（从这个版本起，worktree 的信任和规则按主 checkout 记；local scope 覆盖 worktree 是在 2.1.301 上实测的） |
| pi | 1.0.4 | 1.0.4（MCP 相关源码 sha 一致） | 至少 1.0.1；两台必须同一版本 |
| everos-mcp | 0.1.1（脚本里锁死） | 同 | 升级见 §12 |
| uv | 0.13.0 | 0.11.6 | 能解析 `--from everos-mcp==0.1.1` 就行 |
| bash | 5.2 | PATH 里的是 5.3；shebang 用的 `/bin/bash` 是 macOS 自带的 3.2（没单独查版本） | 模板按 3.2 的语法写 |

## 2. 密钥存放与分发

### 2.1 位置与权限
- 每台机器、每个项目一份：`~/.config/everos/<N>.env`，权限 600，属主是当前用户。目录 `~/.config/everos` 权限 700（box 现在是 755，要改）。
- 现在四个项目用的是**同一个值**，即 site 上 nginx 的 bearer（`/etc/everos/proxy-token`）。审计时用 sha256 前缀比对，box 5 份和 iMac 3 份都是 `2bf30225`，两台一致。

### 2.2 内容（每份 6 行，不多不少；`EVEROS_AGENT_ID` 可以有，导入脚本会用，但值必须等于 sender，MCP 不读它）
```
EVEROS_BASE_URL=https://everos.deepvision.sg
EVEROS_API_KEY=<ops 系统写入，任何人不回显>
EVEROS_APP_ID=<app_id>
EVEROS_PROJECT_ID=<project_id>
EVEROS_ASSISTANT_SENDER_ID=coding-<project_id>
EVEROS_USER_ID=zack
```

### 2.3 谁放、怎么放
- 只有 ops 系统能写这些文件（唯一写入方）；dr eggbot 只读，只做核对，不写。项目 bot 和编码会话不 cat、不 echo、不复制。
- key 不能出现在命令行参数里，因为 `ps` 看得到。`printf` 和 `read` 是 shell 内建命令，不会产生新进程，所以下面的写法安全：
```bash
umask 077; mkdir -p ~/.config/everos; chmod 700 ~/.config/everos
IFS= read -r K < ~/.config/everos/.proxy-token                  # box：已有的 600 副本
# iMac：IFS= read -r K < <(ssh site 'sudo cat /etc/everos/proxy-token')
N=dv-ads APP=deepvision PROJ=deepvision-ads                       # 按 §1.1 填
printf 'EVEROS_BASE_URL=https://everos.deepvision.sg\nEVEROS_API_KEY=%s\nEVEROS_APP_ID=%s\nEVEROS_PROJECT_ID=%s\nEVEROS_ASSISTANT_SENDER_ID=coding-%s\nEVEROS_USER_ID=zack\n' \
  "$K" "$APP" "$PROJ" "$PROJ" > ~/.config/everos/$N.env
unset K; chmod 600 ~/.config/everos/$N.env
```

### 2.4 禁止放的地方
仓库、任何 `.mcp.json`、`.pi/mcp.json`、`~/.claude.json`、`~/.claude/settings*.json`、pi 的扩展和 settings、启动脚本、命令行参数、日志、证据和报告。

### 2.5 核对（不打印 key）
- 每台机器检查 key 是否一致，只打印 8 位哈希前缀。期望只有一组，并且两台机器的前缀相同：
```bash
python3 - <<'PY'
import glob, hashlib, os
g = {}
for f in glob.glob(os.path.expanduser('~/.config/everos/*.env')):
    for l in open(f):
        if l.startswith('EVEROS_API_KEY='):
            g.setdefault(hashlib.sha256(l.split('=', 1)[1].strip().encode()).hexdigest()[:8], []).append(os.path.basename(f))
print(g)
PY
```
- key 出现在配置里的次数：用 `python3 -I EV/tools/audit4.py`，它只输出次数。期望除了 `*.env` 和 `.proxy-token` 以外，其他文件全是 0。

### 2.6 轮换
1. 在 site 上换 nginx 的 token；
2. ops 系统按 §2.3 重写两台机器上的全部 env 文件（box 4 份加 `.proxy-token`，iMac 4 份）；
3. 已经开着的会话里，MCP 进程还拿着旧 key，nginx 切换后会报 401，重开会话就好；
4. 用 §2.5 核对，每台机器再按 §11 抽一格做 recall。

除 env 文件外，其他配置都不用动。

## 3. 启动脚本（统一模板 + 逐字比对）

### 3.1 位置
- `~/.local/bin/everos-mcp-<N>`，权限 755，不含密钥。
- 两台机器、四个项目一共 8 份。除了 `N=` 这一行，其余逐字节相同。

### 3.2 模板（全文）
**2026-10-17 20:30 SGT 起以 v2.2 为准：`templates/everos-mcp-launcher-v2.2.sh`（hybrid 检索 + 服务端 rerank，改动见同目录 `CHANGELOG.md`；v2.1 `everos-mcp-launcher-v2.1.sh` 留作回滚）。** 8 份脚本都从这个文件生成，只把 `N=<N>` 换成项目名。下面是 v2 原文，只留作对照，不要再照抄。

在 box 上实测过的副本是 `EV/everos-mcp-template.sh`，里面 `N=dv-ads`。
```bash
#!/bin/bash
# everos-mcp-<N>: start everos-mcp for one project (EverOS MCP wiring standard v2). Linux and macOS bash 3.2.
# All projects use this file byte for byte; only the N= line differs.
# Key and scope come only from ~/.config/everos/$N.env (mode 600); nothing is printed.
# Scope is locked to that file: EVEROS_* values inherited from the caller are dropped, unless
# EVEROS_ALLOW_SCOPE_OVERRIDE=1 (isolation tests only) lets the caller's app/project/sender/user win.
# EVEROS_MCP_SEARCH_METHOD (default keyword): everos-mcp 0.1.1 hard-codes method=hybrid, which the
# server rejects with 422 while embedding is off. Set it to "hybrid" for the stock behaviour.
set -euo pipefail
N=<N>
ENV_FILE="$HOME/.config/everos/$N.env"
BASE_URL_EXPECTED="https://everos.deepvision.sg"
[ -r "$ENV_FILE" ] || { echo "everos-mcp-$N: $ENV_FILE missing" >&2; exit 1; }
pre_app="${EVEROS_APP_ID:-}"; pre_project="${EVEROS_PROJECT_ID:-}"
pre_sender="${EVEROS_ASSISTANT_SENDER_ID:-}"; pre_user="${EVEROS_USER_ID:-}"
unset EVEROS_BASE_URL EVER_OS_BASE_URL EVEROS_API_KEY EVEROS_APP_ID EVEROS_PROJECT_ID \
  EVEROS_ASSISTANT_SENDER_ID EVEROS_USER_ID EVEROS_SESSION_ID
set -a; . "$ENV_FILE"; set +a
if [ "${EVEROS_ALLOW_SCOPE_OVERRIDE:-0}" = 1 ]; then
  [ -n "$pre_app" ] && export EVEROS_APP_ID="$pre_app"
  [ -n "$pre_project" ] && export EVEROS_PROJECT_ID="$pre_project"
  [ -n "$pre_sender" ] && export EVEROS_ASSISTANT_SENDER_ID="$pre_sender"
  [ -n "$pre_user" ] && export EVEROS_USER_ID="$pre_user"
fi
# Without these, everos-mcp would fall back to api.evermind.ai (sending our key there) or to the
# "default" scope, both silently.
[ "${EVEROS_BASE_URL:-}" = "$BASE_URL_EXPECTED" ] || { echo "everos-mcp-$N: EVEROS_BASE_URL must be $BASE_URL_EXPECTED" >&2; exit 1; }
[ -n "${EVEROS_API_KEY:-}" ] && [ -n "${EVEROS_APP_ID:-}" ] && [ -n "${EVEROS_PROJECT_ID:-}" ] &&
  [ -n "${EVEROS_ASSISTANT_SENDER_ID:-}" ] && [ -n "${EVEROS_USER_ID:-}" ] ||
  { echo "everos-mcp-$N: $ENV_FILE must set EVEROS_API_KEY, _APP_ID, _PROJECT_ID, _ASSISTANT_SENDER_ID, _USER_ID" >&2; exit 1; }
export EVEROS_MCP_SEARCH_METHOD="${EVEROS_MCP_SEARCH_METHOD:-keyword}"
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
exec uvx --quiet --from 'everos-mcp==0.1.1' python -c '
import os
from everos_mcp import client, server
m = os.environ["EVEROS_MCP_SEARCH_METHOD"]
if m != "hybrid":
    _orig = client.EverOSClient.search
    async def search(self, query, *, method="hybrid", **kw):
        return await _orig(self, query, method=m, **kw)
    client.EverOSClient.search = search
server.main()
'
```

### 3.3 逐字比对方法（两台机器通用，box 和 macOS 都有 `shasum`）
```bash
for f in ~/.local/bin/everos-mcp-*; do
  case $f in *.bak*) continue;; esac          # 跳过原地备份（*.bak-*）
  n=${f##*/everos-mcp-}
  [ "$(grep -c '^N=' "$f")" = 1 ] && [ "$(grep '^N=' "$f")" = "N=$n" ] && printf '%s N-ok ' "$n" || printf '%s N-BAD ' "$n"
  sed 's/^N=.*/N=@/' "$f" | shasum -a 256 | cut -c1-64
done
# 每一行都应该是：<n> N-ok befbd0921afc36751323e70152c382f84e4d4257b01d526c597287f8aad7a3c3   （v2.2）
bash -n ~/.local/bin/everos-mcp-<N> && echo syntax-ok     # iMac 上用 /bin/bash 3.2 再跑一遍
```
模板改动后会得到新的「规范 sha」，要把本节的值一起改掉。8 份脚本必须同时换。
- 当前规范：v2.2，模板 `templates/everos-mcp-launcher-v2.2.sh`，规范 sha `befbd092…87aad7a3c3`（2026-10-17 20:30 SGT）。「归一化」就是上面这条：`sed 's/^N=.*/N=@/'` 之后 `shasum -a 256`，不去空白、不去注释。生成方法：`sed 's/^N=<N>$/N=<n>/' templates/everos-mcp-launcher-v2.2.sh > ~/.local/bin/everos-mcp-<n>`。
- 旧值：v2.1 是 `f543542d…b39ce6`（keyword 默认）；vllm hybrid 试点草稿 A 是 `acf10e59…3ab05f7`（试点例外，已由 v2.2 取代）；v2 是 `a165609f…e15ff01a`；心月 PR #10 的样板是 `d5267256…`（过渡版，不是模板）。G1 一律按 v2.2 的 sha 判，不再拿 v2.1 的 f543542d 或试点的 acf10e59 做基准。
- 证据：v2.2 `mcp-evidence/v2.2-rollout/`（上线前 user 线门槛：xinyue、官网的 hybrid 带 atomic facts、跨项目隔离、token 0；8 份逐份换装前后 sha 和真实 MCP 调用）；v2.1 `mcp-evidence/v2.1-template/`（box stdio 实测 tailnet、Host、回落公网、只读 3 个工具；iMac `/bin/bash` 3.2 语法检查）。
- 回滚到 v2.1：每台每份 `install -m 755 ~/.local/bin/everos-mcp-<n>.bak-v21-pre-v22 ~/.local/bin/everos-mcp-<n>`（vllm-omni 的备份是试点草稿 A；要回到 v2.1 用 `everos-mcp-vllm-omni.bak-v21-pre-hybrid`），G1 改回按 f543542d 判。只想临时退回 keyword、不换脚本：在该项目 env 文件加 `EVEROS_MCP_SEARCH_METHOD=keyword`。

### 3.4 和现有脚本的差异，以及实测（box，`EV/template-probe.txt`，用 `EV/tools/mcp_probe.py` 直接跑 MCP stdio）
| 改动 | 原因 | 实测 |
|---|---|---|
| 默认锁定 scope：先 `unset` 继承来的 `EVEROS_*`；只有设了 `EVEROS_ALLOW_SCOPE_OVERRIDE=1`，调用方的值才生效 | pi 拉起 stdio server 时会继承父进程环境（源码确认，`pi-mcp/dist/transports/stdio.js:75`）。Claude Code 这点没单独验证，按常规的 stdio 启动方式也会继承。现有的 xinyue、deepvision、dv-ads 脚本让调用方的值优先 | T4：用现有的 `everos-mcp-dv-ads`，在环境里带上心月的 scope，召回到的是心月的 skill。T2：换成模板，结果仍是广告的 5 条。T3：加上 `EVEROS_ALLOW_SCOPE_OVERRIDE=1` 后能切到心月，隔离测试还可以用这个口子。T6：只覆盖 app_id 也能正常跑 |
| 去掉 `EVEROS_ENV_FILE` 覆盖 | 否则调用方可以指向别的项目的 env 文件，绕过 scope 锁 | — |
| 校验 BASE_URL 必须等于期望值 | everos-mcp 在没有 BASE_URL 时会退回 `api.evermind.ai`，并把我们的 key 带过去 | T5b、T5d（假 HOME，没有发起任何网络请求）都以 exit 1 退出 |
| 校验 5 个必填变量 | 少了 app 或 project 时，everos-mcp 会悄悄用 `default` scope | T5c 以 exit 1 退出 |
| 只有 `N=` 一行不同 | 方便逐字比对 | 规范 sha 是 v2.2 的 `befbd092…`（v2.1 的 `f543542d…`、v2 的 `a165609f…` 已作废） |
| 其余部分（锁版本、keyword 补丁、PATH）和心月脚本一样（v2.2 起 keyword 补丁换成 hybrid 检索补丁，见 CHANGELOG） | — | T1：7 个工具，召回到广告 5 条 |

没跑：模板没在 macOS `/bin/bash` 3.2 上运行过（这次只做只读核对）。上线时在 iMac 上跑 `bash -n` 和 §11 的一格。

## 4. Claude Code 挂载

### 4.1 采用 local scope，在每个 clone 的主 checkout 登记一次
```bash
cd <主 checkout> && claude mcp add -s local everos -- "$HOME/.local/bin/everos-mcp-<N>"
```
- 写进 `~/.claude.json` 的 `projects[<主 checkout>].mcpServers.everos`，`command` 是展开后的绝对路径，没有 `env`。local scope 不需要审批。
- **覆盖范围**：主 checkout 本身、它的子目录、以及这个 clone 的所有 `git worktree`。Orca 的 worktree 就是这样建出来的，所以以后新建的也包括在内。实测证据：
  - box 上 `~/orca/workspaces/*/<wt>`（git common dir 是 `/workspace/repos/<repo>/.git`）显示 `Scope: Local config`；
  - iMac 上心月的 `xinyue-site-cicd`、`xinyue-ci`、`~/orca/workspaces/xinyue-site/*`、`/private/tmp/nightly-xinyue-site` 都只靠主 checkout 那一条就连上了。
- Claude Code 的文档对 MCP local scope 和 worktree 的关系没有明说，只写了信任和规则「按 worktree 解析到主 checkout」（2.1.211 起）。所以每次升级 Claude Code 后都要按 §11 G5 复核一次。
- 不覆盖的情况：独立的 clone（要在它自己的根目录再登记一次），以及 bare 仓库（见 4.2）。

逐格要执行的命令（「已有」表示审计时已经在了）：
| 机器 | 项目 | 命令所在目录 | 现状 |
|---|---|---|---|
| box | 心月 | `/workspace/repos/xinyue-site` | 已有 |
| box | 官网 | `/workspace/repos/deepvision-site` | 已有 |
| box | 广告 | `/workspace/repos/deepvision-ads` | 已有 |
| box | vllm | `/workspace/repos/vllm-omni` | **缺**（脚本和 env 已在） |
| iMac | 心月 | `~/pi/remote/xinyue-site` | 已有 |
| iMac | 官网 | `~/claude/site` | **缺**，脚本和 env 也缺 |
| iMac | 广告 | `~/orca/workspaces/deepvision-ads` | **缺**（现在靠父目录 `.mcp.json`） |
| iMac | vllm | 在 `~/orca/workspaces/repository/<任一 worktree>` 里执行 | **缺**（现在靠父目录 `.mcp.json`）。是 bare 仓库，见 4.2 |

### 4.2 父目录 `.mcp.json`：不再用
- 不再新建。现有的几份（box：xinyue-site、deepvision-site、deepvision-ads 三个 Orca 父目录；iMac：xinyue-site、deepvision-ads、repository），等对应格子的 local scope 按 §11 G5 验证通过后删除。删之前先复制到证据目录。
- 理由：
  - 有 local 时它就被盖掉了（Claude 的优先级是 local > project > user），留着只会造成误解；
  - iMac 上广告的父目录就是仓库根，那份 `.mcp.json` 实际在工作树里，现在靠 `.git/info/exclude` 才没被提交；
  - 它需要审批机制，也就是下面 4.3 那个有安全坑的设置。
- **唯一可能的例外：iMac vllm 的 bare 仓库**。
  - `~/.claude.json` 里已经有一条 key 是 `~/pi/remote/h3-c1-lab/repository.git`，说明 Claude 把它的 worktree 都归到了 bare 目录名下，local scope 很可能也能覆盖；但没实测。
  - 上线时先在一个 worktree 里执行 `claude mcp add -s local`，再到**另一个已有的 worktree** 和**一个新建的 worktree** 里运行 `claude mcp get everos`，都显示 `Local config` 就删掉父目录那份。
  - 如果显示的不是 `Local config`，就保留父目录 `.mcp.json`，并且只对这个项目单独批准：在该项目的交互会话里批准一次，批准结果记在 `~/.claude.json` 这个项目的 `enabledMcpjsonServers` 里。**不要**用 user 级的放行。

### 4.3 `enabledMcpjsonServers`：从 user 级设置里去掉 `everos`
- Claude Code 文档原话：user `~/.claude/settings.json` 里的放行 “still apply in an untrusted folder”。也就是说，任何目录（包括刚 clone 下来、还没信任的第三方仓库）里只要 `.mcp.json` 有个叫 `everos` 的 server，就会自动执行它的 command。
- 4.2 删完父目录 `.mcp.json` 以后它就没用了，两台机器都去掉（命令见 4.5）。

### 4.4 只读：在 user 级设置里禁 4 个工具（两台机器都要加）
```json
"permissions": { "deny": ["mcp__everos__add_memory", "mcp__everos__record_trajectory", "mcp__everos__forget_session", "mcp__everos__get_profile"] }
```
- 文档原话是 “Deny rules block in every mode, including bypassPermissions”。只写裸工具名时，这个工具会直接从模型的上下文里拿掉，模型根本看不到。不要写成带括号的 `mcp__` 规则，那种会被跳过。
- 实测：box 上的广告 worktree，`--permission-mode bypassPermissions` 模式下，用 `--settings` 临时加上这条规则（没有改设置文件）。init 事件里的 everos 工具从 7 个变成 3 个（`EV/claude-nodeny.stream.jsonl` 对比 `EV/claude-deny.stream.jsonl`）。
- 审计时两台机器都**没有**这条规则。box 上的会话在 bypass 模式下，写工具全都能调；iMac 的 `defaultMode` 是 `auto`，要由分类器判断，结果不确定。

### 4.5 命令（先备份）
```bash
cp -p ~/.claude.json ~/.claude.json.bak-everos-v2-$(date +%Y%m%d)
cp -p ~/.claude/settings.json ~/.claude/settings.json.bak-everos-v2-$(date +%Y%m%d)
# 4.4：加 deny（随时可以做，不依赖其他步骤）
python3 - <<'PY'
import json, os
p = os.path.expanduser('~/.claude/settings.json'); d = json.load(open(p))
deny = d.setdefault('permissions', {}).setdefault('deny', [])
for t in ['mcp__everos__add_memory', 'mcp__everos__record_trajectory', 'mcp__everos__forget_session', 'mcp__everos__get_profile']:
    if t not in deny: deny.append(t)
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2); open(p, 'a').write('\n')
PY
# 4.3：要等这台机器上所有父目录 .mcp.json 都已删除（或已经按 4.2 的例外单独批准）之后再做
python3 - <<'PY'
import json, os
p = os.path.expanduser('~/.claude/settings.json'); d = json.load(open(p))
s = d.get('enabledMcpjsonServers') or []
if 'everos' in s: s.remove('everos')
if not s: d.pop('enabledMcpjsonServers', None)
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2); open(p, 'a').write('\n')
PY
claude mcp get everos      # 分别在主 checkout、一个已有 worktree、一个新 worktree 里运行，都应显示 Scope: Local config 和本项目的脚本
```

## 5. pi 挂载（调研后定下的唯一写法）

### 5.1 写法：一个全局扩展，里面一张表
- 文件是 `~/.pi/agent/extensions/everos.ts`，两台机器逐字节相同。这份文件不含密钥。
- 目前在 box 上测过的版本：`EV/everos.ts`，sha256 `743e3d27d88e7d77f3a52fac4371dbd13b95091baad84772e86453f7516214fd`。
- 只有 ops 系统能改表，改完两台机器一起换，并比对 sha。
```ts
// Pi user extension (EverOS MCP wiring standard v2): ~/.pi/agent/extensions/everos.ts, same bytes on box and iMac.
// Mounts the EverOS MCP server "everos" for the project that owns the session's working directory, read-only.
// Each project's wrapper is ~/.local/bin/everos-mcp-<N> (key and scope from ~/.config/everos/<N>.env).
// Nothing secret here.
import { realpathSync } from "node:fs";
import { homedir } from "node:os";

const H = homedir();
// [root, N]: a session whose cwd is the root or below it gets project N. Roots missing on a machine never match.
const PROJECTS: ReadonlyArray<readonly [string, string]> = [
  // xinyue-site
  [`${H}/orca/workspaces/xinyue-site`, "xinyue"],
  ["/workspace/repos/xinyue-site", "xinyue"],
  [`${H}/pi/remote/xinyue-site`, "xinyue"],
  [`${H}/pi/remote/xinyue-site-cicd`, "xinyue"],
  [`${H}/pi/remote/xinyue-ci`, "xinyue"],
  // deepvision-site
  [`${H}/orca/workspaces/deepvision-site`, "deepvision"],
  ["/workspace/repos/deepvision-site", "deepvision"],
  [`${H}/orca/workspaces/site`, "deepvision"],
  [`${H}/claude/site`, "deepvision"],
  // deepvision-ads
  [`${H}/orca/workspaces/deepvision-ads`, "dv-ads"],
  ["/workspace/repos/deepvision-ads", "dv-ads"],
  // vllm-omni
  [`${H}/orca/workspaces/vllm-omni`, "vllm-omni"],
  ["/workspace/repos/vllm-omni", "vllm-omni"],
  [`${H}/orca/workspaces/repository`, "vllm-omni"],
];

function real(p: string): string {
  try { return realpathSync(p); } catch { return p; }
}

function projectOf(cwd: string): string | undefined {
  const p = real(cwd);
  for (const [root, n] of PROJECTS) {
    const r = real(root);
    if (p === r || p.startsWith(r + "/")) return n;
  }
  return undefined;
}

function server(n: string) {
  return {
    command: `${H}/.local/bin/everos-mcp-${n}`,
    args: [],
    description: `EverOS lessons for ${n}: recall before starting work`,
    exposure: "hidden",
    toolExposure: { recall_agent_experience: "direct", search_memory: "direct", list_memories: "direct" },
    timeout: 90,
  };
}

export default function (pi: any) {
  // Background pi-subagents children run with PI_SUBAGENT_CHILD=1. Workers do not mount; the parent recalls.
  if (process.env.PI_SUBAGENT_CHILD === "1") return;
  // A normal start runs in the session's directory: register at load, so the server connects with the
  // session and its tools are declared in the first request.
  let mounted = projectOf(process.cwd());
  if (mounted) pi.registerMcpServer("everos", server(mounted));
  // --session, --resume, /resume and fork can open a session from another directory (pi never chdirs).
  // ctx.cwd is the session's directory: follow it.
  pi.on("session_start", (_event: unknown, ctx: { cwd: string }) => {
    const want = projectOf(ctx.cwd);
    if (want === mounted) return;
    if (mounted) pi.unregisterMcpServer("everos");
    if (want) pi.registerMcpServer("everos", server(want));
    mounted = want;
  });
}
```
为什么这么写（详见 `PI-MCP-FINDINGS.md`）：
- 项目级的 `.pi/` 只认 cwd 本层，还要信任项目，新 worktree 不会自动带上；
- 全局 `mcp.json` 没法按项目切换；
- 按 `process.cwd()` 判断，跨项目 resume 时会挂错（run3）；
- 加载时先按 `process.cwd()` 注册，保证第一次请求就带上工具（run4、run7）；`session_start` 时再按 `ctx.cwd` 校正，跨项目打开的会话也挂对（run6）；
- 后台子 agent 不挂（run8）。

### 5.2 安装和迁移（每台机器一步做完，不能拆开）
```bash
cp -p ~/.pi/agent/extensions/everos-dv-ads.ts <证据目录>/ 2>/dev/null   # 只有 box 有
install -m 644 <规范副本>/everos.ts ~/.pi/agent/extensions/everos.ts && rm -f ~/.pi/agent/extensions/everos-dv-ads.ts
shasum -a 256 ~/.pi/agent/extensions/everos.ts      # 应为 743e3d27…（表有改动的话以新 sha 为准）
```
- 新旧两个扩展**不能同时存在**。两个都会注册 `everos`，后加载的那个会抛错，整个扩展加载失败。
- box 上 deepvision-site FDV-68 worktree 里的 `.pi/mcp.json` 要删掉，删之前复制到证据目录。
  - 删的原因：同名时 `mcp.json` 优先，它会把扩展盖掉；而且它的 `exposure:"direct"` 会把写工具也直接给模型。
  - `~/.pi/agent/trust.json` 里 `deepvision-site` 那两条信任，是专门为这份文件加的。它们让 deepvision-site 下所有 worktree 里的 `.pi/extensions` 都会自动执行。和官网 bot 确认后删掉。
- 「规范副本」：建议上线前由 ops 系统把 `everos.ts`、模板和 `EV/tools/` 提 PR 放进 ops 仓库（比如 `everos/mcp/`），两台机器都从那里取，用 sha 核对。在那之前，以 `EV/` 里的副本为准。

### 5.3 不允许的写法（列进验收 G4）
- `~/.pi/agent/mcp.json` 里有 `everos`：会对所有目录生效；
- 任何 `.pi/mcp.json` 里有 `everos`：会覆盖扩展；
- 每个项目单独一个 `everos-<N>.ts`；
- server 名不叫 `everos`。

### 5.4 iMac 的 pi 在 codemode-only 模式下的影响
- iMac 的 `~/.pi/agent/settings.json` 设了 `codemode.mode:"only"`。direct 工具对模型也是隐藏的，模型要通过 `codemode` 脚本里的 `tools.mcp__everos__recall_agent_experience({task})` 来调用。
- 只读不受影响：hidden 的工具在 codemode 里同样不可达，`ALL_TOOLS` 里也不会列出来。
- 验收提示要相应改写（§11.4）。

### 5.5 「开工前 recall」要写进 AGENTS 或派活规矩
- pi 不会把只有 direct 工具的 server 的 instructions 放进系统提示。Claude 能看到 instructions，但那里面让模型调 `get_profile` 和写工具，而这些已经被禁了。所以两个客户端都要靠文字规矩来要求 recall。
- 每个项目的 AGENTS.md（或 dev-bot-rules 的派活段）加一句：「动手前调用 EverOS `recall_agent_experience`（task 写几个关键词），冲突时以本文件为准；不要调写入类 everos 工具。」
- 各项目现状（只看了 box 上本地的 git，没有 fetch）：
  - 心月：`4f76e2e docs(AGENTS): recall EverOS before starting dispatched work, parent briefs sub-workers` 在分支 `zhongc1211/docs-lessons-everos-box` 上；
  - 官网：`5ea2ae5`、`ec5a579` 在分支 `zhongc1211/dv运维-FDV-68-EverOS接入` 上；
  - 这两个是否已经合进主干，本次没核实；
  - 广告和 vllm：本地没找到相应提交。
  - 上线前要逐个确认合进主干。

## 6. 只读权限与写入通道
| 通道 | 谁 | 能做什么 |
|---|---|---|
| 编码会话（Claude 和 pi，父会话） | 派活对着的会话 | 只能用 `recall_agent_experience`、`search_memory`、`list_memories`。`add_memory`、`record_trajectory`、`forget_session`、`get_profile` 在两个客户端都不可达（§4.4、§5.1） |
| 夜审写入 | box 上的自动化 `75b324a4`（心月）；其他项目以后照做 | HTTP `/api/v2/memory/add` 加 `/flush`（`nightly_addflush.py`），key 从 env 文件读 |
| LESSONS / skill 导入 | ops 系统（唯一写入方；dr eggbot 只读，只做查询/核对） | 在 site 上用 `AgentSkillWriter.write_main`，脚本先在 ops 里审过（`PROJECT-ISOLATION-142.md` P2）；写之前备份，写完核对 |
| 收工回写（`record_trajectory`） | 还没开 | 要开的话 Zack 单独批，然后同时改：Claude 的 deny、pi 的 `toolExposure`、模板的版本号 |

- 限制：nginx 只有一个 bearer，服务端不按项目鉴权。拿到 key 的任何进程都能用 curl 读写任意 scope。客户端的 scope 隔离靠的是脚本锁和每个项目各自的 env 文件。
- 以后如果要在服务端也隔离，在 nginx 上按 token 限定 `app_id`/`project_id` 就行，需要另开任务。

## 7. 父会话 / 子 worker 规则
挂载是按目录**自动**生效的，所以「worker 不挂」得在派 worker 的时候做。

| 情形 | 会不会挂 | 要做什么 | 证据 |
|---|---|---|---|
| bot 派活对着的 Orca 会话（父会话） | 挂 | 开工前 recall，把相关 skill 写进给 worker 的 brief | — |
| pi 后台子 agent（pi-subagents async） | 不挂（扩展看到 `PI_SUBAGENT_CHILD=1` 就跳过） | 不用做 | run8 |
| pi 前台子 agent | 不挂（pi-subagents 的前台子进程不加载外部扩展；box 0.76.1 源码，iMac 0.78.0 grep 确认） | 不用做 | `PI-MCP-FINDINGS.md` §4 |
| 父会话自己开的 pi worker 进程 | 会挂 | 启动参数加 `--exclude-tools 'mcp__everos__*'` | run9 |
| 父会话自己开的 Claude worker 进程（比如 `orca terminal create --command 'claude …'`） | 会挂 | 启动参数加 `--disallowedTools mcp__everos`（裸 server 名会把它的工具全拿掉） | `EV/claude-worker-disallow.stream.jsonl`：server 已连上，但工具 0 个 |
| Claude 会话内的子 agent（Agent 工具） | 继承父会话的工具 | brief 里写明「不要调用 mcp__everos__*」；如果是自定义的子 agent，可以在定义里写 `disallowedTools: mcp__everos` | 没跑 |
| 用 `orca worktree create --agent …` 派的 worker（加不了参数） | 挂（只读） | 靠 brief 里的规矩约束 | — |
| 两个同级的 Orca 工作区（分别对应两个 Linear 任务） | 各自挂 | 不用做 | — |

## 8. 新 worktree 怎么自动生效
| 情况 | Claude Code | pi |
|---|---|---|
| Orca 从已登记的主 checkout 新建 worktree | 自动生效（local scope 跟着主 checkout） | 自动生效，前提是它在表里某个根目录下面。Orca 的 worktree 都在 `~/orca/workspaces/<repo>/` 下，已在表里 |
| 在已登记 clone 的仓库里手动 `git worktree add` 到别的路径 | 自动生效 | 不生效，要往表里加一行 |
| 新出现的独立 clone 或主 checkout | 要在它的根目录 `claude mcp add -s local` | 要往表里加一行 |
| bare 仓库的 worktree（iMac vllm） | 按 4.2 验证后才能确定 | 自动生效（在 `~/orca/workspaces/repository` 下面） |
| 新机器或换了目录结构 | 两边都要重新登记，并重跑 §11 | 同左 |

## 9. 上线步骤（Zack 批了之后；顺序按 v1 §7，心月先做出样板）
1. Zack 拍板：本文 §0 的几处改动，以及 D1（iMac firstmate/treehouse 的心月 clone 挂不挂）、D2（iMac 上 vllm-omni 另外两个 clone 挂不挂）。
2. eggbot 处理密钥：`~/.config/everos` 改成 700；iMac 补上 `deepvision.env`（官网上 iMac 时再补）；按 §2.5 核对。
3. eggbot 换脚本：两台机器上已有的 7 份脚本全部换成模板，iMac 再新增 `everos-mcp-deepvision`；每一份都跑一次 §3.3 的比对和 `mcp_probe` 的 T1、T2；每台机器先跑一次，把 uv 缓存热起来。
4. Claude：
   - 每台机器先做 §4.4 的 deny；
   - 再按 §4.1 的表补 local scope，并按 G5 验证；
   - 验证通过后删父目录 `.mcp.json`（4.2）；
   - 最后去掉 `enabledMcpjsonServers`（4.3）。
5. pi：两台机器按 §5.2 一次做完；删掉 FDV-68 的 `.pi/mcp.json`；trust 的两条和官网 bot 确认后再删。
6. 规矩：每个项目都要有 §5.5 那一句；dev-bot-rules 的派 worker 段加上 §7 的两个参数。
7. 验收：按 §11 逐格跑，结果写进 `mcp-evidence/GRID.md`；不通过的格子不宣布上线。

## 10. 回滚
- **改之前都先备份**：
  - `~/.claude.json` 和 `~/.claude/settings.json` 按 4.5 备份；
  - 旧脚本改名为 `everos-mcp-<N>.bak-v1`；
  - 旧扩展、父目录 `.mcp.json`、FDV-68 的 `.pi/mcp.json` 都复制到证据目录。
- **某个项目在某台机器上关掉**：
  - Claude：在主 checkout 里运行 `claude mcp remove -s local everos`；
  - pi：两台机器都从表里删掉那一行，然后重新比对 sha。
- **所有项目一起紧急关掉**：
  - Claude：在 user 级 deny 里加一个裸的 `"mcp__everos"`，所有项目的 everos 工具都会被拿掉。新会话肯定生效；已经开着的会话，按文档说从下一次工具调用起也会生效。
  - pi：`mv ~/.pi/agent/extensions/everos.ts ~/.pi/agent/everos.ts.off`，移出扩展目录。已经开着的会话要 `/reload` 或重开才会生效。
- **整体退回 v1**：
  - 用备份恢复 `~/.claude.json`、`settings.json` 和旧脚本；
  - 从证据目录放回父目录 `.mcp.json` 和 `everos-dv-ads.ts`；
  - 删掉 `everos.ts`。
  - 服务端没有任何改动，所以不用回滚。
- **只想去掉 deny**：从 `permissions.deny` 里删掉那 4 项。

## 11. 验收（逐格清单 + 证据格式）

### 11.1 每台机器的全局检查（只读，不调用模型）
| # | 检查 | 通过标准 |
|---|---|---|
| G1 | §3.3 脚本比对 | 4 份都是 `N-ok`，规范 sha 一致；`bash -n` 通过 |
| G2 | §2.5 密钥 | 每份 env 都是 600，目录 700，6 个必需的 key 齐全；key 哈希只有一组，两台机器前缀相同 |
| G3 | `EV/tools/audit4.py` | 除 env 和 `.proxy-token` 以外，所有配置里 key 出现次数为 0 |
| G4 | pi | `everos.ts` 的 sha 等于规定值；没有残留的 `everos-*.ts`；`~/.pi/agent/mcp.json` 和工作区下所有 `.pi/mcp.json` 里都没有 `everos`，即 `grep -l everos ~/.pi/agent/mcp.json $(find ~/orca/workspaces ~/pi/remote ~/claude /workspace/repos -maxdepth 4 -path '*/.pi/mcp.json' 2>/dev/null) 2>/dev/null` 输出为空 |
| G5 | Claude | 每个项目在「主 checkout、一个已有 worktree、一个新建 worktree」三处运行 `claude mcp get everos`，都显示 `Scope: Local config`，Command 是本项目的脚本；user 级没有 everos；`enabledMcpjsonServers` 里没有 `everos`；没有父目录 `.mcp.json`，例外须已记录；deny 里有那 4 项 |
| G6 | 对照目录 | 在 ops worktree 和一个无关仓库里，`claude mcp get everos` 应找不到；pi 会话里没有 everos 工具 |
| G7 | worker | Claude 加 `--disallowedTools mcp__everos` 后 everos 工具为 0；pi 设 `PI_SUBAGENT_CHILD=1` 后为 0；pi 加 `--exclude-tools 'mcp__everos__*'` 后为 0 |

### 11.2 16 格（每格一个新会话）
各项目的查询词和期望 id：用 API keyword 搜索得到的基线，见 `EV/acceptance-query-matrix.txt`。

| 项目 | 查询词 Q | 必须出现的 id | 对照（换到别的项目的 worktree 里跑同一个 Q） |
|---|---|---|---|
| 心月 | `切流量 绑定` | `coding-xinyue-site_check-bindings-before-shifting-production-traffic` | 在官网的 worktree 里跑 |
| 官网 | `tailwind` | `coding-deepvision-site_tailwind-v4-custom-theme-tokens` | 在广告的 worktree 里跑 |
| 广告 | `cf CLI` | `coding-deepvision-ads_use-cf-cli-not-wrangler` | 在心月的 worktree 里跑 |
| vllm | `NCCL` | `coding-vllm-omni_secure-h100-nccl-nvls-and-pod-loss` | 在广告的 worktree 里跑 |

隔离的判断标准是：**返回的 id 全部以本会话所在项目的 `coding-<project_id>_` 开头**，**不是**「0 条」。keyword 搜索在别的 scope 里也可能命中那个 scope 自己的 skill，比如 `切流量 绑定` 在 vllm 的 scope 里会命中 vllm 自己的那 1 条（`EV/acceptance-query-matrix.txt`）。

16 格 = 4 个项目 × {box, iMac} × {Claude, pi}。每格都要在本项目的一个 Orca worktree 里跑 Q，再在对照项目的 worktree 里跑同一个 Q。

### 11.3 Claude 格
提示（把 `<Q>` 换成查询词）：
```
这是只读验收。只调用 mcp__everos__recall_agent_experience 一次，参数 {"task": "<Q>"}，不调用任何其他工具。
然后回复：第一行 "TOOLS:" 加上你拥有的全部 mcp__everos__ 开头的工具名（逗号分隔）；之后每行一个返回结果里的 skill 名（照抄 " (confidence" 之前的部分）。
如果没有 mcp__everos__recall_agent_experience，就不调用工具，只回复 "TOOLS:"（同上）和一行 NO_EVEROS_TOOLS。不要编造。
```
```bash
cd <worktree> && claude -p "$(cat prompt.txt)" --model sonnet --permission-mode bypassPermissions \
  --disallowedTools 'Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch' --no-session-persistence \
  --output-format stream-json --verbose > session.jsonl
python3 -I EV/tools/xcheck.py ~/.config/everos/<N>.env "<Q>" > xcheck.json      # API 交叉核对：同一个 Q，同一个 scope
```
通过条件：
- init 事件的 `tools` 里，everos 工具恰好是 `recall_agent_experience`、`search_memory`、`list_memories` 这 3 个；
- 只有一次 `tool_use`，就是 recall；
- 结果里有期望的 skill 名，并且和 `xcheck.json` 的条数、顺序一致；
- 对照跑的结果里只有对照项目的 id。

### 11.4 pi 格
提示：box 用 §11.3 同一条（`EV/prompt.txt` 的格式）；iMac 用下面这条 codemode 版。
```
这是只读验收。用 codemode 运行一次脚本：先 text() 输出 ALL_TOOLS 里名字以 mcp__everos__ 开头的工具名（逗号分隔），
再 await tools.mcp__everos__recall_agent_experience({task: "<Q>"}) 并 text() 它 content 里的文字。不要调用其他工具。
然后回复：第一行 "TOOLS:" 加上那串工具名；之后每行一个 skill 名（照抄 " (confidence" 之前的部分）。没有这个工具就回复 NO_EVEROS_TOOLS。
```
```bash
cd <worktree> && env -i HOME="$HOME" PATH="$PATH" LANG=C.UTF-8 TERM=dumb pi --mode json \
  --session-dir <证据目录>/sessions --tools 'mcp__everos__*' "$(cat prompt.txt)" > events.jsonl          # box
# iMac：--tools 'codemode,mcp__everos__*'，用 codemode 版的提示
python3 -I EV/tools/parse_pi_session.py <证据目录>/sessions/<文件>.jsonl
```
通过条件：
- box：第一条 system 消息的 `toolsAdded` 恰好是那 3 个 everos 工具；
- iMac：`ALL_TOOLS` 输出里恰好是那 3 个；codemode 那次结果的嵌套调用字段里有（pi 1.0.4 的会话文件里叫 `details.calls`，不叫 `nestedCalls`） `mcp__everos__recall_agent_experience`；
- skill 名和 `xcheck.json` 一致；对照跑只出现对照项目的 id。

`env -i` 的作用：不让 Orca 的状态扩展上报，也不让调用方的 `EVEROS_*` 混进来。会话文件放在证据目录，避免污染 worktree 的会话列表。

### 11.5 证据格式
```
mcp-evidence/
  GRID.md                         16 格加 G1–G7 的总表：通过/失败/没跑，失败或没跑要写原因，并链到每格的 RESULT.md
  global-<box|imac>.txt           G1–G7 的原始输出（已过 redact）
  <N>/<box|imac>-<claude|pi>/
    RESULT.md                     一页
    prompt.txt
    session.jsonl | events.jsonl + sessions/<id>.jsonl
    xcheck.json                   API 交叉核对（本项目 Q；对照 Q）
    mount.txt                     claude mcp get everos 的三处输出，或者 pi 的 toolsAdded 摘要
```
RESULT.md 要写的字段：
- 日期时间（SGT）、机器、客户端和版本、everos-mcp 版本；
- 脚本的规范 sha、`everos.ts` 的 sha；
- worktree 路径和 `git rev-parse HEAD`（完整 sha）；
- 跑的命令（原样）、Q、期望 id、实际得到的 skill 名和 id；
- 对照跑的 id、声明的工具；
- 结论：通过 / 失败（附报错原文）；
- 没跑的项逐条写「没跑」和原因；
- token 命中数。

**每格都必须做 token 检查**，对证据目录运行下面的命令，结果必须是 0：
```bash
python3 - <<'PY'
import glob, os
k = [l.split('=', 1)[1].strip() for f in glob.glob(os.path.expanduser('~/.config/everos/*.env')) for l in open(f) if l.startswith('EVEROS_API_KEY=')]
print(sum(open(p, errors='ignore').read().count(x) for p in glob.glob('mcp-evidence/**/*', recursive=True) if os.path.isfile(p) for x in set(k)))
PY
```

## 12. embedding 开启后的升级路径
1. **服务端**：Zack 定 embedding 的来源（magpie 代理或 OpenRouter，涉及花费的要先报预算）。
   - 在 EverOS 里开 `[embedding]`，按上游文档给已有的 episode 和 skill 补向量，并核对 cascade 的计数不变；
   - 对 4 个 scope 用 curl 跑 `method=hybrid` 的 search，都要返回 200 且有结果。
2. **单项目试点**：在某台机器上，给某个项目的 env 文件加一行 `EVEROS_MCP_SEARCH_METHOD=hybrid`。模板里是 `${…:-keyword}`，env 里的值会生效，所以不用改脚本。
   - 跑这一格的 §11，再加几个语义类的查询词，和 keyword 的结果对比。
3. **全部切换**：出一个新版本模板，删掉 `python -c` 那段 monkeypatch，改成 `exec uvx --quiet --from 'everos-mcp==0.1.1' everos-mcp`。
   - wrapper 本身要保留，读 key、锁 scope、校验这些还靠它；
   - 得到新的规范 sha，更新 §3.3；
   - 8 份脚本同时换，再把 16 格全部重跑一遍。
4. **everos-mcp 升级**：出了 0.1.1 以后的版本时，先看 `EverOSClient.search` 的签名和有没有提供检索方式的配置；用 `mcp_probe.py` 测过，再改模板里锁的版本号，同样走第 3 步的流程。
5. **自动抽 skill**：有了 embedding，服务端可以开 skill_extraction 或 OME 来自动抽 skill。这还是服务端的写入通道，编码会话的写工具继续禁用。收工回写见 §6。
6. 同步更新 HANDOFF §2 和 PLAN 里关于 keyword 的说明。

**进度（2026-10-17）**：第 1 步完成（embedding 19:03、补向量、rerank 20:18:21 起 `rerank:true`）。第 2 步实际做法是换 vllm 一份启动脚本（试点草稿 A，没用 env 行），20:20–20:25 通过（`mcp-evidence/vllm-omni/hybrid-pilot/RESULT.md`）。第 3 步按 v2.2 做，但**保留** `python -c` wrapper、不改成直接 `exec everos-mcp`：0.1.1 的 `search_memory` 会丢掉 1.4.2 hybrid 结果里嵌在 episode 下的 atomic facts，wrapper 把它们补进输出，另外还管只读、Host、scope 过滤和 search.log。hybrid **不带** `enable_llm_rerank`（服务端 rerank）。`method=vector` 不用（不返回 atomic facts）。

## 13. 已知坑
1. 照 HANDOFF §2 原样挂 `uvx everos-mcp`，在开 embedding 之前每次都会 422（everos-mcp 写死了 hybrid）。必须走 wrapper。现在 embedding、rerank 都开了，原样挂不再 422，但仍不能用：会把写工具给模型、丢 atomic facts、不带 Host（v2.2 wrapper 处理这些）。服务端 rerank 一旦关掉，agent 线 hybrid 会回到 422，此时在 env 文件加 `EVEROS_MCP_SEARCH_METHOD=keyword`。
2. env 文件里没有 BASE_URL 时，everos-mcp 会退回 `api.evermind.ai`，把 key 发到外部；少了 app 或 project 时，会悄悄用 `default` scope。模板已加校验（§3.4）。
3. 调用方导出的 `EVEROS_*` 会传进 MCP 进程（pi 已从源码 `stdio.js:75` 确认；Claude Code 没单独验证）。旧脚本会被它改掉 scope（T4）。
4. pi 不 `chdir`，所以 `process.cwd()` 不等于会话的 cwd。跨项目 `--session`、`-r`、`/resume` 时会挂错（run3）。
5. pi 里同名的 `.pi/mcp.json` 会覆盖扩展（FDV-68 那份会把写工具也直接给模型）；`pi mcp list` 看不到扩展注册的 server。
6. pi 第一次请求只等 10 秒；uv 缓存是冷的话，第一轮拿不到工具。上线时先把缓存热起来。
7. iMac 的 pi 是 codemode-only 模式，工具要经 codemode 调用，验收提示不同（§11.4）。
8. 新旧 pi 扩展同时存在时会因为 `everos` 重名而加载失败（§5.2）。
9. Orca 会覆盖 `orca-` 前缀的 pi 扩展，自己写的扩展不要用这个前缀。
10. user 级的 `enabledMcpjsonServers:["everos"]` 对任何目录都放行，连不受信任的 clone 也算（§4.3）。
11. iMac 上广告的父目录就是主 checkout，那里的 `.mcp.json` 在仓库工作树里，靠 `.git/info/exclude:9` 才没被提交。
12. 「local scope 覆盖 worktree」是在 2.1.301 上实测的，文档没写。每次升级 Claude Code 都要复核 G5。bare 仓库的情况还没测（§4.2）。
13. 独立 clone 不在覆盖范围内：iMac 上 firstmate、treehouse 的心月 clone（D1），`~/pi/remote/vllm-omni` 和 `~/claude/gpu/vllm-omni`（D2）。
14. everos-mcp 的 instructions 会让模型一开场就调 `get_profile`，还会调写工具。这些在 Claude 里已经被 deny 从上下文里拿掉，pi 根本看不到 instructions。recall 只能靠 §5.5 的规矩。
15. keyword 搜索在任何 scope 都可能命中那个 scope 自己的、不相关的 skill。隔离的判断标准是 id 前缀，不是 0 条（§11.2）。
16. 服务端只有一个 bearer，scope 隔离只靠客户端（§6）。
17. Claude 的 deny 规则里，`mcp__` 规则带括号会被跳过；只能用裸工具名，或者用裸 server 名 `mcp__everos`。
18. 审计脚本不能打印无关的 `.mcp.json`。这次第一轮审计在 iMac 上就打出了一个与 EverOS 无关的明文 secret，详见 `PI-MCP-FINDINGS.md` §5 第 8 条。`EV/tools/audit.py` 已改成只打印含 everos 的文件。
19. episode id（如 `zack_ep_20261017_00000001`）在不同 scope 里会重复，是各自的记录（v2.2 门槛实测：心月和官网同一 id 串是不同 session）。隔离按返回项的 `app_id/project_id` 判，不按 id。

---

## 附录 A：心月现状审计（box + iMac，2026-10-16 13:40–14:20 SGT，只读）
来源：`EV/audit/box-pass1/2/4.txt`、`EV/audit/imac-pass1–4.txt`。iMac 的数据是通过 Orca 在 iMac ops 工作区开临时终端、运行只读脚本拿到的，终端已经关掉。

### A.1 按新标准逐项对照
| 标准项 | box | iMac | 结论 |
|---|---|---|---|
| env 文件 `xinyue.env` | 有，600，5 行非 key 的内容正确，key 和其他文件一致 | 有（07:25），600，内容同 box | **已配**；目录权限 box 是 755，**不一致**（标准要求 700），iMac 没查目录权限 |
| 启动脚本 | `everos-mcp-xinyue`，07:29，sha `b45476dd…f7065` | 09:26，sha **同 box** | 两台一致，但都是 v1 写法：没有 scope 锁和校验，规范 sha 和模板不符 → **要换** |
| Claude local scope | `/workspace/repos/xinyue-site` 有；`~/orca/workspaces/xinyue-site/*` 显示 `Local config` | `~/pi/remote/xinyue-site` 有；`xinyue-site-cicd`、`xinyue-ci`、Orca worktree、`/private/tmp/nightly-xinyue-site` 都显示 `Local config` | **已配**，覆盖完整（D1 那个 clone 除外） |
| 父目录 `.mcp.json` | `~/orca/workspaces/xinyue-site/.mcp.json`（07:27） | 同一路径（09:27） | 现在存在，但被 local 盖掉了 → v2 **要删** |
| `enabledMcpjsonServers` | `["everos"]`（07:27，有备份 `.bak-everos-20261016`） | `["everos"]`（09:27，有备份） | 现在有 → v2 **要去掉** |
| 只读（deny） | 没有；bypass 模式下 7 个工具全在（`EV/claude-nodeny.stream.jsonl`，在广告 worktree 测的，各项目配置方式相同） | 没有；`defaultMode=auto` | **缺** |
| pi | 没接（没有扩展，也没有 `.pi/mcp.json`）；run2 在心月 worktree 里确认看不到 everos 工具 | 没接；而 pi 在 iMac 上的心月 clone 里是真在用的（firstmate、treehouse 下有 7 个会话目录） | **缺** |
| `~/pi/remote` 目录 | 不适用 | `xinyue-site` 是主 checkout，`xinyue-site-cicd`、`xinyue-ci` 是它的 worktree，都已覆盖；另有 `~/pi/remote/vllm-omni`（vllm 的 clone，没挂） | 已覆盖 |
| 有没有挂到别的项目 | user 级没有 everos；ops、vllm-omni 目录里 `claude mcp get` 找不到 | user 级没有；ops、`~/claude/site`、`~/claude/gpu/vllm` 里找不到 | Claude 这边**没有泄漏**。潜在的泄漏途径有两个：旧脚本会被调用方环境改 scope（T4）；广告的 pi 扩展在跨项目 resume 时，会把广告的工具挂进心月会话（run3） |
| 冒烟证据 | `mcp-smoke.md`（box 跑了 3 轮，通过） | **没做**：`~/everos-mcp-smoke-imac.jsonl` 不存在，`mcp-smoke.md` 的「iMac」一节仍写着「没做」 | 缺 |
| token 不进配置 | 命中 0 | 命中 0 | 合规 |

### A.2 iMac 是否按 `imac-mcp-steps.md` 做完
| 步骤 | 状态 | 依据 |
|---|---|---|
| 0 前提（env 600，5 行正确） | 做了 | env 07:25，600，内容正确 |
| 1 放脚本 | 做了 | 09:26，sha 和 box 相同 |
| 2 父目录 `.mcp.json` | 做了 | 09:27，command 是绝对路径 |
| 3 `enabledMcpjsonServers` | 做了 | settings.json 09:27，备份是 `.bak-everos-20261016` |
| 4 local scope（`xinyue-site`、`xinyue-site-cicd`） | 实际效果是做了 | `~/.claude.json` 里只有 `~/pi/remote/xinyue-site` 一条。`xinyue-site-cicd` 是 worktree，所以也显示 `Local config` |
| 5 确认配置里没有 token | 结果合规 | 本次审计，命中 0 |
| 6 挂载检查 | 结果合规 | 心月目录全部 Connected；`~/orca/workspaces/site` 和 ops 下找不到 everos |
| 7 冒烟，并把结果写回 `mcp-smoke.md` | **没做** | 没有找到 jsonl，文档也没更新 |

### A.3 按 v2，心月还要做的事
1. 两台机器都换成模板脚本；
2. 两台机器都加 deny；
3. 两台机器都装 `everos.ts`（心月那几行已经在表里）；
4. 验证 G5 之后，删掉两台的父目录 `.mcp.json`，去掉 `enabledMcpjsonServers`；
5. Zack 定 D1；
6. 心月的 4 格加上 G1–G7 全部按 §11 跑完；
7. iMac 的冒烟改用 §11 的格式，不再用 v1 第 7 步。

## 附录 B：其他三个项目今天的改动（box + iMac，时间是 SGT 的 mtime）

### B.1 文件和条目
| 项 | box | iMac | v2 怎么处理 |
|---|---|---|---|
| `~/.local/bin/everos-mcp-deepvision` | 13:13，sha `2e1f43ed…`，没有 scope 锁 | **没有** | box 换成模板；iMac 等官网上 iMac 时新建 |
| `~/.local/bin/everos-mcp-dv-ads` | 13:13，sha `60241e73…`，没有锁 | 13:15，sha **同 box** | 两台都换成模板 |
| `~/.local/bin/everos-mcp-vllm-omni` | 13:10，sha `c570aac3…`，**有锁**（`EVEROS_ALLOW_SCOPE_OVERRIDE`） | 13:11，sha **同 box** | 两台都换成模板（模板的锁就是照这份做的，另外加了校验） |
| `~/.config/everos/deepvision.env` | 13:10，600；多了一行注释和 `EVEROS_AGENT_ID` | **没有** | box 保留；iMac 上线时补 |
| `~/.config/everos/dv-ads.env` | 13:12，600 | 13:15，600 | 保留 |
| `~/.config/everos/vllm-omni.env` | 13:10，600，多了 `EVEROS_AGENT_ID` | 13:11，600，同样多这一行 | 保留 |
| `~/.config/everos/.proxy-token` | 03:32，600 | 没有 | 作为 box 上 key 的来源保留（也可以由 ops 系统决定删掉） |
| `~/.pi/agent/extensions/everos-*` | `everos-dv-ads.ts`，13:17，sha `e1cc222c…`（广告 FDV-67） | 没有 | 换成 `everos.ts`，同一步删掉旧的（§5.2） |
| `.pi/mcp.json` | `~/orca/workspaces/deepvision-site/dv运维-FDV-68-EverOS接入/.pi/mcp.json`，13:17，没进 git，`exposure:"direct"`（官网 FDV-68） | 没有 | 删掉 |
| `~/.pi/agent/trust.json` | 13:17 新增了 `~/orca/workspaces/deepvision-site` 和 `/workspace/repos/deepvision-site` 两条 | 今天没改（最后修改是 10-10） | 和官网 bot 确认后删掉这两条 |
| 父目录 `.mcp.json` | `~/orca/workspaces/deepvision-site/.mcp.json`（13:13）、`~/orca/workspaces/deepvision-ads/.mcp.json`（13:13） | `~/orca/workspaces/deepvision-ads/.mcp.json`（13:15，在主 checkout 里，被 `.git/info/exclude` 排除）、`~/orca/workspaces/repository/.mcp.json`（13:11，vllm） | local 验证通过后删掉；iMac 的 repository 那份按 §4.2 的例外处理 |
| `~/.claude.json` 里的 local 条目 | `/workspace/repos/deepvision-site`、`/workspace/repos/deepvision-ads` | 这三个项目都没有 | 保留，这就是 v2 用的机制；还要补 box vllm、iMac 三个项目（§4.1） |
| user 级的 everos | 没有 | 没有 | 不变 |
| deny 规则 | 没有 | 没有 | 加上（§4.4） |
| token | 所有配置里命中 0 | 命中 0 | 合规 |

### B.2 审计时的 16 格现状
| 项目 | box Claude | box pi | iMac Claude | iMac pi |
|---|---|---|---|---|
| 心月 | 挂了（local），**不是只读** | 没挂 | 挂了（local），不是只读，没冒烟 | 没挂 |
| 官网 | 挂了（local），不是只读 | 只有 FDV-68 那一个 worktree 挂了（`.pi/mcp.json`，7 个工具全是 direct，**写工具也给了模型**） | 没挂（脚本、env、挂载都没有） | 没挂 |
| 广告 | 挂了（local），不是只读 | 挂了（扩展，有 `process.cwd()` 缺陷） | 挂了（父目录 `.mcp.json`，project scope，靠 user 级放行），不是只读 | 没挂 |
| vllm | **没挂**（脚本和 env 都在） | 没挂 | `repository` 的 worktree 挂了（父目录 `.mcp.json`），不是只读；另外两个 clone 没挂 | 没挂 |

「不是只读」指 Claude 没有 deny 规则：box 上 bypass 模式实测 7 个工具全在；iMac 是 auto 模式，要由分类器判断。

## 附录 C：证据索引（`EV/` = `mcp-evidence/pi-research-20261016/`）
| 文件 | 内容 |
|---|---|
| `EV/sessions/*.jsonl`、`EV/run*-*.events.jsonl` | pi 实测 run1–9 的会话和事件流（对照表见 `PI-MCP-FINDINGS.md` §3） |
| `EV/everos.ts`、`EV/everos.prototype.ts` | pi 扩展的定稿和原型 |
| `EV/everos-mcp-template.sh`、`EV/template-probe.txt` | 模板（`N=dv-ads`）和实测 T1–T6 |
| `EV/claude-nodeny/deny/worker-disallow.stream.jsonl`、`EV/claude-deny-settings.json` | Claude 的 deny 规则和 worker 参数实测（haiku，`--no-session-persistence`） |
| `EV/xcheck-*.json`、`EV/acceptance-query-matrix.txt` | API keyword 交叉核对，和 4×4 查询基线 |
| `EV/audit/box-pass1/2/4.txt`、`EV/audit/imac-pass1–4.txt` | 两台机器的只读审计输出（已过 redact；iMac 第一轮里无关的 `.mcp.json` 只保留了路径） |
| `EV/tools/` | 用到的脚本：解析会话、API 核对、MCP 探针、4 份审计脚本、redact、分页读终端 |

## Zack 决定（2026-10-16 16:15 SGT）
- 方案 v2 批准，开干。
- D1：iMac firstmate/treehouse 的心月 clone 不挂。
- D2：iMac 另外两个 vllm-omni clone 都不挂。
- 顺序：心月先按 v2 补齐当样板（box+iMac × CC+pi），再官网、广告、vllm 照做；Coding助手逐格验收 16 格。

## 12. 补充（2026-10-17，Zack 15:17 批 flush 524 修复、16:56 批按 v2 推进）
1. **优先走 tailnet**：MCP 启动脚本和 HTTP 客户端（采集、夜审）优先连 `http://100.64.0.5`，**每个请求**都带 `Host: everos.deepvision.sg`，key 不变。MCP 启动脚本（v2.1 模板，§3.3）的实际做法：
   - **启动时探一次**：`$EVEROS_TAILNET_URL/health`（默认 `http://100.64.0.5`，可在项目 env 文件里改成别的 `http://100.64–127.x.y` 或 `off`），3 秒，不带 key；
   - **只有连不上才回落公网** `https://everos.deepvision.sg`（拒绝连接、没有路由、DNS 失败、3 秒内没连上）。连上了但 `/health` 不是 200 也留在 tailnet：那是 EverOS 本身的问题，公网到的是同一个后端；
   - 选定后整个进程都用这个 endpoint，中途不切换（MCP 进程随会话重启时会重新探）；
   - 每次启动在 `~/.local/state/everos-mcp/endpoint.log` 记一行 `endpoint=tailnet|public`，回落公网时 stderr 也打一行；
   - Host 头由脚本里的 wrapper 给 everos-mcp 的每个请求加上（everos-mcp 0.1.1 自己没有加请求头的配置）。site nginx 先按「本机地址:端口」选 server：连到 100.64.0.5:80 的请求只会进 `everos-tailnet.conf`，任何 Host 都行，进不了公网 block 或 default_server（444）。显式带 Host 是为了在 tailnet block 被移掉时也能落到公网 block，而不是 444（证据 `mcp-evidence/v2.1-template/host-routing-box.txt`）。
   HTTP 客户端（`nightly_addflush.py` 这类）按请求处理：只有**连接阶段**就失败（请求肯定没发出去）才回落公网；请求发出之后的失败按第 2 条处理。回落要写日志或台账（endpoint=public）。心月样板：ops PR #10（merge 81f75aa）的 `nightly_addflush.py`；MCP 启动脚本以 v2.1 模板为准（PR #10 里的 `everos-mcp-xinyue.sh` 是过渡版，换成 v2.1）。证据：`/workspace/ops/everos-incidents/2026-10-17-flush-524/fix/README.md`。
2. **524、504、502、读超时、发出后断开 = 结果未知**：不能当失败直接重发。先查这条会话有没有落库（`get` 带 `filters.session_id`，再查未 flush 的缓冲）：已落库就停；还在缓冲就 flush 一次；都没有就用**原来的消息和原时间戳**重发 add，再 flush 一次。每条会话最多补一轮，再失败记 failed 并停。原因：EverOS 1.4.2 的 flush 在请求里同步抽取，抽取前就清空 buffer，失败后不重试（根因见 `/workspace/ops/everos-incidents/2026-10-17-flush-524/README.md`）。
   - **flush 后读有延迟，先退避复查再决定**（2026-10-17 16:57 心月 tailnet 真写测试实测）：flush 返回 200 extracted 之后约 1s，按 `filters.session_id` 查这条会话的 episode 还是 0，约 18s 后再查才是 1。所以结果未知时不能只查一次就判「没落库」：按 5s、15s、30s、60s 退避，每次按 session_id 查这条会话的 episode（同时看未 flush 的缓冲），并比对 episode 总数（total_count）有没有比写前多。只有按 session_id 查到了才算已落库，不补发；只是总数变多、按会话查不到，或者复查读不出来，一律记 failed、不补发，交人看。四次都没查到、总数也没变多，才按上面的规则补发（add 重发；flush 则先把 chunk 重新 add 再 flush 一次，消息还在缓冲里就只再 flush 一次）。以 ops PR #11（merge e3093492）的代码为准。每条会话仍然最多补一轮。台账要记每次复查（等了多久、这条会话查到几条、总数多少）和最后的决定。证据：`/workspace/xinyue-web/everos/tailnet-rollout-1017/real-write-test/`（ledger.jsonl 里 session_after=0、count_after=13；filter-recheck.txt 里再查是 1）。
