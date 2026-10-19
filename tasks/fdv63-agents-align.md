# FDV-63：deepvision-site AGENTS.md 对齐

## 目标
按底稿替换仓库根目录 `AGENTS.md`，开 PR 到默认分支（main）。不做部署，不合并。

## 底稿
全文在：`~/orca/workspaces/ops/wake-design/agents-align-draft/02-deepvision-site-AGENTS.md`
- 文件以 DRAFT 说明开头；`---` 之后是拟定的 AGENTS.md 全文。
- 写入仓库时：只保留 `---` 之后的正文（从 `# deepvision-site 协作约定` 起），不要把 DRAFT 说明段放进 AGENTS.md。

## 授权（本派活写明了）
- 可以：本地提交、push、开 PR（base = main）
- 不可以：合并 PR、部署 testing/production、改其他文件（除非底稿要求同文件内必要段落——本次只改 AGENTS.md）

## 步骤
1. `git fetch origin`；确认当前分支基于最新 `origin/main`（若本地 base 旧了，先 `git reset --hard origin/main` 再继续；工作区应干净）。
2. 读现有 `AGENTS.md` 与底稿，按底稿全文替换 `AGENTS.md`（去掉 DRAFT 前言）。
3. `git diff --stat` 确认只有 `AGENTS.md`。
4. 提交（信息简洁，如 `docs: align AGENTS.md with Zack testing + deploy/CI rules (FDV-63)`），push 当前分支。
5. 开 PR → main：
   - 标题含 FDV-63
   - 描述必须写明：**E2E 没跑：纯文档改动**
   - 另写：改了什么（测试段对齐、部署/CI、去掉冲突条款）、没碰代码/生产
   - 关联 Linear FDV-63（`Fixes FDV-63` 或 PR body 链接）
6. 等 CI 出结论；**CI 绿后先别合**。
7. 最后一条消息写：结论 + PR 链接 + head sha + 改动摘要（一两句）+ 报告路径（可写本文件或 `~/orca/workspaces/ops/tasks/evidence/FDV-63/` 若你建了）。
8. 完工 webhook（agent 进程若还停在输入框，务必发）：
   `source ~/.config/grokbot/webhooks/deepvision-ops.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"deepvision-ops","task":"FDV-63","worktree":"/Users/jiawenwang/orca/workspaces/site/dv官网-FDV-63-AGENTS对齐","status":"done","note":"PR opened; see last message"}'`

## 停止条件
- PR 已开、head 已 push、最后一条消息写清 PR/head/摘要 → 停（不要 merge、不要 deploy）。
- 卡住（权限/冲突）→ status stuck webhook + 写明卡点。

动手前先读本工作区 AGENTS.md 与 docs/solutions/LESSONS.md（如有）。不指定用哪种 coding agent——你已在跑即可。
