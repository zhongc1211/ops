#!/bin/bash
# Idempotent: start watchdog.sh if not running (respects its flock). Silent on success.
# No DISPLAY pin (rev 2026-10-20): orca-remote chooses serve's display from ORCA_SERVE_DISPLAY (default own = Orca's own Xvfb)
# and never passes the caller's DISPLAY to serve; :4 is a host-managed Grok desktop, not orca-bot's.
L=/tmp/orca-remote-watchdog.lock; W=/workspace/ops/orca-remote/watchdog.sh
if pgrep -f "^/bin/bash $W" >/dev/null && [ -e $L ] && ! flock -n $L true 2>/dev/null; then exit 0; fi   # lock held -> running
# not running but lock held by an orphaned child (old rev) -> release it
for p in $(fuser $L 2>/dev/null); do [ "$(cat /proc/$p/comm 2>/dev/null)" = sleep ] && kill $p; done
setsid nohup $W >/dev/null 2>&1 < /dev/null &
sleep 0.3; pgrep -f "^/bin/bash $W" >/dev/null || { echo "ensure-watchdog: failed to start $W" >&2; exit 1; }; exit 0
