#!/usr/bin/env bash
# Real /add + /flush against app ops / project everos-smoke.
# usage: everos-smoke.sh <label> [base_url]   (default base http://100.64.0.5)
# Token is read from $EVEROS_TOKEN_FILE (default ~/.config/everos/.proxy-token) and never printed.
set -u
LABEL=${1:?label}; BASE=${2:-http://100.64.0.5}
TOKEN_FILE=${EVEROS_TOKEN_FILE:-$HOME/.config/everos/.proxy-token}
SESSION="everos-smoke-${LABEL}-$(date +%Y%m%d%H%M%S)"
NOW=$(( $(date +%s) * 1000 ))
AUTH="Authorization: Bearer $(tr -d '\n' < "$TOKEN_FILE")"
H=(-H "$AUTH" -H 'Content-Type: application/json' -H 'Host: everos.deepvision.sg')
echo "session=$SESSION base=$BASE (Authorization: Bearer <redacted>)"
BODY=$(cat <<J
{"session_id":"$SESSION","app_id":"ops","project_id":"everos-smoke","messages":[
 {"sender_id":"smoke-user","sender_name":"Smoke","role":"user","timestamp":$NOW,"content":"EverOS smoke test ${LABEL}: unique marker ${SESSION}. Please remember that the tailnet path to site nginx was verified today."},
 {"sender_id":"smoke-agent","role":"assistant","timestamp":$((NOW+1)),"content":"Noted. Marker ${SESSION} recorded for the tailnet smoke test ${LABEL}."}]}
J
)
echo "--- POST $BASE/api/v2/memory/add"
curl -sS -m 400 -w '\n[http %{http_code} in %{time_total}s]\n' "${H[@]}" -X POST "$BASE/api/v2/memory/add" -d "$BODY"
echo "--- POST $BASE/api/v2/memory/flush"
curl -sS -m 400 -w '\n[http %{http_code} in %{time_total}s]\n' "${H[@]}" -X POST "$BASE/api/v2/memory/flush" \
  -d "{\"session_id\":\"$SESSION\",\"app_id\":\"ops\",\"project_id\":\"everos-smoke\"}"
echo "SESSION=$SESSION"
