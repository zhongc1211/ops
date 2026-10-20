#!/usr/bin/env bash
# PER-89 installer checks on a copy of a real settings.json (the source file is only read).
#   tests/install-sandbox.sh --live <settings.json to copy> --out <evidence dir>
# Checks: dry-run = apply result; second apply writes nothing and makes no backup; first apply leaves a
# .bak-<YYYYmmddHHMMSS> equal to the original; --check 0 after apply, 1 before; uninstall removes every PER-89
# item and copying the .bak back restores the original bytes; failed backup = no write, non-zero exit; changing ./hook-timeout moves both hooks' timeout and --check
# follows it, and a hard-coded timeout in the fragment makes that check fail (regression).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
live="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --live) live="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$live" ] && [ -n "$out" ] || { sed -n '2,2p' "$0"; exit 64; }
mkdir -p "$out"; out=$(cd "$out" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/per89-inst.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); r=ok; else fail=$((fail+1)); r=FAIL; fi
  printf '%s\t%s\texpect=%s\tgot=%s\n' "$r" "$1" "$2" "$3" | tee -a "$out/install-sandbox.tsv"
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
timeouts() { python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); h=d["hooks"]
a=[x.get("timeout") for e in h.get("UserPromptExpansion",[]) for x in e["hooks"] if "PER-89" in x["command"]]
b=[x.get("timeout") for e in h.get("UserPromptSubmit",[]) for x in e["hooks"] if "disabled-cmd-prompt-guard" in x["command"]]
print(a,b)' "$1"; }
: > "$out/install-sandbox.tsv"
echo "live sha256 before: $(sha "$live")" | tee "$out/install-sandbox.log"

# 1. dry-run, apply, idempotent apply, backup
S=$T/home/.claude; mkdir -p "$S/hooks"
cp "$live" "$S/settings.json"; orig=$(sha "$S/settings.json")
inst() { bash "$here/install.sh" --settings-file "$S/settings.json" --hooks-dir "$S/hooks" "$@" >> "$out/install-sandbox.log" 2>&1; }
inst --check; check "check before apply exits 1" 1 $?
inst --dry-run --out "$T/dry.json"; check "dry-run leaves source untouched" "$orig" "$(sha "$S/settings.json")"
inst --apply; check "apply exits 0" 0 $?
check "apply result = dry-run result" "$(sha "$T/dry.json")" "$(sha "$S/settings.json")"
baks=$(ls "$S"/settings.json.bak-* 2>/dev/null | wc -l | tr -d ' ')
check "first apply makes one backup" 1 "$baks"
b=$(ls "$S"/settings.json.bak-* 2>/dev/null | head -1)
check "backup name is .bak-YYYYmmddHHMMSS" yes "$( [[ ${b##*.bak-} =~ ^[0-9]{14}$ ]] && echo yes || echo no)"
check "backup equals original" "$orig" "$(sha "$b")"
check "hook script installed 755" "-rwxr-xr-x" "$(ls -l "$S/hooks/disabled-cmd-prompt-guard.sh" | cut -c1-10)"
after=$(sha "$S/settings.json"); sleep 1
inst --apply
check "second apply leaves file unchanged" "$after" "$(sha "$S/settings.json")"
check "second apply makes no new backup" 1 "$(ls "$S"/settings.json.bak-* | wc -l | tr -d ' ')"
inst --check; check "check after apply exits 0" 0 $?
check "timeouts come from hook-timeout ($(cat "$here/hook-timeout"))" "[$(cat "$here/hook-timeout")] [$(cat "$here/hook-timeout")]" "$(timeouts "$S/settings.json")"

# 2. uninstall removes every PER-89 item; full rollback = copy the .bak back
sleep 1; inst --uninstall
check "uninstall leaves no PER-89 items" 0 "$(grep -c -E 'Skill\(skill:|PER-89|disabled-cmd-prompt-guard' "$S/settings.json")"
check "uninstall removes hook script" no "$([ -e "$S/hooks/disabled-cmd-prompt-guard.sh" ] && echo yes || echo no)"
cp -p "$b" "$S/settings.json"
check "rollback from .bak restores original sha256" "$orig" "$(sha "$S/settings.json")"

# 3. failed backup: read-only directory -> non-zero, file unchanged
R=$T/ro; mkdir -p "$R/hooks"; cp "$live" "$R/settings.json"; chmod 555 "$R"
bash "$here/install.sh" --settings-file "$R/settings.json" --hooks-dir "$R/hooks" --apply >> "$out/install-sandbox.log" 2>&1
rc=$?; chmod 755 "$R"
check "backup failure exits non-zero" yes "$([ $rc != 0 ] && echo yes || echo no)"
check "backup failure leaves settings unchanged" "$(sha "$live")" "$(sha "$R/settings.json")"

# 4. single timeout source: copy the bundle, change hook-timeout to 7
C=$T/bundle; cp -R "$here" "$C"; echo 7 > "$C/hook-timeout"
H=$T/h7/.claude; mkdir -p "$H/hooks"; cp "$live" "$H/settings.json"
bash "$C/install.sh" --settings-file "$H/settings.json" --hooks-dir "$H/hooks" --apply >> "$out/install-sandbox.log" 2>&1
check "hook-timeout=7 -> both hooks 7" "[7] [7]" "$(timeouts "$H/settings.json")"
bash "$C/install.sh" --settings-file "$H/settings.json" --hooks-dir "$H/hooks" --check >> "$out/install-sandbox.log" 2>&1
check "check passes with hook-timeout=7" 0 $?
bash "$here/install.sh" --settings-file "$H/settings.json" --hooks-dir "$H/hooks" --check >> "$out/install-sandbox.log" 2>&1
check "check with hook-timeout=5 flags settings written with 7" 1 $?
# regression: an installer that hard-codes the timeout (fragment literal 5, constant ignored) must fail the
# "hook-timeout=7 -> both hooks 7" expectation above
B=$T/broken; cp -R "$here" "$B"; echo 7 > "$B/hook-timeout"
python3 - "$B" <<'PY'
import json, sys
B = sys.argv[1]
f = B + "/settings-fragment.json"; d = json.load(open(f))
d["hooks"]["UserPromptExpansion"][0]["hooks"][0]["timeout"] = 5
d["hooks"]["UserPromptSubmit"][0]["hooks"][0]["timeout"] = 5
json.dump(d, open(f, "w"), indent=2)
i = B + "/install.sh"; s = open(i).read()
s = s.replace('upe_new["hooks"][0]["timeout"] = ups_new["timeout"] = int(timeout)', 'pass')
open(i, "w").write(s)
PY
H2=$T/hb/.claude; mkdir -p "$H2/hooks"; cp "$live" "$H2/settings.json"
bash "$B/install.sh" --settings-file "$H2/settings.json" --hooks-dir "$H2/hooks" --apply >> "$out/install-sandbox.log" 2>&1
got=$(timeouts "$H2/settings.json")
check "regression: hard-coded installer does not follow hook-timeout=7" "[5] [5]" "$got"
check "regression detected (would fail 'both hooks 7')" yes "$([ "$got" != "[7] [7]" ] && echo yes || echo no)"

echo "live sha256 after:  $(sha "$live")" | tee -a "$out/install-sandbox.log"
echo "install-sandbox: $pass ok, $fail failed" | tee -a "$out/install-sandbox.log"
[ "$fail" = 0 ]
