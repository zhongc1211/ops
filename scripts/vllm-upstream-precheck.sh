#!/bin/bash
# vllm-omni upstream watch precheck. Exit 0 = something changed (agent runs), 1 = unchanged, 2 = gh failed.
# Linux/macOS portable: uses sha1sum, falling back to shasum.
D=$HOME/.orca-state/vllm-upstream; mkdir -p "$D"
H=sha1sum; command -v sha1sum >/dev/null || H=shasum
O=$(for p in 8713 8714 8715 8716 8718 8746; do gh pr view $p -R vllm-project/vllm-omni --json comments,reviews,statusCheckRollup,headRefOid || exit 2; done; gh issue view 8686 -R vllm-project/vllm-omni --json comments || exit 2) || exit 2
N=$(printf %s "$O" | $H | cut -c1-40)
[ "$(cat "$D/seen.sha" 2>/dev/null)" != "$N" ] && echo "$N" > "$D/pending.sha" && exit 0
exit 1
