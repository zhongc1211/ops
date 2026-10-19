FDV-60 套餐对比（派活 bot = deepvision-ops）。按 compound-engineering 做（brainstorm → plan → work → review → compound）。
需求（Zack 10-15 14:08）：deepvision.sg 加套餐对比，高度借鉴 Grok 套餐页（SuperGrok / Heavy / Ultra：几栏并排卡片 + 下方逐项对比表）。只借布局和交互，不抄文案和素材。

硬性规矩
- 套餐名、价格、权益只用仓库现有数据（lib/pricing.ts、PricingTable、页面现有文案）和 Stripe 已有产品/价格；一个字都不编。不改价格数值、价格逻辑和 Stripe 代码/配置。注意 FDV-16 已有「package comparison」组件（PR #39），先看现状再决定改它还是新做。
- 缺的数据（某套餐某项权益没写）不要补，列进 MISSING.md，在 webhook note 里列出来。
- 价格页现有可见文案冻结；新对比区放哪里（价格页内新增区块或首页）在 PR 里写理由。中英双语。不提 AI 模型名，不加「示例」标签。
- 新文案写进 COPY.md（中英），先停下发 webhook（status=stuck，note「文案待营销审」+ COPY.md 路径 + MISSING 清单），等我回复再上 testing。
- 上 testing：用 cf 按现有方式（~/cutover-20261008/cf-stage-testing，staging 链接失效就重新构建、stage），先 dry run，打印核对目标 Worker 必须是 deepvision-site-testing，`--strategy percentage`。不用 wrangler。生产绝不动。
- e2e 必须诚实：真实 testing URL，Orca 浏览器，桌面 1440 宽和手机 390 宽各截图，走真实流程（打开页面、切语言、点套餐按钮看跳转），不 mock、不跳步、不放宽断言、不挑重跑；失败照实报。PR 描述写 e2e 命令、URL、commit、截图路径、结果。PR 关联 FDV-60。
- 终端 title 用「主终端」。
完成（或卡住）发 webhook：source ~/.config/grokbot/webhooks/deepvision-ops.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"deepvision-ops","task":"FDV-60","worktree":"<路径>","status":"done|stuck","note":"..."}'
