#!/usr/bin/env bash
# Install the UserPromptSubmit hook that blocks human-typed disabled commands. Idempotent.
set -euo pipefail
SRC="${1:-$(dirname "$0")/block-disabled-skills.sh}"
mkdir -p "$HOME/.claude/hooks"
install -m 755 "$SRC" "$HOME/.claude/hooks/block-disabled-skills.sh"
python3 - <<'PY'
import json,os
f=os.path.expanduser("~/.claude/settings.json"); d=json.load(open(f))
cmd='bash "$HOME/.claude/hooks/block-disabled-skills.sh"'
ups=d.setdefault("hooks",{}).setdefault("UserPromptSubmit",[])
if not any(h.get("command")==cmd for e in ups for h in e.get("hooks",[])):
    ups.append({"hooks":[{"type":"command","command":cmd,"timeout":5}]})
json.dump(d,open(f+".tmp","w"),indent=2,ensure_ascii=False); os.replace(f+".tmp",f)
print("hook entry ok")
PY
