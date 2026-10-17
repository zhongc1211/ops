# EverOS MCP launcher v2.1 — evidence (box, 2026-10-17 17:04–17:11 SGT, eggbot)

Template: `/workspace/ops/everos-lessons-plan/templates/everos-mcp-launcher-v2.1.sh` (+ `CHANGELOG.md`).
Canonical normalized sha (`sed 's/^N=.*/N=@/' | shasum -a 256`, as in §3.3): `f543542db2cd6d5fcdaf33e6688700e4c91e19d01d42f144a475f5f601b39ce6`.
Render under test: `/tmp/v21/everos-mcp-xinyue` (N=xinyue). Live launchers on box and iMac were not touched; xinyue.env not changed
(temp HOMEs under /tmp/v21 got copies, mode 600). No writes to EverOS (search/list only; /health).

| File | What | Result |
|---|---|---|
| host-routing-box.txt | authenticated read-only search on ops/everos-smoke via 100.64.0.5 with Host 100.64.0.5 / everos.deepvision.sg / random.invalid; nginx -T listen lines | all 200 + same 3 episodes → tailnet block picked by local address; default_server would be 444 |
| t1-tailnet.txt | stdio initialize + tools/list + search_memory, real env | PASS: 3 read-only tools, results, endpoint=tailnet url=http://100.64.0.5 health=200 |
| t2-host-header-on-wire.txt | same via a test-only logging proxy on 100.64.0.6:18080 → 100.64.0.5 | PASS: probe and MCP POST both sent Host=everos.deepvision.sg |
| t3-t7-fallback-and-guards.txt | T3 tailnet down (100.64.0.99, blackholed): PASS public after 3s probe, search OK (4.1s total). T4 refused: PASS public (0.9s). T5 tailnet answers 503: stays tailnet (by design, not a connection failure). T6 non-tailnet EVEROS_TAILNET_URL: exit 1. T7 caller-exported EVEROS_TAILNET_URL ignored | as listed |
| t8-imac-bash32.txt | iMac /bin/bash 3.2.57 `-n`, same normalized sha, regex + awk under macOS | PASS (full stdio run on iMac not done) |
| vllm-omni-diff-summary.md, vllm-omni-vs-v2.1.diff | box vllm-omni launcher vs v2.1 (and live xinyue vs v2.1) | pre-v2 launcher; see summary |
| tools-logproxy.py | the test-only proxy used in T2 (logs no auth values) | — |
