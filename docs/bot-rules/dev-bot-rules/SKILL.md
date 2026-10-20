---
name: dev-bot-rules
description: >-
  开发 bot（deepvision 运维、vllm-omni 开发、心月网站 运维、deepvision 广告产品、ops 系统）的通用规矩。每次被唤醒或接到派活、动手前先读；Coding助手
  派活和验收时也按这里核对。
---
# 开发 bot 通用规矩
人设里写的项目规矩跟这里冲突时，以人设为准；但批准分级（「要 Zack 决定的事」第一条）和中文回复以这里为准。不用群聊，协作走私聊（SendToAgent）。

## 写代码
- 一律按 compound-engineering skill，给 Orca coding agent 派活时写明。代码由 coding agent 写、测、初审，我验收抽查。派活前先弄清 Zack 要解决什么、有没有更简单的做法；要自造的基础能力先找维护活跃、许可证合适的开源方案；小改动省掉方案和计划步骤，但仍由 coding agent 做。
- 用哪个 agent、模型、effort 我自选，兼顾用量和能力；Coding助手 指派带理由就照做，没带理由只当建议。
- 推送前对真实 base 看 git diff --stat，删掉脚手架、harness、重复测试和无关改动，按功能/测试/文档/其他拆分行数，确认后再推。每个 PR ≤2000 行，超了拆成叠加 PR，不为压行数牺牲可读性。
- 分阶段推（Zack 10-18 01:00）：每做完一组提交就推到远端功能分支，第一次推完就开 draft PR；每份派活 brief 的最后一步写「退出前全部 push」。iMac 和 MBA 的工作区每小时扫一次，有没推的提交、或超过 2 小时没提交的改动，就叫醒负责的 bot；连续两次叫醒没处理，升级给 Coding助手。
- 配置 Orca 只用原生设置、不装插件；一次性脚本和项目文件放进本项目自己的 Orca 项目，不进提交。
- 动手的活（浏览网页、截图、调研、搬文件、写代码，含上生产/部署和 GPU/B200 这类要长时间盯的活）一律派给 Orca coding agent（派哪台见「Orca 项目与工作区」，派前看负载），我只做判断类的事（拍板、审稿、写文案、验收），省 Grok Bot 用量。不准用 Grok Bot 的后台助手（executor/Task、computerUse）或自己连跑 Shell 去做或盯，连「用 executor 给 Orca 发任务」也不要，直接用 orca CLI 派。Orca 实在做不了的才用 Grok，并在 status.md 写一句原因。做完或卡住都用 webhook 叫醒派活的 bot（iMac、MBA 上的 env 在 ~/.config/grokbot/webhooks/<bot>.env，600）。bot 不自建定时 routine（非 bot 不可的除外），定时检查和取数做成 Orca automation（配备用 agent）。浏览器操作按优先级从高到低（Zack 2026-10-13）：① coding agent 操作 Orca 浏览器；② coding agent 操作 Chrome；③ Grok Bot 自己操作 Orca 浏览器；④ Grok Bot 操作 Chrome；⑤ 都不行才找人完成 Chrome 操作（在自己和 Zack 的私聊里说明，不在别处找）。前一档做不了才降一档，降档时在 status.md 写一句原因。
- 每个项目用自己的 Orca 项目和工作区，按现有命名格式新建，绝不借用别的项目的工作区；项目的所有文件（文档、截图、脚本）都放进它自己的 Orca 项目里管理。
- 部署和写 secret 用 Cloudflare CLI，不用 wrangler。
- 后台不挂常驻进程：预览服务器、轮询用完就关，检查带超时。

## Orca 项目与工作区
- 项目按仓库分，不按 bot 分：同一仓库可以有几个 bot 共用一个项目；新仓库（新产品）就新建自己的项目，不借别的仓库的项目；自动任务放 ops 项目。动 Orca 前先读 iMac ~/orca/workspaces/ops/orca-projects.md（仓库→项目 ID，bot→工作区），新建了项目或工作区，同一轮补进表里。
- 每个 Linear 任务单独开一个自己的工作区，不要一个 bot 守着一个工作区一直用；绝不用别的 bot 的工作区，也不在别人的工作区里开标签或终端。
- 建工作区一律 `worktree create --repo id:<仓库对应的项目ID> --no-parent --name <英文短名>`，再 `worktree set --worktree <新工作区> --display-name "<项目> · <Linear编号> <中文简述>"`（例：「心月 · PER-52 手机测试修复」；项目简称用 心月 / vllm / dv广告 / dv运维 / dv官网 / dv营销 / ops），工作区绝不建在 /tmp 或其他临时目录下。指定工作区用完整 ID `<项目ID>::<路径>`。不带 --repo 会继承当前工作区的项目。
- 派到哪台电脑（Zack 2026-10-18 15:25 本人原话「你的电脑老断，mba 接活优先级最高，然后是 imac 和你按轻重分」，取代 10-14 那条；自动任务不受影响）：MBA（tailnet 100.64.0.7，iMac 上 `ssh mba`）配好并经 Coding助手 验收后，所有动手的活优先派到 MBA 的 Orca；MBA 忙或不可用时派到 iMac Orca，轻活重活都一样；MBA 和 iMac 都不可用时，活等它们空出来，不放 box（见下条）。
- box 不做开发，不起 agent 或工作区（Zack 2026-10-21 01:06、01:10 SGT，dr eggbot 转述；取代 10-20 22:36 那条「轻量且不在意被打断的才放 box」）：开发机器只有 MBA 和 iMac，`orca` 不带 --environment 的 box Orca 不再派活。起 agent 前看目标机内存和 swap，满了就换机器或排队（iMac 只有 8GB，10-20 同时 24 个 claude 撑爆过；上限由 orca-agent-launch 卡）。对照表里注明工作树在哪台。
- 功能多的开发要拆开：一个功能（一个 Linear issue）一个工作树，并行开发，不要把很多功能堆在一个工作树里；拆出来的工作树按叠加 PR 的顺序来定 base。
- 在 Orca 里起 agent（claude / pi / codex）一律用 `orca-agent-launch`（2026-10-19 起，PER-65；iMac、MBA 都在 ~/.local/bin/）：`orca-agent-launch --bot <派活的 bot> --task "<Linear 编号> <简述>：agent 进程退出了" [--issue X --eta "YYYY-MM-DD HH:MM"] -- claude --dangerously-skip-permissions ...`。带 `--issue` 必须同时带 `--eta`（预计回复时间，SGT），它会先把 due 和「负责 bot」写进那张 Linear 卡，写不进去就不起 agent（退出码 3）；不想碰 Linear 的加 `--no-linear`（2026-10-19 起，PER-66）。它检查参数后 exec `notify-run --tty`；没带 --bot/--task、bot 没 webhook 配置、经 `bash -c`/`env`/`nohup` 转一层的都会被拒绝（退出码 2）。直接敲 `claude` 或没经 notify-run 起的，卡住检查会当 `agent_unwrapped` 报给派活的 bot，收到就关掉按这个写法重开。agent 进程退出、崩溃、断线、终端被关，都会叫醒派活的 bot（status 是 done / failed / killed）；收到这条，或被 Orca 启动自检/30 分钟巡检叫醒说「进行中但没 agent」，说明 agent 已经不在了：工作区还没做完就当场重开 agent 接着干，不等人确认；重开前先用 `orca terminal read` 确认那个终端里没有活的 agent，有就不敲。自己关终端也会收到一条 killed，不用处理。不能停下来等 Zack 授权。Orca agent 要审批时，由派活的 bot 自己处理：关掉会话，换成这个模式重开，然后接着干；绝不找 Zack。
- 显示名建的时候就用 --display-name 设好（格式见上），不能事后补；关联 Linear issue；开工、开 PR、卡住时用 `worktree set` 更新 --comment 和 --workspace-status，做完把卡片状态改成 completed。

## Orca 标签页
- 开每个终端都必须带 `--title`：主 agent 终端叫「主终端」，其他按用途起名（如「e2e 测试」）；不允许 untitled。
- 一个任务只留一个主 agent 终端，临时命令在它里面跑；浏览器标签页用完就关。
- 要等 review 或等拍板的：工作区 Sleep。真收尾（completed，PR 已合并或已存档）：`terminal close --all`。不用 `terminal stop`。

## Linear
- 写操作一律用 Orca CLI（orca linear ...）；只读查询可以用 Linear 连接器。
- PR 关联 Linear issue 和 Orca 工作区。上线后自己合并 PR、关 issue、清工作区（未提交文件先归档）；合 main、上生产按「要 Zack 决定的事」要本人批。
- 改 status.md 的同一轮必须同步改 Linear，两边对不上算没做完：开工→In Progress（评论写派给哪个 coding agent）；testing 验收步骤全做完、只等合并→In Review（挂 PR 链接）；卡住、要审批或等点头→保持 In Progress，加「等 Zack」标签或评论写清卡在哪；合进 main 或上生产、验收过、外部依赖（如 key）到位→Done（写验证结果和回滚方法），只合 staging 不算（Zack 10-18 01:35）。
- 报 PR 做完时附一句「为什么安全」：改了什么、没碰什么（如支付、表单、数据）、跑了哪条命令验证、怎么回滚（只撤自己的改动，写明回滚实测过没有）；动手前再读一次目标。Coding助手 验收只核这句、PR 评论五项证据和 head sha，不重抓全文、不重跑已有可复跑产物的 E2E（抽查除外），缺了就退回。

## 要 Zack 决定的事
- 批准分两级（Zack 10-18 00:34，取代「Coding助手 转达视同本人」；全文以这条为准）：
  - 转述就够：Coding助手 或任何 bot 转达、代定的决定，只管文档、规矩、staging/testing（含在自己仓库开 PR、push 分支、合进 staging）。
  - 必须 Zack 本人的话：合进 main（含会触发生产构建的合并）、动生产（部署、生产配置、生产 Build 触发）、花钱、对外发帖/开上游 PR/对外发布（10-20 19:37），以及删数据、换密钥、销毁服务器；都要在负责 bot 私聊的卡片上批。
  - 「本人的话」指能查证的 Zack 原话：在任何私聊里说的或在卡片上点的（转达时附原话、时间 SGT 和出处，或 [Zack答] 链接）。Coding助手 的复述、总结或「他批了」不算。已有本人原话、范围一致的直接照做，不再弹卡、不再问第二遍；超出原话范围才问。Auto-review 弹的审批卡照常弹。
- 要 Zack 本人批、还没有他原话的（Zack 10-18 01:09）：活做完、Coding助手 验收过后，bot 自己在跟 Zack 的私聊里弹批准卡片（SendToUser type widget，一句写清批什么、范围、花多少钱、Linear 编号，选项「批准」「不批」），同一轮私聊 Coding助手 说弹了。Coding助手 不为同一件事另弹卡，验收后只通知负责 bot 弹（Zack 10-20 19:29）。Zack 点的选项就是本人原话，照 [Zack答] 记进 Linear。何时能弹、等批时怎么做见「审批卡片」。
- 其他要 Zack 决定、确认或亲手跑命令时，私聊 Coding助手，不直接找 Zack，也绝不叫 Zack 去给哪个 bot 发消息。要他跑的命令单独一条，放 ``` 代码块里；换了新命令要明说旧的作废。
- 自己有后台权限能查到的，不问 Zack。
- 待 Zack 的问题记进 Linear（Zack 10-18 01:00）：问时在对应 issue 评论「[待Zack-编号] 问题、选项」并加「等 Zack」标签，没有对应 issue 的在 ops 项目开一个；Zack 答了评论「[Zack答-编号] 原话、时间（SGT）、出处」并去掉标签。Coding助手 问的由它写这两条；bot 在自己私聊直接问 Zack 的，自己照样记。
- 问出去就等答：该 issue 或同一 project 里还有开着的「等 Zack」，不许拿旧决定往下做；一问出去旧决定就暂停，只有 Zack 本人的话能关掉问题。
- 合 main、部署、改生产配置前：① 查该 issue 和所在 project 有没有开着的「等 Zack」，有就停；② 派这类活的 brief 里写「动手前调 recall_agent_experience 查上生产、部署相关教训，EverOS 挂了就记一句接着做」，由 coding agent 去查，Grok Bot 自己不查 EverOS，挡住 bot 的是第①步的「等 Zack」检查；③ 向 Coding助手 报这类操作时附对应 [Zack答] 评论链接。

## 审批卡片
- 必要操作被 Auto-review 拦下：马上带审批标志重试，把卡片弹给 Zack，不许只停手或只记一笔；同一轮私聊 Coding助手（SendToAgent priority true）说明哪个操作、为什么要批、花不花钱、卡片在我的私聊里。卡片过期就告诉 Coding助手，不自己重试。
- 只有被 Zack 或 Coding助手 叫醒的那一轮能弹卡片；卡片弹出后到 Zack 批完前，不发起别的对话。
- 后台审批卡片约 10 分钟就过期。要 Zack 批的操作只在他在线时发起（他刚发过消息，或 Coding助手 确认他在），不放进夜间定时任务里等批；他不在就停在草稿或准备好的状态，私聊 Coding助手 排到他在线时再做。

## 出错
- 同一操作或同一问题最多重试 2 次；连续 2 次失败或拿不准结果，停下找根因，找不到就私聊 Coding助手报告卡在哪，不换着花样继续试。
- 生产故障、密钥泄露或超支，先回滚/停机止损，再私聊 Coding助手。

## 沟通
- 被别的 bot（含 Coding助手）或后台任务（webhook、notify-run、routine）叫醒的那一轮，只用 SendToAgent 回给发消息或派活的 bot，绝不调 SendToUser（那会发进 Zack 私聊；10-12～18 五个开发 bot 都犯过）；转来 Zack 原话、说他在线，都不算他找我。SendToUser 只用于：Zack 本人在我私聊里找我（含刚点了我的卡片，同一轮可回他结果），或弹审批/批准卡片。
- 只在做完、卡住或要 Zack 拍板时回 Coding助手，中间不播报；不发只表示收到的消息。进展写进 status.md 顶部（只写现状，≤3KB，过时的移到归档；ops verify 超限会报）。回报用 priority true；纯通知用 false。
- Zack 在私聊直接找我：简短答他，同一轮私聊 Coding助手 转一句、记进 status.md，并马上动手，不能只答应不做。
- 要跑的命令 bot 自己跑，不让 Zack 跑（Zack 2026-10-20 17:46 SGT 原话「你们来执行，回执链接发我让我来点，以后都这样」）：只有要他本人点的授权（设备码、OAuth 链接、2FA）才把链接和验证码私聊报给 Coding助手，由它转给 Zack；agent 留着等授权完成后接着做。
- 对外文字先过 human-communication（iMac ~/.pi/agent/skills/human-communication/SKILL.md，box 副本 /workspace/skills-imac/human-communication/），草稿确认后再发。
- 已定的事没有新信息不提议推翻。
- 上生产后马上报 Coding助手（priority true），不等人问。iMac 每 15 分钟查一次生产版本，有变化就叫醒 Coding助手，没报的部署会被查出来；Coding助手 报生产状态以这份生产台账为准，不看 status.md。
- 给 Zack 的每条回复一律简体中文，包括每轮最后的总结（Zack 2026-10-18）；简短直接。

## deepvision 设计稿分工（Zack 10-15 定）
- 网站和营销页的设计稿（Open Design 出稿、迭代）归 deepvision 营销：它写设计要求，自己派 Orca agent 出稿，定稿交 Coding助手 验收（大改版 Zack 本人过目）。
- deepvision 运维 不再代派设计稿，只接定稿实现进站点代码、发 PR、跑 e2e、上 testing；营销最后在 testing 看版式。设计稿里的价格、logo、事实以运维的 messages 和 MISSING 清单为准。
- 运维按设计稿实现时，PR 描述必须列出与设计稿不一致之处（交互、文案、版式、缺的元素），逐条写原因；营销在下一轮内回复接受或要改。（Zack 10-16 批）

## 派活必须叫醒、做完自己报（Zack 10-12 批）
notify-run --tty 起的 agent 由 orca-wake 自动叫醒（见「叫醒 v5」）；本节手动 curl 只在没法用 notify-run --tty、或 orca-wake hook 没装好时兜底。
- SendToAgent：要对方动手、验收或回话的（含改完 PR、卡住）一律 priority true，纯通知才用 false。转批准或派活的一方当场在 Linear issue 设 due date 和负责 bot；没开工或到点没交，由卡住工作检查叫醒（Zack 10-18 13:18）。
- 谁派的 Orca coding agent，做完或卡住就直接叫醒谁，不经 Coding助手 转。每个开发 bot 有自己的 webhook routine「Orca 完工/卡住唤醒」，地址和密钥放在 MBA / iMac 两台的 `~/.config/grokbot/webhooks/<bot>.env`（URL=…、KEY=…）。bot 名分别是 deepvision-ops、deepvision-ads、vllm-omni、xinyue、deepvision-marketing、ops-system（营销 bot 也照此执行）。
- 验收要看 agent 的工作区或终端时，brief 和工作区名写明要留（如加「[演练」前缀），起跑前告诉各 bot 别关。
- 兜底时，派活任务里只写文件路径，不写密钥：完成或卡住时执行 `source ~/.config/grokbot/webhooks/<bot>.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"<bot>","task":"<Linear 编号>","worktree":"<路径>","status":"done|stuck","note":"..."}'`。
- 被 routine 叫醒后读 payload，按本 skill 验收或处理；需要时回 Coding助手，不找 Zack；bot=test 只确认收到。
- 兜底：Coding助手 的 webhook（`~/.config/grokbot/stuck-webhook.env`）只用于兜底。iMac Orca ops 自动任务「卡住工作检查」每天 8–23 点每 15 分钟跑一次、0–7 点每小时一次（2026-10-17 起周末也跑），iMac 和 MBA 两边的 Orca 都查。completed / in-review 的工作区叫醒后超过 1 小时还没人验收，才 POST 兜底 webhook。
- 「卡住工作检查」对 in-progress 的工作区直接叫醒派活的 bot（payload 里 status=stuck、source=stuck-check，kind 说明是哪一种），只报三种：agent 进程不在了而工作区没标完成（agent_gone）；agent 停在输入框等输入超过 30 分钟（agent_idle）；agent 还在、不在等输入，但 30 分钟没有新输出，也没有 notify-run 在跑（agent_silent）。同一工作区有新活动前只报一次。todo / in-review / completed / Sleep 的工作区不查，所以状态要随时改准：等 review 或等拍板就改 in-review 或 Sleep，做完改 completed，不然会被当成卡住。

## 叫醒 v5 bot 端处理（Zack 10-15 16:55 批；分批生效）
只对放进 enabled-bots（各机 `~/.config/orca-wake/enabled-bots`，两台应一致，用 `wake/install.sh --check` 核对）的 bot 生效；10-17 起 coding-assistant、deepvision-ops、deepvision-ads、vllm-omni、xinyue、deepvision-marketing 都已放行，10-20 起 ops-system 也已放行。
叫醒系统代码（orca-wake、orca-wake-hooks、notify-run、Pi 扩展 dispatch-wake.ts）在 ops 仓库 `wake/`（原 orca-agent-wake 仓库，10-17 并入后已只读归档），卡住检查在 ops `scripts/stuck-check.sh`。装或核对已装版本用 ops 里的 `wake/install.sh`（`--check` 只比对不写）。
1. 去重：叫醒脚本先过滤（已处理的 dedup_key、completed/Sleep 工作区、主动关终端的 killed、同任务 done+idle 双发），命中只记 wake.log、不叫醒；漏过来的查 status.md，记过就忽略。
2. 同一任务收到多条，以最新的 status 为准：
   - done / idle：按本 skill 验收（读结论 + 报告路径，核证据）；验收完把 Orca 卡片改 completed，status.md 记 key。
   - needs_input：读 agent 最后一条消息，在该终端里回答（orca terminal send），不另开会话；答不了的才私聊 Coding助手。碰到要花钱、往外发东西或者需要 Zack 拍板的问题，bot 不自己答，转给 Coding助手 问 Zack。
   - error / blocked：先查原因（日志、额度、权限）；能自己修就派 agent 继续，修不了私聊 Coding助手 并写明卡点。
3. 交接格式：agent 最后一条消息写「结论 + 报告路径」。派活模板里不再写「做完就 /exit」。
4. 不想被叫醒（Zack 自己接手会话）时，在工作区放 .orca-wake-mute，用完删掉。
5. 新 bot 放进 enabled-bots 前：确认它的 webhook routine「Orca 完工/卡住唤醒」能读五种 status（done / idle / needs_input / error / blocked）和 dedup_key，不认识的 status 当 error 处理并私聊 Coding助手；往新 bot 自己的 routine 发一组带「[演练」前缀的 webhook，五种 status 各一条，每条处理对、同一 dedup_key 只处理一次，证据（wake.log + bot 回复）存档后才放行。

## 错题本和验收硬标准（Zack 2026-10-13 批，已推到所有项目）
- 派活给 coding agent 时写明动手前先查教训：4 个项目都已接 EverOS MCP v2.2。动手前调 EverOS `recall_agent_experience`（task 写几个关键词），不调写入类 everos 工具。LESSONS.md 已弃用。接入标准见 ops 仓库 `everos-mcp/`。
- 所有项目都接 EverOS（Zack 10-16），按 app ID+项目 ID 隔离（各项目 ID 见共享记忆）。教训导入（site 上 AgentSkillWriter）和 EverOS 服务端只归 ops 系统。
- agent 报完工必须在 PR 评论里写全以下五项，缺一项 bot 不收：
  1. 回退测试：把旧代码放回去，新测试确实会挂；
  2. 真实使用证据：在 testing 环境或用真账号实测，附截图或日志；
  3. 在哪个 commit 上跑的；
  4. 回滚版本；
  5. 没跑的检查明确写「没跑」，不许省略。
- 部署到 testing 或生产前，该 commit 的 CI 必须跑完并且全绿，被取消的不算。
- 合并时锁定审过的 sha：`gh pr merge --match-head-commit <sha>`。
- 把 CI 或 e2e 失败说成「与本次改动无关」时：PR 评论里写用例名（文件:行）、报错原文，以及同一用例在 base 上的结果（CI 链接或重跑记录），拿不出就写「没对照 base」；重跑了要写重跑方式（整轮/只重跑失败 job）、谁定的、重跑结果。status.md 和给 Coding助手 的报告也带用例名，不许只写「无关」「偶发」「重跑全绿」。同一用例或同一批失败第二次出现，先搜 Linear 有单就补评论记次数，没单就开单查，不再照抄「无关，重跑」。派活给 coding agent 时写明这条。
- 东西放哪（Zack 10-18）：Zack 长期的规矩和偏好放共享记忆（自动推给每个 bot）；做法和 Grok Bot 的教训放本规矩和人设；coding agent 的教训放 EverOS（只有 Claude Code、pi 读）；决定和批准只以 Linear [Zack答] 评论为准，docs/decisions.md 只抄结论附链接，agent 不许自己推翻。
- 每晚 Orca 夜审只把 coding agent 的错记进 EverOS（如退出前没 push、CI 没跑完就部署；走 tailnet）：一条只记一个会改变做法、别处查不到的事实，临时卡点放 Linear；只写新类型，重复的在原条目加次数和日期，每项目每晚 ≤3 条；每条按目标 app/project/user 读回，读不到算没写、报负责 bot。同一条 3 个不同日子出现，夜审 webhook 叫醒项目 bot，依次：改代码结构让它犯不了＞做成 lint/CI/脚本检查（派 coding agent）＞才写进本规矩或项目规范；做成检查后删对应规矩句。被照抄的坏写法先加 lint 拦，再排清理。
- Grok Bot 自己的错不进 EverOS，由 dr eggbot 每天查（只记日报、当场叫该 bot 纠正，不改规矩）；全员自查各 bot 只报 dr eggbot，由它合成一份给 Zack。每周一汇总一次：反复出现的才写进本规矩或该 bot 人设，且只并不增（能并进已有条目就并，加一条就删或并一条，总长不超过上周）。

## 每个 PR 必须有端到端测试（Zack 2026-10-13，永久）

- 每一个 PR（含 vllm-omni 上游 PR 和各项目 PR）都必须有该 PR 本身 head 上跑的真实端到端测试；单元测试过、CI 绿都不能替代。
- PR 描述里写端到端结果：命令、硬件、commit、结果。没跑的写「没跑」并说明原因。
- 没有端到端结果的 PR 不转 ready、不请人 review。

## 派活前核对 AGENTS.md（Zack 2026-10-16）
- 派活给 coding agent 前，先打开该工作区里的 `AGENTS.md`，核对是否含最新「测试规矩」段（至少要有：不事后补单测、诚实 E2E、可复现产物、每个 PR 在 head 上跑 E2E、报告含命令/硬件/commit/结果）。
- 若文件缺失、段落过时，或仍写着「优先补回归测试 / Vitest / 纯 npm test / unit over e2e」等冲突条款：不要假设 worktree 会自动跟上主分支。任选其一写进本次派活 prompt：（1）要求先拉取或 rebase 到已合并最新 AGENTS 的主分支；（2）直接把 iMac `~/orca/wake-design/agents-align-draft/00-shared-testing-block.md`里对应语言的测试段贴进 prompt。贴了就要按贴的内容验收。
- 任何项目都不指定用哪种 coding agent，只有 pstack 验证 skill（`/pstack:*verification-skill`，只能 slash 触发）例外：只派 Claude Code，派活首行就是该 slash 命令；生成的 skill 放 `.claude/skills/`，另建 `.agents/skills` 软链；临时改坏只在本任务分支工作区做，跑完 `git restore` 并附 diff；起不来只报告不修。派活只写任务、验收标准和权限（能否 push / 开 PR / 部署以派活正文为准）。
- **vllm-omni / 上游 vLLM**：不改上游 AGENTS.md。每次派活把 iMac `~/orca/wake-design/agents-align-draft/05-vllm-dispatch-overlay.md`里的覆盖段贴进 prompt 开头；以 Zack E2E 规矩为准，不按上游 unit-first。上游其他约定（风格、目录、提交、sign-off）照常遵守。
- iMac 与 MBA 全局兜底：`~/.pi/agent/AGENTS.md`（`~/.claude/CLAUDE.md` 用 `@~/.pi/agent/AGENTS.md` 引用）。全局有测试规矩，但仓库 AGENTS 仍以本仓库最新版为准；冲突时以 Zack E2E 规矩 + 本 skill 为准。

## 长命令用 notify-run 包（Zack 2026-10-13）

- 超过 15 分钟的长命令（GPU 测试、模型对比、构建、部署、长脚本）一律用 `notify-run --bot <bot> --task "<描述>" [--issue X] -- <命令>` 包起来（各机 ~/.local/bin/）。不管成功、失败还是被 kill，它都会叫醒派活的 bot；我收到后同一轮分析结果、更新 status.md 和 Linear，并私聊 Coding助手，不能只靠事后记得去看。
- 用 notify-run 包了的命令，agent 不再另发完工 webhook，免得一件事叫醒两次。
- 整个 agent 已经用 notify-run 包住时，里面的长命令照样要包：外层只在 agent 进程退出时叫醒，长命令跑完它不知道。

## 花钱前的检查（硬规矩，Zack 2026-10-14「不要再犯同样的错误了」）
起因：10-14 vllm 两套流程抢着开机删机，开出 3 台没人管的 4×H100；另一台启动配置写错白跑 21 分钟；汇报用的是自己记的状态，没实查。
1. 任何花钱的机器只许有一个开机流程。开机前先关掉其他会开机的终端或监控。停机、删机、杀脚本前先查 Linear 最新 [Zack答] 和 status.md，已批、在上限内、没跑完的不动（10-14、10-16 vllm 三次误删已批的 pod/脚本）。
2. 开机前先在本机把启动配置对照官方示例逐项核对，写成文件；开机后先确认 server health，再跑测试。
3. 报告里的机器和花费一律用平台实查的结果；花费报"花了多少"，不报余额。
4. 测完、结果拿回来就立刻删机。
5. 同一范围（机器类型、花费上限、任务）已有 Zack 本人原话的不再问，超出才问；原话怎么认见「要 Zack 决定的事」，复述不算。Auto-review 弹的卡照常弹，不能绕过（Zack 10-14、10-18）。
