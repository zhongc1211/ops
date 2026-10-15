#!/bin/bash
# Offline tests for bin/orca-wake. Everything goes to a temp dir and a local mock webhook
# (tests/mock_webhook.py on 127.0.0.1); no real bot is contacted and no real state is touched.
#
#   tests/unit.sh            run all cases, exit 1 if any fails
#   KEEP=1 tests/unit.sh     keep the temp dir for inspection
set -u
here=$(cd "$(dirname "$0")" && pwd)
WAKE="$here/../bin/orca-wake"
MOCK="$here/mock_webhook.py"
PORT=${PORT:-18799}
tmp=$(mktemp -d)
export ORCA_WAKE_STATE_DIR="$tmp/state" ORCA_WAKE_CONFIG_DIR="$tmp/config" ORCA_WAKE_WEBHOOK_DIRS="$tmp/hooks"
export ORCA_WAKE_RETRY_DELAYS=1,1 ORCA_WAKE_SETTLE_S=1
OUT="$tmp/requests.jsonl"
mkdir -p "$tmp/config" "$tmp/hooks" "$tmp/ws"
printf 'unit-bot\nunit-down\n' >"$tmp/config/enabled-bots"
printf 'URL=http://127.0.0.1:%s/hook/unit\nKEY=unit-key\n' "$PORT" >"$tmp/hooks/unit-bot.env"
printf 'URL=http://127.0.0.1:%s/hook/down\nKEY=unit-key\n' "$PORT" >"$tmp/hooks/unit-down.env"
printf 'URL=http://127.0.0.1:%s/hook/shadow\nKEY=unit-key\n' "$PORT" >"$tmp/hooks/unit-shadow.env"

python3 "$MOCK" --port "$PORT" --out "$OUT" --key unit-key &
mock=$!
sleep 300 &
agent=$!          # stands in for the agent process; its parent is this script
cleanup() { kill "$mock" "$agent" 2>/dev/null; wait 2>/dev/null; [ "${KEEP:-0}" = 1 ] && echo "kept $tmp" || rm -rf "$tmp"; }
trap cleanup EXIT
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" -X POST -d '{}' && break; sleep 0.1; done
: >"$OUT"

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }

# hook <task> <json> [extra env...]: run one Claude hook event as if dispatched by this script
hook() {
    local task=$1 json=$2; shift 2
    echo "$json" | env ORCA_DISPATCH_BOT="${BOT:-unit-bot}" ORCA_TASK_ID="$task" ORCA_DISPATCH_PID=$$ \
        WAKE_AGENT_PID="$agent" "$@" "$WAKE" claude-hook 2>>"$tmp/stderr"
}
ev() {  # ev <event> <session> [extra json fields]
    printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s"%s}' "$1" "$2" "${CWD:-$tmp/ws}" "${3:+,$3}"
}
settle() {  # wait for detached senders to finish
    for _ in $(seq 1 100); do
        [ -z "$(ls "$tmp/state/inflight" 2>/dev/null)" ] && break; sleep 0.1
    done
    sleep "${1:-0}"
}
count() {  # count <task> [status]
    python3 - "$OUT" "$1" "${2:-}" <<'EOF'
import json, sys
n = 0
for line in open(sys.argv[1]):
    b = json.loads(line)["body"]
    if b.get("task") == sys.argv[2] and (not sys.argv[3] or b.get("status") == sys.argv[3]):
        n += 1
print(n)
EOF
}
logged() { grep -F "\"task\": \"$1\"" "$tmp/state/wake.log" 2>/dev/null | grep -cF "$2"; }
expect() {  # expect <name> <actual> <wanted>
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got $2, want $3)"; fi
}

# 1. turn ends -> one idle; a repeated Stop and the later idle_prompt do not send again
hook T1 "$(ev UserPromptSubmit s1)"
hook T1 "$(ev Stop s1 '"last_assistant_message":"done T1","background_tasks":[]')"
settle 1.5
hook T1 "$(ev Stop s1 '"last_assistant_message":"done T1","background_tasks":[]')"
hook T1 "$(ev Notification s1 '"notification_type":"idle_prompt"')"
settle
expect "T1 idle once" "$(count T1 idle)" 1
expect "T1 auth header" "$(grep -c '"auth_ok": true' "$OUT")" 1
expect "T1 duplicate logged as already_sent" "$(logged T1 already_sent)" 2

# 2. background shell running -> Stop and idle_prompt both skip; next turn wakes
hook T2 "$(ev UserPromptSubmit s2)"
hook T2 "$(ev Stop s2 '"background_tasks":[{"id":"b1","type":"shell","status":"running"}]')"
hook T2 "$(ev Notification s2 '"notification_type":"idle_prompt"')"
settle
expect "T2 nothing while shell runs" "$(count T2)" 0
hook T2 "$(ev UserPromptSubmit s2)"
hook T2 "$(ev Stop s2 '"last_assistant_message":"shell done","background_tasks":[{"id":"b1","type":"shell","status":"completed"}]')"
settle 1.5
expect "T2 one idle after follow-up turn" "$(count T2 idle)" 1

# 3. permission dialog -> needs_input with the question
hook T3 "$(ev UserPromptSubmit s3)"
hook T3 "$(ev PermissionRequest s3 '"tool_name":"Bash","tool_input":{"command":"rm -rf build"}')"
hook T3 "$(ev Notification s3 '"notification_type":"permission_prompt","message":"Claude needs your permission"')"
settle
expect "T3 needs_input" "$(count T3 needs_input)" 1
expect "T3 question in body" "$(grep -c 'rm -rf build' "$OUT")" 1

# 4. API error -> error; idle_prompt afterwards stays quiet
hook T4 "$(ev UserPromptSubmit s4)"
hook T4 "$(ev StopFailure s4 '"error":"rate_limit"')"
hook T4 "$(ev Notification s4 '"notification_type":"idle_prompt"')"
settle
expect "T4 error once" "$(count T4 error)" 1
expect "T4 no idle after error" "$(count T4 idle)" 0

# 5. usage-limit notification -> blocked
hook T5 "$(ev UserPromptSubmit s5)"
hook T5 "$(ev Notification s5 '"notification_type":"quota_auto_resume_stale","message":"limit"')"
settle
expect "T5 blocked" "$(count T5 blocked)" 1

# 6. agent is not a direct child of the dispatcher -> nothing, logged as parent_mismatch
hook T6 "$(ev UserPromptSubmit s6)" ORCA_DISPATCH_PID=1
hook T6 "$(ev Stop s6 '"background_tasks":[]')" ORCA_DISPATCH_PID=1
settle 1.5
expect "T6 no webhook" "$(count T6)" 0
expect "T6 parent_mismatch logged" "$(logged T6 parent_mismatch)" 2

# 7. mute file in the workspace -> nothing
mkdir -p "$tmp/ws7/sub" && touch "$tmp/ws7/.orca-wake-mute" && git -C "$tmp/ws7" init -q
CWD="$tmp/ws7/sub"
hook T7 "$(ev UserPromptSubmit s7)"
hook T7 "$(ev Stop s7 '"background_tasks":[]')"
unset CWD
settle 1.5
expect "T7 muted" "$(count T7)" 0
expect "T7 muted logged" "$(logged T7 muted)" 1

# 8. bot not in enabled-bots -> shadow: logged, deduped, not sent
BOT=unit-shadow hook T8 "$(ev UserPromptSubmit s8)"
BOT=unit-shadow hook T8 "$(ev Stop s8 '"background_tasks":[]')"
settle 1.5
BOT=unit-shadow hook T8 "$(ev Notification s8 '"notification_type":"idle_prompt"')"
settle
expect "T8 shadow not sent" "$(count T8)" 0
expect "T8 shadow logged once" "$(logged T8 '"event": "shadow"')" 1

# 9. Pi-style send: same leaf id twice -> one webhook
for _ in 1 2; do
    echo "pi says done" | env ORCA_DISPATCH_BOT=unit-bot ORCA_TASK_ID=T9 ORCA_DISPATCH_PID=$$ \
        "$WAKE" send --agent pi --status idle --session p9 --seq leaf-abc --agent-pid "$agent" --cwd "$tmp/ws"
    settle
done
expect "T9 pi idle once" "$(count T9 idle)" 1

# 10. webhook down -> retries then failed; recheck after recovery sends once, then already_woken
touch "$OUT.fail-down"
BOT=unit-down hook T10 "$(ev UserPromptSubmit s10)"
BOT=unit-down hook T10 "$(ev Stop s10 '"last_assistant_message":"T10","background_tasks":[]')"
settle 1
expect "T10 three attempts" "$(count T10)" 3
expect "T10 failed logged" "$(logged T10 all_attempts_failed)" 1
rm -f "$OUT.fail-down"
"$WAKE" recheck --agent-pid "$agent" --idle-min 0 2>/dev/null
settle
"$WAKE" recheck --agent-pid "$agent" --idle-min 0 2>/dev/null
settle
ok_n=$(python3 -c 'import json,sys; print(sum(1 for l in open(sys.argv[1]) if json.loads(l)["body"].get("task")=="T10" and json.loads(l)["answered"]==200))' "$OUT")
expect "T10 recheck delivered once" "$ok_n" 1
expect "T10 second recheck already_woken" "$(logged T10 already_woken)" 1

# 11. queued notification at Stop (Claude will start another turn) -> skip
printf '%s\n' '{"type":"queue-operation","operation":"enqueue","content":"<task-notification>"}' >"$tmp/t11.jsonl"
hook T11 "$(ev UserPromptSubmit s11)"
hook T11 "$(ev Stop s11 "\"transcript_path\":\"$tmp/t11.jsonl\",\"background_tasks\":[]")"
settle 1.5
expect "T11 queued_followup skip" "$(count T11)" 0
expect "T11 logged" "$(logged T11 queued_followup)" 1

# 12. new turn starts within the settle window -> first wake dropped as superseded
hook T12 "$(ev UserPromptSubmit s12)"
hook T12 "$(ev Stop s12 '"background_tasks":[]')"
hook T12 "$(ev UserPromptSubmit s12)"
settle 1.5
expect "T12 superseded" "$(count T12)" 0
expect "T12 logged" "$(logged T12 superseded)" 1

# 13. not dispatched (no ORCA_DISPATCH_BOT) -> no output, no state
before=$(ls "$tmp/state/sessions" | wc -l)
ev Stop s13 '"background_tasks":[]' | env -u ORCA_DISPATCH_BOT WAKE_AGENT_PID="$agent" "$WAKE" claude-hook
expect "T13 no state written" "$(ls "$tmp/state/sessions" | wc -l)" "$before"

# 14. recheck idle clock: untimestamped metadata appended after the turn does not count as activity
printf '%s\n' '{"type":"assistant","timestamp":"2020-01-02T03:04:05.678Z"}' '{"type":"bridge-session","sessionId":"x"}' >"$tmp/t14.jsonl"
printf '%s\n' '{"type":"ai-title"}' >"$tmp/t14b.jsonl"
got=$(python3 - "$WAKE" "$tmp/t14.jsonl" "$tmp/t14b.jsonl" <<'EOF2'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("orca_wake", sys.argv[1])
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("orca_wake", loader))
loader.exec_module(mod)
print(int(mod.transcript_last_ts(sys.argv[2])), int(mod.transcript_last_ts(sys.argv[3]) == os.path.getmtime(sys.argv[3])))
EOF2
)
expect "T14 last timestamped entry, not mtime" "$got" "1577934245 1"

# 15. hooks wrote nothing to stderr
expect "no stderr from hooks" "$(wc -c <"$tmp/stderr" | tr -d ' ')" 0

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
