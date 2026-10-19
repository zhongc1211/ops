FDV-61 Open Design 重设计稿（派活 bot = deepvision-ops）。Zack 10-15 14:12。只出设计稿：不改 deepvision-site 网站代码、不提交到 main/staging、不部署。按 compound-engineering 做。
1. 在 iMac 装 Open Design（nexu-io/open-design；macOS 用 open-design.ai 或 GitHub Releases 的桌面版；或 `od mcp install claude` 接入 Claude Code）。模型只用 iMac 本地 Claude 订阅，不建新 API key、不付费。装不上或要付费/要登录就发 stuck。
2. 用 Orca 浏览器研究 https://www.get-ryze.ai/ ，写 RYZE-STYLE.md：配色（色值）、字体、版式/栅格、组件、动效、文案语气，附截图（存工作区 shots/ryze/）。只借风格，不抄文案和素材。
3. 截 deepvision.sg 现有主要页面（首页、价格页、联系页、博客，中英，桌面+手机）和结构，交给 Open Design 按 Ryze 风格重构，出设计稿：首页、套餐对比页（几栏并排+逐项对比，带社交平台 logo；套餐名/价格/权益/平台只用站上真实数据，见同时进行的 FDV-60 工作区 MISSING.md，不编）。导出图片（PNG）到 designs/，能给可打开的链接也给。
4. 文案规矩：不提 AI 模型名，不突出 AI，不加「示例」标签（示意图只允许「界面和数据仅作示意」）。
完成或卡住发 webhook：source ~/.config/grokbot/webhooks/deepvision-ops.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"deepvision-ops","task":"FDV-61","worktree":"<路径>","status":"done|stuck","note":"RYZE-STYLE.md 路径、设计稿文件列表/链接"}'
