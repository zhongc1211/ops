# EverOS 记忆接入调研（只读）

- 时间：2026-10-15 21:58–22:10（本机 UTC+8；EverOS 日志用 UTC）
- 执行者：Claude Code（Opus 5.5），按 `~/orca/briefs/everos-research.md` 执行
- 对象：EverOS 1.4.1（随 Raven 0.2.4 用 uv 安装，`~/.local/share/uv/tools/raven/`，下文简写 `SP/` = 其 `lib/python3.12/site-packages/`）
- 现有配置、hook、Raven、magpie、wake 方案都没有改。现有记忆没有删、没有改：试跑前后对 `~/.raven/everos` 下所有 md/toml 做了 shasum，前后一致（`diff` 无输出，见第 7 节）。
- 所有试跑都在临时实例里做：把现有记忆的 md 复制到 scratch 目录，起一个独立的 EverOS（端口 18899），结束后已停掉进程、删除副本。
- 证据文件在 `~/orca/everos/evidence/`。报告和证据里没有 key、token、webhook URL。

## 结论

| # | 问题 | 结论 | 验证程度 |
|---|---|---|---|
| 1 | 不启动 Raven 能否单独运行 | **能**。`everos server start --root <目录>` 单独起 HTTP 服务，接口是 HTTP（`/api/v2/memory/add`、`/flush`、`/search`、`/get`）。没有 MCP，CLI 只有启动和运维命令，没有读写记忆的命令 | 已实测 |
| 2 | 怎么接进 Claude Code 和 Pi | 两种都可行：**读**用 hook 自动注入（Claude Code `UserPromptSubmit`，Pi `before_agent_start`），**写**用工具调用（Claude Code 走 Bash+curl，Pi 走扩展注册的工具）。两个真会话都读到了、写进了，Pi 还读到了 Claude Code 刚写的那条 | 已实测（测试命名空间）；"写入后由 LLM 抽取成 episode"这一步没跑通，原因见下 |
| 3 | 写错的记忆能不能删、改 | 能，方法是改 md 源文件，EverOS 会自动同步索引：episode 和原子事实在 frontmatter 的 `deprecated_entries` 里标删除；用户画像直接改 `user.md`。XYZTEST 那 10 条原子事实和 `user.md` 都有办法清掉。**没有删除/修改的 HTTP 接口** | 已在副本上实测，正本未动 |
| 4 | 能否按项目隔离 | 能。`app_id` / `project_id` 是请求参数，直接对应磁盘目录 `<root>/<app_id>/<project_id>/`，检索强制按这两个字段过滤。心月和 deepvision 两个测试项目互相读不到 | 已实测（缓冲层）；抽取后的 episode 层只看了源码 |
| 5 | 用哪个模型、花多少钱、是否走 magpie 3425 | 现在跑着的 EverOS 只用一个 LLM：`claude-haiku-5-5`，**走 magpie 3425**，magpie 再用 Claude 订阅账号转发到 api.anthropic.com。embedding、rerank、多模态都没配置，不花钱。历史 38 次调用折合 API 价约 **$0.05**。注意：Raven 配置里已改成 Sonnet 5.5，EverOS 重启后生效，同样用量折合约 **$1.08**（约 20 倍） | 来自进程环境变量、magpie 用量日志和价目表 |

> **2026-10-15 23:00 更正：** 第 4 项"能按项目隔离"在抽取后的检索层**不成立**。同一个 user_id 在两个项目写入时，索引 id 会冲突，画像也不分项目。详见文末「后续执行」第 1 项。

**当前有一个问题需要知道：magpie 现在没在运行**（3425 端口没人监听，用量日志最后一条是 02:24）。所以现在线上 EverOS 的写入只能进缓冲区，抽取会失败。临时实例里 `/flush` 实测报 `LLMError: Connection error`。我没有启动 magpie（brief 要求不动 magpie）。这也是第 2 项里"抽取成 episode"没跑通的原因。

---

## 1. 单独运行

**接口形态**
- HTTP（FastAPI）。路由定义在 `SP/everos/entrypoints/api/routes/`，`app.py:138-150` 同时挂在 `/api/v1` 和 `/api/v2`：
  - `POST /memory/add`（写入消息，`defer_extraction=true` 时只进缓冲区）
  - `POST /memory/flush`（把缓冲区交给 LLM 抽取，OSS 版才有）
  - `POST /memory/search`（检索，返回 episodes / profiles / agent_cases / agent_skills / unprocessed_messages）
  - `POST /memory/get`（按类型分页列出：episode / profile / agent_case / agent_skill）
  - 另有 `/health`、`/metrics`、`/ome/trigger`、`/cascade/quiesce`、`/knowledge/*`
  - **没有** delete / update 记忆的路由。
- MCP：没有。`grep -rli mcp SP/everos` 结果为 0。
- CLI：`everos --help` 只有 `init / demo / server / cascade / config`，`everos server` 只有 `start`。

**实测命令**（临时目录，不碰正本）

```
# 复制现有 md 到 scratch（排除 .index/.lock/.tmp），端口改成 18899
rsync -a --exclude .index --exclude .lock --exclude .tmp ~/.raven/everos/ $S/everos-tmp/

# 用干净环境启动，只给 LLM 三个变量（key 用占位字符串）
env -i HOME=$HOME PATH=/usr/bin:/bin EVEROS_ROOT=$S/everos-tmp \
  EVEROS_LLM__MODEL=claude/claude-haiku-5-5 EVEROS_LLM__BASE_URL=http://127.0.0.1:3425/v1 \
  EVEROS_LLM__API_KEY=dummy-not-a-secret \
  ~/.local/share/uv/tools/raven/bin/everos server start --root $S/everos-tmp

curl -s localhost:18899/health
→ {"status":"ok","version":"1.4.1","capabilities":{"llm":true,"embed":false,"rerank":false,"multimodal_llm":false,"parser":true},
   "disabled_features":["vector_search","hybrid_search","reflection","skill_extraction","agentic_search","knowledge","multimodal_upload"], ...}
```

启动后 cascade 自动从 md 重建索引（日志 `cascade_worker_processed ... kind=episode ... upserted=7`），说明 md 是唯一数据源，索引可以随时从 md 重建。

**单独运行要注意的两点**
- LLM 必须配置，否则服务不启动（`SP/raven_everos/config.py:812` `REQUIRED_ROLES = ("llm", "embedding")`，`unclearable_roles` 注释："EverOS refuses to start without it"）。Raven 是通过环境变量 `EVEROS_LLM__*` 传进去的，`everos.toml` 里的 key 全是空的。单独运行时要自己传这几个变量。
- 没配 embedding 时只能用 `method: "keyword"`，`hybrid`/`vector` 不可用（health 里 `vector_search`、`hybrid_search` 被禁用）。

## 2. 接进 Claude Code 和 Pi

EverOS 没有 MCP，也没有现成的 Claude Code / Pi 插件，需要自己写一层薄封装。两种方式我都实测了：

| | 读（自动注入） | 写 |
|---|---|---|
| Claude Code | `UserPromptSubmit` hook：每轮用用户这句话去 `/search`，结果放进 `additionalContext` | 模型用 Bash 调 curl 写 `/add`（也可以做成 `Stop` hook 自动写，未测） |
| Pi | 扩展里 `pi.on("before_agent_start")` 返回一条 message | 扩展里 `pi.registerTool("everos_remember")` |

选择上：读适合做成 hook 自动注入（每轮都要，模型不用记得去查）；写适合做成工具（让模型决定什么值得记，避免把整段对话都塞进去）。如果要像 Raven 那样每轮自动存，也可以用 Claude Code 的 `Stop` hook / Pi 的 `agent_end` 把对话发到 `/add`，但每轮都会触发 LLM 抽取，花钱更多。

**测试命名空间**：`app_id=orca-test`，`project_id=xinyue` / `deepvision`，`user_id=zack`，session 都以 `everos-research-` 开头，全部在临时实例里，没有写进正本。

**测试用文件**（都只在 scratch 里用过，已复制一份到 `evidence/`）：
- `everos_recall.py`：查询临时实例，输出 Claude Code hook 要的 JSON 或 Pi 要的纯文本
- `cc-settings.json`：只含一个 `UserPromptSubmit` hook，用 `claude --settings` 单次传入，不改全局设置
- `everos-test.ts`：Pi 扩展，用 `pi -e` 单次加载，不安装

**Claude Code 真会话**（`claude-haiku-5-5`，空目录）

```
claude -p --model claude-haiku-5-5 --settings $S/integ/cc-settings.json --allowedTools "Bash(curl:*)" \
  "…第一步：只根据你上下文里 '# EverOS memory' 段的内容回答：心月项目的部署机器叫什么？…
   第二步：用 Bash 原样执行这条命令写入一条测试记忆…"
```
输出（全文 `evidence/cc-run.txt`）：
> **第一步：** 心月项目的部署机器叫 **PINEAPPLE-XY**。这来自上下文中的 `# EverOS memory` 段（app=orca-test, project=xinyue）。
> **第二步：** … `{"request_id":"715a774a…","data":{"message_count":1,"status":"accumulated"}}`

PINEAPPLE-XY 只存在于临时实例里，模型只能从 hook 注入拿到。

**Pi 真会话**（Pi 默认模型，settings 里是 `openai gpt-6.1-sol`）

```
pi -p --no-session -e $S/integ/everos-test.ts "…心月项目的部署机器叫什么、测试端口是多少？…调用 everos_remember 工具写入…"
```
输出（全文 `evidence/pi-run.txt`）：
> 第一步：根据本轮注入的 EverOS memory，心月项目的部署机器叫 **PINEAPPLE-XY**，测试端口是 **41234**。
> 第二步：已调用 `everos_remember` … `{"request_id":"6b847e46…","data":{"message_count":1,"status":"accumulated"}}`

测试端口 41234 是上一步 Claude Code 写进去的，说明两个 agent 共用同一份记忆。

**回读**：
```
python3 -I everos_recall.py pi        # project=xinyue
- [TEST everos-research] 心月项目的部署机器叫 PINEAPPLE-XY。
- [TEST everos-research] Claude Code 写入：心月的测试端口是 41234。
- [TEST everos-research] Pi 写入：心月的预发域名是 staging-xy.test。
```

**没跑通的部分**：正式使用时，写入的消息要经 LLM 抽取成 episode / 原子事实 / 用户画像，检索才会命中（不带 session 过滤也能搜到）。这一步需要 3425，现在 magpie 没运行：
```
curl -s localhost:18899/api/v2/memory/flush -d '{"session_id":"everos-research-iso-xinyue","app_id":"orca-test","project_id":"xinyue"}'
→ {"error":{"code":"INTERNAL_ERROR","message":"Internal server error",…}}
日志：LLMError: Connection error.
```
所以上面的读写测试用的是缓冲区：`defer_extraction=true` 写入，检索时用 `filters.session_id` 读回 `unprocessed_messages`（`SP/everos/memory/search/manager.py:285-304`）。这证明了"写得进、读得到、注入到会话里"，但没有证明抽取后的 episode 检索效果。magpie 恢复后再跑一次 `/flush` 就能补上。

## 3. 删除和修改

**机制**：EverOS 以 md 文件为准，LanceDB 索引（`.index/`）是从 md 派生的。cascade 每 30 秒扫描一次，md 一变就重建对应索引行（`SP/everos/memory/cascade/handlers/`）。所以删、改都应该改 md，不能只删索引行，否则下次同步会恢复（Raven `SP/raven_everos/backend.py:1487-1513` 的注释也是这样写的）。

| 记忆类型 | 删除 | 修改 | 依据 |
|---|---|---|---|
| episode | frontmatter `deprecated_entries` 加 `<id>: deleted-by-user` | 改条目正文 | `_daily_log_base.py:223-239` 把 `deprecated_entries` 同步成 `deprecated_by` 列；检索强制 `deprecated_by IS NULL`（`memory/search/filters.py:66-67`） |
| 原子事实 | 同上（文件 `users/<u>/.atomic_facts/atomic_fact-<日期>.md`） | 改 `### Fact` 段 | `infra/persistence/markdown/mds/atomic_fact.py:41` 有 `deprecated_entries` 字段；`AtomicFactHandler` 继承同一个基类 |
| 用户画像 | 删 `user.md` frontmatter 里对应的 `explicit_info` / `implicit_traits` 条目 | 直接改 `user.md` | `cascade/handlers/user_profile.py`："replaced wholesale on edit" |
| agent_case | 没有现成写法 | — | Raven `backend.py:1508-1510` |
| agent_skill | `AgentSkillWriter.delete_skill` | — | 同上 |

Raven 上次报告说原子事实"删不了"，指的是 Raven 的 `delete()` 没实现；EverOS 自身的 md 格式和同步逻辑是支持的。

**XYZTEST 现状**（在副本上查，和正本内容一致）
```
search keyword "XYZTEST test command prefix" (include_profile=true)
→ episodes 0, profiles 1；返回内容里 XYZTEST 出现 5 次，全部来自 user.md
search keyword "XYZTEST" → episodes []
get memory_type=episode → 2 条（01、02），XYZTEST 0 次
get memory_type=profile → XYZTEST 5 次
```
那 10 条原子事实（`af_20261014_00000058`~`…067`）现在已经检索不到，因为检索结果按 episode 返回，它们的父 episode 03 已标删除；`/get` 也不支持列出原子事实。真正还会进 prompt 的只有 `user.md`。

**在副本上实测的清理方法**（正本没动）
1. 在副本的 `atomic_fact-2026-10-14.md` frontmatter 加 `deprecated_entries`，列出 058–067，值为 `deleted-by-user`。
2. 在副本的 `user.md` 里删掉 frontmatter 中提到 XYZTEST 的条目：`explicit_info` 从 6 条剩 4 条（删掉"当前关注点：EverOS 记忆注入…"和"技术偏好：XYZTEST 前缀规则"）；`implicit_traits` 删掉"源码验证导向"（它的 evidence 引用了 XYZTEST）。
3. 约 30 秒后 cascade 自动同步：
```
cascade_worker_processed change_type=modified kind=user_profile md_path=…/users/default/user.md upserted=1
cascade_worker_processed change_type=modified kind=atomic_fact md_path=…/atomic_fact-2026-10-14.md skipped=150
get memory_type=profile → XYZTEST 0 次
LanceDB atomic_fact：150 行，deprecated 10 行（default_af_20261014_00000058 … 067）
LanceDB episode：deprecated = 03、04、05、06、07
```

**在正本上执行的步骤（只写方法，没执行，需要 Zack 批准）**
1. 备份 `~/.raven/everos/default_app/default_project/users/default/`。
2. 改 `.atomic_facts/atomic_fact-2026-10-14.md` 的 frontmatter：`deprecated_entries` 加 058–067（实测两轮的 068–150 也提到 XYZTEST，可一起加）。
3. 改 `user.md`：删掉上面 3 个条目；body 只有一句"default 使用中文与助手交流。"，不用动。
4. 不用重启服务；等 30 秒后用 `/get memory_type=profile` 确认 XYZTEST 为 0。
5. 风险：以后 EverOS 重新生成画像时，会在现有 `user.md` 的基础上合并新 episode。因为相关 episode 都已标删除，理论上不会再把 XYZTEST 带回来，但"重新生成画像会不会读已删除的 episode"我没有验证。另外这两份文件 Raven 运行时也会写，最好在 Raven 不活动时改。

## 4. 按项目隔离

- 写入、检索、列出都带 `app_id` 和 `project_id`（默认都是 `default`），只允许字母数字和 `_ . @ + -`，且拒绝 `.` / `..`（`routes/memorize.py`）。
- 磁盘上直接对应目录：`<root>/<app_id>/<project_id>/users/<user_id>/…`。现有数据就在 `default_app/default_project/` 下。
- 检索时这两个字段是强制过滤条件，请求的 `filters` 里不允许覆盖（`memory/search/filters.py`：`RESERVED_FIELDS = {"owner_id","owner_type","app_id","project_id"}`，`compile_filters` 固定加 `eq("app_id")`、`eq("project_id")`）。
- 缓冲区也按项目分开（`unprocessed_buffer_repo.list_for_track(session_id, …, app_id=…, project_id=…)`）。

**实测**（临时实例）：心月写一条"部署机器叫 PINEAPPLE-XY"，deepvision 写一条"部署机器叫 MANGO-DV"，然后交叉查询：
```
project=xinyue     session=everos-research-iso-xinyue → ['…心月项目的部署机器叫 PINEAPPLE-XY。']
project=xinyue     session=everos-research-iso-dv     → []
project=deepvision session=everos-research-iso-xinyue → []
project=deepvision session=everos-research-iso-dv     → ['…deepvision 的部署机器叫 MANGO-DV。']
```
接入后的 hook 也一样：用 `project=deepvision` 调 `everos_recall.py`，只返回 MANGO-DV，看不到 Claude Code 和 Pi 写进心月的那三条。

**限制**：
- 隔离靠调用方传对 `project_id`。hook 里要按工作目录映射项目（例如 `~/xinyue*` → `xinyue`，`~/deepvision*` → `deepvision`），映射错了就会串。
- 一个 `project_id` 下的用户画像只有一份（每个 `user_id` 一个 `user.md`），所以画像也是按项目分开的。如果希望有一份跨项目共用的"关于 Zack"的画像，需要另开一个项目（如 `project_id=global`），hook 里查两次再合并。
- 抽取后的 episode 层隔离只看了源码（同一套过滤），没实测，原因同第 2 节。

## 5. 模型、费用、是否走 magpie

**现在跑着的 EverOS 用什么**（PID 74903，01:12 启动；从进程环境变量读出，key 已隐去）
```
ps eww -p 74903 | tr ' ' '\n' | grep ^EVEROS_
EVEROS_LLM__MODEL=claude/claude-haiku-5-5
EVEROS_LLM__BASE_URL=http://127.0.0.1:3425/v1
EVEROS_LLM__API_KEY=<已设置，已隐去>
EVEROS_EMBEDDING__MODEL=      （空）
EVEROS_RERANK__MODEL=         （空）
EVEROS_MULTIMODAL__MODEL=     （空）
```
- `everos.toml` 里写的 openrouter / deepinfra 那些模型**不生效**：它们的 key 全是空的，Raven 用环境变量覆盖（`SP/raven_everos/config.py` 开头说明）。
- **各环节**：
  - 抽取（边界检测、episode、原子事实、用户画像、agent_case）：都用这一个 LLM，Haiku 5.5，走 magpie 3425。
  - 检索：本机只有 keyword（BM25），不调模型。`agentic_search` 也会用同一个 LLM（日志 `decider_client_built … inherits_model=True`），但现在被禁用。
  - embedding / rerank / 多模态：没配置，不花钱。
  - foresight 抽取和 reflection 默认关闭（`ome.toml`）。
- **会变的地方**：`~/.raven/config.json`（01:20 修改）里 `plugins.config.everos-memory.llm` 已经是 `custom/claude/claude-sonnet-5-5`，而 EverOS 进程是 01:12 启动的，所以还在用 Haiku。EverOS 下次被 Raven 重启时会换成 Sonnet 5.5。

**magpie 链路**（`~/.config/magpie/usage.jsonl`，按 agent 和模型汇总）
```
('AsyncOpenAI', 'claude-haiku-5-5', '/v1/chat/completions → /v1/messages', 'claude')
  n=38, in=76, out=45,962（其中 reasoning 27,212）, cache_read=95,663, cache_write=150,039, err=0
  时间 2026-10-15 01:21–02:24；上游全部是 api.anthropic.com（Claude 订阅账号）
```
`AsyncOpenAI` 是 EverOS 用的 openai SDK 客户端；Raven host 自己的调用是 `python-httpx` / Opus 5.5，单独计算。这 38 次对应约 5 次抽取（GitHub CI 问答、上次调查的一次性问答、XYZTEST 测试、实测两轮），平均每次约 7–8 次 LLM 调用。

**费用**
- 实际：走的是 Claude 订阅账号，按订阅额度算，不按 token 单独计费。
- 折合 API 价（Haiku 5.5：输入 $0.10/M、输出 $0.50/M；缓存写入按 1 小时缓存 2× 输入价 $0.20/M、缓存读取按 0.1× 输入价 $0.01/M 估算，这两个倍率是我的假设）：
  - 输出 45,962 × $0.50/M ≈ $0.023
  - 缓存写入 150,039 × $0.20/M ≈ $0.030
  - 缓存读取 95,663 × $0.01/M ≈ $0.001
  - **合计约 $0.054，每次抽取约 $0.01**
- 换成 Sonnet 5.5（$2 / $10，缓存读取 $0.20/M，缓存写入按 $4/M 估）同样用量约 **$1.08，每次抽取约 $0.2**，大约贵 20 倍。
- 如果接入后每轮对话都自动写入并抽取，费用和对话轮数成正比；只在模型调用工具时写入则少得多。

## 6. 建议（供 Zack 决定）

1. 先恢复 magpie（或者给 EverOS 配一个不依赖 magpie 的 LLM），否则抽取一直失败，现在线上的 Raven 写入也只会积压在缓冲区。
2. EverOS 的 LLM 用 Haiku 5.5 就够（结构化抽取任务），比 Sonnet 5.5 便宜约 20 倍。如果同意，把 `~/.raven/config.json` 里 `everos-memory.llm` 改回 Haiku；不用 Raven 时则直接在启动命令里传 `EVEROS_LLM__MODEL`。
3. 不用 Raven 编排的话，EverOS 可以用 launchd 单独常驻（`everos server start --root …`），Claude Code 和 Pi 各加一个读 hook / 扩展、一个写工具，按工作目录映射 `project_id`。第 2 节的三个测试文件可以作为起点，但它们只连临时实例、只读缓冲区，正式用要改成按 episode/画像检索。
4. XYZTEST 清理按第 3 节的步骤执行，需要你批准。

## 7. 清理与核对

```
pkill -f "everos server start --root $S/everos-tmp"
lsof -nP -iTCP:18899 -sTCP:LISTEN → 无（18899 closed）
rm -rf $S/everos-tmp
diff live-hashes-before.txt live-hashes-after.txt → 无差异（~/.raven/everos 下所有 md/toml 未变）
ls -d ~/.everos → 不存在（临时实例没有写到默认位置）
```
- 正本 EverOS（18791）只做过 `/health`、`/openapi.json` 两次只读请求。
- 测试用的 Claude Code / Pi 会话只连临时实例。Claude Code 用 `--settings` 单次传入 hook，Pi 用 `-e` 单次加载扩展、`--no-session` 不存会话。
- 没写单元测试，没有 commit，没有 push。

## 8. 没做到或不确定的部分

- LLM 抽取（`/flush` 和自动抽取）没跑通：magpie 未运行，3425 不通。抽取后的 episode 检索、画像生成、episode 层的项目隔离都只看了源码。
- 画像重新生成会不会读到已标删除的 episode、把 XYZTEST 带回来：没验证。
- 用 `Stop` hook / `agent_end` 每轮自动写入的方式没有实测，只实测了"模型调用工具写入"。
- Haiku 5.5 的缓存写入、读取单价是按常见倍率估的，不是查到的确切价格。

---

## 后续执行（2026-10-15 22:52 Zack 批准三项，22:55–23:00 执行）

- 执行者：Claude Code（Opus 5.5），按 `~/orca/briefs/everos-followup.md` 执行。
- 结果：第 1 项**判定失败**（EverOS 本身的问题，不是测试方法的问题）；第 2、3 项完成并核对通过。
- 没写单元测试，没有 commit，没有 push。报告和证据里没有密钥。
- 证据在 `~/orca/everos/evidence/followup/`，备份在 `~/orca/everos/backups/20261015-followup/`。注意：备份里的 `config.json.bak` 是 Raven 配置原件，里面有 key，不要外发。

### 1. 补测抽取（临时实例）：判定失败

**做法**：新建一个空的临时 EverOS（scratch 目录，端口 18899），LLM 设为 `claude/claude-haiku-5-5`，经 magpie 3425 转发。key 由启动脚本从 `~/.raven/config.json` 直接读进环境变量，没有打印，也没有写进文件。两个项目 `orca-test/xinyue`、`orca-test/deepvision`，同一个 `user_id=zack`，各写 4 条对话（2 问 2 答），各 `/flush` 一次。只跑了这一次。

**事先定的判定标准**：①两次 flush 都返回 `extracted`；②每个项目都生成 episode、原子事实、user.md；③`PINEAPPLE` 只在心月搜得到，`MANGO` 只在 deepvision 搜得到；④画像不串项目。

**结果**

| 标准 | 结果 |
|---|---|
| ① flush | 通过。心月 `{"status":"extracted"}`（15.0 秒），deepvision `{"status":"extracted"}`（26.7 秒） |
| ② md 文件 | 通过。每个项目 1 条 episode；原子事实心月 6 条、deepvision 7 条；各有一份 user.md。md 内容没有串项目（心月文件 PINEAPPLE 3 次、MANGO 0 次；deepvision 相反） |
| ③ 检索隔离 | **失败**。见下 |
| ④ 画像隔离 | **失败**。见下 |

```
project=xinyue     query=PINEAPPLE-XY 部署机器 episodes=[]                          | profile:PINEAPPLE=0 profile:MANGO=3
project=xinyue     query=MANGO-DV 部署机器    episodes=[]                          | profile:PINEAPPLE=0 profile:MANGO=3
project=deepvision query=PINEAPPLE-XY 部署机器 episodes=['zack_ep_20261015_00000001'] ep:MANGO=3 | profile:MANGO=3
project=deepvision query=MANGO-DV 部署机器    episodes=['zack_ep_20261015_00000001'] ep:MANGO=3 | profile:MANGO=3
```
心月搜不到自己的 episode，返回的画像却是 deepvision 的。

**原因**（查了临时实例的索引和源码）：
```
episode: 1 rows      id=zack_ep_20261015_00000001 project=deepvision
atomic_fact: 7 rows  id=zack_af_20261015_0000000{1..7} project=deepvision
user_profile: 1 rows id=zack project=deepvision
cascade 日志：xinyue 的 episode/atomic_fact/user_profile 先 upserted=1/6/1，deepvision 随后 upserted 同样的 id
```
- 索引 id 只由 `<user>_ep_<日期>_<序号>` 组成，不含 app/project；索引写入按 `id` 做 upsert（`SP/everos/infra/persistence/index/router.py:47` `upsert(..., by="id")`）。同一个 user 在两个项目的同一天里，id 都从 00000001 开始，后写的项目覆盖先写的。md 文件分目录存放，没有丢；但检索用的是索引，所以先写的项目就搜不到了。
- 画像检索只按 owner 取，不看项目（`SP/everos/memory/search/manager.py:628-631` `self._profile.fetch(req.owner_id)`），画像索引 id 就是 `zack`。

**对第 4 项结论的更正**：上一节说"能按项目隔离"，只在缓冲区和 md 目录层面成立。抽取后的检索层，同一个 user_id 跨项目会互相覆盖。

**可能的规避办法（没有测试）**：每个项目用不同的 `user_id`（例如 `zack@xinyue`、`zack@deepvision`）。这样 id 前缀不同，不会冲突；画像也按 owner 分开。代价是没有跨项目共用的画像。brief 要求只跑一次，所以这个办法我没有再测。要用它，需要 Zack 批准再跑一次。

**清理**：临时实例已停掉（18899 已关闭），scratch 目录已删除。抽取出来的 md、索引行和服务日志都留在 `evidence/followup/`（`x-write.txt`、`x-search.txt`、`x-index.txt`、`x-server.log`、`x-md/`）。

**费用**：两次抽取经 magpie 调用 Haiku 5.5，各约十几到二十几秒。按上一节的估算，每次约 $0.01（API 折算价，实际走订阅额度）。

### 2. EverOS 的模型改回 Haiku：完成

```
cp -p ~/.raven/config.json ~/orca/everos/backups/20261015-followup/config.json.bak
（改前 shasum 两份一致：ad5ee092…）
只替换 "everos-memory" 块里 llm.model 那一处（同一字符串在 providers.custom.models 列表里也出现，没动）

diff config.json.bak ~/.raven/config.json
16c16
<           "model": "custom/claude/claude-sonnet-5-5",
---
>           "model": "custom/claude/claude-haiku-5-5",

逐键对比 JSON：changed keys: ['.plugins.config.everos-memory.llm.model']
```
用 Raven 自己的读取函数核对（只读）：
```
role_pin(llm) = ('custom/claude/claude-haiku-5-5', 'custom')
resolve_role(llm): model=claude/claude-haiku-5-5 base_url=http://127.0.0.1:3425/v1 key=SET
正本 EverOS 进程（PID 74903）：EVEROS_LLM__MODEL=claude/claude-haiku-5-5   ← 一致
```
**没有重启**：Raven gateway（PID 85449）还在运行，可能有会话在用；正本 EverOS 本来就在用 Haiku，不重启也一致。下次 Raven 重启 EverOS 时会读到新配置，仍然是 Haiku。

**回滚**：`cp -p ~/orca/everos/backups/20261015-followup/config.json.bak ~/.raven/config.json`

### 3. 清理正本的 XYZTEST：完成

**开始前发现的变化**：magpie 恢复后，正本在 22:28 又做过抽取。新增了 `episode-2026-10-15.md`、`atomic_fact-2026-10-15.md`（这两份里 XYZTEST 都是 0 次），`user.md` 也重新生成过：新增"deepvision.sg 视觉改版"和"任务委托型"两条，但 XYZTEST 那 3 条原样保留。这说明重新生成画像时会沿用旧画像里的条目，不手动删的话会一直留着。

**备份**
```
~/orca/everos/backups/20261015-followup/everos-users-default/   ← users/default/ 整个目录（diff -r 与原目录一致）
~/orca/everos/backups/20261015-followup/hashes-before.txt        ← 改前 ~/.raven/everos 下全部文件的 shasum
```

**修改**：用 EverOS 自带的 `parse_frontmatter` / `dump_frontmatter`（`SP/everos/core/persistence/markdown/frontmatter.py`），只重写文件头，正文逐字不变（脚本里断言过）。
- `users/default/.atomic_facts/atomic_fact-2026-10-14.md`：frontmatter 加 `deprecated_entries`，列出 `af_20261014_00000058` ~ `…067` 共 10 条，值为 `deleted-by-user`。
  - 选取依据：这个文件里属于植入测试 session `test:raven-memory-xyztest-20261015` 的条目正好是这 10 条。第一次执行时我用"正文含 XYZTEST"做检查，058、062、067 三条没出现这个词（内容分别是"有人设定了一条项目规则"、"这是植入的测试记忆"、"没有其他话题"），检查不通过，脚本在写入前就退出了，文件没被改动（哈希未变）。改成按 session 检查后重新执行。
- `users/default/user.md`：删掉 frontmatter 里的 3 条，`explicit_info` 7→5，`implicit_traits` 4→3：
  - `explicit_info`「当前关注点」：Raven 中 EverOS 记忆注入…（含 XYZTEST 2 次）
  - `explicit_info`「技术偏好」：运行测试命令时须以 XYZTEST 作为前缀（2 次）
  - `implicit_traits`「源码验证导向」（evidence 里提到 XYZTEST 1 次）

**索引同步**（正本 EverOS 日志）
```
14:57:55Z cascade_worker_processed change_type=modified kind=user_profile …/users/default/user.md upserted=1
14:57:56Z cascade_worker_processed change_type=modified kind=atomic_fact  …/atomic_fact-2026-10-14.md skipped=150 upserted=0
```

**哈希对比**（`diff hashes-before.txt hashes-after.txt`）：只有两个目标文件变了，其余 7 个文件（agent_case、两份 episode、atomic_fact-2026-10-15、everos.toml、ome.toml、.raven-role-digest）不变。
```
< 60efd885…  …/.atomic_facts/atomic_fact-2026-10-14.md
> 31efc533…  …/.atomic_facts/atomic_fact-2026-10-14.md
< 7d44dfaf…  …/users/default/user.md
> d4237fe6…  …/users/default/user.md
```

**用正本 /search 证明搜不到**（`evidence/followup/live-search-after.txt`）
```
search 'XYZTEST test command prefix': episodes=[] profiles=1 XYZTEST_in_response=0
search 'XYZTEST':                     episodes=[] profiles=1 XYZTEST_in_response=0
search 'pytest 前缀 测试命令 规则':     episodes=['default_ep_20261014_00000001'] profiles=1 XYZTEST_in_response=0
get profile: XYZTEST = 0
get episode: count = 7 XYZTEST = 0
对照 search 'github CI 额度':          episodes=['default_ep_20261014_00000001']        ← 其他记忆照常可搜
对照 search 'deepvision.sg 视觉 ryze': episodes=[…20261015_00000001 … 00000005]          ← 22:28 的新记忆照常可搜
正本索引 atomic_fact：214 行，deprecated 10 行（default_af_20261014_00000058 … 067）
```
改前用同样的 `include_profile` 检索，返回内容里 XYZTEST 出现 5 次，全部来自 user.md（见第 3 节）；改后是 0 次。

**没处理的部分**：实测两轮对话抽出的原子事实 068–150 里也有提到 XYZTEST 的。它们的父 episode 04–07 已经标删除，检索不会返回；这次也不在批准范围内，所以没动。

**回滚**
```
cp -p ~/orca/everos/backups/20261015-followup/everos-users-default/.atomic_facts/atomic_fact-2026-10-14.md \
      ~/.raven/everos/default_app/default_project/users/default/.atomic_facts/
cp -p ~/orca/everos/backups/20261015-followup/everos-users-default/user.md \
      ~/.raven/everos/default_app/default_project/users/default/
```
约 30 秒后 cascade 会自动重新同步，不用重启。注意：如果之后 EverOS 又重新生成了画像，用备份的 user.md 覆盖会丢掉这期间新加的画像条目。

### 需要 Zack 决定

1. 项目隔离：是否批准再跑一次临时实例测试，验证"每个项目用不同 user_id"这个规避办法。不验证的话，心月和 deepvision 不能共用一个 user_id 接入 EverOS。（推荐：批准，成本约 $0.02）
2. 是否向 EverOS 上游报告"索引 id 不含项目、画像不分项目"这个问题。报告属于对外发布，需要你批准；我可以先写好草稿给你看。

### 叫醒

本会话是用 `notify-run --tty --bot coding-assistant` 启动的。`orca-wake` 挂在 Claude Code 的 Stop hook 上，本轮结束、停在提示符时会自动通知 coding-assistant，不需要另外手动发送。
