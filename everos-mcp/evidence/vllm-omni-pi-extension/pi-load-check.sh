#!/bin/bash
# usage: pi-load-check.sh <cwd> <outfile>   Loads pi in rpc mode, asks /mcp status, no model call.
cd "$1" || exit 1
( sleep 15; printf '%s\n' '{"id":"m1","type":"prompt","message":"/mcp"}'; sleep 8; printf '%s\n' '{"id":"s2","type":"get_state"}'; sleep 2 ) |
  env -i HOME="$HOME" PATH="$PATH" LANG=C.UTF-8 TERM=dumb pi --mode rpc --no-session --tools 'codemode,mcp__everos__*' > "$2" 2> "$2.err" &
p=$!; sleep 35; kill $p 2>/dev/null; wait $p 2>/dev/null
python3 - "$2" <<'P'
import json,sys
for l in open(sys.argv[1]):
    try: m=json.loads(l)
    except Exception: print("  RAW", l[:200]); continue
    if m.get("type")=="extension_ui_request": print("  notify:", m.get("message"))
    elif m.get("command")=="get_state": print("  get_state messageCount =", m["data"]["messageCount"], "(0 = no model call)")
    else: print("  ", m.get("type"), m.get("command"), m.get("success"), (m.get("data") or {}).get("disposition"))
P
echo "  stderr bytes: $(wc -c < "$2.err")"
