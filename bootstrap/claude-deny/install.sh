#!/usr/bin/env bash
# PER-89: merge bootstrap/claude-deny/settings-fragment.json into Claude Code settings. Idempotent.
#   install.sh [--settings-file F] [--hooks-dir D] --dry-run --out O    write the merged result to O only, print its sha256
#   install.sh [--settings-file F] [--hooks-dir D] --apply              install the hook script, back up F, write F atomically
#   install.sh [--settings-file F] [--hooks-dir D] --check              compare only; exit 1 and list what is missing
#   install.sh [--settings-file F] [--hooks-dir D] --uninstall [--dry-run --out O]
# Only touches permissions.deny, hooks.UserPromptExpansion and hooks.UserPromptSubmit entries that belong to this feature.
# Before writing a settings file it is copied to <file>.bak-<YYYYmmddHHMMSS>; no change = no write, no backup;
# a failed backup exits non-zero without writing. The hook timeout comes only from ./hook-timeout.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
settings="$HOME/.claude/settings.json"
hooks_dir="$HOME/.claude/hooks"
mode="" dry=0 out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --settings-file) settings="$2"; shift 2 ;;
    --hooks-dir) hooks_dir="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --out) out="$2"; shift 2 ;;
    --apply|--check|--uninstall) mode="${1#--}"; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ "$dry" = 1 ] && [ -z "$mode" ] && mode=apply
[ -n "$mode" ] || { echo "need one of --dry-run --out O, --apply, --check, --uninstall" >&2; exit 64; }
if [ "$dry" = 1 ]; then
  [ -n "$out" ] || { echo "--dry-run needs --out <file>" >&2; exit 64; }
  [ "$mode" != check ] || { echo "--check does not take --dry-run" >&2; exit 64; }
fi
[ -f "$settings" ] || { echo "settings file not found: $settings" >&2; exit 66; }
guard_src="$here/hooks/disabled-cmd-prompt-guard.sh"
guard_dst="$hooks_dir/disabled-cmd-prompt-guard.sh"
hook_timeout=$(tr -d ' \n' < "$here/hook-timeout")
case "$hook_timeout" in ''|*[!0-9]*) echo "bad hook-timeout: '$hook_timeout'" >&2; exit 65 ;; esac

# Merge logic. argv: settings fragment mode(apply|uninstall|check) target hooks_dir hook_timeout backup(0|1)
merge_py=$(cat <<'PY'
import json, os, shutil, sys, tempfile, time
settings, fragment, mode, target, hooks_dir, timeout, backup = sys.argv[1:8]
raw = open(settings).read()
d = json.loads(raw)
frag = json.load(open(fragment))
NEW_SCRIPT = "disabled-cmd-prompt-guard.sh"
OLD_SCRIPT = "block-disabled-skills.sh"
MARK = "Blocked (PER-89)"
deny_new = frag["permissions"]["deny"]
upe_new = frag["hooks"]["UserPromptExpansion"][0]
ups_new = frag["hooks"]["UserPromptSubmit"][0]["hooks"][0]
upe_new["hooks"][0]["timeout"] = ups_new["timeout"] = int(timeout)

def ours_upe(e):
    return any(MARK in h.get("command", "") for h in e.get("hooks", []))

def merged(d):
    d = json.loads(json.dumps(d))
    deny = d.setdefault("permissions", {}).setdefault("deny", [])
    for r in deny_new:
        if r not in deny:
            deny.append(r)
    hooks = d.setdefault("hooks", {})
    upe = hooks.setdefault("UserPromptExpansion", [])
    idx = [i for i, e in enumerate(upe) if ours_upe(e)]
    if idx:
        upe[idx[0]] = upe_new
        for i in reversed(idx[1:]):
            del upe[i]
    else:
        upe.append(upe_new)
    ups = hooks.setdefault("UserPromptSubmit", [])
    placed = False
    for e in ups:
        hs = []
        for h in e.get("hooks", []):
            c = h.get("command", "")
            if NEW_SCRIPT in c or OLD_SCRIPT in c:
                if not placed:
                    hs.append(ups_new)
                    placed = True
            else:
                hs.append(h)
        e["hooks"] = hs
    hooks["UserPromptSubmit"] = [e for e in ups if e.get("hooks")]
    if not placed:
        hooks["UserPromptSubmit"].append({"hooks": [ups_new]})
    return d

def unmerged(d):
    d = json.loads(json.dumps(d))
    perms = d.get("permissions", {})
    if "deny" in perms:
        perms["deny"] = [r for r in perms["deny"] if r not in deny_new]
    hooks = d.get("hooks", {})
    if "UserPromptExpansion" in hooks:
        hooks["UserPromptExpansion"] = [e for e in hooks["UserPromptExpansion"] if not ours_upe(e)]
        if not hooks["UserPromptExpansion"]:
            del hooks["UserPromptExpansion"]
    if "UserPromptSubmit" in hooks:
        for e in hooks["UserPromptSubmit"]:
            hs = []
            for h in e.get("hooks", []):
                if NEW_SCRIPT not in h.get("command", ""):
                    hs.append(h)
            e["hooks"] = hs
        hooks["UserPromptSubmit"] = [e for e in hooks["UserPromptSubmit"] if e.get("hooks")]
        if not hooks["UserPromptSubmit"]:
            del hooks["UserPromptSubmit"]
    return d

def dump(d):
    return json.dumps(d, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else "")

if mode == "check":
    want = merged(d)
    missing = []
    deny = d.get("permissions", {}).get("deny", [])
    missing += ["permissions.deny: " + r for r in deny_new if r not in deny]
    upe = d.get("hooks", {}).get("UserPromptExpansion", [])
    if upe_new not in upe:
        missing.append("hooks.UserPromptExpansion: PER-89 entry missing or different")
    ups_hooks = [h for e in d.get("hooks", {}).get("UserPromptSubmit", []) for h in e.get("hooks", [])]
    if ups_new not in ups_hooks:
        missing.append("hooks.UserPromptSubmit: " + NEW_SCRIPT + " entry missing or different")
    if any(OLD_SCRIPT in h.get("command", "") for h in ups_hooks):
        missing.append("hooks.UserPromptSubmit: old " + OLD_SCRIPT + " entry still present")
    if want != d and not missing:
        missing.append("settings differ from merged result (duplicate PER-89 entries?)")
    for m in missing:
        print("missing: " + m)
    sys.exit(1 if missing else 0)

new = merged(d) if mode == "apply" else unmerged(d)
text = dump(new)
if os.path.abspath(target) == os.path.abspath(settings) and text == raw:
    print("no change: " + settings)
    sys.exit(0)
if backup == "1":
    bak = settings + ".bak-" + time.strftime("%Y%m%d%H%M%S")
    try:
        shutil.copy2(settings, bak)
    except OSError as e:
        sys.exit("backup failed, settings not written: %s" % e)
    print("backup: " + bak)
dirn = os.path.dirname(os.path.abspath(target))
fd, tmp = tempfile.mkstemp(dir=dirn, prefix=".per89-")
with os.fdopen(fd, "w") as f:
    f.write(text)
if os.path.exists(target):
    os.chmod(tmp, os.stat(target).st_mode & 0o7777)
else:
    os.chmod(tmp, os.stat(settings).st_mode & 0o7777)
os.replace(tmp, target)
print("wrote: " + target)
PY
)

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

if [ "$mode" = check ]; then
  rc=0
  python3 -c "$merge_py" "$settings" "$here/settings-fragment.json" check "$settings" "$hooks_dir" "$hook_timeout" 0 || rc=$?
  if [ ! -f "$guard_dst" ]; then echo "missing: hook script $guard_dst"; rc=1
  elif ! cmp -s "$guard_src" "$guard_dst"; then echo "differs: hook script $guard_dst"; rc=1; fi
  [ "$rc" != 0 ] || echo "ok: $settings matches the PER-89 fragment"
  exit "$rc"
fi

before=$(sha "$settings")
if [ "$dry" = 1 ]; then
  python3 -c "$merge_py" "$settings" "$here/settings-fragment.json" "$mode" "$out" "$hooks_dir" "$hook_timeout" 0
  echo "sha256 source: $before  $settings"
  echo "sha256 out:    $(sha "$out")  $out"
  exit 0
fi

if [ "$mode" = apply ]; then
  mkdir -p "$hooks_dir"
  install -m 755 "$guard_src" "$guard_dst"
  echo "hook script: $guard_dst"
fi
python3 -c "$merge_py" "$settings" "$here/settings-fragment.json" "$mode" "$settings" "$hooks_dir" "$hook_timeout" 1
if [ "$mode" = uninstall ] && [ -f "$guard_dst" ]; then
  rm -f "$guard_dst"
  echo "removed: $guard_dst"
fi
echo "sha256 before: $before"
echo "sha256 after:  $(sha "$settings")"
