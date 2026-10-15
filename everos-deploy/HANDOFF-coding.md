# Coding助手交接：EverOS 心月切主规格

- 日期：2026-10-16
- 状态：**health 已绿** + **LESSONS 已导入**（15 skills，2026-10-16）；base URL **已锁定**；LLM→magpie 已通 → Coding助手可改 `75b324a4`
- owner=dr eggbot；证据：`EVIDENCE.md` + `IMPORT-EVIDENCE.md`

## 1. 身份分区

| 键 | 值 |
|---|---|
| `EVEROS_BASE_URL` | `https://everos.deepvision.sg`（**已锁定**；`/health` 200，version 1.4.2） |
| `EVEROS_API_KEY` | nginx Bearer；值在 VPS `/etc/everos/proxy-token`（**勿提交仓库**）。MCP/curl 除 `GET /health` 外都要带 |
| `EVEROS_APP_ID` | `xinyue`（产品） |
| `EVEROS_PROJECT_ID` | `xinyue-site`（仓库） |
| `EVEROS_ASSISTANT_SENDER_ID` | `coding-xinyue-site`（Claude/Pi 共用） |
| `EVEROS_USER_ID` | `zack`（用户侧；错题召回用 agent 路径） |

API：`/api/v2/memory/*`。search 起步用 `"method":"keyword"`（无 embedding 时 hybrid 会 422）。
数据根：`/var/lib/everos`。LLM 已指 magpie `http://100.64.0.4:3425/v1`（Tailscale），模型 `claude/claude-haiku-5-5`；`/add`+`/flush` 已实测可抽 episode。
LESSONS：**15** 条 agent_skill 已写入 `agents/coding-xinyue-site/skills/`（9 规则 + 6 done_right）；见 `IMPORT-EVIDENCE.md`。

## 2. Claude MCP JSON 片段

```json
{
  "mcpServers": {
    "everos": {
      "command": "uvx",
      "args": ["everos-mcp"],
      "env": {
        "EVEROS_BASE_URL": "https://everos.deepvision.sg",
        "EVEROS_API_KEY": "<from /etc/everos/proxy-token on VPS>",
        "EVEROS_APP_ID": "xinyue",
        "EVEROS_PROJECT_ID": "xinyue-site",
        "EVEROS_ASSISTANT_SENDER_ID": "coding-xinyue-site",
        "EVEROS_USER_ID": "zack"
      }
    }
  }
}
```

CLI 等价：

```bash
claude mcp add everos \
  -e EVEROS_BASE_URL=https://everos.deepvision.sg \
  -e EVEROS_API_KEY="<from /etc/everos/proxy-token>" \
  -e EVEROS_APP_ID=xinyue \
  -e EVEROS_PROJECT_ID=xinyue-site \
  -e EVEROS_ASSISTANT_SENDER_ID=coding-xinyue-site \
  -e EVEROS_USER_ID=zack \
  -- uvx everos-mcp
```

**谁挂**：凡 bot 派活对着的 Orca coding 会话。子 worker 不挂；由父会话 recall 后贴进 brief。

冒烟：新开心月小任务 → `recall_agent_experience` / `search_memory` 通；用 `app_id=deepvision` 搜应搜不到心月 skill。

## 3. LESSONS 决定

- **导入**：现有 `docs/solutions/LESSONS.md` + `lessons/*.md` → EverOS `agent_skill`（保留 seen_dates）
- **切主后**：**停写并删除**仓库 `LESSONS.md`（`lessons/` 可归档一周再删）
- **不**长期双写

## 4. 双机会话输入 schema（夜审 75b324a4）

每日 SGT 日历日 `D`（例 2026-10-16）。夜审开始时必须凑齐下面清单；**缺任一侧且当日有开发迹象 = 失败告警**。

### 4.1 会话清单文件（每机一份，JSONL）

路径约定（运维/采集就绪后可微调）：

- box：`/var/lib/everos-ingest/xinyue/${D}/sessions-box.jsonl`
- iMac → 推到 box：`/var/lib/everos-ingest/xinyue/${D}/sessions-imac.jsonl`  
  （iMac 本地生成后 rsync/scp；**不**在 iMac 跑第二套写入夜审；`0ad74d58` 保持 disabled）

每行一个对象：

```json
{
  "session_id": "orca-ws-…或终端会话 id",
  "machine": "box|imac",
  "workspace": "路径或 Orca 工作区名",
  "linear_id": "PER-xx|null",
  "started_at": "ISO8601",
  "ended_at": "ISO8601|null",
  "status": "completed|stuck|running|unknown",
  "transcript_path": "可读路径|null",
  "status_md_path": "…/status.md|null",
  "summary_path": "收尾报告路径|null",
  "git_branch": "string|null",
  "pr_urls": ["https://…"]
}
```

### 4.2 夜审算法（贴合 EverOS）

1. 读两侧 jsonl，去重 `session_id`；若一侧文件缺失且另一侧/git 显示当日有心月活动 → **失败**，webhook Coding助手。
2. 对每个会话：读 transcript/status/summary → 整理成 messages → `POST /api/v2/memory/add`（`app_id=xinyue`,`project_id=xinyue-site`, agent 侧用 `coding-xinyue-site`）→ `flush`。
3. 对照当日 commit/PR/Linear：标「返工 / 不该合 / 验证太糙 / Done right」；**优先让 OME 抽 case/skill**；无 embedding 时脚本直接写/更新 `SKILL.md`（含 `seen_dates`）。
4. Seen 满 3 个不同 SGT 日 → webhook 心月 bot 升硬规则（沿用）。
5. 摘要仍写 `~/xinyue-deploy/nightly-review/${D}.md`，并注明：会话数 box/iMac、写入 skill 数、失败项。

### 4.3 派活段（dev-bot-rules）

- 接派活会话必须挂 everos-mcp；开工前 recall；子 worker 不挂、父贴 brief。
- 删「动手前读 LESSONS.md」；改为 EverOS recall。

## 5. 你改自动化的时机

触发条件：
1. ~~`/health` ok + 域名通~~ **已满足**（2026-10-16）
2. ~~eggbot「LESSONS 已导入」+ LLM 真钥可用~~ **已满足**（2026-10-16；IMPORT-EVIDENCE.md）  
→ **现在**改 `75b324a4` + 派活规矩 + MCP 冒烟。
