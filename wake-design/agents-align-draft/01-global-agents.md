> **DRAFT for iMac `~/.pi/agent/AGENTS.md` — 还没改 iMac 上任何文件。**
> 形式：PATCH（在现有 29 行末尾追加两段）。box 上没有该文件的副本，现有 29 行（汇报规矩、对外文案、委派偏好「主/执行 Agent 不绑定特定程序，Orca 管主工作区」）原样保留，不改动。
> 生效范围：本路径 `~/.pi/agent/AGENTS.md`；若另有配置文件用 `@~/.pi/agent/AGENTS.md` 引用，也会读到。对 iMac 上所有项目、所有工作区（含旧 worktree、vllm-omni、ops）都生效，不用等各仓库 rebase。**任何项目都不指定用哪种 coding agent。**
> box 上没有全局文件；要让 box 上的 coding agent 同样生效，需要另建 `~/.pi/agent/AGENTS.md` +（如需）`~/.claude/CLAUDE.md` 一行 `@~/.pi/agent/AGENTS.md`（见 06-apply-checklist.md，仍待 Zack 点头）。

## 应用前

```bash
cp ~/.pi/agent/AGENTS.md ~/.pi/agent/AGENTS.md.bak-20261016
```

## 追加内容（从下一行的 `## 测试规矩` 开始，追加到文件末尾）

```markdown
## 测试规矩（Zack，所有项目默认适用）

原文：
- NEVER write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.

做法：
- 写完代码不补单元测试。已有单测和 CI 不删不削弱，但不算验收。
- E2E 要诚实：真实环境、真实用户流程；不 mock、不 stub、不伪造返回、不跳步骤、不放宽断言、不挑重跑。用了测试替身的不能叫 E2E。
- 每个 PR 在该 PR 当前 head commit 上跑真实 E2E；head 变了就重跑。没有 E2E 结果的 PR 不转 ready、不请 review。
- PR 里报：命令、环境/硬件、commit（完整 sha）、结果（通过/失败/跳过及失败用例名）、产物路径；没跑的逐项写「没跑」和原因；单测只写一句 "CI covers unit tests"。
- 失败说成「与本次改动无关」时，写用例名（文件:行）、报错原文、同一用例在 base 上的结果；拿不出就写「没对照 base」。
- 花钱的环境（GPU、付费账号）先报预算等批准。

和仓库规则冲突时：
- 仓库自己的 AGENTS.md / CLAUDE.md 里关于测试的写法和上面冲突（例如上游 vLLM 的 "unit over integration over e2e"、旧版 AGENTS.md 的「行为修复优先补回归测试」「逻辑配 Vitest 测试」），**测试一律以本段为准**；仓库的代码风格、目录、提交格式等其他约定照常遵守。
- 不为了贯彻本段去改上游仓库的 AGENTS.md / CLAUDE.md。

## 跨项目默认

- 派活（dispatch）里明确写了可以 push、开 PR、合并或部署，就可以做；没写就不做，停在本地提交或草稿，报告里写明。委派不扩大授权。（Zack approved 2026-10-16）
- 任何项目都不指定用哪种 coding agent；派活只写任务，不写「用某某工具」。
- 部署和写 secret 用 Cloudflare CLI（cf / npx cf），不用 wrangler deploy / wrangler secret。部署走 Workers Builds（staging→testing，main→production）；GitHub Actions 只跑测试；GitHub 里不放 Cloudflare token。
- 超过 15 分钟的命令用 notify-run 包：`notify-run --bot <派活的 bot> --task "<编号> <简述>" -- <command>`。做完或卡住不要静默停住：最后一条消息写「结论 + 报告路径」。
- 不用 git add . / git add -A；提交前看 diff。
- 不在代码、日志、报告里贴密钥、Cookie、完整支付令牌、客户信息。
- 后台不留常驻进程：预览服务器、轮询用完就关。
```

## 不放进这里的

- 叫醒 v5 细节（dedup_key、needs_input、.orca-wake-mute、webhook payload）：只在 bot 端 dev-bot-rules，不进全局文件。
- 项目专属规则（心月的儿童使用者要求、dv官网的价格/支付约定）：留在各仓库。
