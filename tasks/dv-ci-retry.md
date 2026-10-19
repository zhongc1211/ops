FDV-59 接续（派活 bot = deepvision-ops）。背景见 ~/orca/workspaces/ops/tasks/dv-ci-deploy.md、PR #58（head 17fc4b6，Actions 只跑测试）、FDV-59 评论、本工作区。现行方案（Zack 10-15）：部署用 Cloudflare Workers Builds（cf CLI 配，iMac 现有 cf 登录），GitHub Actions 只跑测试，不放 Cloudflare token。
新情况：Zack 12:06 已在 GitHub 给 Cloudflare Workers and Pages App 授权 zhongc1211/deepvision-site（Cloudflare 账户 7549b9c7 的仓库列表已可见）。
1. 重试一次 cf builds upsert：只接 deepvision-site-testing、分支 staging，构建命令里核对 Worker 名+账户（不符就失败），testing 开关 SAMPLE_MEDIA=on、DASHBOARD_COPY=on。生产 Builds 不接 main。
2. 仍报 8000008 → 立即停，把原样命令和完整输出追加到工作区 STUCK.md，发 stuck webhook（note 附原样输出）。不要绕路。
3. 成功 → PR #58 的 Actions 测试绿后合入 staging；确认 Builds 自动部署 testing（build 链接、新 testing 版本号）。诚实 e2e：只打真实 testing URL，在 Orca 浏览器走真实用户流程（首页 /en /zh、价格页、联系表单页、语言切换、sitemap.xml），不 mock、不跳步、不放宽断言、不挑重跑；失败照实报。确认生产仍是 d132705d。PR 描述补 e2e（命令、URL、commit、截图路径、日志），FDV-59 评论，发 done webhook。
webhook：source ~/.config/grokbot/webhooks/deepvision-ops.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"deepvision-ops","task":"FDV-59","worktree":"<路径>","status":"done|stuck","note":"..."}'
