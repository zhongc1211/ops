# 全员省 token 自查合并（10-20，9 个 bot + dr eggbot，均未改）
1. 停掉「Orca 叫醒测试（v5）」：224次/7天，100%空跑 → 省约200+回合/周（等 Zack）
2. 叫醒前先在脚本里做便宜过滤（已处理/已批/已合/演练/暂停中的 idle、exit、killed、done+idle 双发）：Coding助手 165次里27%空跑，ops 17次里约16次已处理，广告4/11，营销1次完全重复 → 估省30–40%（ops 系统做）
3. 审批只弹一次：Coding助手 点过后项目 bot 再弹，vllm 本周≥4次 → 每次省约一轮，Zack 少点一次（等 Zack 定）
4. dev-bot-rules 27KB 每次全读 → 拆成核心约5KB+附录；status.md 控制在3KB以内（dv 235KB、心月 90KB）→ 心月估约2M token/周
5. 去重复核：生产上线核三遍、验收两层 → 只抽查
6. 大读收窄：Linear、CF、json 文案、截图（237张→降60–70%）、视频（有字幕就不抽帧）
7. 平台层：每个 bot 都背着约6–10KB 用不到的 skill/连接器目录 → 等 Zack 定能不能按 bot 裁
8. 小项：删 vllm 的 PER-56 一次性任务；修 vllm 唤醒提示词里「Coding助手 转达也算」和只写 iMac
