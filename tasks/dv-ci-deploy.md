任务：deepvision-site（zhongc1211/deepvision-site）配 GitHub Actions 自动部署。Zack 10-15 01:49 要求。派活 bot = deepvision-ops。按 compound-engineering 做。

目标
- push 到 staging 分支 → 部署 testing Worker `deepvision-site-testing`（testing 构建开关：SAMPLE_MEDIA=on、DASHBOARD_COPY=on）。
- push 到 main → 部署生产 Worker `deepvision-site-production`（SAMPLE_MEDIA=on、DASHBOARD_COPY=off，production env）。
- 没有 staging 分支就从 main 建一个。

硬性规矩
- 只用 Cloudflare CLI `cf`，不用 wrangler。照现有做法：参考 iMac ~/cutover-20261008/cf-stage.sh、cf-stage-testing 和仓库的 cf 配置（PR #51）。
- 部署前在 job 里先 dry run，打印并核对目标 Worker 名，对不上就失败退出。
- `cf workers deployments create` 必须带 `--strategy percentage`。
- Cloudflare API token 权限尽量小（只给这个账户的 Workers Scripts 编辑等必要权限），存成 GitHub secret（建议名 CLOUDFLARE_API_TOKEN，账户 ID 存 CLOUDFLARE_ACCOUNT_ID）。token 不准出现在日志、提交、PR 或任何文件里。建 token 用 Orca 浏览器（Cloudflare 后台）；登不上就发 stuck。
- 生产 job 在 Zack 批准合并这个 PR 之前绝不能触发：开 PR 到 main 时生产 job 不能跑；给生产 job 加 GitHub environment `production` 并开 required reviewer（Zack / zhongc1211）作为额外闸门。不要合并到 main。
- 每个 PR 都要在该 PR 的 head 上真跑 e2e。

步骤
1. 新分支开 PR（目标 main），PR 描述写清楚：workflow、secret 名、闸门、回滚命令。
2. 把这个分支推到 staging，确认 Actions 自动部署了 testing Worker：记下 run 链接和新 testing 版本号；验证 testing 站 /en /zh /en/pricing /en/contact /sitemap.xml 都 200、首页正常（Orca 浏览器截图）。
3. 确认没有任何生产部署被触发（cf 查生产当前版本仍为 d132705d-7026-45d0-b2d2-183e608fe42d）。
4. PR 描述补上 e2e：命令、run 链接、commit、结果。

完成或卡住时叫醒我（只写路径不写密钥）：
source ~/.config/grokbot/webhooks/deepvision-ops.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"deepvision-ops","task":"dv CI 自动部署","worktree":"<路径>","status":"done|stuck","note":"PR 链接；secret 名；staging run 链接；testing 版本；5 个页面状态码；生产版本是否未变"}'
