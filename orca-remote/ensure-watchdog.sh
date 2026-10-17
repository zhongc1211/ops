#!/bin/bash
# Idempotent: start watchdog.sh if not running (respects its flock). Silent on success.
# DISPLAY pinned to :4 so the watchdog (and orca-remote it starts) never inherits a caller's display.
export DISPLAY=:4
L=/tmp/orca-remote-watchdog.lock; W=/workspace/ops/orca-remote/watchdog.sh
if pgrep -f "^/bin/bash $W" >/dev/null && [ -e $L ] && ! flock -n $L true 2>/dev/null; then exit 0; fi   # lock held -> running
# not running but lock held by an orphaned child (old rev) -> release it
for p in $(fuser $L 2>/dev/null); do [ "$(cat /proc/$p/comm 2>/dev/null)" = sleep ] && kill $p; done
setsid nohup $W >/dev/null 2>&1 < /dev/null &
sleep 0.3; pgrep -f "^/bin/bash $W" >/dev/null || { echo "ensure-watchdog: failed to start $W" >&2; exit 1; }; exit 0
