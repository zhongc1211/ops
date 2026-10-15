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
