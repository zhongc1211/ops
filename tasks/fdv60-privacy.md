# FDV-60 隐私页补 Messenger（Zack 19:16）
Zack 已确认：Messenger 文案、「包含 Essential/Growth 全部内容」、IG logo 144px 都可以用。
1. 在隐私页（中英）补 Messenger 数据处理说明：参照现有 WhatsApp 段落的结构和措辞，只写真实做法（经 Meta Messenger Platform 接入、收到哪些数据、用途、保存/删除方式与现有 WhatsApp 一致的部分）；不确定的事实不要编，列进 note。
2. 先只出文案，不提交：写 PRIVACY-COPY.md（原文对照 + 新增段落中英），发 webhook status=stuck，note「等营销审隐私页文案」，停下。
3. 营销审过后：英文分支开 PR 到 staging，PR head 上跑 e2e（加隐私页断言），锁 commit 合 staging，等 testing 重建，在真实 testing URL 跑 e2e + 中英桌面手机截图（定价页和隐私页）存 evidence，PR 写五项说明。生产不动。完成发 done webhook。

## 营销审过（19:21）→ 继续到 testing
- 按 PRIVACY-COPY.md 实现，只改一处：intro 中文最后一句改为「本页写给向这类企业发 WhatsApp 或 Messenger 消息的用户，也供 Meta 应用审核使用。」
- lastUpdated 改 October 2026 / 2026 年 10 月。
- /data-deletion 同一轮加：「附上你使用的 WhatsApp 号码，或你在 Messenger 上联系的 Facebook 主页名称」/ "with the WhatsApp number you used, or the name of the Facebook Page you messaged in Messenger"。
- 待 Zack 确认的事实 1–4 未定，所以只上 testing；PR 描述写明这是上生产门槛。
然后照第 3 步：PR → head e2e → 锁 commit 合 staging → testing 真实 e2e + 截图（定价、隐私、data-deletion，中英桌面手机）→ done webhook。生产不动。

## 改向（Zack 19:21：四个事实问题「按 ryze 来」）——优先于上一节
- 先别合并/部署。如已开 PR，暂停在 PR。
- 用真实浏览器读 Ryze 隐私政策（get-ryze.ai 上的 privacy policy）里关于 Messenger/Meta/Facebook 数据的段落，存档网址、原文摘录、截图到 ~/orca/workspaces/ops/tasks/evidence/FDV-60-ryze-privacy-20261015/。
- 参照其写法改 PRIVACY-COPY.md：不照抄；事实不明处用 Ryze 那种保守写法，不承诺我们查不到的事实（是否读姓名头像、存储方/保存期、删除可追溯性等）。保留营销已定的措辞（intro 那句、lastUpdated、data-deletion 句）除非与新写法冲突。
- 写 RYZE-PRIVACY-DIFF.md：Ryze 原文出处 ↔ 我们改动对照表。
- 发 webhook status=stuck，note「等营销审改后隐私文案」，停下。营销审过后再走 PR → e2e → testing。生产不动。
