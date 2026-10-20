#!/usr/bin/env bash
# Install the UserPromptSubmit hook that blocks human-typed disabled commands. Idempotent.
set -euo pipefail
SRC="${1:-$(dirname "$0")/block-disabled-skills.sh}"
mkdir -p "$HOME/.claude/hooks"
install -m 755 "$SRC" "$HOME/.claude/hooks/block-disabled-skills.sh"
python3 - <<'PY'
import json,os,sys,datetime,subprocess
f=os.path.expanduser("~/.claude/settings.json"); d=json.load(open(f)); n0=json.dumps(d)
cmd='bash "$HOME/.claude/hooks/block-disabled-skills.sh"'
# 超时 Claude Code 会放行 prompt（不挡），所以给 30 秒；已有条目也改成 30
ups=d.setdefault("hooks",{}).setdefault("UserPromptSubmit",[])
found=False
for e in ups:
    for h in e.get("hooks",[]):
        if h.get("command")==cmd: h["timeout"]=30; found=True
if not found:
    ups.append({"hooks":[{"type":"command","command":cmd,"timeout":30}]})
if json.dumps(d)!=n0:  # 内容没变就不写也不备份
    # 改前备份成 settings.json.bak-<YYYYmmddHHMMSS>；同一秒已有就不覆盖；备份失败就退出、不写
    b=f+".bak-"+datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    if not os.path.exists(b) and subprocess.run(["cp","-p",f,b]).returncode!=0: sys.exit(f"备份 {f} 失败，没改")
    with open(f+".tmp","w") as o: json.dump(d,o,indent=2,ensure_ascii=False); o.write("\n")
    os.replace(f+".tmp",f)
print("hook entry ok")
PY
