# FDV-60 第二轮（Zack 16:48 亲自回答 MISSING）
## 第一阶段：只调研+出方案，做完发 done webhook 停下等审，不改站码
1. 内容发布平台、Meta 广告范围、Google 广告范围：Zack 说和 Ryze 官网（https://www.get-ryze.ai/）写的一样。用真实浏览器在 Ryze 官网找出原文，存档：网址、原文摘录、整页截图 → ~/orca/workspaces/ops/tasks/evidence/FDV-60-ryze-20261015/。
2. 各档平台数仍是 Essential 3 / Growth 5 / Premium 8，从 Ryze 的平台列表里分配。⑤高档包含低档全部内容（Growth ⊇ Essential，Premium ⊇ Growth）。写分配方案 PLATFORM-PLAN.md（表格+理由），不要动代码。
3. AI 销售助手支持 WhatsApp 和 Messenger。
4. 每个支持的平台都要用官方 logo。逐家找官方品牌规范（Meta/Facebook/Instagram/Messenger/WhatsApp、Google/Google Ads/YouTube、TikTok，以及分配到的其他平台），存档官方链接+相关原文条款，判断"用 logo 表示支持该平台/在该平台投放"是否允许、要用哪个官方素材包、有哪些用法限制。只有官方原文确实禁止时才不用，并附原文。写 LOGO-RULES.md。上一轮 MISSING 8–11 说要授权，这次重新核实，别沿用旧结论。
5. 发 done webhook（deepvision-ops.env，task=FDV-60），note 写三份文件路径和结论摘要。
## 第二阶段（等我批准方案后再做）：改 messages/对比表+logo，文案先过营销，staging PR，PR 自己 head 上跑 e2e，锁 commit 合 staging，testing 上真实 e2e+截图证据。生产不动。

## 第二阶段已批准（Zack 17:15 亲自拍板，方案 A）
- 平台：Essential = Facebook / Instagram / TikTok；Growth 加 YouTube / LinkedIn；Premium 加 Pinterest / Reddit / Snapchat。表格写「最多 N 个，可任选」/ "Up to N, your choice"（N=3/5/8）。高档包含低档全部。
- Google 广告写：搜索 / 展示 / YouTube / PMax（Search, Display, YouTube, Performance Max）。
- logo：按 LOGO-RULES.md 用官方素材原样；Instagram、Facebook 的 logo 单独成行，不和其他平台 logo 并排；YouTube 先只写文字不放 logo；不对外申请任何许可。
- AI 销售助手：三档都写 WhatsApp + Messenger。
- FAQ 中与此冲突的 WhatsApp 文案：不要自己改，先列出原文+建议改法，连同所有新增/改动文案写进 COPY.md，发 webhook（status=stuck，note 写"等营销审文案"）停下；我转营销，审过后你再继续。
- 营销审过后：staging PR（英文分支名），PR 自己 head 上跑真实 e2e（加断言：各档平台和 logo、行序、手机不遮挡），锁 commit 合 staging，等 Workers Build 部署 testing，在真实 testing URL 截中英桌面手机图存 evidence 目录，PR 写五项说明。生产不动。完成发 done webhook。

## 营销定稿（17:20，逐字照用）→ 继续实现
- platformsChoiceSuffix：zh「，可任选」；en " of your choice"（前有空格、无逗号，显示 "Up to 3 of your choice"）。
- adGoogleScope：zh「Google（搜索、展示、YouTube、PMax）」；en "Google (Search, Display, YouTube, Performance Max)"。
- 各格排法照 COPY.md 第二节。表下不加说明。写 LinkedIn 不加 ®。写 PMax。
- faq.groups.assistant.items.channel 回答：en "WhatsApp and Messenger, both connected through Meta's official APIs."；zh「WhatsApp 和 Messenger，都通过 Meta 官方接口接入。」
- revenueFunnel.faq.items.q4：问题用你 COPY.md 的建议；回答 en "It runs on WhatsApp and Messenger, connected through Meta's official WhatsApp Cloud API and Messenger Platform."；zh「在 WhatsApp 和 Messenger 上运行，分别通过 Meta 官方的 WhatsApp Cloud API 和 Messenger Platform 接入。」删「其他渠道还在计划中」。
- glossary.terms.t1.definition：只把「在 WhatsApp 上运行」改「在 WhatsApp 和 Messenger 上运行」，en 同理 "runs on WhatsApp and Messenger"，其余不动。第四节其他句子不改。
- Growth 卡加「包含 Essential 全部内容」/ "Everything in Essential"；Premium 卡加「包含 Growth 全部内容」/ "Everything in Growth"。
- 注意：Messenger 相关文案和「包含…全部内容」只上 testing，不上生产（PR 描述里写明这两项是上生产前的门槛）。
然后照「营销审过后」一节：staging PR → PR head 跑 e2e → 锁 commit 合 staging → testing 真实 e2e + 中英桌面手机截图 → done webhook。生产不动。
