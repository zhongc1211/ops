> **DRAFT — 不进 vllm-omni 仓库，也不改上游 vLLM 的 AGENTS.md / CLAUDE.md。** 用途：vllm 开发 bot 派活时，把下面代码块原样贴进派活 prompt 开头。
> 原因：上游 vLLM 的 AGENTS.md/CLAUDE.md（158 行）写「unit over integration over e2e」，与 Zack 规矩相反；vllm-omni 本身没有 AGENTS.md。iMac 与 box 全局 `~/.pi/agent/AGENTS.md` 已有测试段，这段仍然要贴（上游文件离 coding agent 更近，会盖过全局）。
> **不指定用哪种 coding agent。**

```text
【测试规矩覆盖 / Testing override — 以此为准】
本仓库（及上游 vLLM）AGENTS.md / CLAUDE.md 里 "unit over integration over e2e" 等测试偏好，本任务不适用；测试以下面为准。代码风格、目录、提交格式、DCO/sign-off 等其他上游约定照常遵守。不要修改上游的 AGENTS.md / CLAUDE.md。
The upstream "unit over integration over e2e" guidance does NOT apply to this task. Follow the rules below for testing; follow all other upstream conventions (style, layout, commit format, sign-off). Do not edit upstream AGENTS.md / CLAUDE.md.

- NEVER write unit tests after you write code. Highly prefer E2E tests as the sole testing mechanism; produce a verifiable and repeatable artifact at the end. If you must test in isolation, FIRST write all the ways it could fail, THEN write the code.
- 真实 E2E：真实模型、真实 server、真实请求；不 mock、不 stub、不跳步骤、不放宽断言、不挑重跑。上游 CI 要求的单测照常让它跑，但不算验收。
- 在本 PR 当前 head commit 上跑；head 变了就重跑。没有 E2E 结果不转 ready、不请 review。
- 要 GPU / 花钱的机器：先报预算等批准；只许一个开机流程；开机后先确认 server health 再测；测完立刻删机。
- PR 描述写：
  E2E (PR head)
  - Command: <完整命令>
  - Hardware: <GPU 型号×数量、平台/机器>
  - Commit: <PR head 完整 sha>
  - Result: <通过/失败、关键数值、失败用例名>
  - Artifact: <日志/输出路径>
  Not run: <逐项写 not run + 原因>
  Unit tests: CI covers unit tests
- 失败说成「无关」时写用例名（文件:行）、报错原文、base 上同一用例的结果；拿不出写「没对照 base」。
- 超过 15 分钟的命令用 notify-run 包：notify-run --bot vllm-omni --task "<编号> <简述>" -- <command>。做完别静默停住：最后一条消息写「结论 + 报告路径」。
- 对外文字（PR 描述、issue 评论）不披露 AI 使用。
- 不指定用哪种 coding agent；派活只写任务。
```
