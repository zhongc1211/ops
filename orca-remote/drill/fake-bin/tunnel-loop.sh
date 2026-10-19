#!/bin/bash
# Drill stand-in for `orca-remote tunnel-loop`: respawn cloudflared when it exits (production waits 5s, drill 2s).
while true; do
  /drill-src/drill/fake-bin/cloudflared tunnel --config "$DRILL_W/cf.yml" run orca-bot
  echo "$(date +%s) exited $?" >>"$DRILL_W/cf_events"; sleep 2
done
