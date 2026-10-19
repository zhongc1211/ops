> **DRAFT — 还没进 deepvision-site 仓库。** 拟替换仓库根目录 `AGENTS.md`（当前 origin/HEAD 159 行版）。
> 相对 159 行版的改动：
> 1. 「分工与自主推进」「Orca 协作」改写：去掉「主 Agent / 执行 Agent 绑定具体工具」「执行 Agent 不 stage/commit/push/PR/部署，由主 Agent 统一执行」；改成派活写明了就可以 push / 开 PR / 部署，没写就不做（Zack approved 2026-10-16）。**不指定用哪种 coding agent。**
> 2. 删掉「行为修复优先补充回归测试」和「tests/：Vitest 测试」的说法，验证段与测试规矩统一（只认诚实 E2E）。
> 3. 新增「部署与 CI」（cf CLI、Workers Builds、GH Actions 只测试、GitHub 不放 CF token）。
> 4. 新增一句 notify-run / 别静默停住。
> 5. Testing 段换成 00-shared-testing-block.md 中文版（含 PR head E2E 报告格式、无关失败规则）。
> 项目结构、分支整理、代码整理、业务约定、数据与外部操作、汇报：基本照搬 159 行版。
> 下面 `---` 之后是拟定的文件全文。

---

# deepvision-site 协作约定

## 分工

- 任务由开发 bot 派给 Orca 里的 coding agent。coding agent 负责实现、测试和初审；bot 负责验收。不冒充用户本人。不指定用哪种 coding agent。
- 派活里会写明：目标、工作区、分支、base commit、修改范围、已定决定、禁止事项、验收条件、停止条件，以及**是否允许 push、开 PR、合并、部署**。
- 派活写明可以 push / 开 PR / 合并 / 部署的，就照做；没写的不做，停在本地提交，报告里写明停在哪一步。push 权限不等于生产操作权限。（Zack approved 2026-10-16）
- 在派活范围内自主完成实现、修复和验证，不反复询问下一小步。
- 需要新增费用、凭据、生产权限、不可逆操作或业务决定时，停下说明事实、推荐方案和影响，再提具体问题。
- 一个子任务受阻时，记录原因，继续做独立且已授权的部分。不把某一轮完成写成整个项目完成。

## Orca

- 一个 Linear issue 一个工作区，一个工作区一个 PR。不在别的任务的工作区里改东西，不自行二次委派。
- 动手前读本工作区的 `AGENTS.md` 和 `docs/solutions/LESSONS.md`（如有）。本工作区的 AGENTS.md 如果比主分支旧，先 rebase 到最新 base，或按派活里附的测试规矩执行。
- 超时、断线或没有输出不代表别的执行者已停止。未核实前不启动重复写入者。
- 超过 15 分钟的命令（构建、E2E、部署）用 notify-run 包：`notify-run --bot <派活的 bot> --task "<编号> <简述>" -- <command>`。做完或卡住不要静默停在输入框：最后一条消息写「结论 + 报告路径」。
- 叫醒、webhook 等细节以派活说明为准，不写在本文件。

## 项目结构

- Next.js App Router、React、TypeScript、Tailwind CSS；部署在 Cloudflare Workers（OpenNext）。
- 使用 npm 和 package-lock.json。安装现有依赖优先 `npm ci`；不为普通整理换包管理器、批量升级依赖或重写锁文件。
- `app/[locale]/`：中英文公开页面。
- `app/admin/`：管理后台。
- `app/api/`：接口、认证和外部服务回调。
- `app/p/[token]/`：WhatsApp 机器人支付链接入口。
- `components/`：共享界面组件。
- `lib/`：业务逻辑、认证、数据库和外部服务集成。
- `messages/`、`i18n/`：翻译与语言路由。
- `content/`：文件内容；`data/`：本地数据目录。
- `tests/`：现有测试（Vitest 单测 + Playwright E2E）。现有单测保留，不删不削弱；新改动的验收靠 E2E，见「测试规矩」。
- `docs/solutions/`：已解决问题与经验记录。
- `docs/plans/`、`docs/brainstorms/`：历史设计材料，用前核对当前代码，不当作现状。
- `docs/decisions.md`：Zack 拍过板的产品决定，不许自己推翻。

## 分支与工作区整理

- 开始前检查当前分支、未提交改动、跟踪关系和 worktree。先确认修改归属，不覆盖其他会话或用户的工作。
- 按提交关系、实际差异和任务状态判断分支用途，不凭分支名或最后提交时间认定可删。
- 疑似已合并分支，核对目标分支是否包含其工作；squash / cherry-pick 的要看内容，不能只看祖先关系。
- 清理 worktree 前，检查未提交、未跟踪及忽略文件，确认没有要保留的资料或运行中的任务。
- 未合并分支保留，并说明独有改动和建议处置。不用强制删除、`reset --hard` 或 `git clean` 解决不确定状态。
- 不擅自改写已推送的历史。整合时保留贡献归属，不把他人改动混入自己的提交。
- 提交前检查 diff，用明确文件列表暂存。不用 `git add .` 或 `git add -A`。
- 推送前对真实 base 看 `git diff --stat`，删掉脚手架、临时脚本、重复测试和无关改动。每个 PR ≤2000 行，超了拆成叠加 PR。
- 推送前核对全部待推送历史、目标分支和自动部署行为（push 到 staging / main 会触发 Workers Builds）。工作区干净不代表待推送历史安全。

## 代码整理

- 优先处理影响正确性、维护和验证的问题。不为目录整齐或个人风格大范围搬动与重写。
- 重构与业务行为变化尽量分开，保持差异可审查。
- 删除代码前检查静态引用、动态路由、配置、脚本及外部调用约定。搜不到引用不等于可以删。
- 复用现有组件、样式和业务函数。没有明确复用需求时不提前建通用框架。
- 不因界面不再使用某功能，就删对应数据库表或历史数据。
- 范围外问题记录影响；只有阻塞当前任务时才纳入修复。

## 业务约定

- 页面改动同时检查英文和中文。新增翻译键同步维护 `messages/en.json` 与 `messages/zh.json`。
- 套餐与金额以 `lib/pricing.ts` 为统一来源。修改时核对展示文案、Stripe 参数和相关 E2E。不在整理代码时改价格、计费周期或促销承诺。
- 支付相关变更检查来源标识、金额、币种、订单状态及重复回调处理。不把无关 Stripe 会话当成本项目订单。
- `lib/checkout-link-token.ts` 是与 wa-multi-agent 的跨仓库接口。改字段、签名、编码或有效期时检查兼容性和契约测试；不假定另一个仓库会同步发布。
- 后台权限在服务端执行。隐藏按钮不能代替接口授权检查。
- 数据库入口是 `lib/db/index.ts`。`getDb()` 会初始化表，并可能创建初始管理员；调用前确认 `DATABASE_PATH` 指向预期的本地测试数据库。
- 数据结构变更验证已有数据兼容性、唯一约束和事务行为。不用空数据库测试代替升级验证。

## 数据与外部操作

- 本地开发用临时数据库和测试配置，不默认读取生产秘密或连接生产服务。
- 不在代码、日志、报告或委派任务中复制密钥、Cookie、完整支付令牌、客户信息或数据库导出。
- `.env`、SQLite 数据库及其 WAL 文件、上传资料、备份和监督记录，不顺手加入提交。
- 运行 seed、增长脚本或外部服务验证前，检查实际副作用。脚本名带「测试」「检查」不代表只读。
- 真实支付、邮件、消息发送、生产数据修改和部署，必须有当轮派活的明确授权。
- 本地验证通过不等于已部署，已部署不等于生产验收通过。

## 部署与 CI

- 部署和写 secret 用 Cloudflare CLI（`npx cf` / `cf`），不用 `wrangler deploy`、`wrangler secret`。
- 部署走 Cloudflare Workers Builds：`staging` 分支 → testing 环境，`main` 分支 → production。不从本机手动推生产，除非派活明确要求。
- GitHub Actions 只跑测试，不部署。GitHub 里不放 Cloudflare token。
- 部署到 testing 或 production 前，该 commit 的 CI 必须跑完且全绿；被取消的不算。
- 合并锁定审过的 sha：`gh pr merge --match-head-commit <sha>`。
- 不留常驻进程：预览服务器、轮询用完就关。

## 验证与验收

- 测试方法见下面「测试规矩」。行为修复用能复现问题的 E2E 证明（回退测试：把旧代码放回去，这条 E2E 会挂），不事后补单元测试。
- 不删除已有测试、不削弱断言来换取通过。
- 涉及代码的最终整合，另外跑这三条（只证明能构建，不算验收）：
  - `npm run lint`
  - `npm test`（现有单测，CI 也会跑）
  - `npm run build`
- 每条命令分别记录真实退出状态。不用管道末端成功代替原命令成功。
- 跑 E2E 前确认数据库及外部服务配置指向 testing / 隔离环境。缺环境时说明具体阻塞，不用生产配置凑出成功。
- 页面交互或布局变化要看实际页面（截图）。构建通过不能代替视觉与交互验证。
- 区分原有失败和本次引入的失败。未运行、超时和环境失败都不能写成通过。
- 工具操作被权限拒绝时保留原因，不绕过权限限制。

## 测试规矩（Zack，适用于本仓库所有改动）

原文照录：

- NEVER write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.

具体做法：

- 写完代码后不补单元测试。已有的单元测试和 CI 不删、不削弱，但它们不算验收。
- E2E 要诚实：测真实部署（testing 环境）和真实用户流程。不 mock、不 stub、不伪造接口返回、不跳步骤、不放宽断言、不挑着重跑。用了测试替身的跑法只能写成「本地替身检查」，不能写成 E2E。
- 失败照实报告。如果是测试本身写错了，写明原因和改了什么，保留失败那次的结果，再把整套重跑一遍。
- 结束时留下别人能复现的产物：命令、URL、commit、构建 id / 部署版本号，以及截图、录屏或日志的路径。

每个 PR 的 E2E：

- 每个 PR 都要在**该 PR 当前 head commit** 上跑真实 E2E。单元测试过、CI 绿都不能替代。head 变了（新 push、rebase）就要重跑，旧 commit 上的结果不算。
- 没有 E2E 结果的 PR 不转 ready、不请人 review。
- 需要花钱的环境先报预算等批准，再开。

PR 描述 / PR 评论里的 E2E 报告，全部写全：

```
E2E（PR head）
- 命令：<完整命令，如 BASE_URL=<testing URL> npm run test:e2e -- <spec>；不含密钥>
- 环境/硬件：<testing URL；跑在哪台机器（box / iMac）；浏览器；视口>
- commit：<PR head 的完整 sha>
- 结果：<通过 N / 失败 M / 跳过 K；失败用例名>
- 产物：<截图/日志/trace 路径或链接；Workers 部署版本号>
回退测试：<把旧代码放回去，这条 E2E 确实会挂：是/否/没跑>
回滚：<回滚到哪个 Workers 版本 / commit，怎么回滚>
为什么安全：<改了什么、没碰什么（支付/表单/数据）>
没跑的：<逐项写「没跑」和原因>
单元测试：CI covers unit tests
```

把失败说成「与本次改动无关」时：

- PR 评论写清用例名（文件:行）、报错原文，以及同一用例在 base 上的结果（CI 链接或重跑记录）；拿不出就写「没对照 base」。
- 重跑了要写：整轮还是只重跑失败 job、谁定的、重跑结果。`status.md` 和汇报也不能只写「无关」「偶发」「重跑全绿」。
- 同一用例或同一批失败第二次出现：先搜 Linear，有单就补评论记次数，没单就开单查；不许再照抄「无关，重跑」。

## 汇报

- 中文。先说结果和需要谁做什么，再补必要细节。最后一条消息写「结论 + 报告路径」。
- 写明实际执行者（哪个 coding agent / 工作区）、修改内容、验证范围和剩余事项。
- 区分已实现、本地检查通过、已提交、已推送、已开 PR、已部署 testing、已部署生产、生产验收通过。
- 分支整理结束时，列明已保留、已整合、已删除的分支，以及尚未处理的独有提交或工作区改动。
- 不冒称用户已亲自审阅、测试或批准。
