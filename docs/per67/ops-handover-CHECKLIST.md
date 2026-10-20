# ops 交接完成标准（dr eggbot 牵头，Zack 10-20 18:34 SGT 原话「你负责整体交接，直到整个 ops 达到预期」）

每项要有证据才打勾。合 main / 生产 / 花钱 / 删数据 = Zack 本人卡片。

- [ ] 1 叫醒修复 F1–F8：各组 PR 合 main 并装上三台机器（#44 等），真 E2E 通过
- [ ] 2 交接单：Coding助手 → ops 系统，旧 ops 活全部转走（F1–F8、ops·23/24、PER-66 第二批、Linear sync 修、CE+pstack 调研、stuck-check 无终端修、gi-wt 清理）
- [ ] 3 EverOS：10-19 补写完成并读回（[Zack答-PER67-9]）→ 服务端移交 ops 系统；dr eggbot 只读权限配好
- [ ] 4 ops 系统 webhook：三台机器配好；dev-bot-rules 81/88 行加上 ops-system
- [ ] 5 pstack 0148b78 + compound-engineering 同一 commit：box / iMac / MBA 都钉住；bootstrap 锁版本（⑧）；禁用命令真禁住
- [ ] 6 verify skill：官网 ✅（#101）；去掉 ports.test.mjs 单测；心月；vllm（落点待 Zack 定）；ops verify / SYSTEM_MAP（#28）
- [ ] 7 ops 仓库文档里「eggbot 管 EverOS」的说法改掉（见 reports/ops-bot-handover-20261019/ownership-grep.txt）
- [ ] 8 采集脚本 box 冻结后能自动补推
- [ ] 9 卡住检查误报（子进程无 notify-run）修复；告警路由到 ops-system ✅
- [ ] 10 「Orca 叫醒测试（v5）」routine 去留（等 Zack）；重活离开 box
- [ ] 11 F1–F8 全部合完后，ops 系统 跑一次 /maintain-formal-verification-skill 对齐 wake-tla-verify 模型与代码，区分模型过时 vs 代码 bug；开跑前单独给 Zack 弹费用卡（Zack 10-20 18:49 SGT「可以」）
