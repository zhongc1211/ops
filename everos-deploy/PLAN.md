# EverOS 替代 LESSONS — 接入方案（对照上游，不装）

- 日期：2026-10-16（对照 [EverMind-AI/EverOS](https://github.com/EverMind-AI/EverOS) README / docs、[everos-mcp](https://github.com/EverMind-AI/EverOS-MCP)、docs.evermind.ai）
- 状态：**执行中**（2026-10-16）；装服/反代/LLM→magpie/headscale 三节点/LESSONS 导入已完成；**Mac 日备暂缓**（Zack）；夜审改写交给 Coding助手；运维只负责开机与 DNS/证书基建
- 已拍板全上；装服与切主按 §5 执行

## 0. 已拍板（含 Zack 2026-10-16 02:16）

| 项 | 决定 |
|---|---|
| 部署 | **原 site VPS（旧 DigitalOcean）自托管**；挂 **deepvision 域名**（子域待运维确认，如 `everos.deepvision.sg`）；HTTPS 反代到 EverOS |
| 备份 | **日常在 Mac（iMac）备份** Markdown 根（rsync/定时）；VPS 为线上源 |
| 客户端 | iMac + box 的接派活 coding 会话经 MCP `EVEROS_BASE_URL=https://<域名>` 指 VPS |
| 收工回写 | **先关**；开场 recall + 夜审写入 |
| 切主 | **方案定了直接全上**（心月先行切主：导入 + MCP + 夜审改写 + 停 LESSONS）；不再「只草案再等点头装」 |
| 夜审覆盖 | **必须跑稳且审到位**：会话级；**凡参与开发的机器都审**（box + iMac），不能只看一边 |
| 分区 | `app_id`=产品，`project_id`=仓库 |
| 谁挂 | 凡 bot 派活对着的 coding 会话都挂；其子 worker 不挂 |

## 0a. 谁挂记忆（2026-10-16，与 Coding助手对齐）

**实际**：多数时候没有稳定的「主 / 子 coding agent」。常态是开发 bot → Orca **一个工作区、一个 Claude/Pi 会话**直接干完；子 agent / 并行 worker 很少。bot 只对着该主终端下任务。

**规则**：**凡 bot 派活对着的 coding 会话，都挂 EverOS MCP/recall。**

- 覆盖绝大多数单会话任务；治「LESSONS 靠提示词才读」。
- 仅当该会话自己再拉 worker：worker **不挂**；由接派活会话 recall 后把相关 skill 写进 worker brief。
- 两个同级 Orca 工作区（两个 Linear、bot 分别派）→ **各自挂**。
- 不要「每一个动手进程都挂」（含 worker）；也不要先判断有没有 parent 才挂。

## 1. 目标

用自托管 EverOS 取代心月 `docs/solutions/LESSONS.md` 错题本：可读可改的 Markdown、按项目分区、Claude/Pi **开场自动拿到**相关教训，夜审继续负责复盘与 Seen×3 升级。

**成功标准**

1. 心月动手会话开场能召回相关 `agent_skill` / case，不依赖派活文案写「读 LESSONS」。
2. 夜审写入走 EverOS；人可直接改 `~/.everos/.../skills/*/SKILL.md`。
3. 双写期过后停 LESSONS；Seen×3 → webhook 升级硬规则仍可用。
4. **不**经 Raven 编排注入（已证实 Raven host 记忆进不了 Claude/Pi）。

## 2. 对照上游：该怎么接

官方栈（与 LESSONS 替代最贴的部分）：

| 上游能力 | 我们怎么用 |
|---|---|
| `uv pip install everos` → `everos init` → `everos server start`（默认 `http://127.0.0.1:8000`） | box 唯一实例；root 用 `everos init --root` 固定路径（建议 `/home/box/.everos`（产品用 app_id 分区，不必 per-app root），与 Raven 自带 EverOS **隔离**） |
| `/api/v2/memory/*`（v1 仅兼容，新代码只用 v2） | 夜审脚本、导入脚本、健康检查 |
| Tier 1：仅 `[llm]` → keyword + add/flush；**skill 抽取要 `[embedding]`** | 起步可 Tier 1；导入旧 LESSONS **手写 skill Markdown**（源真相可直接改 .md，cascade 同步索引），不空等 OME 抽 skill |
| 要 hybrid / reflection / skill_extraction | 再加 `[embedding]`（可走 magpie 本地代理或 OpenRouter，装时定） |
| **[everos-mcp](https://github.com/EverMind-AI/EverOS-MCP)**：`uvx everos-mcp` + `EVEROS_BASE_URL` | **Claude Code 主路径**：`claude mcp add everos -e EVEROS_BASE_URL=http://<box>:8000 …`；官方会在 session 用 `search_memory` / `recall_agent_experience` 等，无需自写「拼进 prompt」除非 MCP 不可靠 |
| MCP 工具 | 开场侧重 `recall_agent_experience` + `search_memory`；写入侧重夜审 API；收工阶段再开 `record_trajectory` |
| Knowledge Wiki | 可选：把长篇 `lessons/*.md` 当 knowledge 文档；**短规则仍进 agent_skill** |
| OSS **无** Cloud 的 delete/edit API | 删错用改 Markdown / deprecate；测试数据绝不用 `default` 脏空间；错题主路径走 agent skill，少污染 user profile |

**刻意不用**

- Raven 当记忆网关（记忆只进 host）。
- EverOS Cloud（除非以后要跨公网；本期自托管）。
- 官方 Claude Code Cloud 插件（绑 console key）；我们绑 **自托管 + MCP**。

## 3. 数据映射（LESSONS → EverOS）

| LESSONS | EverOS | 路径形态（上游） |
|---|---|---|
| 规则一行 | `agent_skill` | `agents/<agent_id>/skills/skill_<name>/SKILL.md` |
| Seen N× | skill frontmatter：`seen_dates`、`seen_count`、`category` | 夜审只追加日期 |
| Done right | skill（`category: done_right`）或不升级的 knowledge | 不进 ×3 |
| 夜审日志 | `episode`（日更）或 ops 日志 | 不注入 coding |
| 验收硬标准 | **仍在** AGENTS / [dev-bot-rules](sand-workflow:dev-bot-rules) | 冲突以 AGENTS 为准 |

**分区**

- `app_id`: **跟产品走**（Zack 2026-10-16）：如 `xinyue`、`deepvision`（广告/官网同属 deepvision 则同 app，靠 project 再分）
- `project_id`: 跟仓库走，如 `xinyue-site` / `deepvision-site` / `deepvision-ads`
- MCP：`EVEROS_APP_ID` / `EVEROS_PROJECT_ID` 按工作区切换（可在项目 `.mcp.json` 或派活环境里设）
- `EVEROS_ASSISTANT_SENDER_ID`: `coding-xinyue-site`（Claude 与 Pi **共用**，池化经验）
- `EVEROS_USER_ID`: `zack`（用户侧；错题召回用 agent 身份）

## 4. 读写路径

```
夜审 / 导入 ──write──► EverOS Markdown (skills/cases)
                              │
                     everos server (VPS + deepvision 域名)
                              │
         ┌────────────────────┼────────────────────┐
         │ MCP everos-mcp     │  (可选) HTTP hook  │
         ▼                    ▼                    │
   Claude Code            Pi（若无 MCP）            │
   recall_agent_experience / search_memory         │
```

### 4.1 开场（替代读 LESSONS）

1. **首选**：Claude Code 挂 everos-mcp，依赖其 autonomy 协议在开场 recall；AGENTS 加一句「动手前用 EverOS 召回本仓 agent 经验，冲突以本文件为准」。
2. **兜底**：若 MCP 未加载或 Pi 无 MCP——SessionStart hook `POST /api/v2/memory/search`（`agent_id` = coding-…，`method=keyword` 或有 embedding 时 hybrid），把 skill 摘要注入。
3. EverOS 挂 → fallback 读本地归档 `lessons/`（过渡期）或明确「无错题本」。

### 4.2 写入 — 尽量贴合 EverOS（OME），少自造

**复用上游（开箱）**
- 会话轨迹 → `POST /api/v2/memory/add` + `flush` → `agent_case`
- 有 embedding 时：OME `extract_agent_skill` / `trigger_skill_clustering` 升 skill
- 可选周更：`reflect_episodes`（`ome.toml` 开启或 `POST /api/v2/ome/trigger`）合并碎 episode
- 无 embedding 起步：导入与关键规则仍可 **直接写** `agents/.../skills/*/SKILL.md`（Markdown 源真相 + cascade）

**我们只做薄层（上游没有的）**
- **双机会话收集器**：枚举当天 SGT box + iMac 上心月相关 Orca 会话/工作区（transcript、status、收尾报告）；漏会话 = 夜审失败
- **质量门**：对照 commit/PR/Linear，标「返工 / 不该合 / 验证太糙」后喂进 EverOS（不是另维护 LESSONS 逻辑）
- **Seen×3**：读 skill frontmatter；满 3 个不同 SGT 日 → webhook 叫醒心月 bot 升 AGENTS / [dev-bot-rules](sand-workflow:dev-bot-rules)
- **收工**：先关 `record_trajectory`

### 4.3 夜审调度（Coding助手 事实，2026-10-16）

| 项 | 现状 → 目标 |
|---|---|
| 自动化 | box `心月夜审` **75b324a4** 23:30 SGT → **改 prompt**，仍只保留这一套写入调度 |
| iMac 副本 | `0ad74d58` **保持 disabled**；双机是采集面，不是第二套夜审 |
| 现输入 | 仅 git/PR/Linear（+ 偶发 status）→ **会话级 + 双机**（box 本地 + iMac 可读路径或「只采集推 box」小任务） |
| 现输出 | LESSONS.md PR → **EverOS skill/case**；LESSONS 停更后删除 |
| 没扫到的 | 会话 transcript、iMac 当天未 push 的错 → 必须纳入 |

### 4.4 切主

全上：导入后即写 EverOS；停 LESSONS；不搞长期双写（Zack）。

## 5. 全上执行顺序

1. **运维**：原 site VPS 开机（FDV-14）；按 `DNS-PLAN.md` 建 `A everos → 157.230.194.108`（橙云）；确认 SSH/Origin CA 可用。**不装 EverOS**
2. **eggbot（Orca CLI，ops 工作区）**：SSH 装 EverOS（`:8000`）+ Caddy/nginx 反代 `everos.deepvision.sg` → health；建 Mac 日备自动化（Orca automation，rsync Markdown root）；导入心月 LESSONS → skill；定 MCP JSON / 双机会话 schema；更新本 PLAN + HANDOFF
3. **Coding助手**：接到 HANDOFF 后改 `75b324a4`；改 `dev-bot-rules` 派活；心月 MCP 冒烟 + 隔离测；宣布切主
4. **首周**：盯夜审是否真覆盖 iMac 会话；没有则停扩下一仓
5. Pi：有 MCP 则同挂；否则 SessionStart HTTP hook

## 6. 风险

| 风险 | 对策 |
|---|---|
| 无 embedding → 无自动 skill_extraction / hybrid | 直接写 SKILL.md；search 用 `keyword` 直到加 embedding |
| 把 EverOS reflection 当成「审代码」 | reflection 只合并记忆碎片；审漏会话/不该合仍靠薄收集器 |
| OSS 不能 API 删 | 独立 root；手改 Markdown |
| MCP 不强制 recall | AGENTS 硬性要求；不够再加 SessionStart hook |
| 旧 VPS 已关机 | 运维先开机/确认快照 |
| 与 Raven EverOS 混淆 | VPS 独立实例；不经 Raven |

## 7. 本期范围（Zack：全上）

- 做：VPS EverOS + 域名、Mac 备份、导入心月 LESSONS、接派活会话挂 MCP、夜审改会话级双机、切主停 LESSONS、更新 dev-bot-rules
- 暂缓：广告/官网建独立夜审（hook 可先挂同产品 app）；Raven 编排；其它记忆产品
- 依赖：运维开机+DNS；eggbot 给出 base URL/MCP；Coding助手 改夜审与派活

## 8. 分工与阻塞

**Owner**：ops 系统（EverOS 服务端、部署、教训导入、写入的唯一写入方；Orca CLI 装管）；dr eggbot 只读，只做查询/核对

**进行中 / 已完成（eggbot）**
1. deepvision 运维：开机 `157.230.194.108`、DNS `everos.deepvision.sg`（橙云）、SSH/证书可达 — **已完成**
2. eggbot：Orca ops 工作区装 EverOS + 反代 + LESSONS 导入 + 交 HANDOFF — **已完成**
   - EverOS 1.4.2 health 200；Cloudflare 公网路径保留
   - headscale 已恢复（Zack 2026-10-16）；节点 online：`imac 100.64.0.4` / `site 100.64.0.5` / `box 100.64.0.6`；详见 site `/opt/headscale/OPERATIONS.md`
   - LLM → iMac magpie `http://100.64.0.4:3425/v1`（模型 `codex/gpt-6.1-sol`，Zack 定；embedding 未配置，health embed=false，待有效 Qwen/DashScope key）；`/add`+`/flush` 已验
   - **LESSONS 已导入（15 skills，2026-10-16）**；已叫醒 Coding助手
   - **Mac 日备**：Zack「继续搞，除了 imac 备份」— **暂缓**
3. headscale OPERATIONS.md 已补 site/box 节点与 restore 说明（2026-10-16）

**Coding助手 已认领（接到规格后做）**
1. 改 box `75b324a4` prompt（会话级+双机采集→写 EverOS）
2. 改 `dev-bot-rules` 派活段（挂 MCP + recall；子 worker 贴 brief）
3. 心月 MCP 冒烟 + `app_id`/`project_id` 隔离验收 → 宣布切主
4. 首周盯 iMac 会话是否进夜审；iMac `0ad74d58` 保持 disabled

## 9. 参考

- https://github.com/EverMind-AI/EverOS
- https://github.com/EverMind-AI/EverOS-MCP
- https://docs.evermind.ai/llms.txt（v2 API、MCP、memory types）
- 本地约束：`/workspace/ops/raven-memory/REPORT.md`（Raven 不注入子 agent）
- 现错题本：`xinyue-site/docs/solutions/LESSONS.md`

---
路径：`/workspace/ops/everos-lessons-plan/PLAN.md`
