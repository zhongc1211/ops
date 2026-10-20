# PER-106 密钥扫描

## 进仓前（ops 系统，box，抄自 box `/workspace/ops/tmp/git-sot-1020/SCAN.md`）

- 范围：暂存树 16 个文件（清单和 sha256 见 stage-sha256.txt）。
- gitleaks 8.30.1 `gitleaks dir stage --redact`：0 条。
- 正则（bearer、KEY=/token=/secret= 赋值、带 key 的 URL、webhook URL、已知前缀 sk-/ghp_/github_pat_/xox*/AKIA/lin_api_/tskey-/hskey-/AIza、配对码、私钥头、JWT）：0 条。
- 长串（≥40 字符）38 处，逐条归类全是文件路径或 x.com 帖子 URL，无密钥。
- URL 只有公开站点；1 处 tailnet IP（dev-bot-rules 原文，不是密钥）。
- 剔除/打码：无。

## PR 上复扫（PER-106 工作区的 Claude Code，iMac，2026-10-20 20:46 SGT）

gitleaks 8.30.1（iMac 本机 `/usr/local/bin/gitleaks`），仓库里没有自定义 `.gitleaks.toml`，用默认规则。

| 命令 | 范围 | 结果 |
|---|---|---|
| `gitleaks git --redact --log-opts="origin/main..dd5da74ea0a75e3f3a2465e69b6e21c11f60907b" .` | 本 PR 的 4 个提交（数据、脚本、测试、SYNC.md），约 149 KB | 0 条 |
| `gitleaks dir --redact <git archive dd5da74 的本 PR 文件>` | 本 PR 新增或改动的 20 个文件（16 个数据文件 + SYNC.md、targets.tsv、sync-bot-rules、测试），约 152 KB | 0 条 |

之后这个 PR 只再加了本目录的两份报告（干跑表和本文件），内容是 sha256、路径和命令输出。PR 最后的 head 上又跑了一次，结果写在 PR 评论里。
