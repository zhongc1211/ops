# 任务：分析 futuredeepvision/ryze 为什么复刻得像（只读）

背景：Zack 2026-10-18 22:19 SGT 看了私有仓库 github.com/futuredeepvision/ryze（10-17 建，JavaScript，约 94MB），觉得它复刻 get-ryze.ai 比我们好得多。我们的复刻是 deepvision 官网 FDV-70（zhongc1211/deepvision-site，staging 分支）和 deepvision 广告产品（futuredeepvision/deepvision-ads）。

要做：
1. `gh repo clone futuredeepvision/ryze ~/orca/research/ryze-ref -- --depth 50`（只读，不 push、不开 PR、不改仓库任何东西）。
2. 查清它是怎么做出来的：技术栈；是抓取/镜像原站 HTML、CSS、图片，还是手写重建；素材从哪来（原站下载还是生成）；git log 看做法和节奏；有没有用什么工具或脚本（爬虫、截图对比、AI 生成）；它覆盖了哪些页面，是官网还是广告管理后台。
3. 本地跑起来（npm ci 失败就只读代码，不要硬修），1440 宽截首页和定价页，放 ~/orca/research/ryze-ref-shots/。
4. 跟我们对比：deepvision-site staging（PR4 head 3e050d2 或 origin/staging）和 deepvision-ads。说清楚差距的根本原因，比如方法、素材、像素对照流程、验收标准，而不是逐像素列差异。
5. 给出我们能直接照搬的做法，按「立刻能用 / 要 Zack 拍板」分两栏，注意版权和品牌风险（直接用 Ryze 原图、原文要标出来）。

输出：~/orca/workspaces/ops/briefs/ryze-repo-analysis-RESULT.md，中文，开头 5 行结论。截图路径写进去。
不打印任何 token 或密钥，不花钱，不碰生产。MBA 负载超过 15 就先等。
做完运行 notify-run 的完工通知即可。
