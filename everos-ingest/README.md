# EverOS 心月会话采集

夜审 `75b324a4` 需要每日 SGT 日 `D` 的：

- `/var/lib/everos-ingest/xinyue/$D/sessions-box.jsonl`
- `/var/lib/everos-ingest/xinyue/$D/sessions-imac.jsonl`

## 脚本

- `collect_xinyue_sessions.py` — 从本机 `orca worktree list` + `~/.claude/projects` 抽心月会话
- `collect-box.sh` / `collect-imac.sh` — Orca automation **precheck**（工作全做完后 `exit 1`，不启模型）
- `ensure-sshd.sh` — box 上保证 Tailscale IP `:22` 有 sshd，供 iMac `scp`

## 自动化（Orca，非 cron）

- box：`ops · EverOS 心月会话采集 box` — 每天 22:00 SGT
- iMac：`ops · EverOS 心月会话采集 iMac` — 每天 21:50 SGT（先推到 box）

手动：

```bash
# box
MACHINE=box D=$(TZ=Asia/Singapore date +%F) /workspace/ops/everos-ingest/collect-box.sh; true

# iMac
EVEROS_INGEST_ROOT=$HOME/.orca-state/bin/everos-ingest \
  $HOME/.orca-state/bin/everos-ingest/collect-imac.sh; true
```

不含密钥；不要把 `~/.config/everos/` 写进仓库。

## 2026-10-16 修改（备份：/home/box/orca-backups/everos-ingest-20261016/）

- iMac：transcript 先过滤密钥（env 文件里的字面值 + 常见 token 格式），再推到 box 的
  `/var/lib/everos-ingest/xinyue/$D/imac/<session_id>.jsonl`（目录 700、文件 600，先传到 `imac.incoming/` 再整体换上）；
  jsonl 的 `transcript_path` 写 box 路径，原路径放在 `transcript_source_path`。jsonl 最后推。
  读不到 env 密钥列表时拒绝推送（exit 3）。ssh 用复用连接，首连最多重试 8 次（约 5 分钟），precheck 超时为 420s。
- 两台机器：排除冒烟会话、夜审会话和采集会话本身（按工作区名、auto-run 路径、开场 prompt 判断），
  被排除的会话写到 `sessions-<machine>.excluded.jsonl`，并注明原因。
- 采集脚本出错时 exit 4（exit 1 留给「做完了，不启动模型」）。
- 手动 `orca automations run` 不会执行 precheck；要验证只能等定时运行。
- 第二轮（同日，备份在 /home/box/orca-backups/everos-ingest-20261016-r2/）：去掉按工作区名排除的规则，改为按会话任务类型判断：
  首条消息（或它指向的 brief .md）的前两行。冒烟、夜审、采集、接入/配置（挂 everos-mcp、接入 EverOS、改采集/夜审 automation）都排除；
  前两行里出现 PER-N、PR、feat/ 分支或 Linear 的，一律当开发会话保留。

## deepvision-site 采集（FDV-68，2026-10-16 19:xx，**disabled**）

- 规则 A+E+H+K（Zack 19:07）：按 git remote 认 deepvision-site；接入/配置规则先于工单保护（FDV-N）；夜审 43c55a22 会话排除
- 脚本：`collect_deepvision_site_sessions.py`（复用 `collect_xinyue_sessions.py` 的函数，心月脚本没改）、`collect-box-deepvision-site.sh`、`collect-imac-deepvision-site.sh`（iMac 副本在 `~/.orca-state/bin/everos-ingest/`）
- 输出：`/var/lib/everos-ingest/deepvision-site/$D/`，D = 前一天
- automation：box `207ff52e-2dfb-4365-9b3d-3951ef3054ca`（00:05），iMac `34fe1ab0-7b3d-4e6a-917a-2c254e0e6dc6`（00:01），都是 disabled
- dry-run：`DRY_RUN=1 D=YYYY-MM-DD <precheck 脚本>`，只打印，不写文件
- 19:21 改动（备份在 /home/box/orca-backups/fdv68-collect-20261016-1921/，iMac 上是 ~/orca-backups/…）：加 OD 规则（固定前缀 `~/Library/Application Support/Open Design/namespaces/release-stable/data/projects/fdv61-`）；首条消息被 `<pasted_content>` 包着时先拆包装再判定；输出每行加 `included_by`。43c55a22 夜审改成读 `/var/lib/everos-ingest/deepvision-site/$D/`
- 19:28：207ff52e / 34fe1ab0 已启用；一次性核查 `098bc4e7-7bcd-4d2f-a391-1ab2b665c8c0`（2026-10-17 00:30，`fdv68-firstrun-check.sh` + `fdv68_firstrun_check.py`，跑完自己 disable）
