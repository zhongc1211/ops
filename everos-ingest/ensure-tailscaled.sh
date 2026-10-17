#!/bin/bash
# Ensure box tailscaled is running and online against headscale. No keys used.
LOG=/tmp/ensure-tailscaled.log
SOCK=/var/run/tailscale/tailscaled.sock
ts(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
grep -q 'headscale.deepvision.sg' /etc/hosts || { echo '157.230.194.108 headscale.deepvision.sg' | sudo tee -a /etc/hosts >/dev/null; ts "restored /etc/hosts entry"; }
start(){ sudo sh -c "setsid tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=$SOCK --port=41641 >>/tmp/tailscaled.log 2>&1 </dev/null &"; sleep 6; }
# Self.Online from headscale is unreliable for this node (reports false while healthy),
# so judge health by the data plane: a real tailscale ping to site or imac.
running(){ timeout 10 tailscale status --json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);sys.exit(0 if d["BackendState"]=="Running" else 1)'; }
dataplane(){ for p in 100.64.0.5 100.64.0.4; do timeout 12 tailscale ping --c 2 --timeout 4s "$p" 2>/dev/null | grep -q '^pong' && return 0; done; return 1; }
online(){ running && dataplane; }
if ! pgrep -x tailscaled >/dev/null; then ts "tailscaled not running, starting"; start; fi
online && exit 0
sleep 15; online && exit 0   # give control a moment after a wake
ts "not online, restarting tailscaled"
sudo pkill -x tailscaled; sleep 2; start
sudo timeout 40 tailscale up --login-server=https://headscale.deepvision.sg:8443 --hostname=box --accept-dns=false --timeout=30s >>"$LOG" 2>&1
online && ts "online after restart" || ts "STILL OFFLINE after restart"
