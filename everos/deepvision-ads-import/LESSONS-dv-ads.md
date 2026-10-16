# deepvision-ads LESSONS → EverOS agent_skill（16 条，待 eggbot 在 site 导入）

- 整理：2026-10-16 SGT，FDV-67 会话（box）。**本会话没有写入 EverOS**
- 源：仓库 `futuredeepvision/deepvision-ads` commit `645f2bf`（= origin/main = origin/staging）的 `AGENTS.md`、`docs/deploy.md`、`status.md`；#15、#16 来自 box 上本项目的 Claude auto-memory（`~/.claude/projects/-workspace-repos-deepvision-ads/memory/`，不在仓库里）
- 仓库里原本没有 LESSONS.md。下面是从规则和文档里整理出的经验条目
- seen_dates 取该条第一次进仓库的 commit 日期（`git log -S`），auto-memory 的两条取文件日期和事件日期

## 导入用的 ID（Zack 13:07，经 Coding助手）

| 键 | 值 |
|---|---|
| app_id | `deepvision` |
| project_id | `deepvision-ads` |
| agent_id | `coding-deepvision-ads` |
| user_id | `zack` |

SKILL.md 落盘位置（和心月的形态一致）：`/var/lib/everos/deepvision/deepvision-ads/agents/coding-deepvision-ads/skills/skill_<slug>/SKILL.md`

## 导入说明（给 eggbot，在 site 上执行）

方法和心月的 `import/import_lessons.py`、`vllm-omni-import/write_one_skill.py` 相同：`AgentSkillWriter.write_main` 直接写 SKILL.md，frontmatter 字段也一样。

```bash
# 1. 把本目录拷到 site（例如 /tmp/everos-lessons-dv-ads/），然后：
sudo -u everos env EVEROS_ROOT=/var/lib/everos /opt/everos/venv/bin/python3 \
  /tmp/everos-lessons-dv-ads/import_lessons_dvads.py /tmp/everos-lessons-dv-ads/LESSONS-dv-ads.md
#    先用 --dry-run 看解析结果（只解析，不写入）：应为 16 条，slug 都不超过 50 字符
# 2. 回到 box 核对（见 README.md 的 check_recall）
```

- 每条的 `## skill: <slug>` 是 skill 名；下面那个 ```yaml 块是 frontmatter 扩展字段；再往下到下一个 `## skill:` 之前是 SKILL.md 正文
- `description` = 「规则：」那一行；`source` = `deepvision-ads-lessons-import-2026-10-16`
- `category`：`rule` 是硬规则（来自 AGENTS），`lessons` 是踩过的坑；两类都计入 Seen×3。这次没有 done_right 条目
- #15、#16 来自 auto-memory。导不导入由 Zack 定；如果不导，删掉这两节再跑，check_recall 用 `--skip` 跳过

---

## skill: never-copy-reference-product-assets

```yaml
title: 不照抄参照产品的文案、图片、logo、代码
category: rule
seen_dates: [2026-10-12]
origin: AGENTS.md Hard rules（7bbf786）
```

# 不照抄参照产品的文案、图片、logo、代码

**规则：** 复刻的是参照产品的功能、流程和信息结构，不照抄它的文案、图片、logo、代码；英文 UI 文案自己写，品牌名一律用 Deepvision Ads。

Seen 1×（2026-10-12）

## 怎么做

- 对照 `ryze-screens/` 的截图和 `.txt` 只为看清控件和流程，界面文字要重新写。
- Pixel 叫 Deepvision Pixel；对外文案以后交给营销审。

## skill: no-prod-deploy-no-real-ad-accounts

```yaml
title: 不部署生产、不用真实广告账户、不花钱
category: rule
seen_dates: [2026-10-12]
origin: AGENTS.md Hard rules（7bbf786）
```

# 不部署生产、不用真实广告账户、不花钱

**规则：** 不部署生产（ads.deepvision.sg、main），只用 Google Ads 测试账户和 Meta sandbox 广告账户，不接真实支付，不做任何花钱的事。

Seen 1×（2026-10-12）

## 怎么做

- Buy / Subscribe 按钮在 testing 只走到「确认弹窗 → 提示支付未开通」。
- 要动生产或花钱，先停下来问 Zack，等批准。

## skill: one-issue-one-worktree-one-pr-2000

```yaml
title: 一个模块对应一个 issue、一个 worktree、一个 PR，不超过 2000 行
category: rule
seen_dates: [2026-10-12]
origin: AGENTS.md Hard rules（7bbf786）
```

# 一个模块对应一个 issue、一个 worktree、一个 PR，不超过 2000 行

**规则：** 一个功能模块对应一个 Linear issue、一个 Orca worktree、一个 PR；每个 PR 不超过 2000 行改动（不计 package-lock.json），按 docs/features.md 表格的顺序叠加。

Seen 1×（2026-10-12）

## 怎么做

- 开 PR 前跑 `git diff --stat <base>`，确认行数，并确认只改了本模块的文件。
- PR 正文写：改了什么、没碰什么、验证命令、回滚方式，并链接 Linear issue。

## skill: use-cf-cli-not-wrangler

```yaml
title: 部署和设置 secret 用 Cloudflare CLI（npx cf），不用 wrangler
category: rule
seen_dates: [2026-10-12]
origin: AGENTS.md Hard rules（7bbf786）
```

# 部署和设置 secret 用 Cloudflare CLI（npx cf），不用 wrangler

**规则：** 部署和设置 secret 用 Cloudflare CLI（`npx cf`），不用 `wrangler deploy` / `wrangler secret`；不留常驻的 server 或预览进程。

Seen 1×（2026-10-12）

## 怎么做

- testing 的部署走 Workers Builds（push 到 staging 触发），手工部署用 `scripts/deploy.sh testing`。
- 用完的预览服务器和轮询要关掉。

## skill: node22-and-legacy-peer-deps

```yaml
title: 本项目用 Node 22，装依赖要带 --legacy-peer-deps
category: rule
seen_dates: [2026-10-12]
origin: AGENTS.md Hard rules（7bbf786）；docs/deploy.md 构建变量
```

# 本项目用 Node 22，装依赖要带 --legacy-peer-deps

**规则：** box 上系统自带的是 Node 20，本项目要用 Node 22：先 `export PATH=$HOME/.local/node22/bin:$PATH`，装依赖用 `npm install --legacy-peer-deps`。

Seen 1×（2026-10-12）

## 怎么做

- Workers Builds 的构建变量同样要设：`NODE_VERSION=22.23.2`、`NPM_CONFIG_LEGACY_PEER_DEPS=true`。

## skill: migration-number-equals-linear-issue

```yaml
title: 迁移文件编号等于 Linear issue 编号，已合并的迁移不改
category: rule
seen_dates: [2026-10-12]
origin: AGENTS.md Conventions（7bbf786）
```

# 迁移文件编号等于 Linear issue 编号，已合并的迁移不改

**规则：** D1 迁移文件命名为 `migrations/00NN_<name>.sql`，NN 是 Linear issue 编号（FDV-37 → `0037_…`），这样叠加的分支之间不会撞号；已经合并的迁移不改。

Seen 1×（2026-10-12）

## 怎么做

- 要撤销一个已合并迁移的效果，另写一个新的迁移。

## skill: tenant-queries-filter-workspace-or-org

```yaml
title: 租户数据的查询必须带 workspace_id 或 org_id 过滤
category: rule
seen_dates: [2026-10-12]
origin: AGENTS.md Conventions（7bbf786）
```

# 租户数据的查询必须带 workspace_id 或 org_id 过滤

**规则：** D1 一律通过 `getDb()` 用 prepared statement 访问；查询租户数据时必须按 `workspace_id` 或 `org_id` 过滤；工作区页面先调用 `requireWorkspace(org, ws)`，组织页面先调用 `requireOrg`。

Seen 1×（2026-10-12）

## skill: honest-e2e-on-pr-head

```yaml
title: E2E 要诚实，并在 PR head 上跑
category: rule
seen_dates: [2026-10-15]
origin: AGENTS.md Testing（beb790a）
```

# E2E 要诚实，并在 PR head 上跑

**规则：** 写完代码后不补单元测试；E2E 是主要的验收手段，必须在真实环境里走真实用户流程，不 mock、不跳步骤、不放宽断言、不挑重跑的结果；在 PR 当前 head 上跑，head 变了就重跑；跑完留下可复现的产物。

Seen 1×（2026-10-15）

## 怎么做

- 必须单独测某个部件时，先写下它所有可能出错的方式，再写代码。
- 失败照实报告并附上证据；说某个失败「与本次改动无关」时，要给出用例名、报错原文，以及同一用例在 base 上的结果。

## skill: green-checks-before-merging-staging

```yaml
title: 合进 staging 前先确认 PR 检查是绿的
category: lessons
seen_dates: [2026-10-15]
origin: docs/deploy.md §1（8b5001c）
```

# 合进 staging 前先确认 PR 检查是绿的

**规则：** Workers Builds 只看 Cloudflare 那边配置的分支，不等 GitHub Actions 的结果；staging 上的检查失败了，testing 也照样部署，所以合进 staging 之前要先确认 PR 上的检查是绿的。

Seen 1×（2026-10-15）

## skill: cf-deploy-auto-creates-d1-r2

```yaml
title: cf deploy 会自动创建不存在的 D1/R2
category: lessons
seen_dates: [2026-10-15]
origin: docs/deploy.md §2（7c1fe2c）
```

# cf deploy 会自动创建不存在的 D1/R2

**规则：** `cf deploy`（1.0.0-beta.14）默认会自动创建配置里引用、但实际不存在的 D1 和 R2；生产资源必须先由人手工建好，把真实 ID 写进配置，然后才把 main 连到生产 Worker。

Seen 1×（2026-10-15）

## 怎么做

- 生产 D1 ID 是占位符 `PRODUCTION_D1_DATABASE_ID`；`scripts/deploy.sh production` 看到占位符会报错退出。不要为了让部署跑通去换掉占位符。

## skill: cf-custom-domain-overwrites-dns

```yaml
title: cf 部署自定义域名会直接覆盖已有 DNS 记录
category: lessons
seen_dates: [2026-10-15]
origin: docs/deploy.md §2（7c1fe2c）
```

# cf 部署自定义域名会直接覆盖已有 DNS 记录

**规则：** cf 在非交互环境里部署自定义域名时，会直接覆盖该子域名（例如 ads.deepvision.sg）已有的 DNS 记录，不会询问；部署前先查清这个子域名现在有没有别的用途。

Seen 1×（2026-10-15）

## skill: d1-migrations-do-not-roll-back

```yaml
title: 回滚 Worker 版本不会回退 D1 迁移
category: lessons
seen_dates: [2026-10-15]
origin: docs/deploy.md §5（7c1fe2c）
```

# 回滚 Worker 版本不会回退 D1 迁移

**规则：** 在后台回滚 Worker 版本，或把 staging 重置到上一个 commit，都不会回退 D1 迁移；需要回退的迁移要另写一个迁移。

Seen 1×（2026-10-15）

## skill: no-slash-in-orca-workspace-names

```yaml
title: Orca 工作区名里不要带「/」
category: lessons
seen_dates: [2026-10-12]
origin: status.md（2026-10-13 00:00 条目，23:49 事件）
```

# Orca 工作区名里不要带「/」

**规则：** 工作区名（显示名）里不要带「/」：2026-10-12 23:49，队列启动 FDV-51 时失败，原因是名称里的「/」弄坏了启动脚本。

Seen 1×（2026-10-12）

## 怎么做

- 显示名按「dv广告 · FDV-xx 简述」命名，简述里用「、」或空格，不用「/」。

## skill: stop-when-cf-builds-repo-not-visible

```yaml
title: cf builds 报 8000008/8000012 时停下报告，不自己建 token
category: lessons
seen_dates: [2026-10-15]
origin: status.md FDV-58（df5412e）
```

# cf builds 报 8000008/8000012 时停下报告，不自己建 token

**规则：** `cf builds repos connections upsert` 报 8000008（Cloudflare GitHub App 看不到仓库）或 8000012（repository no longer exists），说明 App 没装到仓库所在的 owner，或者仓库转到组织后 owner id 已经失效；这时照 brief 停下报告，不要自己新建 API token 绕过去。

Seen 1×（2026-10-15）

## 出了什么事

- FDV-58：仓库转到 GitHub 组织 futuredeepvision 后，brief 里的 provider-account-id 28890418 失效；用旧 owner 报 8000012，用新 owner 报 8000008。
- 建 trigger 需要 build token，`cf builds tokens list` 返回空；CICD.md 规定不能自己建 token，所以停下，由 Zack 二选一。

## skill: box-heavy-job-gate

```yaml
title: box 上的重任务要先过阻塞闸门（内存 ≥4G、load <6）
category: rule
seen_dates: [2026-10-14]
origin: box auto-memory box-heavy-job-gate.md（FIXSTACK seg3，Zack 定）
```

# box 上的重任务要先过阻塞闸门（内存 ≥4G、load <6）

**规则：** 在 box 上跑 build、测试、部署、e2e 之前，先在循环里阻塞等待，直到可用内存 ≥4G 且 1 分钟 load <6，每 3 分钟查一次；load ≥16 时绝不启动；同一时间只跑一个重任务。

Seen 1×（2026-10-14）

## 出了什么事

- FIXSTACK 第 3 段：只把 load 打印出来、没有真的拦住，testing 部署在 load 32 时启动了。之后 Zack 定为硬规则。

## 怎么做

- 用一个只有闸门打开才会退出的脚本，再用 `&&` 串起来：`gate.sh && scripts/deploy.sh testing`。不要只 echo 一下 load 就继续往下跑。

## skill: dvads-tooling-gotchas

```yaml
title: deepvision-ads 在 box 上的工具坑：gh pr edit、node_modules 软链、cf d1 cwd
category: lessons
seen_dates: [2026-10-14]
origin: box auto-memory dv-ads-tooling-gotchas.md
```

# deepvision-ads 在 box 上的工具坑：gh pr edit、node_modules 软链、cf d1 cwd

**规则：** `gh pr edit --body-file` 在本仓库会失败，改用 `gh api -X PATCH repos/<owner>/deepvision-ads/pulls/N -F body=@file`；不要软链 node_modules（typecheck 和测试能过，但 OpenNext 部署会失败），要用 `cp -al`；`npx cf d1 query` 必须在一个含 node_modules 的目录里跑。

Seen 1×（2026-10-14）

## 细节

- gh pr edit 失败的原因是 Projects classic 的 GraphQL 已弃用。
- 软链 node_modules 时，OpenNext 会按解析后的路径去打包 sharp 的 `.node` 文件。
- `cf d1 query` 在没有 node_modules 的目录下会报 `EACCES mkdir /node_modules/.cache`。
