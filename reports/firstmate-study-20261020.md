# Firstmate 研究与借鉴方案（2026-10-20，只读调研，未改任何东西）

调研范围：Zack 的 Firstmate store.db（只读）、公开模板页、Kun 的公开仓库 kunchenguid/firstmate（main@a65dcee，最后提交 10-20 14:15 SGT）、X 帖子（用了 3 次 x 调用）。对照材料：dev-bot-rules、orca-projects.md、token-audit-20261020/*.md。
没做的事：没给任何 bot 发消息，没改 Firstmate 或其他 bot 的设定，没写 store.db。ReadTranscript 和 SearchBotTemplates 这两个工具我这边没有，Firstmate 的会话是从 store.db 直接读的（是空的）。

---

## 0. 先说一个风险：Zack 这份 Firstmate 还没跑过，第一轮会自动改别的 bot

- 出处 store.db：`transcript_entries` 0 行，`blobs` 0 行，`automation_completion_inbox` 0 行；`kv.metadata` 里 name 还是 "New Agent"，`latestRootBlobId` 为空，createdAt 是 10-20 19:15:42 SGT，mode=default，isRunEverything=false（metadata 里有一个 blobEncryptionKey 字段，已脱敏，没打印）。profile.json 里 name=Firstmate，harness=temporal；settings.json 里 notifyOnAgentUpdates=true。
- store.db 里没有人设正文、skill 或 routine。本机 agent 目录里也查不到 routine（Coding助手 明明有 routine，它的目录下也没有 automations 文件），所以 skill 和 routine 应该存在服务端。**Zack 这份副本实际启用了哪些 skill 和 routine，从盘上查不到**，只能在 App 里看。
- 模板页（grokbotsdirectory.com/bots/firstmate-zpyWK5）写着 `firstmate-first-run` skill 会在「导入后的第一轮」静默执行：把 charter 写进 profile、初始化任务库、**根据各 bot 的会话改写已有 bot 的 profile（reconcile existing bots' profiles）**、检查工具，然后才打招呼。
- 模板还带一个 routine `Heartbeat`：每 6 小时的 :06 跑一次。
- **建议**：Zack 在决定之前先别跟 Firstmate 说话；在 App 里先关掉 Heartbeat、停用 first-run。不然它会改写 Coding助手 和各项目 bot 的人设，越过 dr eggbot 管人设的分工。（注：store.db-shm 和 0 字节的 store.db-wal 时间是 19:19，应该是我只读打开时 SQLite 自己生成的；主库 mtime 还是 19:15，没有被改。）

---

## (a) Firstmate 实际是怎么设计的（每条带出处）

两个版本。**Grok Bot 模板**是 Zack 导入的那个；**本地 distro**（仓库主体，在 tmux/Orca 里跑 coding agent）是 Kun 的另一套。Kun 自己说这两套是分开用的（x.com/kunchenguid/status/2112336449173610700，10-20 08:13 SGT）。

| # | 设计点 | 出处 |
|---|---|---|
| a1 | 定位：「The only agent you talk to」。Zack 只跟它说话，它在后台调度其他 bot | profile.json description；模板页 |
| a2 | 7 个 skill：firstmate-first-run、Firstmate charter、Crewmate charter（签新项目 bot 时填项目范围后 CreateAgent）、Project management（接活和派活时用）、Adversarial review（cloud agent 推完分支、开 PR 之前对抗式审查）、Lavish session（用 lavish-axi 把方案和报告做成可批注的 HTML）、Ahoy（/ahoy：只看历史，回顾上次说话以来发生了什么，加上还没答的决定，不实时拉状态） | grokbotsdirectory 模板页 |
| a3 | 1 个 routine：Heartbeat，每 6 小时 :06，便宜地查进行中的工作和没转达的 crew 消息，没事就不出声 | 同上 |
| a4 | crewmate 是长期存在、按角色分工的 bot，charter 固定。签新的之前先查已有 bot 的职责有没有重叠：重叠就复用，部分重叠就新签，并在两边 charter 里写清分界 | 仓库 GROK_BOT.md 第 3–5 行 |
| a5 | charter 里写死：crewmate 的结果和卡点只报给 Firstmate，从不直接找 captain | GROK_BOT.md 第 6 行；AGENTS.md §1 硬规矩 4 |
| a6 | 默认交出去：超过一次工具调用的活（尤其浏览器和电脑操作）交给对口 crewmate；不因为自己有登录或 token 就自己做；secret 按 bot 分，要 key 时让 crewmate 去申请，由 captain 在安全卡片上给那个 bot | GROK_BOT.md 第 9–10 行 |
| a7 | 代码只经 crewmate 用 cursor cloud agent 做，Firstmate 自己从不调 cloud agent，也不用 subagent | GROK_BOT.md 第 12–14 行；Kun 帖「none of the second mates and crewmates… is a subagent」x.com/kunchenguid/status/2108981614873371048 |
| a8 | 每个交出去的任务带短任务 id，要求按 id 回报结果；「空、没有、什么都没发生」也必须回报。定时唤醒在自己队列为空时可以不出声 | GROK_BOT.md 第 16–18 行 |
| a9 | 异步：交出去就不等，先告诉 captain 在办，结果来了再转；priority 发送只留给必须打断 crewmate 的情况 | GROK_BOT.md 第 20–21 行 |
| a10 | 发现 crewmate 犯错或低效，Firstmate 直接改它的 description | GROK_BOT.md 第 23 行 |
| a11 | 决策礼仪：一个决定一条消息，写清是什么、为什么现在要定、真实选项、推荐和一句理由；用选择卡片，一次一张，不把不相关的决定打包 | GROK_BOT.md 第 27 行 |
| a12 | 跟 captain 只说结果和后果，不说内部机制；有一张术语翻译表（worktree→本地副本、heartbeat→监控……）；绝不把 worker 报告原样转给 captain；最后一条消息要能单独看懂，PR 要带完整 URL | AGENTS.md §9 |
| a13 | 只在这几种情况立刻找 captain：待 review 的 PR、调研结论、真卡住、破坏性/不可逆/安全相关、要凭据；不报自动修复、重试和例行进展；真的没事就只回一句「Captain, shipshape.」 | AGENTS.md §9 |
| a14 | 「脚本管机械，agent 管判断」；把 token 效率当头等事；指挥层级要扁平，「每多一层都损失保真度和 token」；常驻规矩上限 9000 词，超了必须删或挪到触发式 skill 后面 | VISION.md「Scripts own the mechanics」节（仓库 AGENTS.md 实测 7257 词，约 50KB） |
| a15 | 本地 distro 用纯 bash 的 watcher 监督，零 token，只在需要时叫醒 first mate；唤醒队列要先 drain，处理完再 ack-through，同一序号不重复处理；空轮询、没变化不算进展 | README「Event-driven, zero-token supervision」；AGENTS.md §8 |
| a16 | 权限要显式授予，不推断：合并、丢弃、破坏性操作要 captain 明确发话；「证据不等于授权」；first mate 只读项目，改动归 worker | VISION.md「Authority is explicit」；AGENTS.md §1 硬规矩 1–3 |
| a17 | 交付路径自带审查力度，「不叠串行的人工审查」，不额外加独立 reviewer | AGENTS.md §7「Selected delivery path」 |
| a18 | 「重启无所谓」：在办的活、答应过的事、待定的决定都写在持久记录里，按记录关闭，不靠记忆 | VISION.md「A restart is a non-event」 |
| a19 | 太忙时把一部分 charter 拆给 second mate 扩容 | x.com/kunchenguid/status/2112261818320347454（10-20 03:17 SGT） |
| a20 | 人设：称呼 captain，带点航海口吻 | GROK_BOT.md 第 25–26 行 |
| a21 | 背景：统一 X 订阅后，Grok Bot 和 coding 共用每周额度 | x.com/kunchenguid/status/2112307458848997803（10-20 06:18 SGT） |
| a22 | 首发帖：「firstmate is THE chief of staff」 | x.com/i/status/2097076598499668193（09-08 05:36 SGT） |

查不到的：Grok Bot 模板里 Crewmate charter、Project management、Adversarial review、Heartbeat 的正文（模板页只有一句描述，仓库里也没有同名文件）；Zack 副本实际启用了哪些。

---

## (b) 我们能借鉴的地方（按收益排序）

**B1. 先用便宜检查再叫醒，空轮询不叫醒 bot**（对应 a3、a8 后半句、a14、a15）
- 改哪里：ops 系统负责的 orca-wake、notify-run、stuck-check，以及「Orca 叫醒测试（v5）」。叫醒前在脚本里先过滤这些情况：已处理的 dedup_key、已有 [Zack答]、已合并且工作区干净、`[演练` 工作区、主动关终端产生的 killed、done 和 idle 双发。规矩里只加一句原则（「能用脚本判断的不叫醒 bot」），替换掉叫醒 v5 第 1 条的去重描述，不加新条目。
- 预期：v5 测试 224 次/7 天全是空跑，停掉或改写本地日志，估省 200+ 回合/周；其余叫醒估省 30–40%（Coding助手 27% 空跑，ops 约 16/17 无需动作）。（估）
- 风险：过滤写错会漏掉真卡住。缓解：被过滤的写一行本地日志，夜审抽查；E2E 每种 status 各发一次。
- 冲突：没有。改脚本是代码活，交 Orca coding agent；ops 的 PR 由 Zack 合（agent 不自合）。停 v5 要 Zack 定（已在合并清单第 1 项）。

**B2. 每件事只批一次：卡片点过就是本人原话，不再二次弹卡**（对应 a11、a16）
- 改哪里：dev-bot-rules「要 Zack 决定的事」第 3 小条，改准一句：「Zack 在任何私聊卡片上点的选项，由弹卡的 bot 当场记 [Zack答] 链接；负责 bot 查到范围一致的 [Zack答] 就直接做，不再弹卡」。改的是现有句子，不加长。同时修 vllm 唤醒提示词里「Coding助手 转达也算」这种旧说法。
- 预期：vllm 本周 ≥4 次重复弹卡，每次约 2–3 万 token（估），Zack 也少点一次。
- 风险：范围判断放宽可能越权。缓解：只认带 Linear 链接、范围一致的。
- 冲突：**有一处要 Zack 定**。他的规矩是「merge main 等在负责 bot 的私聊卡片上批」，而 Firstmate 的做法是所有决定都在前门 bot 的聊天里批。两个选择：① 弹卡位置不变（负责 bot），Coding助手 不再为同一件事另弹；② 允许在 Coding助手 私聊里批，负责 bot 认这个 [Zack答]。我推荐 ①：不动他的规矩，只去掉重复。

**B3. 汇报只走一条线：项目 bot 不直接找 Zack，Coding助手 用「结果语言」统一转**（对应 a1、a5、a12、a13）
- 改哪里：dev-bot-rules「沟通」第 1 条已经写了只回派活的 bot，再在同一条里补半句「给 Zack 的话只由 Coding助手 说，转述用结果和后果，不贴 worker 原文」。审批卡是唯一例外，保持不变。各 bot 人设里有直接给 Zack 发总结的残留，由 dr eggbot 在日查里纠正。
- 预期：减少审计里的重复汇报链（ops 同一结果发给 dr eggbot、Coding助手、Zack 三方；运维上线后五处写同一个版本号），Zack 少同时跟几个 bot 说话。token 估省每天 5–10 回合（估，参考 coding.md d 项）。
- 风险：Coding助手 成了单点，它被叫醒的负担变重（今天 18:00–19:15 已约 20 次）。所以要和 B1、B5 一起做。
- 冲突：没有，和「只在做完、卡住、要拍板时回」一致。

**B4. 验收不叠层：谁派活谁验收，Coding助手 只抽查**（对应 a17）
- 改哪里：dev-bot-rules「Linear」最后一条（「为什么安全」那句），改成「项目 bot 按五项验收，写进 PR 评论；Coding助手 只核 PR head 和 Linear 状态，不重抓全文」。生产上线由三方核三遍改成「生产台账 + 负责 bot」两方。
- 预期：去掉审计里的双层验收（FDV-94、ops#46）和上线三核，估每次省 1–2 万 token（估）。
- 风险：项目 bot 自己验自己，可能放水。缓解：五项证据缺一项就退回；Coding助手 每周抽查若干条（抽查比例待定）。
- 冲突：没有。sha256 三方核对是规矩明确要求的，保留。

**B5. 「/ahoy」式回顾：Zack 回来时一条消息讲清进展和待定事项**（对应 a2 Ahoy、a11）
- 改哪里：不建新 routine，也不加新 skill。在 Coding助手 人设里加一句：Zack 说「ahoy」或「我回来了」时，从 Linear「等 Zack」标签和上次对话以来的 [Zack答] 生成回顾，然后按影响大小一张卡一张卡地问。
- 预期：Zack 不用逐个 bot 去问进度。省的主要是 Zack 的注意力；token 很少。
- 风险：Linear 标签不准，回顾就不准。依赖「问出去就记进 Linear」这条现有规矩执行到位。
- 冲突：人设加一句。规矩总长要守「只并不增」，在 Coding助手 人设里合并掉一句旧的。

**B6. 常驻规矩设上限，其余挪到按场景触发**（对应 a14）
- 改哪里：dev-bot-rules 现在 27,152 字节，每次唤醒全读。按 Firstmate「常驻 ≤ 上限，超了就删或挪到触发后面」的做法，拆成核心（约 5KB：批准分级、沟通、出错）加按场景读的附录（Orca 细节、花钱、叫醒 v5、AGENTS 核对）。
- 预期：心月一个 bot 估约 2M token/周（MERGED 第 4 项）；全体每次唤醒少读约 20KB（估）。
- 风险：bot 不读附录就漏规矩。缓解：核心里列「做 X 前先读附录 Y」的触发表。
- 冲突：没有，正好符合「越写越准不越长」。这是 dr eggbot 的本职，改 skill 文件要 Zack 点头。

**B7. 派活带任务 id，结果按 id 回，空结果也回**（对应 a8、a18）
- 改哪里：我们已经用 Linear 编号当任务 id。只把「被派活的回报，空结果也要按编号回」并进「派活必须叫醒」第 1 条，同时把 dedup_key 和 Linear 编号对齐。
- 预期：减少「派了没回、靠 stuck-check 追」的情况，少量 token。
- 风险：低。
- 冲突：没有。

**B8. 签新 bot 前先查职责重叠，并写清分界**（对应 a4、a19）
- 改哪里：dr eggbot 设计新 bot 的流程里加一步「先对照现有 bot 职责，重叠就复用」，比如杂务助手职责很窄。
- 预期：避免新 bot 和已有 bot 重复（zawu.md 里有 ops#1 合并 Zack 先找杂务再转 Coding助手 的例子）。
- 风险：低。
- 冲突：和「每个 bot 只做一件事」一致。

---

## (c) 不该照搬的地方

1. **first-run 自动改写其他 bot 的 profile，以及「发现 crewmate 犯错就直接改它的 description」**（a2、a10）：和「Grok Bot 的错由 dr eggbot 每天查，只并不增」冲突，也会绕过 Zack 对规矩和人设的把关。
2. **Firstmate 自己 CreateAgent 签新 crewmate**（a2 Crewmate charter）：bot 设计归 dr eggbot，加 bot 应该由 Zack 定。
3. **Heartbeat 每 6 小时的 routine**（a3）：规矩是「bot 不自建定时 routine，定时检查做成 Orca automation」；而且 ops 的 stuck-check 已经每 15 分钟跑一次，再加一层就是重复唤醒，正是这次审计要砍的东西。
4. **代码走 cursor cloud agent**（a7）：我们的规矩是交 Orca coding agent（MBA > iMac > box），不换通道。
5. **yolo 合并自主权、local-only 自合**（仓库 README「+yolo merge-autonomy」）：和「agent 不能自己合 PR」「合 main 要 Zack 本人批」冲突。
6. **决定全在前门 bot 的卡片上批**（a11）：和「在负责 bot 的私聊卡片上批」冲突（见 B2），除非 Zack 改规矩。
7. **Lavish session（lavish-axi HTML 报告）**（a2）：要装新工具，多花 token。Zack 要的是简短中文。
8. **captain 称呼和航海口吻**（a20）：Zack 要求简体中文、简短直接。
9. **Adversarial review 再加一层审查**（a2）：会和 B4 去重的方向相反。我们已经有五项验收和 E2E 硬标准，不再叠一层。
10. **本地 distro 的 tmux、treehouse、no-mistakes 那一整套**：我们已经有 Orca、notify-run、orca-wake，换掉成本高。只借原则（a14、a15），不借实现。
11. **把 Firstmate 放到 Coding助手 上面当总入口**：Firstmate 自己的 VISION 也说「指挥层级要扁平，每多一层都损失保真度和 token」（a14）。加一层等于又多一个每次被叫醒都要重载上下文的 bot；Kun 也说 Grok Bot 现在和 coding 共用每周额度（a21）。

---

## (d) Firstmate 要不要取代或合并 Coding助手

| 选项 | 做法 | 好处 | 代价和风险 |
|---|---|---|---|
| A 取代 | 把 Firstmate 人设改成中文加我们的规矩，接过 Coding助手 的 routine 和 webhook，退役 Coding助手 | 名字和定位就是「唯一前门」 | dev-bot-rules 里 31 处提到 Coding助手；兜底 webhook、SEO 周检、生产台账、[Zack答] 链路都要迁；Coding助手 的上下文丢失；迁移期双前门；first-run 有改写其他 bot 的风险。估 1–2 天的迁移加验收（估） |
| B 吸收不并（推荐） | 不用 Firstmate 这个 bot，把 B2、B3、B5、B6、B7 写进 Coding助手 和 dev-bot-rules；Firstmate 先停用（关 Heartbeat、不跟它说话），保留还是删除由 Zack 定（删 bot 要本人批） | 零迁移；层级不变；直接解决审计里的重复唤醒、重复审批、汇报链问题；规矩改准不变长 | Coding助手 负担变重，必须先做 B1 降噪；Zack 还是要找 dr eggbot、ops 这类非开发 bot（可以约定开发类只找 Coding助手） |
| C 并存 | Firstmate 当 Zack 唯一前门，Coding助手 降成开发调度（second mate） | Zack 只对一个 bot 说话 | 多一层，token 和延迟都增加；审批卡该在哪个 bot 弹又要重新定；两个总管职责重叠，违反「每个 bot 只做一件事」 |

**推荐 B**。理由：Firstmate 真正值钱的是几条原则（单一汇报线、一事一卡、脚本先过滤、扁平、常驻规矩有上限），不是这个 bot 本身。我们的 Coding助手 已经占着这个位置，换人只会增加迁移和 token 成本。

**落地顺序建议**（全部等 Zack 点头）：先 B1（交 ops 系统，走 PR，Zack 合）→ B2、B3、B4（规矩改准，dr eggbot 起草 diff）→ B6 拆规矩 → B5、B7、B8。

---

出处汇总：
- store.db：/home/box/agent-data/agents/0304cfbd-4bf5-49d5-aa1d-071f6bfbabef/store.db（kv、transcript_entries、blobs、automation_completion_inbox）
- 模板：https://grokbotsdirectory.com/bots/firstmate-zpyWK5 、https://www.grokbotwiki.com/bots/firstmate
- 仓库：https://github.com/kunchenguid/firstmate（GROK_BOT.md、AGENTS.md、VISION.md、README.md，main@a65dceee）
- 帖子：上表里的 x.com 链接
