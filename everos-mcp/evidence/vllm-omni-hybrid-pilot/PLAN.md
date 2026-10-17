# vllm-omni hybrid pilot — plan (20:07 SGT; updated 20:12: live start is gated on a separate go-signal from the parent, NOT 22:45; nothing live touched, no EverOS calls)
Approval: Zack 20:04 via Coding助手. Scope: only ~/.local/bin/everos-mcp-vllm-omni on box + iMac. No template/env/pi extension/other launchers.

## Feasible in the launcher alone
everos-mcp 0.1.1 `EverOSClient.search(query, *, top_k, method, include_profile, agent)` builds the payload itself; both tools go through it
(recall_agent_experience → agent=True, search_memory → agent=False). The v2.1 wrapper already monkeypatches it. The draft replaces the
patch with a full `search` that sends method=$EVEROS_MCP_SEARCH_METHOD (default now hybrid) and adds `enable_llm_rerank: true` only when
agent=True; logs one line per search to ~/.local/state/everos-mcp/search.log (track, method, rerank flag, outcome, ms; no key/headers).
Server facts (embedding-enable/RUN-20261017.md step 6): agent hybrid without rerank → 422 PROVIDER_NOT_CONFIGURED; with enable_llm_rerank 200 (~3.6–5s); user hybrid 200, no rerank.
Offline payload test (httpx MockTransport, no network): offline-payload-test.txt.
Drafts (two variants; only the default of EVEROS_MCP_AGENT_RERANK and one comment line differ):
- **A** `everos-mcp-vllm-omni.hybrid-draft-A` raw sha 85cecc4b64e26fd5dda8437557ae5955796831fbae491e0f811f723829db0899 — use if server `/health` capabilities.rerank=true (eggbot's qwen3-rerank wired): recall = hybrid WITHOUT enable_llm_rerank.
- **B** `everos-mcp-vllm-omni.hybrid-draft-B` raw sha 5d0ce2d0a0419343556e0293739a489f32b54882c9a753ecad012fa5520ac320 — otherwise: recall = hybrid + enable_llm_rerank=true.
- search_memory = hybrid, no rerank, in both. Diffs vs v2.1 (raw 7b28f7e9…): hybrid-draft-A.diff, hybrid-draft-B.diff. Offline payload test for both: offline-payload-test.txt.
- Normalized (§3.3) sha will no longer be f543542d for vllm-omni: expected for a pilot, G1 to record it as the documented pilot exception.

## After the go-signal
1. tailnet /health (no key, Host header) on box and iMac; read capabilities.rerank → pick A (true) or B (false); with A also check agent hybrid without rerank flag returns 200 via xcheck_hybrid.py `agent 0` before installing. Not 200 → retry every 5 min for up to 1 h, else stop = blocked.
2. Each machine: cp -p launcher → everos-mcp-vllm-omni.bak-v21-pre-hybrid; sha before; install the chosen draft (iMac: already staged in ~/agent-tools/everos-hybrid-pilot/, check sha); chmod 755; bash -n (iMac /bin/bash 3.2); sha after.
3. Claude cell (haiku, bypassPermissions, Bash/Edit/... disallowed, --no-session-persistence, stream-json) in a vllm-omni worktree with prompt.txt (recall NCCL + search_memory NCCL);
   control same prompt in a deepvision-ads worktree (dv-ads launcher, unchanged).
4. Evidence: session.jsonl, search.log lines (method/rerank/ms), endpoint.log, xcheck (API hybrid+rerank, same scope), mount.
5. Pass: recall returns secure-h100-nccl-nvls-and-pod-loss (= coding-vllm-omni_… via xcheck); search.log shows agent hybrid with the variant's rerank flag (A false / B true) and user hybrid rerank=false outcome=ok; control has no vllm ids.
   Fail → restore .bak-v21-pre-hybrid, sha check, report.
6. §11.5 token check = 0.
