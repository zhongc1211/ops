# S12 ③：宿主收尾草案（第 5 轮安装／顺序修复待验收）

第3轮版本已由独立验收方安装；第89条及收尾批准后执行的一次 E2E **失败，未重跑**：adapter 注入 MCP 参数，旧 host 在起模型前熔断。报告为私有归档 `E2E-s12-3.md` 的「最终续办」。该次触发额度已经用掉，不能因没启动模型而再次使用。

第5轮已读 `E2E2-s12-3.md`：复验停在安装前，第二次 E2E 未触发、未消耗。报告确认第92条已批准复验通过后的执行；本次阻断是代码门禁和顺序，不是实时费用或否认已有批准。本轮按派活只改代码，**不安装、不收尾 apply、不触发**，也没有在线重新核状态。下述顺序改为先收尾后重装，新 SHA／顺序的执行安排仍由主会话和验收方核对批准范围。

## 设计与信任边界

```text
Paperclip claude_local engine=cli
  -> host.py（adapterConfig.command，模型不可调用）
     -> GNU timeout -> 真 claude（原 extraArgs 不变，dontAsk，不 skip）
        -> 唯一 Bash allow：linear-safe.py read / log / comment
           -> 固定本机 Orca CLI：Linear 当前卡只读或一次评论
     -> Orca 只读核本次评论
     -> 宿主本机 API：本次 issue done，读回
     -> 才交还 Claude stream-json，退出
```

- 管理 HTTP 客户端只在 `host.py`，不在模型 helper。API origin 取安装器已有 config.sh；不取模型参数、不继承 proxy、不跟重定向。
- 模型没有原始 orca 权限，不能用其 `--environment` / `--pairing-code` 改目标；helper 不转发任何选项，只接受 read、log PATH、comment BODY。
- settings 完全拒绝 Read/Write/Edit 等，只有三个 Bash 命令模式。仅用 Read 的 allow 路径不是文件隔离，所以日志读取也走固定 helper。额外 `--tools Bash`、空 setting-sources、空 strict MCP 配置，避免继承用户 allowlist、额外工具或 MCP。
- 宿主／helper／配置／状态位于 agent-work 以外的私有目录。模型不能读写这些文件，也不能直接调用宿主。解释器的内部文件访问不是模型工具权限调用。
- 这依赖 Claude Code 对 Bash 参数、组合命令、环境前缀及重定向的权限检查；**不是操作系统级不同用户沙箱**。同一宿主用户的人仍可改文件。权限负例必须由验收方跑过，未过不装、不恢复。
- helper 本身可执行但不可读取其源文件；它只有固定 Orca 子命令，没有管理端口访问能力。日志只读限定本机目录，不跟随符号链接，不接受 `..` 或绝对路径。

## 时机证据：固定版本 v2026.1012.0

| 源码 | 结论 |
| --- | --- |
| `packages/adapters/claude-local/src/server/execute.ts:176,220–248,343–346` | 支持 config.command；注入本次 run/task 标识；保留 extraArgs |
| 同文件 `437,844–880,965–985`；`permissions.ts:11–12` | skip=false 不生成 bypass 参数；拼接原参数；await 包装进程 |
| 同文件 `484–486,978–981` | 默认最终结果清理窗口五秒；不能先泄露最终 result 再慢慢回查 |
| `server/src/services/heartbeat.ts:25964–25990` | 进程完成后评论／release／legacy reconciliation，无须等周期轮询 |
| `server/src/services/recovery/legacy-continuation.ts:25–30,62–84` | 最终消息不算处置；无处置最多两次修复执行 |
| `server/src/services/recovery/service.ts:3760–3908` | 成功的 legacy run 收尾即核持久处置、安排下一次（不是安全轮询窗口） |
| `server/src/routes/agents.ts:5764–5787` | pause 先写 paused，再 cancelActiveForAgent，可能终止包装脚本自身 |
| 同文件 `7003–7014,7156–7199` | 列运行、读运行、取消单次运行；列表最多一千条，不能假定无限历史 |
| `server/src/routes/issues.ts:13491–13533` | done 遇 active runner goal 可能先停运行；本方案仅接受 CLI 非 native，无 goal 的常规 routine；实际 E2E 必核 |
| 同文件 `3602–3617` | 没有 runner goal 时该额外停止分支返回空 |
| 同文件 `8414–8437`；`server/src/services/runner-goals.ts:276–349` | GET runner-goal 可指定 agent；返回绑定、goal 和 pendingAction。host 在启动前及 done 前要求同一绑定且后二者明确为 null，不把非 native 当无 goal |
| `server/src/routes/agents.ts:745–750,5305–5365` | 指令读回 content + revision；更新须带 baseRevisionId |
| 同文件 `5557–5558,5608–5628`；`packages/shared/src/validators/agent.ts:157` | replaceAdapterConfig=true 才跳过同类型 adapter 的默认浅合并；回滚须用全量替换移除新增键 |

宿主在结果交给 adapter 之前核 Linear 并 done；失败时**先持久熔断再暂停**，因为暂停 API 会杀本进程。停止模型和熔断不是模型能请求的管理工具。

## 第 4 轮：丢弃 adapter 自动注入的 MCP

固定版本的两个内建服务（按源码注入链重建，作者未读取真实 MCP 文件）：

| 服务 | 能力与源码 | agent 配置能否直接关闭 |
| --- | --- | --- |
| Paperclip connections | `heartbeat.ts:4937–4969,25012–25041`；`registry.ts:254–256` 将 claude_local 的 runtimeToolDelivery 固定为 native_mcp；入口 `/mcp/runtime-tools`，`connection-intent-guidance.ts:21–24` 列 connections_search / connections_request | 没有：条件是负责用户、可签发 token、服务 API 地址、adapter 注册常量，不读 agent adapterConfig 开关 |
| Paperclip projects | `heartbeat.ts:25043–25045`；`routes/project-tools.ts:11–35`、`services/project-tools.ts:6–15`；入口 `/api/mcp/project-tools`，可列／创建项目、列项目仓库，按工作模式可创建任务／改任务标题 | 没有：条件是 run authToken、API 地址和 issueRef，不是 agent 配置开关 |

`buildPaperclipRuntimeMcpServers` 的外部连接授权筛选（`heartbeat.ts:4616+`）与这两个随后 unshift 的内建入口是两层。清空工具 profile 或外部 MCP 分配不能取消它们；`enableMcpAggregators` 也不是这里的 per-agent 开关。没有添加无效的 `disableMcp` 字段、修改 adapter 类型／服务全局环境／服务源码或降级认证来绕开注入。**因此本轮不改 agent 配置；用宿主过滤落实第80条。**

`execute.ts:552–566,875–876,946–949` 将运行时列表写入私有配置，非空时自动追加 `--mcp-config <file> --strict-mcp-config`，不是 extraArgs。实际事件记录数量为2；完整真实参数顺序（所有路径换占位）在 `adapter-argv.example.json`。

- `args_checked` 成对识别并**丢弃**这两个输入参数及文件参数值；重复、缺失半对和未知旗标仍拒绝，resume/skip 也仍拒绝。
- 最终只有宿主自己的一个 `--strict-mcp-config` 和一个 `--mcp-config '{"mcpServers":{}}'`。其余已识别结构参数按原顺序保留，仍限制 Bash/dontAsk/空 setting-sources/两美元预算。
- 为准确记录丢弃数量，**仅宿主**按已核 settings 所属的 ops 实例及本次 company/agent/run 绑定路径，读取 adapter 自己生成的 MCP 配置计数。依据 `claude-config.ts:144–183`，该文件含 Authorization；因此拒绝不绑定路径、符号链接、非本人所有／非0600／非普通文件、超过一 MiB 或未知结构。内容不进入 child argv/env、日志、state 或异常输出；不请求任何 MCP 服务。
- stderr 只记 `ops-host: discarded adapter MCP servers: N`；私有 `state/mcp-filter.json` 仅含 run 和 discardedServers，不存名称、URL、token、文件路径或原文。无注入时记0；未知不能冒充0，直接熔断。
- 这是运行时宿主的特定私有读取，不是给模型新增 Read/MCP/网络能力。本轮作者未打开这次真实 mcp-config.json；计数逻辑尚未在真实 adapter 上执行。

可在离线源码目录执行以下**参数契约检查**，不会运行 Claude、API、权限自查或读真实 MCP 文件：

```sh
python3 -I paperclip/imac/ops-system/check-adapter-argv.py
```

检查使用事件里的完整 argv 而非仅 extraArgs，核其它参数全部被识别且原样保留、旧 MCP 路径不被转发、末尾只有 strict 空配置。它不能替代真实 adapter 集成或工具权限验收。

## 什么算写成

1. 从服务端核 run/company/agent/task、issue executionRunId 和指定 routine 归属；不相信模型输出中的标识。同时读本次 issue/agent 的 runner-goal projection，要求 goal、pendingAction 明确为空；启动前与 done PATCH 前各核一次，未知／404／缺字段拒绝。即使 goal 已 complete 也拒绝，不扩展到带 goal 的任务。检查与 PATCH 不是原子事务，外部管理员并发改 goal 仍可能使 PATCH 失败或取消当前 run；不得声称消除了这种竞态。
2. 从模板顶部唯一的 issue 字段选 PER 卡；空／缺省值归 PER-67 汇总，非 PER 或多义值拒绝。note/log_tail 中的目标不算。
3. 宿主生成随机一次性标记，含本次 run；读目标卡已有评论，保存旧评论集合；在私有 active.json 保存本次上下文。
4. helper 只对该目标写一次，正文最后一行须精确标记、禁止 [Zack答]，先持久写意图。超时／不明响应不重试。
5. helper 只有 Orca 返回成功才写私有回执。宿主再次读目标卡，要求新的、未截断的评论，正文完整等于回执、标记精确一致、创建时间不早于本次启动、作者等于安装时确认的共享账号。
6. `orca linear issue … --comments --json` 已只读验证。使用 `result.comments`、`bodyTruncated`、`createdAt`、`user.id` 和 `result.meta`。partial/includeErrors 拒绝；分页截断时只接受确实找到了的正证据，未找到就失败，不把“不在本页”说成“没写”。

同账号不等于证明是哪位模型写的，所以同时要求固定 helper 的私有回执、一次性随机标记、完整正文和读回。这不能抵御已控制宿主用户的攻击者；不宣称该威胁下的隔离。

## 熔断阈值

- **每 issue 一次模型启动**：持久独占 claim + 所有关联 heartbeat run 检查。adapter 重试、第二次包装调用、历史超过一千条无法完整核实，都拒绝启动模型并暂停。
- **全局单模型**：非阻塞 flock；持久 INFLIGHT 租约。SIGKILL／崩溃留下租约，下一次任何 issue 都不能启动模型，先熔断暂停；不能自行清掉它。
- **时间**：全流程模型阶段至多 840 秒，留一分钟收尾；外部 GNU timeout 同时限制孤儿 Claude，并在五秒后强杀。adapter 900 秒兜底。宿主异常先杀模型组。宿主若被强杀不能立即发暂停请求，但持久租约阻止后继模型、外部 timeout 限制孤儿；需要人工确认 paused，不能宣称它瞬间自动暂停。
- **单次费用**：CLI `--max-budget-usd 2`，结束后 result.total_cost_usd 超两美元或缺失就熔断，不标 done。
- **月费用**：固定两万美分，即 **200 美元**；每次启动先保守预留两美元且不退还，取持久预留与 Paperclip spentMonthlyCents 较大者。达到上限拒绝，等于一个 UTC 月最多一百次启动；Paperclip 的月预算若被改动也拒绝。
- **不是精确计费硬上限**：CLI 的 max-budget 是估算，检查点之间可能超过；Paperclip 在 adapter 收尾后才可汇总当前 run，不能用旧 spentMonthlyCents 当实时花费。E2E 仍需人看时间／费用，超限立即停，不起第二次。月边界的保守预留不清旧月数据；API 账期不同时取较大值会更早停。
- **输出体积**：stdout+stderr 超十六 MiB 熔断，防失控日志。

在 done PATCH 前失败（Paperclip 离线、Linear/Orca 读不到、认证失败、作者不符、无评论、超时、未知费用、绑定或 goal 漂移）不标完成，熔断暂停。若 PATCH 已生效但其响应／随后 GET／证据落盘失败，issue 可能已是 done：仍熔断，报告“评论已核，处置或收尾证据待核”，由人只读核实，不自动重开 issue 或重跑模型。暂停失败也保留 FUSED/INFLIGHT 并告警 stderr，后继包装执行不跑模型。不要把失败改成 done 来挡补跑。

## 安装与回滚（本轮均没执行）

由主会话及验收方核对新 SHA、顺序与批准范围后操作。安装不是更改任何已装发送方的授权。本次固定顺序为：同一完整源码包 → 旧 host 上精确收尾 → 取得完成凭据 → 用该源码包重装。

```sh
# 默认只打印，不连 API、不写文件
bash paperclip/imac/ops-system/install.sh
# 显式只读检查：显示实际 agent 历史 ID/status，不写、不调用 key-fill
bash paperclip/imac/ops-system/install.sh --inspect
# 本次先完成下节收尾，复核批准后；账号不能写入仓库
bash paperclip/imac/ops-system/install.sh --apply --claude "$HOME/.local/bin/claude" --linear-author '<已确认的账号标识>' \
  --cleanup-backup '<收尾输出的 BACKUP 目录>'
# 回滚也须确认范围；从本次备份目录还原，不重启／恢复 agent
bash paperclip/imac/ops-system/install.sh --rollback '<本次备份目录>' --apply
```

- 安装 apply 前检查 paused、完整历史全部为终态、原 extraArgs 和 skip=false，调用 key-fill --check；仅退出码零且 stdout 去首尾空白后精确为“有”才继续。“没有”、空输出、未知输出、非零或超时，都在 mkdir／备份／文件写入／API 修改之前停止；不读取密钥文件。回滚不以 key 存在为前提，不因 key 缺失阻止恢复旧配置。
- 先备份 settings、指令内容、adapterConfig、两条 routine 的描述／策略、已有宿主文件。再原子写、mode 600（可执行脚本 700）、更新指令和 adapter command；extraArgs 不变；routine 设 coalesce_if_active / skip_missed，不改 trigger。
- 安装读回完整 API 可见 adapterConfig，必须与本次期望对象完全相等（含 command、timeoutSec=900、graceSec=5、extraArgs、skip=false）；两条 routine 各自的 description／concurrencyPolicy／catchUpPolicy 逐字段比较，缺字段也失败。指令内容、入口及新 revision、settings 内容／600、paused／无活动运行及原历史逐项不变均须符合。host/helper 落盘摘要另与仓库文件比较，host.json 与构造对象比较，之后才记 manifest；运行前也核 manifest。
- 允许已有终态历史，不删任何历史。`run_snapshot` 只接受 succeeded/interrupted/failed/cancelled/timed_out；queued/running/scheduled_retry 及未知状态均拒绝。按 ID 排序，拒绝错归属、重复、达到一千条上限／未知结构；修改前打印 PLAN_RUNS、PREWRITE_RUNS，备份保存 runs，修改后打印 READBACK_RUNS 并要求 ID/status 数组完全一致，新增、删除、变状态都不能报 PASS。枚举依据固定版本 heartbeat.ts:793–817。回滚也核当前历史前后不变，不恢复／删除历史记录。
- 默认离线计划不读线上，不会虚构 ID；显式 `--inspect` 只读显示真实历史后返回，`--apply` 也会先显示实际历史计划再做其它前置检查。本轮作者只运行默认模式，没有调用 --inspect 或 --apply。
- 安装不清 claim、FUSED、INFLIGHT 或预留。遇 FUSED／INFLIGHT 先拒绝；本次有历史的已失败旧 host 额外必须有 `--cleanup-backup` 完成凭据，否则拒绝覆盖旧 host。普通终态历史不再被当成活动 run。
- 回滚先用当前 baseRevisionId 把备份指令内容提交成**新 revision**，再以 `replaceAdapterConfig: true` 全量恢复备份配置（不改 adapterType），不是默认浅合并；原来没有的 command／timeoutSec／graceSec 必须消失。配置替换后再读指令入口、内容及 revision，须仍指向刚提交的版本，不假装回到历史 revision。
- 回滚只有在完整 API 可见 adapterConfig 与备份完全相等、两条 routine 三字段与备份相等、指令／revision／settings 摘要与600／paused 都读回符合时才打印成功；任一差异即失败，不能只核 paused。保留宿主文件和状态作证据不等于仍允许执行宿主；不恢复、不触发。
- 脚本故障后保持暂停，检查本次备份再回滚；不是跨 API／文件系统事务，未声称部分失败自动全部回滚。

## 第 4 轮：仅本次失败演练的收尾脚本（未 apply）

`close-failed-e2e.py` 是人工宿主维护工具，不安装给模型、不加 allowlist。默认只打印计划，连 incident／已装状态文件也不读；仅 `--apply` 才进入管理 API 和状态修改。

```sh
python3 -I paperclip/imac/ops-system/close-failed-e2e.py
# 以下仅为另获批准后在 iMac 的用法，本轮没有运行：
python3 -I paperclip/imac/ops-system/close-failed-e2e.py \
  --incident '<已核私有 incident.json>' --apply
```

私有 incident.json 由本次报告的 company/agent/routine/trigger/issue/run、UTC 月及精确 FUSED 内容组成，保存在作者本轮私有源码归档，不提交真实 ID。脚本钉住该 JSON 的规范化 SHA256，不能拿同名 OPS-1 或另一次失败来复用。还钉住已失败的第3轮 host.py 摘要，证明该 unsupported_cli_flag 路径在模型 spawn 前。

**apply 前拒绝条件：**旧 host 摘要不符、状态目录／文件有符号链接或不是本人普通文件、无法取得原 host.lock 独占锁、agent 非 paused、不是唯一原 cancelled heartbeat、记录费用变化、原 PID／进程组仍存在或不可核（即便 PID 已被无关进程复用也拒绝）、issue 绑定／blocked／空 executionRunId 不符、存在 parent/conversation/runner goal/pending action、测试 trigger 不是原 disabled/setupPending=false、state 不是原四个文件、FUSED／claim 时间或绑定不同、预留不再恰好为原月200。无权限／未知响应同样停止，不尝试修权或广泛清理。

备份发生在任何 API／原 state 修改之前：在私有 `backups/failed-e2e-<UTC>/` 创建0700目录，原字节备份四个 state 文件到0600文件、核摘要并 fsync；snapshot 保存 incident、API 安全字段、原触发器对象及正式 routine 摘要，不含 env、bearer、MCP 内容。写操作期间保持独占锁，前后重复只读核安全条件。

| 项 | 动作及读回 |
| --- | --- |
| OPS-1 | 只 PATCH `/api/issues/<issue>` 为 `{"status":"cancelled"}` 并 GET 核同一 issue 已 cancelled；不设 done、不追加评论、不 reopen/resume |
| reservations.json | 原值必须精确为 `{<本次UTC月>:200}`，备份后原子写为同一月0；不删整份账本、不碰 Paperclip 费用或预算，这只是一次未启动模型的保守预留释放，不是账单退款 |
| issue claim | 路径由本次 issue ID 的 SHA256 计算；内容必须只有原 run 与 started 且时间位于原 run 内，备份后仅 unlink 该文件，fsync state；不 glob 删除 claim |
| FUSED.json | 必须等于本次 unsupported_cli_flag 的精确记录；备份后**最后**删除，再核最终目录只剩 host.lock／零预留 |
| 测试 trigger | 必须已经 enabled=false/setupPending=false，并保持整个对象不变；脚本不写 trigger，也不恢复 setupPending=true |
| 其余 | 保留原 heartbeat／routine run／issue 历史、host.lock、独占 E2E-FIRE-CLAIM、安装备份和正式 routine/trigger；不改 agent 配置、模型权限或部署文件 |

`cancelled` 的源码依据：`shared/src/constants.ts:189–198` 和 issue validator 接受该终态；`routes/issues.ts:12803+` 的 PATCH、`12925–12926,13843+` 的取消处理、`14877+` 的终态判断。脚本要求没有父任务，避免终态父任务唤醒分支；无 comment/reassignment/reopen 字段，不制造新的工作请求。正常 API 仍会记录审计及终态清理，不声称绕过服务副作用。

每阶段在备份内写 progress。任何写入阶段失败，尝试持久写 `cleanup_incomplete` 熔断并以非零退出；磁盘故障下也不能声称熔断写成功。它不是 API/文件系统事务，不会自动重开 issue、恢复预留或盲重试。收到超时／未知结果时只读核备份与线上状态后再人工处理；完整读回通过才报 PASS。

### 第5轮固定顺序及两个脚本的互核

选 **先收尾、后重装**，不支持倒序：旧 host 摘要是本次失败发生在 spawn 前的直接证据。先清理可原样保留这个门禁；若先覆盖 host，就必须另设计旧版本证据迁移，反而扩大本次改动。新安装器接受原 cancelled 历史，所以先收尾不会再被零历史断言卡住。

1. 在独立源码目录准备本次完整 `paperclip/imac` 包，不覆盖部署。先审核／确定目标 settings 等源文件，再收尾；收尾到安装间不得改包。
2. 新收尾脚本在旧 host 上运行，仍核唯一原 cancelled run、blocked OPS-1、原 FUSED／claim／200预留及停用触发器；备份和清理范围不放宽。
3. 收尾 snapshot 增加 `nextInstallSha256`：同包 install.py/install.sh、close-failed-e2e、host、generate、helper、settings、AGENTS 及上级 provision/config/key-fill 源文件的摘要（不读取凭据文件）。结束再核摘要未变，只有完整读回成功才写 progress.phase=complete 和 snapshotSha256，并输出下一步的 `--cleanup-backup` 目录。
4. 安装器使用**仓库同包**的验证函数，不导入已安装代码；核凭据在 root/backups 下、目录私有、incident 摘要、原备份字节摘要、旧 host 证明、phase=complete、snapshot 摘要、当前待安装源码摘要。还 GET 核 OPS-1 cancelled、paused、原 cancelled run、测试trigger disabled，核清理后 state 只有锁和零预留。任一不符在安装备份／部署写之前拒绝。
5. 安装备份保存 run ID/status 和收尾凭据路径／摘要；完成后重新核历史完全一致、凭据／源码／清理状态不变、trigger 整对象不变及已有完整配置读回。安装允许更新 routine 描述／策略，可能使 updatedAt 改变，所以装后不错误要求正式 routine 的整对象摘要仍等于收尾前；改用安装器已有的两条 routine 三字段完整读回，触发器仍不得变。

这是具体可执行的升级路径，不是删历史或删旧 hash 保护。当前事件的收尾凭据仍严格限定唯一原 run，不接受清理到安装间又多一条 run；一般安装历史门禁则接受任意未截断终态集合。默认计划和 --inspect 不等于全部 apply 前提已验证。

两个脚本仍不是跨文件系统/API事务，也不能阻止其它管理员并发恢复 agent。执行窗口应保持暂停、不修改配置；反复读回发现漂移即失败，不自动修状态／重试。清理成功后安装失败，只保留各自备份供核实，不自动恢复200预留、不重开 OPS-1、不再清一次。回滚只还原配置／文件，不倒转收尾或历史；保留 paused 和测试 disabled。

第92条及本次任务已存在的批准不被脚本文案否认；新 SHA／调整后顺序是否符合执行安排交主会话核对。作者本轮没有执行两个 --apply，也没有消耗第二次 E2E。

## 指令来源及可重复步骤

AGENTS.md 是人工收敛的生成结果，不在仓库存私有原人设。重复生成按下面映射逐段核对、原样保留本目录文本；权限文件用 `python3 paperclip/imac/ops-system/generate.py` 重建（默认 iMac HOME，可显式 --home）。

| AGENTS 段 | 来源和裁剪 |
| --- | --- |
| 身份与边界 | personas.json 的 ops 系统范围 + box 拷回 ops-bot.description 新增全设备配置／box 收尾归属；受决定 32A 收窄为只读日志／写 Linear，不继承开发维护执行权 |
| 输入是数据 | 原 provision 占位防注入规则 + 本轮失败清单；不加载 payload 指令 |
| 处理叫醒 | dev-bot-rules 叫醒 v5 五类 status；取消回终端／重启／派修复／自行验收动作，只记事实和待决事项 |
| 唯一工具通路 | PLAN 3.1 五本机日志 + 台账 80／82；删远程读取、stuck-check 执行和 MBA 归档；增加安全 helper 的精确契约 |
| 批准通路 | 决定 35A、36A；取代 main 的 Coding助手 转达、box 版的直接私聊批准；禁止 bot 写 [Zack答] |
| 输出 | 两个人设的中文简短要求、规矩证据与未知项；增加宿主回执，不继承 Grok 工具或标识 |

删除：SendToAgent/SendToUser、私聊卡片、Grok agent/server 标识、box 工作路径、版本地址、账号邮箱、起 coding agent／直接操作基础设施／合并例外；不把 box 版“直接找 Zack”错误迁移成 Paperclip 网页批准。

规矩仅新增出行批准通路优先段、为卡片节加例外、改 Linear 唯一批准凭证句，以及 SYNC 第 6 行例外。以下 Grok 耦合仍归 S1，未动：私聊协作工具、Grok 用量和后台助手、watchdog、box 工作路径／项目映射、EverOS 读写分工、webhook env／routine／enabled-bots、共享记忆推送、夜审与 dr eggbot 其余职责、其他人设、SYNC 历史落点及 targets。

## 模板与发送方

只改仓库代码，不安装两台 notify-run/orca-wake。只对 ops-system 将所有反引号／波浪线改成全角字符，涵盖内联、缩进和围栏；其他标量换行变字面转义，避免伪造顶部 issue 字段。note/log_tail 仍保留换行。静态围栏只是呈现层，不承担权限隔离。

orca-wake 的键为机器+bot+既有 dedup_key 的摘要；notify-run 没旧事件键，以机器+启动时间+本次 mktemp 随机名+**显式事件类型+status** 作键，并写 payload。start_watch 使用 startup-warning，finish 使用 final；同一进程的 stuck 预警与最终 done/failed/killed 因事件类型不同而不会互相去重。每个事件的键在其重试循环之外固定，重试不重新生成；两个事件也分别使用 payload 文件，避免彼此覆盖待重试正文。只对 ops-system 发送 Idempotency-Key；其它 bot 不增加 header。

服务端依据：`routes/routines.ts:669`；`services/routines.ts:1799–1836,3044–3108`。bearer 去重范围 company/routine/source/trigger/key；记录保留期间无 TTL。setupPending 收据单独记，不能拿测试收据去触发正式 run。去重不能代替收尾，也不抵消 model 内部补跑。

## 验收与 E2E 门禁（历史步骤与当前边界）

第2轮作者的订阅权限自查因 OAuth 过期没跑成；这是历史记录，不代表后来独立验收未做。后续权限验收及唯一 E2E 以私有报告为准。本轮不做权限自查、不重试 E2E；新修复仍须独立验收。

**下面保留第3轮第一次 E2E 的原步骤作为历史，不是第二次的执行指令。**第92条后续获准演练须以原 cancelled 历史为基线，仅新增获准的那一次，不套用下文第一次演练的空基线，也不删历史来满足它。报告中的第89条已经为那一次取消了实时费用前提，采用 CLI 两美元估算预算和十五分钟强制结束；第1/4/5步的实时费用要求不能再被说成那一次的停止原因。那一次已经失败且用完，第89条不是下一次运行的许可，后续门禁须重新明确。当前测试 trigger 保持 disabled/setupPending=false，不自行恢复。新的源码交付不改变任何批准。

权限验收覆盖要求仍包括：curl/python/node、命令替换、管道、重定向、环境前缀、原始 orca 的其它命令和远程参数、gh pr merge、写设置／台账／宿主文件均被拒；helper 正例只用假目录或只读，不真的写 Linear。

获批安装且核过以后，单次 E2E：
1. 查安装哈希、600、paused、零 run、key 存在、settings 唯一 helper；确认外部 timeout 和 Orca 在场。确认权限验收通过、宿主配置的 Linear 作者正确、安装完整读回通过。**触发前还须确定本次 run 的费用来源和刷新时效**；只有终态 last-model-result／可能滞后的 Paperclip 累计值不构成运行中的观测来源。本轮没有验证实时费用来源，若仍没有，前提不成立，不恢复／不触发，交主会话向 Zack 说明缺口；不能自行改成“只靠两美元 CLI 参数就跑”。
2. 仅验收方按批准恢复，测试 routine 触发一次；bearer 只由脚本读，经 stdin／header，不输出、不作命令行参数。正式 routine bearer 不用。setupPending 的更改须核对该次批准范围，不能把测试回执当真实运行。触发前存空运行列表基线，触发后固定本次 run/issue/routine 的绑定，后续不再触发。
3. 模型只在 PER-67 写一条 `[演练] S12 ③ E2E` 评论，末行本次标记。核 helper 回执、Linear 读回、issue done，以及实际 Claude argv 的 dontAsk／无 skip；Paperclip 记录显示的是 host command，要另核宿主生成的真 Claude 参数。核两次 runner-goal 检查无 goal／pending action；未知或带 goal 不得以“非 native”代替核实。
4. 从运行开始立即取样，之后**每五秒**读本次 heartbeat run 和该 agent 的完整 heartbeat 列表（GET `/api/heartbeat-runs/<本次运行>`、GET `/api/companies/<本次公司>/heartbeat-runs?agentId=<本次agent>&limit=1000`），同时读约定费用来源及私有 last-invocation、last-model-result、last-success、FUSED/INFLIGHT。费用须绑定本次 run、覆盖当前已发生调用、并符合来源已核实的刷新时效，最长不得超过十秒；未上报、只有旧零值、来源不可达／过期、或数值冲突都记**未知，不当零**。
5. **任一取样费用未知就立刻停止本次运行并暂停**，不等到十五分钟或等它以后补报；不再起第二次。超过两美元、十五分钟未结束、观察到额外 run 或状态／接口不可核实也走同样流程：POST `/api/heartbeat-runs/<本次运行>/cancel`，随后 POST `/api/agents/<本次agent>/pause`，GET agent 确认 paused，并只读核模型组已退出。取消请求失败也必须尝试 pause，不因取消的 HTTP 错误跳过暂停；取消未确认或模型还在就记失败并请人工处理，不宣称已安全停止。运行已经终态但费用未知，仍暂停、保留记录、只读补查费用，结果保持失败／未核实；不能重跑来补成本证据。CLI cap 是估算，五秒轮询也不是瞬时账单硬闸。
6. 第一个 run 一到终态，成功失败都立即暂停并 GET 确认；**不为观察补跑而保持 agent 可运行**。以“本次 run 已终态且已读回 paused”的较晚时刻为 T0，继续只读观察 **十五分钟，每五秒一次**，T0+十五分钟再做最终快照。每次查同一 agent 的全部 run、当前 issue、测试 routine 的 runs 和宿主状态；列表触及一千条上限、返回不完整或任何取样失败都判观察不完整，不用空列表算通过，也不靠再次恢复弥补。
7. “本窗口内无补跑”通过条件必须同时满足：相对空基线始终恰有本次一个 heartbeat run；本次为 succeeded、issue 为 done、对应 routine run 为 completed、agent 持续 paused；没有任何 queued/running/scheduled_retry，没有第二个 run（即便第二个已经 cancelled/failed/timed_out/interrupted/succeeded 也失败），没有新增包装调用、FUSED 或残留 INFLIGHT，Linear 仅一条本次演练评论。活动／终态枚举依据 `services/heartbeat.ts:793–817`。发现额外记录即记失败并确保该 agent 仍暂停，不等 scheduled_retry 到点才处理。这里是规定观察窗口的证据，**不是“以后永远不会补跑”的证明**；即使 claim 阻止了第二次模型、没多花钱，第二条 heartbeat 记录仍算失败。

所有上述读写管理调用都由验收宿主执行，绝不塞进模型 allowlist。真实 E2E 已失败，当前修复尚未安装／再验，不转 ready。
