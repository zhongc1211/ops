# 没挂 Linear 的工作区审查：per-8714-schedule-400

审查人：Claude（Opus 5.5，iMac 终端里的 PER-139 会话），只读查看，2026-10-21 09:37 SGT。

PATH: /Users/jiawenwang/orca/workspaces/repository/per-8714-schedule-400
HEAD: c92d061c06ed8b59189b07c28bf394644050f959
VERDICT: KEEP

| 项 | 内容 |
|---|---|
| 仓库 | vllm-omni · H3/C1 |
| 工作区路径 | `/Users/jiawenwang/orca/workspaces/repository/per-8714-schedule-400`（目录在） |
| 分支 | zhongc1211/per-8714-schedule-400 |
| HEAD | `c92d061c06ed8b59189b07c28bf394644050f959` |
| 远端哪里有这个 sha | 只在本地跟踪引用 fork/diffusion-attention-schedule-config 上，那是 10-17 抓下来的旧值。上游 PR #8714 OPEN，它现在的 head 0b35e03 和这个 sha 分叉（GitHub compare：领先 38、落后 2），这个 sha 不在 PR 现在的历史里。 |
| 未推送的提交 | 0 个（这是相对本地的远端跟踪引用算的；那个引用已过时，GitHub 上的分支已改写，见上一行） |
| 未跟踪 / 被忽略的文件 | 未提交改动 0 项，未跟踪文件 0 个。被忽略的 172 项，按顶层目录：.pytest_cache/、.ruff_cache/（4 项）、analysis/、tests/（10 项）、vllm_omni.egg-info/、vllm_omni/（155 项）。 |
| 最后活动 | 2026-10-17 16:02（Orca 记录），Orca 状态 completed |

## 做的是什么

vllm-omni 上游 PR #8714（[Core][Diffusion] Step attention schedules on MiniMax-H3）里的 schedule 400 修复：格式不对的 attention schedule 在 stage 进程里也按客户端错误返回。analysis/ 下有 8714-SCHEDULE-400.md、8714-REPLY-FINAL.md、证据目录、gpu-l4 / l4pack 和两个 tgz。

## 结论

不能删。上游 PR #8714 还开着（10-20 还有更新），而且已经 rebase 过：它现在的 head 0b35e03 和这里的 HEAD c92d061 是分叉的（GitHub compare：领先 38、落后 2），c92d061 不在 PR 现在的历史里。本地的 fork/diffusion-attention-schedule-config 跟踪引用是 10-17 的旧值，GitHub 上的这个分支已经被改写了。analysis/ 里约 756 KB 的分析、回复稿和 GPU 证据不在 git 里。脚本的 W9 没认出这个 PR，因为 PR 是从 fork 的另一个分支名开的。等 #8714 合并或关闭、analysis/ 另存之后再审。
