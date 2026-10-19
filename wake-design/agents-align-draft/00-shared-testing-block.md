> **DRAFT — 还没进任何仓库。** 用途：web 仓库 AGENTS.md 里统一的「测试规矩」段，原样粘贴。中文版给 deepvision-site、xinyue-site；英文版给 deepvision-ads。
> 来源：Zack 测试硬规则 + dev-bot-rules「每个 PR 必须有端到端测试」「错题本和验收硬标准」+ 心月主分支 aca529e 的「无关失败」条款。
> 粘贴时 `<...>` 换成本仓库的实际值；心月已有的「模拟手机尺寸和真机分开报告」保留在心月版里。

---

## 中文版（粘贴从这里开始）

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
- 需要花钱的环境（GPU、付费账号）先报预算等批准，再开。

PR 描述 / PR 评论里的 E2E 报告，五项写全：

```
E2E（PR head）
- 命令：<完整命令，含环境变量名，不含密钥>
- 环境/硬件：<testing URL 或机器：如 box 8 核 / iMac / 真机型号 / 模拟尺寸>
- commit：<PR head 的完整 sha>
- 结果：<通过 N / 失败 M / 跳过 K；失败用例名>
- 产物：<截图/日志/录屏路径或链接，部署版本号>
回退测试：<把旧代码放回去，这条 E2E 确实会挂：是/否/没跑>
回滚：<回滚到哪个版本、怎么回滚>
没跑的：<逐项写「没跑」和原因>
单元测试：CI covers unit tests
```

把失败说成「与本次改动无关」时：

- PR 评论写清用例名（文件:行）、报错原文，以及同一用例在 base 上的结果（CI 链接或重跑记录）；拿不出就写「没对照 base」。
- 重跑了要写：整轮还是只重跑失败 job、谁定的、重跑结果。`status.md` 和汇报也不能只写「无关」「偶发」「重跑全绿」。
- 同一用例或同一批失败第二次出现：先搜 Linear，有单就补评论记次数，没单就开单查；不许再照抄「无关，重跑」。

## 中文版（粘贴到这里结束）

---

## English version (for deepvision-ads; paste from here)

## Testing (Zack's rules — apply to every change in this repo)

Verbatim:

- NEVER write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.

In practice:

- Do not add unit tests after writing code. Existing unit tests and CI stay as they are (don't delete or weaken them), but they are not acceptance.
- E2E must be honest: real deployment (testing environment) and real user flows. No mocks, no stubs, no faked API responses, no skipped steps, no loosened assertions, no cherry-picked reruns. A run that uses test doubles is a "local check with doubles", never "E2E".
- Report failures as they are. If the test itself was wrong, say why and what you changed, keep the failed run's output, then rerun the whole suite.
- Leave an artifact someone else can reproduce: command, URL, commit, build id / deployed version, and paths to screenshots, recordings or logs.

E2E on every PR:

- Every PR runs real E2E on **that PR's current head commit**. Passing unit tests or green CI do not replace it. If the head changes (new push, rebase), rerun; results from an older commit don't count.
- No E2E result → the PR does not go ready and does not request review.
- Anything that costs money (GPU, paid accounts) needs an approved budget first.

E2E report in the PR body / PR comment — all fields required:

```
E2E (PR head)
- Command: <full command, env var names, no secrets>
- Environment/hardware: <testing URL or machine, e.g. box 8-core / iMac / device model>
- Commit: <full sha of the PR head>
- Result: <passed N / failed M / skipped K; names of failing cases>
- Artifact: <paths/links to screenshots, logs, recordings; deployed version>
Revert check: <with the old code put back, this E2E fails: yes / no / not run>
Rollback: <version to roll back to, and how>
Not run: <each item marked "not run" with the reason>
Unit tests: CI covers unit tests
```

When you call a failure "unrelated to this change":

- In the PR comment give the case name (file:line), the raw error, and the same case's result on base (CI link or rerun record). If you don't have it, write "not compared against base".
- If you reran, say whether it was the full run or failed jobs only, who decided, and the result. Never write just "unrelated", "flaky" or "green on rerun" in `status.md` or reports.
- Second time the same case or batch fails: search Linear first; add a comment counting the occurrence if a ticket exists, otherwise open one. Don't repeat "unrelated, rerun".

## English version (paste ends here)
