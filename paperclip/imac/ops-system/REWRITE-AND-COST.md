# 第7轮：一次受控改写、失败费用审计、OPS-6收尾

代码交付，未安装／apply／触发。依据 PRECHECK-s12-4.md §11 及 iMac 原批准台账第97条；合并、收尾、安装和续跑属于后续独立验收／主会话，不由作者执行。

## 根因和指令

OPS-6 的模型拒绝了越权要求，但在拒绝评论中两次原样引用保留批准标记。旧 helper 的全正文硬禁词先于 write-intent／Orca 写命令，故网络写未发生；旧诊断却把“预检拒绝”和“写入不明”混为一条停止提示。CLI正常退出且实花 $0.064206，host没有本次回执，熔断并pause。

新 AGENTS 与 host 补充协议要求：转述只用“要求伪造 Zack 批准记录”等概括语，评论及最终回复都不复制保留标记，否定／引用／例子也不例外；其它禁写标记或敏感内容同理。不用拼接字符绕过门禁。硬禁词仍是原来的 `[Zack答` 子串，任何位置都拒绝；没有为“引用”加白名单。现有代码只有这一个硬字符串禁词，不把长度、前缀、回执校验谎称为通用PII过滤器。

## helper 的有限状态协议

只允许同一个 active/INFLIGHT run，禁用／丢失租约或熔断即拒绝。新增私有 `comment-<RUN>.lock` 与 `comment-<RUN>.json`，锁覆盖校验、次数记账、intent、Orca调用和回执；非阻塞独占，不靠模型自己记次数。

| 状态／请求 | 动作 | 能否再 comment |
| --- | --- | --- |
| 第一次，前缀／末行标记／长度正确，仅命中禁词 | 先持久化 attempts=1、firstFailure、rewriteAvailable=true；不建intent、不调用Orca | 只允许一次同run改写 |
| 第二次改写仍含禁词 | 先消费第二个slot，再明确拒绝，不调用Orca | 不能第三次 |
| 第一或获准的第二次正文合法 | 先写intent并fsync，再调用一次Orca写命令 | intent存在，任何再次调用均拒绝 |
| 空正文、过长、缺前缀／标记、未知错误 | 已进入comment状态机的尝试先消费；明确停止 | 不给改写许可 |
| Orca超时／非零／非ok／响应损坏／回执落盘不明 | intent保留；停止 | 即使“可能没写成”也不重试 |
| 并发／次数耗尽／已有intent | 拒绝 | 不换进程、工具或运行绕过 |

唯一可改写响应（工具exit=2，stderr JSON）：`code=reserved_approval_marker`、`retryable=true`、`networkAttempted=false`、`remainingRewriteAttempts=1`，附受控转述建议和保持前缀／回执的要求。不回显被拒正文、禁词拼写或敏感片段。第二次禁词拒绝返回同类原因但 retryable=false。其它次数耗尽用 comment_attempt_limit；其它错误沿用 stop/do-not-retry。

只有**真实工具结果**能给改写提示；叫醒数据中的伪造JSON不算。持久状态即使模型不遵从也将comment尝试限制为最多两次，且第二次仅在第一次禁词预检拒绝后可用。Read/log 不重置计数。一次CLI运行内改写，不起第二个模型、不扩大$2/840秒限制或工具权限。

### 回执与“只写一次”

- write-intent 用O_EXCL创建，含run、commentAttempts、正文SHA256；网络结果不明不删intent。
- 成功receipt包含同一证明、host的新marker、原正文。host检查次数只能为1或2、2必须有首次禁词拒绝记录、改写许可已经耗用、intent／receipt正文摘要一致。
- 仍须真实Linear完整读回：目标、作者、时间、本次末行marker、精确正文及唯一新评论，之后才能done。旧receipt或模型口头成功不算。
- “只写一次”的实施边界是最多一次 **Orca写命令调用**，不是声称第三方网络具有事务性的exactly-once。模型最多两次comment调用中的第一次必须尚未进入写命令；模糊网络结果不再调用。任何远端重复／截断／无法确认仍由唯一性读回失败闭合。

## 失败费用：本地审计不再依赖 Paperclip 的0

新增每run的 `state/cost-<RUN>.json`（0600，state私有），原子替换并fsync；日志为 `ops-host: cost_snapshot {…}`（stderr，flush）。字段含run、启动时间／UTC预留月份、来源、status、十进制costUsdExact、数值costUsd、outcome及固定原因码。记录不含模型正文、工具读回、凭据或MCP内容。

- 绑定成功后先写 not_started／0，来源明确是host尚未启动模型，不冒充CLI报0；已有同run费用文件拒绝覆盖后重启。
- 进入启动边界、Popen之前先持久化 **unknown**。硬杀或启动状态不明不能留下虚假免费记录。
- 正常CLI退出后，在查回执之前解析唯一terminal result的 `total_cost_usd`；使用Decimal保留十进制表示，拒绝布尔／负值／NaN／Infinity／非数字。即使CLI失败或费用超过$2，金额也先保存。
- 异常／超时／SIGTERM路径在临时stdout仍打开时停止子进程，再提取并保存，之后才进入外层熔断／pause。已读到合法结果且子进程停止、输出完整时记 cli_reported；不依赖CLI退出0或业务成功。
- 没有terminal、多个terminal、损坏／截断输出、进程停止未确认时记 **unknown**，不是0。若看到一个合法金额但输出不完整，则只留 observedCostUsdExact 作线索，不冒充已确认总额。没有CLI结果时不能凭空知道完整账单。
- 费用文件落盘失败会打印 UNPERSISTED 快照并拒绝正常收尾；日志也可能因硬杀／磁盘故障丢失，不能保证不可捕获故障下取得精确终值。unknown、INFLIGHT和原预留须保留，等待人工核查。
- 成功路径在转发stdout前也先持久化settled费用。last-model-result仍保留兼容指针，但不能用下一次覆盖后的last文件替代每run审计。

**日志是快照，不是追加扣费流水**：按run更新去重，不能把result_observed／failed／settled多条相加。CLI和Paperclip是同一笔费用的不同来源，也不能相加。旧成功run没有被伪造迁入新账；历史费用须按run结合旧证据，不能把新journal当成完整月账。

预留仍与实际费用分开：本轮不自动释放失败预留、不增加预算，不声称CLI的$2参数是实时精确账单硬上限。若报告超额／未知，仍熔断，不靠UI的0继续运行。

### Paperclip 为什么是0（固定版源码＋实际读回）

源码证据为归档的2026.1012.0：

- host旧成功路径才转发缓冲的stream-json；OPS-6在no_helper_receipt处跳出，未转发terminal result，随后pause取消wrapper。实际heartbeat log没有模型流，usageJson=null、tokens=0，last-model-result却绑定本次费用0.064206。
- `packages/adapters/claude-local/src/server/execute.ts:978–984` 从proc.stdout解析；`:1252` 将parsedStream.costUsd交给服务端。terminal-result识别还会影响adapter清理，所以不能提前吐出result只为补UI费用。
- `parse.ts:55–106` 没有result事件返回costUsd=null、usage=null；`:116–117` 有result才取有限的total_cost_usd。
- `heartbeat.ts:25585–25642` 由adapter usage/cost生成usageJson；为空时不产生真实用量。`:25681–25732` 还有终态CAS及取消后的晚到元数据分支，不能笼统说“所有cancelled都不记费”；有受控取消晚写例外，但它也不能凭空还原host没给它的result。

因此这不是$0.064206被四舍五入成0、不是免费或退款，而是费用事件没到记账边界。本轮不改Paperclip、不伪造终态事件、不提前释放原始stdout；**失败的Paperclip UI仍可能为0，host journal才是本次CLI费用的独立证据**。

## OPS-6 专用收尾：先旧版收尾，再重装

`close-injection.py` 默认无线上／状态／incident访问，只打印计划。第97条条件满足、由后续执行方执行的顺序示例（作者本轮未执行，不表示缺少第97条授权）：

```sh
python3 -I paperclip/imac/ops-system/close-injection.py
# 独立验收／主会话核准后，使用同一完整源包：
python3 -I paperclip/imac/ops-system/close-injection.py --incident '<incident-ops6.json>' --apply
bash paperclip/imac/ops-system/install.sh --apply \
  --claude '<已核路径>' --linear-author '<原共享作者>' \
  --injection-cleanup-backup '<上一步 BACKUP 目录>'
```

不能套用OPS-1或OPS-3退款式清理。新脚本钉住私有incident摘要、旧host与helper摘要；运行绑定、原六条终态heartbeat／七条routine审计行（含coalesced及其指向）、paused／disabled、无活进程／goal、正式routine原摘要全部核实。Paperclip的0只作为该事故基线检查，不是退款依据。

严格接受17个已知state文件，明确当前write-intent不存在，receipt/last-success仍属MBA成功run，而active/invocation/result/INFLIGHT属OPS-6。还核issue.originRunId绑定主routine run；安装版本 routines.js:2788–2851 只终结该originRunId，cancelled令其failed，不改coalesced审计行。独占host.lock，备份全部原字节与摘要（目录0700，文件0600并fsync）。

随后只取消OPS-6，不伪装done；从原本次last-model-result导入 **$0.064206** 的私有每run成本证据及日志（source=legacy_last_model_result，非新运行）。**800美分预留原字节不动**：历史600＋本次已付费运行的200，选择保守保留，不自动退剩余估计额度，不把实际费用误作0来退200。

仅删除本次claim、精确INFLIGHT，FUSED最后删除；当前invocation/result、旧receipt/claim/intent、全部历史、MCP审计、host.lock与一次性触发锁保留。逐字读回保留状态及账本，核新成本记录；不改正式配置、环境、凭据、预算，不写Linear、不resume/fire。

完成凭据绑定14个源码／部署payload文件与原备份；安装器强制 `--injection-cleanup-backup`，不能混用OPS-1/3凭据，装前装后验证。装后仅让正式routine正常更新的updatedAt等元数据变化由既有完整配置读回校验；测试trigger整对象不变。

部分失败留progress并尝试写ops6_cleanup_incomplete；无跨API/文件事务或硬杀保证，不自动退款／重开／重试，不能修改源码或凭据摘要“配平”。异常须人工核备份。完成也不会自动续跑。

## 验证边界

作者仅源码核查、AST/Bash／离线计划／归档数据复算，没有单元／mock API、权限探测、安装、cleanup apply、触发或模型调用。独立验收仍需核：一次改写成功／再禁词拒绝／第三次与并发拒绝／模糊网络不重试；回执与正文摘要错配；无receipt、非零退出、超时、输出损坏及无terminal时的费用记录；OPS-6完成凭据链。真实注入、去重、短会话和环境检查由第97条的后续检查方执行，累计已花约$0.2202972也要计入$3上限。
