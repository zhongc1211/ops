# 「SEO weekly check」加入 AI 搜索引用检查（2026-10-12）

执行者：Claude Code（ops 工作区），按 Coding助手转来的任务执行。

## 结果

- 改了 iMac 上已有的 Orca 自动化「SEO weekly check」（id `827e1814-648b-41d5-bd9a-7d21c3e1f981`，每周一 08:47 新加坡时间）的提示词，没有新建自动化。自动化总数仍是 6 个。
- 改后用 `orca automations show --json` 核对：提示词与预期文本完全一致，除 `prompt` 和 `updatedAt` 外没有字段变化（预检、时间、provider、工作区都没动）。
- 新提示词还没有被自动化实际运行过。下次运行是 2026-10-19 08:47。我没有用 `orca automations run` 触发，因为那会重写今天已有的 report.md。
- 用同样的方法手动跑了一次 5 个问题：deepvision.sg 被引用 0 次。结果已追加到 `~/deepvision/seo-geo/2026-10-12/report.md` 的第 9 节，原始结果 URL 在同目录的 `ai_search.json`。

## 检查方法

用 Claude Code 内置的 WebSearch 工具，不需要登录，也不需要 API key。自动化的 provider 本来就是 claude，所以不用装新东西。每个问题搜索一次，原文不改写，不加 `site:` 限定。

两个限制，提示词里也要求写进每周报告：

- 这个工具的结果来自美国地区，不是新加坡。
- 它只代表 Claude 网页搜索这一个渠道。ChatGPT、Perplexity、Google AI Overview 的引用情况没有检查，免登录的方式查不了它们。

另外，每个问题只搜一次，同一问题重复搜索的结果可能不同，周与周的小变化不能当作趋势。

## 5 个问题

| 编号 | 问题 |
|---|---|
| Q1 | 新加坡有哪些好用的 WhatsApp 销售助手？ |
| Q2 | WhatsApp 上的销售线索怎么自动跟进？ |
| Q3 | What is the best WhatsApp sales assistant for small businesses in Singapore? |
| Q4 | How do I follow up WhatsApp leads automatically? |
| Q5 | deepvision（品牌词） |

问题的措辞是我定的，任务只给了主题。要换措辞，改提示词里对应的那一句即可。

## 今天手动运行的结果

| 编号 | 引用 deepvision.sg | 被引用的域名 |
|---|---|---|
| Q1 | 否 | respond.io、ycloud.com、hubspot.com、aichat.com |
| Q2 | 否 | wati.io、ycloud.com、aurorainbox.com、jestor.com、cliengo.com、funnelchat.com |
| Q3 | 否 | sleekflow.io、chatdaddy.tech、cresclab.com、zoko.io |
| Q4 | 否 | wati.io、swiftask.ai |
| Q5 | 否 | 无竞品，9 条结果全是同名的其他实体 |

- 4 个非品牌问题里，wati.io 和 ycloud.com 各出现在 2 个问题中，其余域名各 1 个。
- Q4 的 9 条结果有 8 条来自 wati.io 的 `/geo/` 路径和 geo.wati.io 子域名；Q3 的 9 条有 6 条来自 sleekflow.io。
- 品牌词的结果是美国视觉芯片公司 Deep Vision、法加合作的 DeepVision 研究项目、Deep Vision Consulting、Deep Vision AI，没有 deepvision.sg。

## 提示词改动

改了三处：

1. 在原第 3 步后面插入新的第 4 步「AI 搜索引用检查」。
2. 原第 4 步（写 report.md）变成第 5 步，报告内容里加了「AI 搜索引用」一项：每个问题一行的表格、5 个问题中引用 deepvision.sg 的个数、各竞品域名被引用的问题数、与上周的差异。
3. 原第 5 步（运行 `orca-ok.sh`）变成第 6 步，内容没变。

开头的只读限制和第 1 到 3 步一字未改。

### 改前

```text
每周 SEO/GEO 检查 deepvision.sg（只读：不改代码、不提交、不部署、不发消息、不建 issue，结果只写文件）。预检已把 robots.txt、sitemap.xml、llms.txt 和 precheck.log 存到 ~/deepvision/seo-geo/<新加坡日期>/。步骤：1) 读该目录的文件，记录抓取失败、首页状态码和耗时。2) 用服务账号密钥文件 ~/.config/gcloud/seo-sa.json 调用 Search Console API（资源 sc-domain:deepvision.sg，只读范围 webmasters.readonly）：最近 28 天与前 28 天的点击、展示、点击率、平均排名，按查询词和页面各取前 25；sitemap 状态。不打印、不复制、不记录密钥内容。API 返回未启用或无权限时，把原始错误码写进报告并继续后面的步骤。3) 抽查 sitemap 中的页面：状态码、canonical、hreflang（en/zh）、title 与 description 长度、结构化数据能否解析；核对 robots.txt 和 llms.txt 与 sitemap 一致。4) 把报告写到同一目录的 report.md：本周数据、与上周 report.md 的差异、发现的问题（按影响排序，附 URL 和证据）、建议人工处理的事项、未能检查的部分及原因。原始 API 响应另存为同目录的 json 文件。5) 报告写完后，最后一步运行 ~/.orca-state/bin/orca-ok.sh seo-weekly claude。
```

### 改后

```text
每周 SEO/GEO 检查 deepvision.sg（只读：不改代码、不提交、不部署、不发消息、不建 issue，结果只写文件）。预检已把 robots.txt、sitemap.xml、llms.txt 和 precheck.log 存到 ~/deepvision/seo-geo/<新加坡日期>/。步骤：1) 读该目录的文件，记录抓取失败、首页状态码和耗时。2) 用服务账号密钥文件 ~/.config/gcloud/seo-sa.json 调用 Search Console API（资源 sc-domain:deepvision.sg，只读范围 webmasters.readonly）：最近 28 天与前 28 天的点击、展示、点击率、平均排名，按查询词和页面各取前 25；sitemap 状态。不打印、不复制、不记录密钥内容。API 返回未启用或无权限时，把原始错误码写进报告并继续后面的步骤。3) 抽查 sitemap 中的页面：状态码、canonical、hreflang（en/zh）、title 与 description 长度、结构化数据能否解析；核对 robots.txt 和 llms.txt 与 sitemap 一致。4) AI 搜索引用检查：用内置的 WebSearch 工具（不需要登录；如果它是延迟加载的工具，先用 ToolSearch 加载）对下面 5 个问题各搜索一次。问题原文照抄，不改写，不加 site: 或域名限定。Q1「新加坡有哪些好用的 WhatsApp 销售助手？」Q2「WhatsApp 上的销售线索怎么自动跟进？」Q3「What is the best WhatsApp sales assistant for small businesses in Singapore?」Q4「How do I follow up WhatsApp leads automatically?」Q5 品牌词「deepvision」。每个问题记录：返回的全部结果 URL 和顺序；deepvision.sg 是否在结果里（在则记位置和具体 URL）；搜索给出的回答正文是否提到 DeepVision 或 deepvision.sg；被引用的竞品域名（子域名并入主域名，例如 geo.wati.io 算 wati.io）和回答正文点名的竞品。Q5 另外记录排在前面的同名实体。把 5 个问题的原始结果存为同目录的 ai_search.json。WebSearch 不可用或某个问题搜索失败时，把原始错误写进报告并继续后面的步骤，不改用需要登录的服务。这个工具的结果来自美国地区，只代表 Claude 网页搜索这一个渠道，不等于新加坡用户在 ChatGPT、Perplexity 或 Google AI Overview 里看到的内容，报告里写明这一点。5) 把报告写到同一目录的 report.md：本周数据、与上周 report.md 的差异、发现的问题（按影响排序，附 URL 和证据）、AI 搜索引用（每个问题一行的表格：是否引用 deepvision.sg、位置、被引用的竞品域名；5 个问题中引用 deepvision.sg 的个数；各竞品域名被引用的问题数；与上周的差异）、建议人工处理的事项、未能检查的部分及原因。原始 API 响应另存为同目录的 json 文件。6) 报告写完后，最后一步运行 ~/.orca-state/bin/orca-ok.sh seo-weekly claude。
```

## 回滚

把上面「改前」的文本存成文件后运行：

```bash
orca automations edit 827e1814-648b-41d5-bd9a-7d21c3e1f981 --prompt "$(cat prompt-before.txt)"
```

## 没有验证的部分

- 自动化无人值守运行时 WebSearch 是否可用。这次是在交互会话里验证的，同一台机器、同一个 Claude Code；提示词写了工具不可用时把原始错误记进报告并继续。要到 2026-10-19 的运行才能确认。
- 多了 5 次搜索后，整次运行的耗时。上次运行约 4 分钟（08:47 到 08:51）。
