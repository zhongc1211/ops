# S12 ③：宿主收尾草案（未安装，未 E2E）

依据批准第 82 条，只交设计与代码。合并、安装和第 81 条单次演练均未执行；验收后须再问 Zack。不得把本目录的脚本运行权限当作安装批准。

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

先由主会话向 Zack 另问是否安装，再由验收方操作。安装不是更改任何已装发送方的授权。

```sh
# 默认只打印，不连 API、不写文件
bash paperclip/imac/ops-system/install.sh
# 另获安装批准后；作者账号值经只读核对，不能写入仓库
bash paperclip/imac/ops-system/install.sh --apply --claude "$HOME/.local/bin/claude" --linear-author '<已确认的账号标识>'
# 回滚也须确认范围；从本次备份目录还原，不重启／恢复 agent
bash paperclip/imac/ops-system/install.sh --rollback '<本次备份目录>' --apply
```

- 安装 apply 前检查 paused、运行零条、原 extraArgs 和 skip=false，调用 key-fill --check；仅退出码零且 stdout 去首尾空白后精确为“有”才继续。“没有”、空输出、未知输出、非零或超时，都在 mkdir／备份／文件写入／API 修改之前停止；不读取密钥文件。回滚不以 key 存在为前提，不因 key 缺失阻止恢复旧配置。
- 先备份 settings、指令内容、adapterConfig、两条 routine 的描述／策略、已有宿主文件。再原子写、mode 600（可执行脚本 700）、更新指令和 adapter command；extraArgs 不变；routine 设 coalesce_if_active / skip_missed，不改 trigger。
- 安装读回完整 API 可见 adapterConfig，必须与本次期望对象完全相等（含 command、timeoutSec=900、graceSec=5、extraArgs、skip=false）；两条 routine 各自的 description／concurrencyPolicy／catchUpPolicy 逐字段比较，缺字段也失败。指令内容、入口及新 revision、settings 内容／600、paused／零运行均须符合。host/helper 落盘摘要另与仓库文件比较，host.json 与构造对象比较，之后才记 manifest；运行前也核 manifest。
- 幂等重跑不删 claim、FUSED、INFLIGHT 或预算预留。安装后有运行历史时拒绝再次安装；应人工定维护方案，不能清运行历史绕过。
- 回滚先用当前 baseRevisionId 把备份指令内容提交成**新 revision**，再以 `replaceAdapterConfig: true` 全量恢复备份配置（不改 adapterType），不是默认浅合并；原来没有的 command／timeoutSec／graceSec 必须消失。配置替换后再读指令入口、内容及 revision，须仍指向刚提交的版本，不假装回到历史 revision。
- 回滚只有在完整 API 可见 adapterConfig 与备份完全相等、两条 routine 三字段与备份相等、指令／revision／settings 摘要与600／paused 都读回符合时才打印成功；任一差异即失败，不能只核 paused。保留宿主文件和状态作证据不等于仍允许执行宿主；不恢复、不触发。
- 脚本故障后保持暂停，检查本次备份再回滚；不是跨 API／文件系统事务，未声称部分失败自动全部回滚。

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

## 验收与 E2E 门禁

作者在 iMac 内存门槛通过后试了订阅 Claude 权限自查，但 OAuth 已过期且无法刷新，返回 authentication_failed、API duration 零、cost 零。**工具正负例没跑成**；不换认证、不用 Paperclip key。临时目录已删除，专属 Claude 进程零个。现不能称 allowlist 已实测安全。

验收方先核静态代码及权限负例，再由主会话问 Zack 装不装、跑不跑第 81 条那次。必须包括：curl/python/node、命令替换、管道、重定向、环境前缀、原始 orca 的其它命令和远程参数、gh pr merge、写设置／台账／宿主文件均被拒；helper 正例只用假目录或只读，不真的写 Linear。

获批安装且核过以后，单次 E2E：
1. 查安装哈希、600、paused、零 run、key 存在、settings 唯一 helper；确认外部 timeout 和 Orca 在场。确认权限验收通过、宿主配置的 Linear 作者正确、安装完整读回通过。**触发前还须确定本次 run 的费用来源和刷新时效**；只有终态 last-model-result／可能滞后的 Paperclip 累计值不构成运行中的观测来源。本轮没有验证实时费用来源，若仍没有，前提不成立，不恢复／不触发，交主会话向 Zack 说明缺口；不能自行改成“只靠两美元 CLI 参数就跑”。
2. 仅验收方按批准恢复，测试 routine 触发一次；bearer 只由脚本读，经 stdin／header，不输出、不作命令行参数。正式 routine bearer 不用。setupPending 的更改须核对该次批准范围，不能把测试回执当真实运行。触发前存空运行列表基线，触发后固定本次 run/issue/routine 的绑定，后续不再触发。
3. 模型只在 PER-67 写一条 `[演练] S12 ③ E2E` 评论，末行本次标记。核 helper 回执、Linear 读回、issue done，以及实际 Claude argv 的 dontAsk／无 skip；Paperclip 记录显示的是 host command，要另核宿主生成的真 Claude 参数。核两次 runner-goal 检查无 goal／pending action；未知或带 goal 不得以“非 native”代替核实。
4. 从运行开始立即取样，之后**每五秒**读本次 heartbeat run 和该 agent 的完整 heartbeat 列表（GET `/api/heartbeat-runs/<本次运行>`、GET `/api/companies/<本次公司>/heartbeat-runs?agentId=<本次agent>&limit=1000`），同时读约定费用来源及私有 last-invocation、last-model-result、last-success、FUSED/INFLIGHT。费用须绑定本次 run、覆盖当前已发生调用、并符合来源已核实的刷新时效，最长不得超过十秒；未上报、只有旧零值、来源不可达／过期、或数值冲突都记**未知，不当零**。
5. **任一取样费用未知就立刻停止本次运行并暂停**，不等到十五分钟或等它以后补报；不再起第二次。超过两美元、十五分钟未结束、观察到额外 run 或状态／接口不可核实也走同样流程：POST `/api/heartbeat-runs/<本次运行>/cancel`，随后 POST `/api/agents/<本次agent>/pause`，GET agent 确认 paused，并只读核模型组已退出。取消请求失败也必须尝试 pause，不因取消的 HTTP 错误跳过暂停；取消未确认或模型还在就记失败并请人工处理，不宣称已安全停止。运行已经终态但费用未知，仍暂停、保留记录、只读补查费用，结果保持失败／未核实；不能重跑来补成本证据。CLI cap 是估算，五秒轮询也不是瞬时账单硬闸。
6. 第一个 run 一到终态，成功失败都立即暂停并 GET 确认；**不为观察补跑而保持 agent 可运行**。以“本次 run 已终态且已读回 paused”的较晚时刻为 T0，继续只读观察 **十五分钟，每五秒一次**，T0+十五分钟再做最终快照。每次查同一 agent 的全部 run、当前 issue、测试 routine 的 runs 和宿主状态；列表触及一千条上限、返回不完整或任何取样失败都判观察不完整，不用空列表算通过，也不靠再次恢复弥补。
7. “本窗口内无补跑”通过条件必须同时满足：相对空基线始终恰有本次一个 heartbeat run；本次为 succeeded、issue 为 done、对应 routine run 为 completed、agent 持续 paused；没有任何 queued/running/scheduled_retry，没有第二个 run（即便第二个已经 cancelled/failed/timed_out/interrupted/succeeded 也失败），没有新增包装调用、FUSED 或残留 INFLIGHT，Linear 仅一条本次演练评论。活动／终态枚举依据 `services/heartbeat.ts:793–817`。发现额外记录即记失败并确保该 agent 仍暂停，不等 scheduled_retry 到点才处理。这里是规定观察窗口的证据，**不是“以后永远不会补跑”的证明**；即使 claim 阻止了第二次模型、没多花钱，第二条 heartbeat 记录仍算失败。

所有上述读写管理调用都由验收宿主执行，绝不塞进模型 allowlist。当前没有真实 E2E，不转 ready。
