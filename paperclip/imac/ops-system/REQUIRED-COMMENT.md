# S12 r8：先列失败，再实现

## 失败清单（代码前记录）
1. 正式无卡号、`true` 完工通知被视为无需记录：必须仍用 helper 写一条；空卡号仍归 PER-67。
2. 最终回复「无需处理」不能冒充网络回执；host 原有回执、作者、时间、正文读回检查不放宽。
3. 测试首行和强制演练前缀使测试不等价：验收须复制正式描述并临时取消测试前缀，结束恢复。
4. 成功、CLI 错误、无 helper、超时的 result 文本必须在 pause/临时文件关闭前私存；没有 result 必须记 missing，不编造。
5. 输出含凭据、地址、邮箱、路径：先打码再限长；不存原始事件/工具输入，不打印正文，不发送 Paperclip。
6. 归档无界、权限宽、run 路径注入：600 文件、700 子目录、验证 run、单份及数量上限；归档失败熔断。
7. OPS-10 清理误删历史/退还预留/清其它熔断：固定 run 和旧部署，核暂停及双触发器禁用、绑定和费用；先备份，只删三份本次状态，熔断最后删。
8. 清理部分失败不得盲重试；保留备份和熔断，不重写 heartbeat 历史，不 resume。

## 原因与选择
已读线上两个 routine 描述，除首行外一致。旧 AGENTS 有分类处理和“每次最多一次网络评论写入”，但只有演练写死一条指定前缀评论。host 提示“只在目标写一条”可被理解为写入范围约束；host 却无条件要求 helper 回执。07:33 的无卡号、无工作内容 true 通知可能被模型当成无需记录。这是协议歧义的推断，不是已恢复的模型思路：旧 host 只存费用/退出码，最终文本已丢失，无法离线复现模型决策。

选 A，不选 B。每次通知都留可核证据最简单；不让模型用“无需处理”绕过真实异常。即使无事可办也写“收到，无需处理”，异常仍分类记录未知项/待处理事项。只增加明确义务，不放宽工具、回执、禁词或重试。

## 私有输出
`state/model-results/<run>.json`：目录 700、文件 600，最多 100 份，每份 result 最多 32768 UTF-8 字节（计入 JSON 转义后单文件小于 200 KiB，总计小于 20 MiB）。按最旧 mtime 滚动淘汰，失败结果同样受上限约束；只记录淘汰数量，不记录正文。重要事故结果须由操作者在后续 100 次运行前私有归档。先 NFKC 规范化，再打码截断：敏感字段整行（含口令/令牌/私钥/证书）、PEM 块、URL/邮箱和所有 ASCII 可见字符串（包括地址、路径、邮箱、无标签凭据）保守遮盖；英文结论也会损失，这是安全取舍。任意中文自然语言秘密无法自动识别，仍必须只在私有目录查看，不转贴原文。只存 terminal result 文本，不存工具事件。无 result、重复 result 或强杀未观察到结尾记 missing；不能保证 SIGKILL 后恢复尚未观察到的输出。启动前先落 missing，正常/异常收尾覆盖，失败也在 pause 前归档。归档失败熔断且不放出原文；费用先保存，避免诊断失败丢账。

Paperclip 只收到固定宿主结论及 CLI 计费元数据，原始 assistant/result/tool stream 不再转发。源码依据：Paperclip `v2026.1012.0:packages/adapters/claude-local/src/server/parse.ts` 的 `parseClaudeStreamJson` 可直接处理单条 result，计费优先 modelUsage，不需要 assistant 或 session id。本 agent 本来只允许 fresh session。失败路径仍以 host 私账为准。

## OPS-10 专用收尾（仅验收方获准后执行）
`timeout 840 python3 -B paperclip/imac/ops-system/close-switch.py` 默认离线只打印计划，不读线上状态。

作者只读发现 r7 已有 `cost-<本次run>.json`，实花精确值 **0.0548338**，状态 cli_reported/failed/no_helper_receipt；所以本轮“导入”是核验并保留既有按 run 记账行，不新增第二笔、不把 Paperclip 的 0 覆盖进去。缺失或金额改变拒绝，不能静默补造。预留 1400 分原样保留。

验收方：先在旧 host 上运行同脚本加 `--apply`（作者未执行）；固定 OPS-10/run、旧 host sha、时间、claim、熔断和实花，要求 agent paused、两条触发器 disabled、所有 heartbeat terminal、该 issue 仅一次运行、进程已不存在、无 runner goal。锁内私有备份全部 state 并哈希，关 OPS-10 为 cancelled（不把失败说成 done），只删本次 claim/INFLIGHT/FUSED，后者最后删。完整历史、旧回执、私账、预留不变；部分失败留下熔断和备份，停下人工查，不盲重跑。

随后原安装命令增加 `--switch-cleanup-backup <脚本打印的备份目录>`，同一源文件包，不能复用 OPS-1/3/6 回执。安装器在写前和写后核收尾回执；不自动 resume/fire。

## 验收方：在测试 routine 按正式写法重现一次
这是后续获批验收操作，不是作者已执行的步骤。遵守第 99 条本轮累计 $3、单次 CLI $2、15 分钟上限；仅一次，失败暂停回退并报告，不再触发第二次。禁止 MBA SSH。

1. 清理 OPS-10、安装新版本并完整读回后，保持 agent paused、**正式 trigger 全程 disabled**。私有备份测试 routine 描述、并发/catch-up 策略、测试 trigger 状态，以及 host.json/manifest.json（700 目录、600 文件，不打印 bearer）。线上两者均 webhook、coalesce_if_active、skip_missed，setupPending=false、enabled=false。
2. 将**正式 routine 完整 description 原样复制到测试 routine**（包括首行），并复制 concurrencyPolicy/catchUpPolicy。不是改正式 routine，也不是发送演练文案。只使用测试 webhook 的现有 bearer/URL，不复制正式 bearer，不新建 trigger。
3. 为消除演练前缀差异，在暂停状态把私有 host.json 的 `formalReplayRoutine` 设置为它已有的 `drillRoutine` 值，再**只更新 manifest 中 host.json 的 SHA256**；其他条目不动并读回。该开关只允许等于测试 routine ID；正式路径不受影响，模型不能写该文件。新 AGENTS 的演练前缀服从宿主；这个模式宿主指定无前缀，helper 的 prefix 也为空。仅改描述而不做这一步不算等价重现。不要改 helper、权限或测试目标限制（仍必须 PER-67）。
4. 用独立临时 HOME：700 的临时目录 `$DRILL_HOME` 下建立 `.config/grokbot/webhooks/ops-system.env`（600），由脚本从测试凭据文件读 URL/KEY 写入，地址仍经过正式转发器，但路由指向**测试** webhook。不改真实 HOME 的正式 ops-system.env，不打印密钥，不加 --issue 或人工要求写评论。`wake/bin/notify-run:125` 实际按 HOME 选配置；先取并核已安装 notify-run 的绝对路径 `$NOTIFY_RUN`，再只为该子进程覆盖 HOME（不影响 Paperclip/host）。预检临时 env 存在且目标正确，杜绝 fallback。工作目录 `/tmp`；不要让其他自动任务共享配置。测试 trigger 临时 enabled=true，读回，然后 resume。
5. 仅一次实际叫醒（在 `/tmp`）：`timeout 840 env HOME="$DRILL_HOME" NOTIFY_RUN_TRIES=1 "$NOTIFY_RUN" --bot ops-system --task "[切换] ops 系统通路核对（iMac）" --no-tty -- true`。实质任务与 07:33 的 `notify-run --bot ops-system --task "[切换] ops 系统通路核对（iMac）" --no-tty -- true` 一致；只隔离配置并禁止发送重试，bot 仍 ops-system，以覆盖正式发送方归一化/幂等分支。用正式 notify-run → 转发器 → webhook 通路，不用 API 直接创建 issue/heartbeat，不用演练别名或文案。临时 HOME 的 notify 日志另存为验收证据；agent 看不到该临时日志时应记未核实，不扩充日志允许清单。核不到已安装脚本同一 HOME 选配置行为就停。
6. 202 只表示接收，不算成功。等这一条结束立即 pause，禁用测试 trigger；核只一个 heartbeat、host 回执对应本次 run、PER-67 评论末行 marker/作者/时间/body 均核到、Paperclip issue done、CLI 与 host/Paperclip 花费读回。私有 result 文件为 600，目录 700；Paperclip 与运行日志里只有固定宿主结论，没有模型最终文本。评论可以“收到，无需处理”，但必须确实调用 helper。没有回执/重复运行/金额超限均失败。
7. 无论成功失败，保持暂停、测试和正式触发器 disabled；恢复测试 routine 原描述/策略；恢复备份的 host.json 和 manifest.json（去掉 replay 开关，读回全部 hashes），移除隔离演练配置。不要恢复为 enabled，不 resume 正式。恢复后普通测试仍要求 `[演练] S12 ③ E2E` 前缀。把备份/结果交主会话，由其按第 98 条另做切换；作者不执行。

这个重现验证的是“修复后的正式写法能否写评论”，不能证明旧模型当时为什么沉默。若要比较旧指令还需另获批准，不能在本次额度内擅自多跑旧版。
