# 生产版本哨兵和未推送扫描（ops · 23 / ops · 24）

两个纯脚本的 Orca 自动任务：活都在预检脚本里干完，预检永远 exit 1，不启动模型。

## ops · 23 生产版本哨兵（iMac，每 15 分钟）

| 文件 | 跑在哪 | 做什么 |
|---|---|---|
| `prod-watch.sh` | iMac `~/.orca-state/bin/sentinels/` | 预检入口：调 `prod_fetch.py`，结果经 ssh 交给 box 的 `prod_ledger.py apply`，box 的日志行在 iMac 存镜像 |
| `prod_fetch.py` | iMac | 用 iMac 上已有的只读令牌 `~/.config/cloudflare/readonly-usage.token`（orca-cf-usage-readonly）GET 每个生产 Worker 的最新 deployment 和版本详情。不打印令牌 |
| `prod_ledger.py` | box `/workspace/ops/sentinels/` | 和台账 `/workspace/ops/reports/prod-ledger.md` 比 deployment id；不同就追加一行「未报」并 `notify-run --bot coding-assistant` |

生产 Worker（取自各仓库 wrangler 配置的生产环境）：`deepvision-site-production`（deepvision.sg）、`deepvision-ads`（ads.deepvision.sg）、
`xinyue-site`（xy.deepvision.sg）、`xinyue-studio-control`、`xinyue-game-runtime`。

- 日志：box `/workspace/ops/reports/prod-watch-YYYYMMDD.log`；iMac 镜像 `~/.orca-state/prod-watch/mirror-YYYYMMDD.log`
- 每个变化只叫一次（追加的那行就成了新的比对基准）。
- 查询失败连续 4 次才叫醒 Coding助手，6 小时内最多一次；iMac 连续 4 次 ssh 不到 box 时由 iMac 叫醒，同样 6 小时一次。
- 演练：`PROD_WATCH_DRILL=1 PROD_LEDGER=<过期的台账副本> ~/.orca-state/bin/sentinels/prod-watch.sh`

## ops · 24 未推送扫描（box 和 iMac 各一个，每小时）

| 文件 | 做什么 |
|---|---|
| `unpushed-scan.sh` | 预检入口。box 直接写 `/workspace/ops/reports/unpushed-scan-YYYYMMDD.log`；iMac 写本机镜像再 ssh 追加到 box，ssh 不通时留到下次补发 |
| `unpushed_scan.py` | 扫本机 `orca worktree list` 的每个工作区：不在任何远程分支里、最早一个超过 2 小时的提交；放了 2 小时以上的未提交改动（未跟踪的 node_modules 软链接不算）。只读：`GIT_OPTIONAL_LOCKS=0`，不 fetch |

叫醒对象按 git remote 认：deepvision-site → `deepvision-ops`，deepvision-ads → `deepvision-ads`，xinyue → `xinyue`，
vllm-omni → `vllm-omni`，其他（ops 等）→ `coding-assistant`。同一个 bot 一次运行只收一条消息。

限流（`~/.orca-state/unpushed-scan/state.json`）：新的或变了的发现马上叫；没变的满 4 小时再叫一次；叫过 2 次还没变，
改叫 `coding-assistant`，之后每 24 小时最多一次。

演练：`UNPUSHED_LOG_NAME=drills/x.log unpushed-scan.sh --only <工作区路径> --state <单独的状态文件> --drill`；
只看不叫：`unpushed_scan.py --dry-run`。
不扫的工作区写在 `unpushed_scan.py` 的 `IGNORE`（按 `--machine` 和路径），现在有 MBA 的 `~/orca/projects/local`（Orca 自动生成的占位仓库）和 iMac 的 `~/claude/worker`（停用的 Lark 秘书 worker，没有远程，2026-10-19 已归档到 `~/ops-archive/20261019/`）。

## 安装

box：`cp sentinels/{prod_ledger.py,unpushed-scan.sh,unpushed_scan.py} /workspace/ops/sentinels/`。
iMac：从 box `scp box:/workspace/ops/sentinels/{prod-watch.sh,prod_fetch.py,unpushed-scan.sh,unpushed_scan.py} ~/.orca-state/bin/sentinels/`。
