# PER-67 开发体系方案 v4（最新完整版，dr eggbot，2026-10-20 18:5x SGT）

> 依据：v3 已批方案（[Zack答-PER67-5]，原文 per67-verification-skills-overlap-PLAN.md）+ 10-20 只读核实结果。合 main、动生产、花钱、删数据仍逐张 Zack 本人卡片。

## 0. 谁做什么（10-20 新定）
- **ops 系统** 干 ops 仓库和整套开发体系的活；**dr eggbot** 牵头交接、只验收（[Zack答-PER67-11]）；Coding助手 派项目活、验收项目活。
- 完成标准：`ops-handover-CHECKLIST.md`（11 项，有证据才打勾）。
- EverOS 服务端归 ops 系统，dr eggbot 只读。

## 1. 标准（不变）
- 每个项目一个 `verify-<app>` skill + `features/`（每功能一个文件、4 个 H2），放 `.claude/skills/`，`.agents/skills` 软链过去。
- 只用 E2E，产物可复跑；每个检查先在改坏的变体上失败过；改坏只在 Orca 分支工作区，跑完 `git restore` 附 diff。
- pstack 用最新兼容版：10-20 目标 88d4751（0.15.29），兼容检查通过才升；以后出新版同样先查兼容（Zack 10-20 18:53，取代锁 0148b78）。compound-engineering 统一 2e41b44。
- 禁用 5 个命令：pstack 的 poteto-mode、tdd、reflect、setup-pstack，CE 的 lfg（要做到人手动输入也跑不了）。
- 广告产品暂停，不推广。

## 2. 第 4 步进度（10-20 核实）
| # | 内容 | 状态 | 下一步 |
|---|---|---|---|
| 1 | 夜审写入读回（#30） | ⚠️ 10-20 首次真跑因 box 冻结没跑成，只 vllm 读回 PASS | 10-19 记录补写进行中（ops 系统，[Zack答-PER67-9]）；采集脚本冻结后自动补推另开 PR |
| 2 | 官网 verify-dv-site（FDV-92） | ✅ #101 10-19 15:06 合 main，iMac 9/9 真跑通过；#103 10-20 合 | ports.test.mjs 是单测，dv 运维改 E2E 或删（10-21 12:00 前，PR） |
| 3 | 合并/验收脚本 | ❌ 未开工（10-20 ops 系统核实：无脚本、分支、PR、issue） | ops 系统 接手开工 |
| 4 | 模板 → 心月 → vllm | ❌ 未开始 | 第 3 步后开；vllm skill 落点（fork ops 分支 / ops 仓库）届时问 Zack |
| 5 | SYSTEM_MAP + `ops verify`（#28） | draft 未合 | ops 系统 rebase 成 feature map 格式 |
| 6 | 形式验证 | ✅ 叫醒系统 TLA+ 查出 F1–F8，wake-tla-verify 随 #36 合 main；修复 #37–#43 已合并并安装；真实 E2E 缺口 9 未过，缺口 3、4、7、8 未跑；#45（卡住检查路由到 ops-system、子进程误报）未合 | 缺口补完、#45 合并安装、第⑧步升到 88d4751 之后，跑 `/maintain-formal-verification-skill` 对齐模型（单 agent、只用 Claude 订阅额度，不另花钱，仍弹卡告知 Zack） |
| 7 | 园丁 `/maintain-verification-skill`（官网试 2 周） | 未开始 | 费用卡未上 |
| 8 | bootstrap 锁版本 | ❌ 未做；只有 box 手工钉了 pstack，iMac/MBA 没装（v3 写「从 0.15.26 升」有误） | ops 系统 在做：88d4751 兼容检查 → 三台钉版本、5 命令真禁、写进 bootstrap（PR）；新版每日监测先出设计 |

## 3. 交接清单其余项（详见 CHECKLIST）
F1–F8 全部合完装好；Coding助手 → ops 系统 交接单（ops-system-HANDOFF.md）；EverOS 补写后移交；ops 系统 webhook 三机配好、dev-bot-rules 81/88 行补名；ops 文档改掉「eggbot 管 EverOS」；卡住检查子进程误报修复；「Orca 叫醒测试（v5）」去留待 Zack；重活离开 box。

## 4. 检查上线后要删的规则句（不变）
合并脚本上线删 Linear 核对类句子；verify skill 上线删各 AGENTS 推前测试句；`ops verify` 上线删人工核对叫醒句；bootstrap `--check` 上线删派活参数句。

## 5. 还要 Zack 定的
- 园丁费用卡；maintain-formal 卡（不另花钱，由 ops 系统弹）。
- vllm verify skill 落点（第④步）。
- 项目 bot 能否直接照 Zack 在 Coding助手 私聊的原话办（10-20 违规检查第 3/11 条）。
- MBA 归档的 1.3GB FDV-70 截图删不删；「Orca 叫醒测试（v5）」去留。

## 6. 收尾
清单全部验收通过后，dr eggbot 把整套正式交给 ops 系统，此后不再跟进（Zack 10-20 18:55）。
