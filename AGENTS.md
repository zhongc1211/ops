# ops 仓库给 agent 的规矩

pi、codex 直接读这个文件；Claude Code 默认不读 AGENTS.md，靠根目录 `CLAUDE.md` 里的 `@AGENTS.md` 引用读到。
`wake/bin/orca-agent-launch` 起 agent 前会检查指令链里有没有下面「NEVER write unit tests」这一句，改这一段时别把它删掉。

## 测试规矩（Zack，适用于本仓库所有改动）

原文照录：

- NEVER write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.

具体做法：

- 写完代码后不补单元测试。
- 本仓库的 E2E 是：`wake/` 的真机演练（在 iMac / MBA / box 上真跑叫醒链路）、`automations/migration-1020/e2e/run-e2e.sh`、每个 PR 的 `reports/<PR 号>/rerun.sh`。
- E2E 要诚实：测真实机器和真实流程。不 mock、不 stub、不伪造接口返回、不跳步骤、不放宽断言、不挑着重跑。用了测试替身的跑法只能写成「本地替身检查」，用构造输入的写成「演练」，都不能写成 E2E。
- 失败照实报告。如果是测试本身写错了，写明原因和改了什么，保留失败那次的结果，再把整套重跑一遍。
- 结束时留下别人能复现的产物：命令、机器、commit，以及 `results.tsv`、日志的路径。

每个 PR 的 E2E：

- 每个 PR 都要在**该 PR 当前 head commit** 上跑 `reports/<PR 号>/rerun.sh`，涉及真机的再加真机只读核对。head 变了（新 push、rebase）就要重跑，旧 commit 上的结果不算。
- 没有 E2E 结果的 PR 不转 ready、不请人 review。
- 需要花钱的环境（GPU、付费账号）先报预算等批准，再开。

PR 描述 / PR 评论里的 E2E 报告，五项写全：

```
E2E（PR head）
- 命令：<完整命令，含环境变量名，不含密钥>
- 环境/硬件：<机器：iMac / MBA / box；用了沙箱 HOME 也写明>
- commit：<PR head 的完整 sha>
- 结果：<通过 N / 失败 M / 跳过 K；失败用例名>
- 产物：<results.tsv 和日志路径；别的机器写 imac:/mba:/box: 前缀>
回退测试：<把旧代码放回去，这条 E2E 确实会挂：是/否/没跑>
回滚：<回滚到哪个 commit、怎么回滚>
没跑的：<逐项写「没跑」和原因>
```

把失败说成「与本次改动无关」时：

- PR 评论写清用例名（文件:行）、报错原文，以及同一用例在 base 上的结果（重跑记录）；拿不出就写「没对照 base」。
- 重跑了要写：整轮还是只重跑失败用例、谁定的、重跑结果。`status.md` 和汇报也不能只写「无关」「偶发」「重跑全绿」。
- 同一用例或同一批失败第二次出现：先搜 Linear，有单就补评论记次数，没单就开单查；不许再照抄「无关，重跑」。
