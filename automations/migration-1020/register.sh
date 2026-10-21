#!/bin/bash
# register.sh mba|imac [--apply]: turn defs.json into orca automations commands for one machine (PER-79).
# Default is a dry-run: prints the commands and calls nothing. Every create carries --disabled and
# --missed-run-grace-minutes 120; enabling, disabling the old box tasks and deleting stay manual (README §上线顺序).
# --apply runs them through `orca` on this machine; it needs Zack's approval first (BRIEF: creating or editing
# automations is his call) and refuses to run on a machine other than the one named.
# box is not a target since B2a (PER-146): the plan creates no box task and changes no box task's definition;
# the rollout cards disable the old box tasks being replaced: disable only, never delete (README §上线顺序).
set -u
here=$(cd "$(dirname "$0")" && pwd)
m=${1:-}; apply=no; [ "${2:-}" = --apply ] && apply=yes
case "$m" in mba|imac) ;;
  box) echo "register.sh: box is not a target any more (B2a: no new task runs on box; box's own tasks are Zack's call, README §待 Zack 决定)" >&2; exit 2;;
  *) echo "usage: register.sh mba|imac [--apply]" >&2; exit 2;; esac
if [ $apply = yes ]; then
  h=$(hostname -s | tr 'A-Z' 'a-z')
  case "$m:$h" in mba:mba|imac:imac*) ;; *) echo "register.sh: --apply for $m but this is $h; run it on $m" >&2; exit 2;; esac
fi
python3 -I - "$here" "$m" "$apply" <<'PY'
import json, os, shlex, subprocess, sys
here, m, apply = sys.argv[1], sys.argv[2], sys.argv[3] == "yes"
d = json.load(open(os.path.join(here, "defs.json"), encoding="utf-8"))
cmds = []
for c in d["create"]:
    if c["machine"] != m:
        continue
    ws = c["workspace"].replace("$HOME", os.environ["HOME"])
    prompt = open(os.path.join(here, c["prompt"]), encoding="utf-8").read()
    argv = ["orca", "automations", "create", "--name", c["name"], "--trigger", c["rrule"], "--timezone", c["timezone"],
            "--provider", c["provider"], f"--extra-agent-args={c['extraAgentArgs']}", "--workspace", ws,
            "--precheck", c["precheck"], "--precheck-timeout", str(c["precheckTimeout"]),
            "--missed-run-grace-minutes", str(c["grace"]), "--fresh-session", "--disabled", "--prompt", prompt]
    shown = argv[:-1] + ['"$(cat %s)"' % c["prompt"]]
    note = [f"# {c['key']}" + (f" (replaces box {c['replaces']})" if c.get("replaces") else "")]
    if c.get("before"):
        note.append("# first: " + c["before"])
    cmds.append((note, argv, " ".join(shlex.quote(a) if not a.startswith('"$(') else a for a in shown)))
for e in d["edit"]:
    if e["machine"] != m:
        continue
    s, argv = e["set"], ["orca", "automations", "edit", e["id"]]
    if "grace" in s: argv += ["--missed-run-grace-minutes", str(s["grace"])]
    if "precheck" in s: argv += ["--precheck", s["precheck"], "--precheck-timeout", str(s["precheckTimeout"])]
    if "rrule" in s: argv += ["--trigger", s["rrule"]]
    cmds.append(([f"# edit {e['id']}" + (f": {e['why']}" if e.get("why") else "")], argv, " ".join(map(shlex.quote, argv))))
print(f"# register.sh {m}: {len(cmds)} command(s), " + ("APPLY" if apply else "dry-run, nothing is called"))
rc = 0
for note, argv, shown in cmds:
    print("\n".join(note)); print(shown)
    if apply:
        r = subprocess.run(argv); rc |= r.returncode
sys.exit(rc)
PY
