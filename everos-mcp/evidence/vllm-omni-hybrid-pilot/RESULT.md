# vllm-omni EverOS hybrid 试点（v2 §12 第 2 步）— 变体 A — 通过

- 时间：2026-10-17 20:20–20:25 SGT。批准：Zack 20:04（经 Coding助手）；开工信号 20:20（eggbot：rerank:true，向量已补，20:18 起健康）。依据：`../../../../everos-incidents/rerank-forwarder/README.md`。
- 范围：只换了两台的 `~/.local/bin/everos-mcp-vllm-omni`。env 文件、模板、pi 扩展、其他项目脚本都没动（install.txt 里有其他 3 份的 raw sha，前后一致）。
- 变体 A：recall_agent_experience = `method=hybrid`，**不带** `enable_llm_rerank`（服务端自己 rerank：qwen3-rerank 经 loopback 转发）；search_memory = `method=hybrid`，不带 rerank。

## 开工前检查（两台，tailnet）
| 检查 | box | iMac |
|---|---|---|
| /health | 200，`rerank:true`，embed:true，disabled 只剩 multimodal_upload | 200，`rerank:true` |
| agent hybrid 不带 rerank（vllm NCCL） | **200**，688 ms，[coding-vllm-omni_secure-h100-nccl-nvls-and-pod-loss]（19:32 是 422） | 200，419 ms，同上 |
| user hybrid（vllm NCCL） | 200，514 ms，0 条 | 200，226 ms，0 条 |
| 对照 agent hybrid（dv-ads NCCL） | 200，521 ms，0 条 | 200，985 ms，0 条 |
文件：`box/precheck-*`、`imac/precheck-*`。

## 启动脚本 sha
| 机器 | 之前 raw（v2.1） | 备份 `.bak-v21-pre-hybrid` raw | 之后 raw（草稿 A） | 之后规范化（N=@） | 语法 |
|---|---|---|---|---|---|
| box | 7b28f7e916f1362990359c230ff4129445a690b8fc07292a3306fb36b6db4430 | 7b28f7e9…6db4430（cmp 一致） | 85cecc4b64e26fd5dda8437557ae5955796831fbae491e0f811f723829db0899 | acf10e598199b59bc6b7a7ad6baed6c95d8354f1c9a94e5863d31f3dc3ab05f7 | bash -n ok |
| iMac | 7b28f7e9…6db4430 | 7b28f7e9…6db4430（cmp 一致） | 85cecc4b…29db0899 | acf10e59…3ab05f7 | /bin/bash 3.2 -n ok |

**G1 试点例外**：vllm-omni 这份的规范化 sha 现在是 `acf10e59…`，不是 v2.1 的 `f543542d…`。这是 §12 第 2 步的单项目试点，是有意的，G1 按「已记录的试点例外」判，不算失败。其他 3 份仍是 f543542d。试点转正时要出新模板（§12 第 3 步：8 份一起换，得到新规范 sha）；回滚：`install -m 755 ~/.local/bin/everos-mcp-vllm-omni.bak-v21-pre-hybrid ~/.local/bin/everos-mcp-vllm-omni`。

## Claude 格（haiku，claude 2.1.302，--no-session-persistence；提示 prompt.txt：recall NCCL + search_memory NCCL 各一次）
| 格 | worktree | 结果 | 每次调用耗时（search.log，MCP 进程内测） |
|---|---|---|---|
| box · vllm | ~/orca/workspaces/vllm-omni/PER-7-review-导入挪顶部 @5a93ec1b | **通过**：3 个只读工具；recall → `secure-h100-nccl-nvls-and-pod-loss`；search_memory → 无结果 | recall 1080 ms；search_memory 360 ms |
| iMac · vllm | ~/orca/workspaces/repository/per-8714-schedule-400 @c92d061c | **通过**：同上 | 第一次：recall 346 ms、search_memory 207 ms；复跑：recall 720 ms、search_memory 131 ms |
| box · 对照 dv-ads | ~/orca/workspaces/deepvision-ads/dv广告-FDV-36-栈修复 @8fc579b9 | **通过**：recall 和 search 都 0 条，没有 vllm id | （dv-ads 脚本 v2.1，没改，不写 search.log） |
| iMac · 对照 dv-ads | ~/orca/workspaces/deepvision-ads/dvads-everos-v21-imac @5b1e3e48 | **通过**：0 条，没有 vllm id | 同上 |
- iMac 第一次的 init 事件里 everos 还是 `pending`（MCP 进程启动慢于会话 init），模型用 ToolSearch 找到恰好 3 个 everos 工具（recall、search_memory、list_memories）再调用，结果正确。为拿到干净的 init 证据复跑了一次：init `connected`，3 个工具，只有 2 次调用，结果相同（imac/session-rerun.jsonl）。
- 每格整段会话墙钟：box 12 s / 对照 13 s；iMac 19 s / 对照 15 s / 复跑 16 s。

## 请求参数证据（launcher 写的 `~/.local/state/everos-mcp/search.log`，不含 key/请求头）
```
box  2026-10-17T20:22:02+0800 everos-mcp-vllm-omni search track=agent method=hybrid enable_llm_rerank=false top_k=-1 outcome=ok ms=1080 agent_skills=1 agent_cases=0 episodes=0
box  2026-10-17T20:22:03+0800 everos-mcp-vllm-omni search track=user method=hybrid enable_llm_rerank=false top_k=-1 outcome=ok ms=360 agent_skills=0 agent_cases=0 episodes=0
iMac 2026-10-17T20:22:48+0800 everos-mcp-vllm-omni search track=user method=hybrid enable_llm_rerank=false top_k=-1 outcome=ok ms=207 ...
iMac 2026-10-17T20:22:48+0800 everos-mcp-vllm-omni search track=agent method=hybrid enable_llm_rerank=false top_k=-1 outcome=ok ms=346 agent_skills=1 ...
iMac 2026-10-17T20:23:47+0800 ... track=agent method=hybrid enable_llm_rerank=false ... ms=720 agent_skills=1 / 20:23:49 track=user ... ms=131
```
`enable_llm_rerank=false` 表示请求体里**没有**这个字段（只有变体 B 才加，见 offline-payload-test.txt 的请求体原样）。endpoint.log：两台都是 `endpoint=tailnet url=http://100.64.0.5 health=200`（box/endpoint.txt、imac/endpoint.txt）。

## API 交叉核对（xcheck_hybrid.py，公网 URL，同 scope、同请求体）
box：agent 200 651 ms [coding-vllm-omni_secure-h100-nccl-nvls-and-pod-loss]；user 200 525 ms 0 条；对照 agent 200 492 ms 0 条，对照 user 200 482 ms 0 条。
iMac：agent 200 3078 ms（同一 id）；user 200 514 ms；对照 agent 200 1074 ms 0 条；对照 user 200 270 ms 0 条。和会话结果一致。

## atomic facts
看不到：vllm-omni 的 user 线没有任何 episode（hybrid 和 keyword 都是 0 条），所以 search_memory 返回空。1.4.2 hybrid 响应的 data 键是 episodes、profiles、agent_cases、agent_skills、unprocessed_messages，没有单独的 atomic_facts 列表（data_counts 见各 xcheck-*.json）。要验证 atomic facts 需要一个有 user episode 的 scope，不在本次范围。

## 回滚
没回滚（全部通过）。备份在两台原地：`~/.local/bin/everos-mcp-vllm-omni.bak-v21-pre-hybrid`（raw 7b28f7e9…）。

## token 检查（§11.5）
见末行。
- token: hybrid-pilot = 0（50 个文件）；mcp-evidence 全部 = 0；search.log/endpoint.log(box) = 0
