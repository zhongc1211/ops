# deepvision-site：AGENTS.md 加测试规矩（Zack 15:23）
在仓库根目录 AGENTS.md（没有就新建）加入下面这段，原样：

## Testing
- e2e 必须诚实：真实环境、真实用户流程，不 mock、不跳步骤、不放宽断言、不挑重跑结果，失败照实报告并附证据。
- NEVER write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. Use them to verify complex features work. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.

只改这个文档，基于 origin/staging 开分支，开 PR 到 staging（不合并）。纯文档改动，PR 描述注明无代码改动、无需 e2e。
完成后发 done webhook（source ~/.config/grokbot/webhooks/deepvision-ops.env），note 里写 PR 链接。
