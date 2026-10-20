# Firstmate 做法 × 省 token 清单：和现有体系的兼容性对照（2026-10-20 19:3x SGT，只读，没改任何东西）

前提（Zack 定的）：
- 10-20 19:31：只吸收做法，不用 Firstmate 这个 bot；干活 bot 不直接向 Zack 汇报，但可以找他弹审批卡片。
- 10-20 19:29：审批卡只由负责 bot 在自己私聊里弹，Coding助手 验收后只通知，不另弹。这条已经写在 dev-bot-rules 第 48 行。
- v5 routine 正在删。

对照材料：
- dev-bot-rules：/home/box/agent-data/workflows/dev-bot-rules/SKILL.md，当前 27,252 字节，下文写「L 行号」。
- 各 bot 人设：/home/box/agent-data/agents/*/profile.json 的 description。
- /workspace/ops/orca-projects.md：box 这份只有一行「已搬到 iMac，以那份为准」加命名规则，iMac 原件我没读（要用户电脑权限）。
- 上一份报告：firstmate-study-20261020.md 的 B1–B8。
- 省 token 清单：token-audit-20261020/MERGED.md 的第 2、4、5、6、8 条。

两份清单里的重复项合并成一条：B1 = M2，B4 = M5，B6 = M4；B2 和 M8 的后半条是同一个问题。合并后共 10 条，编号 C1–C10。
字数统一按字符算（中英混排，len 计数）。

一个缺口：「全员检查时各 bot 只向 dr eggbot 报」这条规矩，我在 dev-bot-rules、各人设和本 bot 的 store 里都没找到。目前只有 Zack 在聊天里说的原话（「不要让每个 bot 单独给我汇报」），没有落到文件里。见 C3。

---

## C1（B1 + M2）叫醒前先用脚本过滤空跑 —— 要调整

- **对上的规矩**：
  - L91（叫醒 v5 第 1 条：去重，由 bot 自己查 status.md）；
  - L85–86（卡住工作检查的触发条件）；
  - L97（.orca-wake-mute）；
  - L16「bot 不自建定时 routine，定时检查做成 Orca automation」；
  - L84「bot=test 只确认收到」；
  - ops 系统人设「叫醒和卡住检查……归我」。
- **有没有等效规矩**：部分有。L91 现在是 bot 被叫醒以后再去重，等于整轮已经花掉了。「脚本先过滤、不叫醒」这一层还没有。
- **改法**（dev-bot-rules L91，替换，+7 字）：
  - 旧：「1. 去重：每个 dedup_key 只处理一次。处理前查自己 status.md 里有没有记过这个 key，记过就忽略。来源 wake-hook / stuck-check-recheck / notify-run 一视同仁。」
  - 新：「1. 去重：叫醒脚本先过滤（已处理的 dedup_key、completed/Sleep 工作区、主动关终端的 killed、同任务 done+idle 双发），命中只记 wake.log、不叫醒；漏过来的查 status.md，记过就忽略。」
  - 代码改动：orca-wake、notify-run、stuck-check 加过滤，「[演练」工作区跳过（gap 7 除外）。由 ops 系统写 brief，交 Orca coding agent 实现，开 PR。合进 ops main 要 Zack 本人在 ops 系统私聊的卡片上批，agent 不自合。
- **对现有功能的影响**：真卡住的事件可能被误过滤。保护措施：
  - agent_gone、error、blocked、needs_input 一律不过滤，只过滤上面列的四类；
  - 被过滤的每条都写一行 wake.log，夜审抽查；
  - L85 的 1 小时兜底 webhook 不动；
  - E2E 按 L98 的方法，五种 status 各发一条，再加四种该被过滤的情况，存 wake.log 加 bot 回复，作为可复跑产物。
- **v5 删除的连带影响**：L84 的「bot=test 只确认收到」有可能变成死句（见 C3 的字数抵扣）。但 L98 新 bot 放行时仍要发测试 webhook，删这半句前，ops 系统要先确认测试 payload 里的 bot 字段是不是 test。不确认就保留。
- **估算**：其余叫醒省 30–40%（估，来自 MERGED 第 2 条）。
- **归谁**：ops 系统（实现）；dev-bot-rules 文字由 Coding助手 写入（它人设「工具」节写着 Zack 定的新规矩由它写进 dev-bot-rules），dr eggbot 起草。

## C2（B2 + M8 后半）每件事只批一次 —— 规矩已有，不加；两份人设和一个 routine 提示词要跟上

- **对上的规矩**：
  - L44–47（只有本人原话算批准；有原话、范围一致的不再弹卡）；
  - L48（10-20 19:29：只由负责 bot 弹卡，Coding助手 不另弹）；
  - L57–58（只有被 Zack 或 Coding助手 叫醒的那一轮能弹卡，而且只在 Zack 在线时弹）。
- **有没有等效规矩**：dev-bot-rules 已有，不加。
- **还对不上的三处**：
  1. **Coding助手 人设「代定」节**有一句「Zack 在我这里点过卡片的同一范围，不再叫 bot 重弹。」这句默认 Coding助手 自己弹卡，跟 L48 冲突。替换为「Zack 在负责 bot 私聊点过卡片的同一范围，不再叫它重弹；我不为同一件事另弹卡。」（+13 字）。归 Coding助手 改自己的人设。
  2. **杂务助手 人设**有「Coding助手 转达的决定视同 Zack 本人的。」，跟「只有本人的话算批准」冲突。dev-bot-rules 的适用范围（L4）不含杂务助手，所以要改人设。替换为「Coding助手 转达的决定只管杂事本身，付款、删数据、换密钥仍要 Zack 本人原话。」（+18 字）。杂务助手 本来就不付款、不删数据，所以功能不受影响。归 杂务助手 改人设，dr eggbot 复核。
  3. **vllm 的唤醒 routine 提示词**：据 vllm.md，里面还写着「Coding助手 转达也算」，而且只写了 iMac。routine 提示词在服务端，我看不到原文。改法：删掉「Coding助手 转达也算」，改成「批准按 dev-bot-rules『要 Zack 决定的事』」；派活机器写「MBA 优先，其次 iMac（见 dev-bot-rules L26）」。归 vllm-omni 开发。
- **灰区（不在这次改动范围，提给 Zack）**：
  - vllm 人设写着「没经 Zack 决定（本人或经 Coding助手 转达）不在上游发帖或开 PR」；
  - 营销人设写着「对外发布先拿到 Zack 的决定（本人或经 Coding助手 转达）」。
  - 对外发布不在五类必须本人批的事里，也不在 L45「转述就够」的文档、规矩、staging 范围里。要不要算本人批，需要 Zack 定。
- **影响**：项目 bot 对 Zack 在别的私聊里点过的卡片，认 [Zack答] 链接就直接做（L47 本来就这么写）。保护措施：只认带 Linear [Zack答] 链接、范围一致的。
- **估算**：vllm 本周少弹 ≥4 次卡，每次约 2–3 万 token（估）。

## C3（B3）只由 Coding助手 一个出口转达 —— 兼容；规矩已有，不加；补一句「全员检查只报 dr eggbot」

- **对上的规矩**：
  - L49（要 Zack 决定、确认、跑命令的，私聊 Coding助手，不直接找 Zack）；
  - L65（被 bot 或后台叫醒的那一轮不许 SendToUser；例外只有 Zack 本人在我私聊找我，或弹审批卡）；
  - L66（只在做完、卡住、要拍板时回 Coding助手）；
  - L67（Zack 直接找我就答他，同一轮转告 Coding助手）；
  - Coding助手 人设「项目 bot 不直接找 Zack……我只把要紧的简短转给 Zack，不逐条转」和「长日志……聊天里只写结论和文件路径」。
  - 各项目 bot 人设都有「被 bot 或后台任务叫醒的那一轮只回给它，不调 SendToUser（弹卡片除外）」。
  - Zack 19:31 举的例子「干活 bot 不直接向我汇报，但是可以找我弹审批卡片」，就是 L65 加 L48 的组合，已有。
- **三条线怎么共存**（写清楚，不改结构）：

| 线 | 什么内容 | 谁说给 Zack | 在哪 |
|---|---|---|---|
| ① 日常开发结果 | 做完、卡住、要拍板、上线、花钱、出事 | 项目 bot → Coding助手 → Zack（只转要紧的） | Coding助手 私聊 |
| ② 审批卡 | 合 main、生产、花钱、删数据、换 key，以及 Auto-review 拦下的操作 | 负责 bot 自己弹（L48、L56），只在 Zack 在线、而且是被 Zack 或 Coding助手 叫醒的那一轮（L57–58）；Coding助手 只通知 Zack 去哪个私聊批 | 负责 bot 私聊 |
| ③ 全员检查 | 省 token 自查、Grok Bot 错题日查（L114） | 各 bot（包括 Coding助手 自己）→ dr eggbot → 合成一份给 Zack | dr eggbot 私聊 |

  - Zack 主动在某个 bot 私聊找它（L67），属于他自己开的口子，不算违反单出口。
  - 线 ③ 进行时，Coding助手 也是被查对象，不负责转交。
- **要补的一句**（dev-bot-rules L114，替换，+36 字）：
  - 旧：「Grok Bot 自己的错不进 EverOS，由 dr eggbot 每天查（只记日报、当场叫该 bot 纠正，不改规矩），每周一汇总一次：」
  - 新：「Grok Bot 自己的错不进 EverOS，由 dr eggbot 每天查（只记日报、当场叫该 bot 纠正，不改规矩）；全员自查各 bot 只报 dr eggbot，由它合成一份给 Zack。每周一汇总一次：」
- **字数抵扣**（守住「不越写越长」）：
  - 删 L133 末句「agent 做完活停在输入框时由 orca-wake 自动叫醒，不再手发完工 webhook（没走 notify-run --tty 的按「派活必须叫醒」兜底）。」（−81 字，和 L80 重复）；
  - 删 L47 的史料括号「（10-17～18 vllm、广告、运维都重问过）」（−25 字）；
  - 如果 C1 确认 bot=test 不再用，L84「；bot=test 只确认收到」也可以删（−15 字）。
- **一个例外要标出来**：营销人设允许「大改版要 Zack 本人过目的，可直接给 Zack 发一条简短的过目请求」。它不是卡片，但属于「要 Zack 拍板」，和 Zack 19:31 的例子精神一致。建议保留，不改。
- **已知违规（不用改规矩）**：ops 系统 在隐藏轮里给 Zack 发过总结（ops.md，已自纠），属于 L65 已经覆盖的情况，交 dr eggbot 日查盯着。
- **风险**：Coding助手 成了单点，被叫醒的次数会增加。必须先做 C1 降噪。
- **归谁**：dev-bot-rules 文字 dr eggbot 起草、Coding助手 写入；其余不用改。

## C4（B5）ahoy 式进展汇总 —— 要调整（只改 Coding助手 人设一句，不建 routine、不加 skill）

- **对上的规矩**：
  - Coding助手 人设「Zack 问进度时只看各项目 status.md 直接答，不去问 bot；生产部分按生产账本读线上实际版本」和「告诉 Zack『在等你』之前，先对一遍 Linear 和决定记录」；
  - L51（[待Zack] 和「等 Zack」标签）；
  - L16 不自建定时 routine；
  - L57–58 卡片规矩。
- **有没有等效规矩**：大部分有，缺的是「Zack 一句话触发」和「待定事项按影响大小一次问一件」。
- **改法**（Coding助手 人设「用量」节，替换，+48 字）：
  - 旧：「Zack 问进度时只看各项目 status.md 直接答，不去问 bot；生产部分按生产账本读线上实际版本。」
  - 新：「Zack 问进度或说「ahoy」时，只看各项目 status.md、生产账本和 Linear 开着的「等 Zack」直接答，不去问 bot；待定的按影响大小一次问一件，等卡片的只写去哪个 bot 私聊批。」
- **和其他规矩怎么共存**：
  - 只由 Zack 主动触发，所以他一定在线，不违反「只在他在线时弹」。也不是定时任务，不违反 L16 和「不建新 routine」。
  - 等批的卡片只列出来（去哪个 bot 私聊、批什么），Coding助手 不重弹，符合 L48。如果卡片已经过期（约 10 分钟），按 L58 叫醒负责 bot 重弹，不是 Coding助手 自己弹。
  - 全员检查（线 ③）的结果不进 ahoy，只写一句「省 token 合并清单在 dr eggbot 私聊」，避免两份汇报。
- **影响**：status.md 过时或太长，回顾就不准，所以依赖 C6 的 status.md ≤3KB。保护措施：生产部分照旧以生产账本为准。
- **归谁**：Coding助手 改自己的人设。

## C5（B4 + M5）验收不叠层 —— 要调整（不能去掉 Coding助手 这一层，只能收窄）

- **对上的规矩**：
  - L11「我验收抽查」；
  - L41（「为什么安全」那句，Coding助手 按这句核对）；
  - L48「活做完、Coding助手 验收过后，bot 自己弹卡」；
  - L71（上线即报，iMac 每 15 分钟对生产账本）；
  - L103–110（五项证据、锁 sha）；
  - ops 系统人设「它派活、做最终验收」「要等 Coding助手 验收后……弹卡」；
  - Coding助手 人设「验收时先查 Linear……再核对 PR 符合 dev-bot-rules 的提交规矩」。
- **为什么不能照 Firstmate 去掉一层**：L48 和 ops 人设都要求「Coding助手 验收后才弹卡」，这是 Zack 定的流程。所以只能把 Coding助手 这层从「重做一遍」改成「核证据加抽查」。
- **改法**（两处替换）：
  1. dev-bot-rules L41（+47 字）。旧：「Coding助手 验收按这句核对，缺了就退回。」新：「Coding助手 验收只核这句、PR 评论五项证据和 head sha，不重抓全文、不重跑已有可复跑产物的 E2E（抽查除外），缺了就退回。」
  2. Coding助手 人设（+19 字）。旧：「再核对 PR 符合 dev-bot-rules 的提交规矩。」新：「再核对 PR 评论里的五项证据和 head sha；项目 bot 已附可复跑产物的只抽查，不重跑。」
  - 生产上线核三遍：不加规矩。由 Coding助手 按 L71 只认生产账本，不再自己去重核 Zack 已经点过卡的部署。这已经是 L71 的原意，只是执行问题。
- **保留不动**：sha256 三方核对（ops 规矩）、L110 锁 sha、L109 CI 全绿、五项证据、只做 E2E（L116–120）。
- **影响和保护**：项目 bot 自己验自己，可能放水。保护措施：
  - 五项缺一项就退回；
  - 「出现即失败」（没有可复跑 E2E 产物、超预算）照旧；
  - 抽查比例建议每周每个 bot 至少抽 1 个 PR 全量重跑（估，等 Zack 定）。
- **估算**：每次少约 1–2 万 token（估）。
- **归谁**：L41 由 dr eggbot 起草、Coding助手 写入；人设由 Coding助手 自己改。

## C6（B6 + M4）规矩瘦身和 status.md 上限 —— 兼容；status.md 上限已有不加；拆分要调整

- **对上的规矩**：
  - L66「status.md ≤3KB」，已有，不加。问题出在执行：dv 运维 235KB、心月 90KB（审计数据）。
  - L114「只并不增，总长不超过上周」；
  - 5 个开发 bot 人设都有「每次干活前读 dev-bot-rules（…/SKILL.md）」，营销人设是「干活前读」。
- **dev-bot-rules 拆分**：
  - 当前各段字节数：头 516、写代码 3,040、Orca 项目与工作区 3,966、标签页 434、Linear 1,091、要 Zack 决定 2,823、审批卡片 749、出错 286、沟通 1,814、设计稿分工 704、派活叫醒 2,426、叫醒 v5 2,055、错题本 3,038、E2E 463、AGENTS 核对 1,867、notify-run 866、花钱 1,098。
  - 核心留：头、写代码前两条、Linear、要 Zack 决定、审批卡片、出错、沟通、E2E、错题本的五项证据和锁 sha，**估约 9KB**。MERGED 写的约 5KB 偏乐观，我实算达不到。
  - 其余挪到同一 skill 目录下的附录文件：Orca 细节、标签页、设计稿分工、派活兜底 curl、叫醒 v5、AGENTS 核对、notify-run、花钱。
  - 核心末尾放一张触发表，形式是「做 X 前读附录 Y」，例如「起 Orca agent 前读 orca.md；开 GPU、花钱前读 spend.md」。
  - SKILL.md 本身就变成核心，路径不变，所以**6 份人设一个字都不用改**。
- **status.md**：不加规矩，改成脚本检查。ops verify（或卡住检查）发现某个 bot 的 status.md 超过 3KB，就叫醒那个 bot 归档。L66 改一句（替换，+14 字）：
  - 旧：「进展写进 status.md 顶部（只写现状，≤3KB，过时的删或移到归档）。」
  - 新：「进展写进 status.md 顶部（只写现状，≤3KB，过时的移到归档；ops verify 超限会报）。」
  - dv 运维、心月 先各做一次归档（一次性的活，不进规矩），交给各自的 bot。
- **影响和保护**：bot 可能漏读附录。保护措施：
  - 触发表放在核心最上面；
  - dr eggbot 日查里专门看「该读附录没读」；
  - 拆分前后总字数，核心加附录不能超过拆分前。
- **估算**：每次唤醒少读约 18KB（估）；心月一个 bot 约 2M token/周（估，来自 MERGED）。
- **归谁**：dr eggbot 起草拆分稿；Zack 点头后 Coding助手 写入；ops 系统 做 status.md 超限检查（脚本，走 PR）；各 bot 自己归档 status.md。

## C7（M6）大读收窄 —— 兼容；部分已有；写进各 bot 人设，替换现有句

- **对上的规矩**：
  - L112「做法和 Grok Bot 的教训放本规矩和人设」；
  - Coding助手 人设「长日志、diff……存成文件」「少截图」；
  - 营销人设「优先看 testing 链接和文字说明，必要时才看截图」，已有一半；
  - L38 Linear 只读可以用连接器。
- **改法**（只改用得上的 bot，各替换一句）：
  - 营销人设（+52 字）。旧：「优先看 testing 链接和文字说明，必要时才看截图。」新：「优先看 testing 链接和文字说明，必要时才看截图，只截改动页面×4 个宽度，先用运维已有的图；json 文案按 key grep，另一分支只看 diff。」
  - 杂务助手、dv 运维、心月、广告：各自在人设「做法」句后补半句，各约 20–30 字（估），由各 bot 自己起草：
    - 杂务助手：有字幕先拉字幕，视频超过 20MB 用 1080p；
    - dv 运维：Linear 不拉 attachments，orca terminal 带 --worktree；
    - 心月：terminal list 只看 xinyue；
    - 广告：CF 查询收窄到本项目 Worker。
  - 不进 dev-bot-rules，因为每条都只对个别 bot 有用。
- **影响**：读得太窄可能漏证据。保护措施：验收时证据不够照旧退回（C5），这时再放宽读取范围。
- **估算**：截图量降 60–70%（估，来自营销自查）。
- **归谁**：各 bot 改自己的人设，dr eggbot 复核「只并不增」。

## C8（M8 前半）删掉 vllm 的 PER-56 一次性 routine —— 兼容

- **对上的规矩**：L16「bot 不自建定时 routine」；Coding助手 人设「实在要建 ≤3 个，跟进完就删」。PER-56 那个 routine 10-18 已经跑完，但还是 enabled。
- **有没有等效规矩**：已有「跟进完就删」，不加。
- **改法**：不改文字，vllm-omni 开发 删掉这个 routine。删 routine 不算删数据，但 Zack 说过「批准前什么都不改」，所以要等他点头。
- **影响**：无。保护措施：删之前在 status.md 记一行 routine 名和最后运行时间。
- **归谁**：vllm-omni 开发。

## C9（B7）派活带任务 id，结果按 id 回 —— 兼容；已有，不加

- **对上的规矩**：
  - L81（派活当场在 Linear 设 due date 和负责 bot）；
  - L83（payload 带 task=Linear 编号）；
  - L29（orca-agent-launch --issue 加 --eta）；
  - L91（dedup_key）；
  - L66「只在做完、卡住、要拍板时回」。被派的活做完了、哪怕结果是空的，也属于「做完」，要回；「不发只表示收到的消息」说的是确认收到，不冲突。
- **改法**：不改。只建议 C1 实现时让 dedup_key 带上 Linear 编号（ops 系统顺手做，不进规矩）。
- **归谁**：ops 系统（随 C1）。

## C10（B8）建新 bot 前先查职责重叠 —— 要调整（只改 dr eggbot 人设一句）

- **对上的规矩**：「每个 bot 只做一件事」；dr eggbot 人设「one job… explicit anti-jobs」。
- **有没有等效规矩**：没有显式的「先查重叠」。
- **改法**（dr eggbot 人设，英文，替换，+69 字符）：
  - 旧：「Asks a few preference questions, then creates them with CreateAgent.」
  - 新：「Asks a few preference questions, checks existing bots for overlap (reuse, or sharpen both anti-jobs), then creates them with CreateAgent.」
- **影响**：建 bot 前多一次查重。保护措施：建新 bot 仍要 Zack 同意，dr eggbot 不自建。
- **归谁**：dr eggbot。

---

## 字数账（dev-bot-rules，不含 C6 拆分）

| 改动 | 字数 |
|---|---|
| L91 | +7 |
| L114 | +36 |
| L41 | +47 |
| L66 | +14 |
| 删 L133 末句 | −81 |
| 删 L47 括号 | −25 |
| **合计** | **−2**（如果 L84 半句也删，合计 −17） |

满足「越写越准、不越写越长」。人设：Coding助手 +80，杂务 +18，营销 +52，dr eggbot +69，另有 4 个 bot 各 +20–30（估）。人设没有「不得变长」的硬约束，但按 L114 的精神，建议各 bot 改的时候顺手删掉同等长度的过时句子。

## 顺带发现（不在 10 条里，只报不改）

- 心月人设写着「只在最新副本 ~/claude/firstmate/projects/xinyue-site 上开工作区；firstmate 不再碰这个项目」。说明 Zack 以前跑过 Kun 的本地 firstmate distro，和这次的 Grok Bot Firstmate 是两回事。
- orca-projects.md 的 iMac 原件没有核对。
- Firstmate bot 的去留（留着停用还是删除），按规矩要 Zack 本人定。

## 执行顺序建议（全部等 Zack 点头）

C1（ops 系统，走 PR）→ C2 / C3 / C5（规矩和人设替换，一次改完）→ C6（拆分加 status.md 检查）→ C4 / C7 / C8 / C10。C9 不用动。
