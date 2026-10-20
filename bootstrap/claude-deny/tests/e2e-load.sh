#!/usr/bin/env bash
# PER-89 end-to-end test: real `claude -p` runs under CPU load, isolated from the live user settings.
#   tests/e2e-load.sh --live <settings.json to copy> --out <evidence dir> [--load N] [--budget USD] [--only selftest|main]
#                     [--run-timeout S] [--cases REGEX]   (--load 0 = no added load; --cases runs only matching case names)
# The live file is only copied (read). Settings for each case are generated from that copy with install.sh --dry-run.
# MCP servers are not started (--strict-mcp-config): they are unrelated to skills and hooks and dominate startup time under load.
# Load: N busy loops started by this script (perl alarm 300, so each round lasts at most 5 minutes);
# only those PIDs are killed. Needs: claude logged in (run from a GUI-session terminal on macOS), python3, perl, node.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
live="" out="" load_n=8 budget=1.00 only=all run_timeout=900 cases=.
while [ $# -gt 0 ]; do
  case "$1" in
    --live) live="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --load) load_n="$2"; shift 2 ;;
    --budget) budget="$2"; shift 2 ;;
    --only) only="$2"; shift 2 ;;
    --run-timeout) run_timeout="$2"; shift 2 ;;
    --cases) cases="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -n "$live" ] && [ -n "$out" ] || { sed -n '2,3p' "$0"; exit 64; }
mkdir -p "$out"
out=$(cd "$out" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/per89-e2e.XXXXXX")
mkdir -p "$T/proj" "$T/hooks"
cp "$here/hooks/disabled-cmd-prompt-guard.sh" "$T/hooks/"
chmod 755 "$T/hooks/disabled-cmd-prompt-guard.sh"
cp "$live" "$T/live-copy.json"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$out/run.log"; }
load1() { sysctl -n vm.loadavg | awk '{print $2}'; }
log "tmp=$T live_sha256=$(shasum -a 256 "$live" | cut -d' ' -f1) claude=$(claude --version 2>/dev/null) host=$(hostname) ncpu=$(sysctl -n hw.ncpu)"

# ---------- hook self-test (no claude) ----------
selftest() {
  local f="$out/selftest.tsv" ok=0 bad=0
  printf 'layer\tinput\texpect\tgot\n' > "$f"
  # UserPromptExpansion matcher, evaluated the way Claude Code does (JavaScript RegExp.test)
  local m
  m=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["hooks"]["UserPromptExpansion"][0]["matcher"])' "$here/settings-fragment.json")
  while IFS=$'\t' read -r name expect; do
    got=$(node -e 'process.stdout.write(new RegExp(process.argv[1]).test(process.argv[2])?"block":"pass")' "$m" "$name")
    printf 'UserPromptExpansion matcher\t%s\t%s\t%s\n' "$name" "$expect" "$got" >> "$f"
    [ "$got" = "$expect" ] && ok=$((ok+1)) || bad=$((bad+1))
  done <<'EOF'
pstack:poteto-mode	block
poteto-mode	block
pstack:tdd	block
tdd	block
pstack:reflect	block
reflect	block
pstack:setup-pstack	block
setup-pstack	block
compound-engineering:lfg	block
lfg	block
pstack:how	pass
tdd-guide	pass
superpowers:tdd	pass
superpowers:test-driven-development	pass
lfgx	pass
pstack:tdd-x	pass
xpstack:tdd	pass
compound-engineering:lfg2	pass
pstack:lfg	pass
EOF
  # UserPromptSubmit guard script, fed the same JSON shape Claude Code sends
  while IFS=$'\t' read -r prompt expect; do
    json=$(python3 -c 'import json,sys;print(json.dumps({"session_id":"x","hook_event_name":"UserPromptSubmit","prompt":sys.argv[1].replace("\\n","\n")}))' "$prompt")
    printf '%s' "$json" | bash "$T/hooks/disabled-cmd-prompt-guard.sh" 2>/dev/null
    rc=$?; got=pass; [ $rc = 2 ] && got=block
    printf 'UserPromptSubmit guard\t%s\t%s\t%s\n' "$prompt" "$expect" "$got" >> "$f"
    [ "$got" = "$expect" ] && ok=$((ok+1)) || bad=$((bad+1))
  done <<'EOF'
/pstack:poteto-mode	block
/poteto-mode do it	block
/pstack:tdd	block
/tdd	block
  /tdd	block
\n/tdd	block
/pstack:reflect	block
/reflect	block
/pstack:setup-pstack	block
/setup-pstack	block
/compound-engineering:lfg	block
/lfg	block
/lfg ship it	block
/pstack:how	pass
/tdd-guide	pass
/superpowers:tdd	pass
/lfgx	pass
please run /tdd later	pass
hello	pass
/compound-engineering:lfg2	pass
EOF
  # 100 sequential runs of the guard script (no nice/taskpolicy), wall time
  local j start end
  j=$(python3 -c 'import json;print(json.dumps({"hook_event_name":"UserPromptSubmit","prompt":"/pstack:how something "+"x"*2000}))')
  start=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
  for _ in $(seq 100); do printf '%s' "$j" | bash "$T/hooks/disabled-cmd-prompt-guard.sh" 2>/dev/null; done
  end=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
  log "selftest: $ok ok, $bad wrong; guard x100 wall=$(python3 -c "print(round($end-$start,3))")s load1=$(load1)"
  [ "$bad" = 0 ]
}

# ---------- settings variants ----------
gen_settings() {
  bash "$here/install.sh" --settings-file "$T/live-copy.json" --hooks-dir "$T/hooks" --dry-run --out "$T/merged.json" >> "$out/run.log"
  python3 - "$T" <<'PY'
import json, sys
T = sys.argv[1]
live = json.load(open(T + "/live-copy.json"))
m = json.load(open(T + "/merged.json"))
guard = 'bash "$HOME/.claude/hooks/disabled-cmd-prompt-guard.sh"'
def fix(d):
    s = json.dumps(d).replace(json.dumps(guard)[1:-1], json.dumps('bash "%s/hooks/disabled-cmd-prompt-guard.sh"' % T)[1:-1])
    return json.loads(s)
def ups_guard(d):
    return [h for e in d["hooks"]["UserPromptSubmit"] for h in e["hooks"] if "disabled-cmd-prompt-guard.sh" in h["command"]][0]
def save(name, d):
    json.dump(d, open("%s/%s.json" % (T, name), "w"), indent=1)
pr = fix(m); save("pr", pr)
# control: live settings without this PR and without the old block-disabled-skills hook (old 10 deny rules stay)
c = json.loads(json.dumps(live))
c["hooks"]["UserPromptSubmit"] = [e for e in c["hooks"]["UserPromptSubmit"] if not any("block-disabled-skills" in h["command"] for h in e["hooks"])]
save("control", c)
# UserPromptSubmit runs before UserPromptExpansion, so with both hooks the guard script blocks first.
# upe-only drops the guard script to exercise the main hook alone (what happens when the guard times out).
u = fix(m)
u["hooks"]["UserPromptSubmit"] = [e for e in u["hooks"]["UserPromptSubmit"] if not any("disabled-cmd-prompt-guard" in h["command"] for h in e["hooks"])]
save("upe-only", u)
# (a) UserPromptExpansion hook hangs past its timeout
a = fix(m); h = a["hooks"]["UserPromptExpansion"][-1]["hooks"][0]; h["command"] = "sleep 10"; h["timeout"] = 1; save("fault-a", a)
# (a2) same hang with the guard script removed, so only the main hook decides; (a2-nofail) regression: no onFailure
a2 = json.loads(json.dumps(u)); h = a2["hooks"]["UserPromptExpansion"][-1]["hooks"][0]; h["command"] = "sleep 10"; h["timeout"] = 1; save("fault-a2", a2)
a3 = json.loads(json.dumps(a2)); del a3["hooks"]["UserPromptExpansion"][-1]["hooks"][0]["onFailure"]; save("fault-a2-nofail", a3)
# (b) UserPromptSubmit guard hangs past its timeout
b = fix(m); h = ups_guard(b); h["command"] = "sleep 10"; h["timeout"] = 1; save("fault-b", b)
# (c) deny rules only, both hooks removed
cc = fix(m)
cc["hooks"]["UserPromptExpansion"] = [e for e in cc["hooks"]["UserPromptExpansion"] if not any("PER-89" in h["command"] for h in e["hooks"])]
cc["hooks"]["UserPromptSubmit"] = [e for e in cc["hooks"]["UserPromptSubmit"] if not any("disabled-cmd-prompt-guard" in h["command"] for h in e["hooks"])]
save("fault-c", cc)
# pstack's poteto-mode/tdd/reflect carry disable-model-invocation, which refuses the Skill call before any
# permission rule is consulted. The *-mi configs load a temp copy of pstack without that flag (--plugin-dir)
# so the deny rules themselves are tested; nodeny-mi drops every Skill(...) deny rule as the control.
mi = fix(m); mi.setdefault("enabledPlugins", {})["pstack@cursor-plugins"] = False; save("pr-mi", mi)
nd = json.loads(json.dumps(mi)); nd["permissions"]["deny"] = [r for r in nd["permissions"]["deny"] if not r.startswith("Skill(")]; save("nodeny-mi", nd)
cm = json.loads(json.dumps(cc)); cm.setdefault("enabledPlugins", {})["pstack@cursor-plugins"] = False; save("fault-c-mi", cm)
PY
  local src
  src=$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.claude/plugins/installed_plugins.json")))["plugins"]["pstack@cursor-plugins"][0]["installPath"])')
  cp -R "$src" "$T/pstack-mi"
  for k in poteto-mode tdd reflect; do
    sed -i.orig '/^disable-model-invocation:/d' "$T/pstack-mi/skills/$k/SKILL.md"
    log "pstack-mi: $k disable-model-invocation lines left: $(grep -c '^disable-model-invocation:' "$T/pstack-mi/skills/$k/SKILL.md")"
  done
  log "pstack-mi source: $src"
  cp "$T"/{pr,upe-only,control,fault-a,fault-a2,fault-a2-nofail,fault-b,fault-c,pr-mi,nodeny-mi,fault-c-mi}.json "$out/" 2>/dev/null
  # settings copies contain env values from the live file; keep only the hooks/permissions parts as evidence
  for n in pr upe-only control fault-a fault-a2 fault-a2-nofail fault-b fault-c pr-mi nodeny-mi fault-c-mi; do
    python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));json.dump({"permissions":{"deny":d.get("permissions",{}).get("deny")},"hooks":{k:d["hooks"].get(k) for k in ("UserPromptExpansion","UserPromptSubmit")}},open(sys.argv[1],"w"),indent=1)' "$out/$n.json"
  done
}

# ---------- load ----------
LOAD_PIDS="" LOAD_START=0
load_stop() {
  [ -n "$LOAD_PIDS" ] || return 0
  kill $LOAD_PIDS 2>/dev/null; wait $LOAD_PIDS 2>/dev/null
  log "load stop: pids=[$LOAD_PIDS] uptime: $(uptime)"
  local left; left=$(ps -o pid= -p ${LOAD_PIDS// /,} 2>/dev/null | wc -l | tr -d ' ')
  log "load leftovers: $left"
  LOAD_PIDS=""
}
load_ensure() {
  [ "$load_n" -gt 0 ] || return 0
  local now; now=$(date +%s)
  if [ -n "$LOAD_PIDS" ] && [ $((now - LOAD_START)) -lt 240 ]; then return 0; fi
  load_stop
  log "load start: uptime: $(uptime)"
  for _ in $(seq "$load_n"); do perl -e 'alarm 300; 1 while 1' & LOAD_PIDS="$LOAD_PIDS $!"; done
  LOAD_PIDS=${LOAD_PIDS# }; LOAD_START=$now
  log "load pids=[$LOAD_PIDS]"
  sleep 20
}
CHILD=""
trap 'load_stop' EXIT
trap '[ -z "$CHILD" ] || kill -9 "$CHILD" 2>/dev/null; load_stop; rm -rf "$T"; exit 130' INT TERM

# ---------- one claude run ----------
COST=0
printf 'case\tconfig\tkind\tinput\tload1\tresult\tblocked_by\tskill_body_seen\tcost_usd\tsecs\tdetail\n' > "$out/results.tsv"
run() { # case config kind(human|model) input expect
  local case=$1 cfg=$2 kind=$3 input=$4 expect=$5 prompt turns
  [[ $case =~ $cases ]] || return 0
  if python3 -c "import sys;sys.exit(0 if float('$COST')>float('$budget') else 1)"; then
    log "budget reached ($COST > $budget), skip $case"; printf '%s\t%s\t%s\t%s\t-\tnot run (budget)\t-\t-\t-\t-\t-\n' "$case" "$cfg" "$kind" "$input" >> "$out/results.tsv"; return
  fi
  load_ensure
  if [ "$kind" = human ]; then prompt="$input"; turns=1
  else prompt="Call the Skill tool exactly once with skill=\"$input\" and no args. Do not use any other tool. After the tool result, reply with the tool result text verbatim."; turns=3; fi
  local l0 t0 t1 f="$out/$case.jsonl" extra=()
  [[ $cfg == *-mi ]] && extra=(--plugin-dir "$T/pstack-mi")
  l0=$(load1); t0=$(date +%s)
  cd "$T/proj"
  perl -e 'alarm shift; exec @ARGV or die' "$run_timeout" claude -p "$prompt" \
    --setting-sources project --settings "$T/$cfg.json" --strict-mcp-config "${extra[@]}" --model haiku --max-turns "$turns" \
    --dangerously-skip-permissions --disallowedTools "Bash Edit Write NotebookEdit WebFetch WebSearch Agent" \
    --output-format stream-json --verbose --debug-file "$T/$case.debug.log" </dev/null > "$f" 2> "$out/$case.stderr" &
  CHILD=$!; wait "$CHILD"; local rc=$?; CHILD=""; t1=$(date +%s); cd - >/dev/null
  # keep only hook lines from the debug log (it can be large); drop env-like lines
  grep -i -E 'hook' "$T/$case.debug.log" 2>/dev/null | grep -v -i -E 'token|secret|key=|bearer|cookie' > "$out/$case.hooks.log"
  local row
  row=$(python3 - "$f" "$kind" "$input" "$expect" "$rc" <<'PY'
import glob, json, os, sys
f, kind, inp, expect, rc = sys.argv[1:6]
ev = []
for l in open(f):
    try: ev.append(json.loads(l))
    except Exception: pass
res = [e for e in ev if e.get("type") == "result"]
r = res[-1] if res else {}
cost = r.get("total_cost_usd", 0) or 0
text = str(r.get("result", ""))
assistant = [e for e in ev if e.get("type") == "assistant" and e.get("message", {}).get("model") != "<synthetic>"]
users = [e for e in ev if e.get("type") == "user"]
# stream-json does not echo the expanded command; the session transcript does
sid = next((e["session_id"] for e in ev if e.get("session_id")), None)
tr = glob.glob(os.path.expanduser("~/.claude/projects/*/%s.jsonl" % sid)) if sid else []
body = bool(tr) and "Base directory for this skill" in open(tr[0]).read()
blocked_by = "-"
for k in ("UserPromptExpansion", "UserPromptSubmit"):
    if k + " operation blocked by hook" in text: blocked_by = k
detail = text.replace("\n", " ")[:220]
if kind == "human":
    result = "blocked" if blocked_by != "-" and not assistant else ("passed" if assistant or cost > 0 else "unclear")
else:
    calls = [c for a in assistant for c in a.get("message", {}).get("content", []) if c.get("type") == "tool_use" and c.get("name") == "Skill"]
    outs = [c for u in users for c in (u.get("message", {}).get("content") or []) if isinstance(c, dict) and c.get("type") == "tool_result"]
    if not calls:
        result = "no Skill call"
    else:
        o = outs[0] if outs else {}
        oc = o.get("content")
        otext = oc if isinstance(oc, str) else json.dumps(oc, ensure_ascii=False)
        if "disable-model-invocation" in otext:
            result = "refused (disable-model-invocation)"
        elif o.get("is_error") and "has been denied" in otext:
            result = "denied"
        elif o.get("is_error"):
            result = "error"
        else:
            result = "allowed"
        detail = ("input=" + json.dumps(calls[0].get("input"), ensure_ascii=False) + " tool_result=" + otext.replace("\n", " "))[:300]
if not res:
    result = "no result (rc=%s)" % rc
elif "Not logged in" in text:
    result = "invalid: not logged in"
print("\t".join([result, blocked_by, "yes" if body else "no", str(cost), detail.replace("\t", " ")]))
PY
)
  local result blocked body cost detail
  IFS=$'\t' read -r result blocked body cost detail <<< "$row"
  COST=$(python3 -c "print(round(float('$COST')+float('${cost:-0}'),6))")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$case" "$cfg" "$kind" "$input" "$l0" "$result" "$blocked" "$body" "$cost" "$((t1-t0))" "$detail" >> "$out/results.tsv"
  local verdict=MISMATCH; [ "$result" = "$expect" ] && verdict=ok
  log "$case cfg=$cfg $kind '$input' load1=$l0 -> $result (expect $expect) by=$blocked body=$body cost=$cost ${verdict} total=$COST"
}

humans="/pstack:poteto-mode /poteto-mode /pstack:tdd /tdd /pstack:reflect /reflect /pstack:setup-pstack /setup-pstack /compound-engineering:lfg /lfg"
skills="pstack:poteto-mode pstack:tdd pstack:reflect pstack:setup-pstack compound-engineering:lfg"
slug() { echo "$1" | tr -c 'a-zA-Z0-9-\n' '_' | sed 's/^_*//'; }

st=0
if [ "$only" != selftest ] && ! claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
  log "claude is not logged in here (on macOS run from a GUI-session terminal); stop"; rm -rf "$T"; exit 69
fi
if [ "$only" != main ]; then selftest || st=1; fi
if [ "$only" != selftest ]; then
  gen_settings
  for c in $humans; do run "pr-human-$(slug "$c")" pr human "$c" blocked; done
  for c in $humans; do run "upe-only-human-$(slug "$c")" upe-only human "$c" blocked; done
  for s in $skills; do
    case $s in pstack:poteto-mode|pstack:tdd|pstack:reflect) e="refused (disable-model-invocation)" ;; *) e=denied ;; esac
    run "pr-model-$(slug "$s")" pr model "$s" "$e"
  done
  for s in pstack:poteto-mode pstack:tdd pstack:reflect; do run "pr-mi-model-$(slug "$s")" pr-mi model "$s" denied; done
  run nodeny-mi-model-pstack_tdd nodeny-mi model pstack:tdd allowed
  run pr-allow-pstack-how pr human /pstack:how passed
  run fault-a-human-pstack-tdd fault-a human /pstack:tdd blocked
  run fault-a2-human-pstack-tdd fault-a2 human /pstack:tdd blocked
  run fault-a2-nofail-human-pstack-tdd fault-a2-nofail human /pstack:tdd passed
  run fault-b-human-pstack-tdd fault-b human /pstack:tdd blocked
  run fault-c-model-pstack_tdd fault-c model pstack:tdd "refused (disable-model-invocation)"
  run fault-c-mi-model-pstack_tdd fault-c-mi model pstack:tdd denied
  run fault-c-model-pstack_setup-pstack fault-c model pstack:setup-pstack denied
  run fault-c-human-pstack-tdd fault-c human /pstack:tdd passed
  for c in $humans; do run "control-human-$(slug "$c")" control human "$c" passed; done
  load_stop
  # does /tdd-guide exist as a command on this machine?
  python3 - "$out/pr-allow-pstack-how.jsonl" <<'PY' | tee -a "$out/run.log"
import json, sys
for l in open(sys.argv[1]):
    try: e = json.loads(l)
    except Exception: continue
    if e.get("type") == "system" and e.get("subtype") == "init":
        sc = e.get("slash_commands", [])
        print("slash_commands containing tdd/lfg/poteto/reflect/setup-pstack:", [s for s in sc if any(k in s for k in ("tdd", "lfg", "poteto", "reflect", "setup-pstack"))])
        print("tdd-guide present:", any(s.endswith("tdd-guide") for s in sc))
        print("plugins:", [p.get("name") for p in e.get("plugins", [])])
        break
PY
fi
log "total_cost_usd=$COST tmp=$T"
log "live_sha256_after=$(shasum -a 256 "$live" | cut -d' ' -f1)"
rm -rf "$T"
exit $st
