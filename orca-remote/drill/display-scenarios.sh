# display-scenarios.sh: sourced by in-container.sh. Scenarios X1-X5 for the watchdog's display-failure rule
# (FAILURE-MODES-display.md, W1-W7). serve.log is a stand-in written here in the format of box's real serve.log
# (orca-remote serve-loop lines, Chromium's X error, Orca's "not verifiably live", the orca_server_ready JSON line).
[ $# = 0 ] && SCEN="$SCEN X1 X2 X3 X3b X4 X5 X6 X7"

slog(){ echo "$*" >>"$W/serve.log"; }
s_start(){ slog "[$(date '+%F %T %Z')] starting orca-ide serve on 127.0.0.1:6768 (advertise wss://orca-bot.deepvision.sg${1:+, display=$1})"; }
s_ready(){ slog '{"type":"orca_server_ready","schemaVersion":1,"runtimeId":"drill","endpoint":"ws://0.0.0.0:6768"}'; }
s_xerr(){ slog "[$$:1020/105401.000000:ERROR:ui/gfx/x/connection.cc:66] X connection error received."; }
s_nvl(){ slog "[serve] DISPLAY=$1 is not verifiably live; leaving it untouched. Unset DISPLAY to let Orca start its own Xvfb."; }
s_exit(){ slog "[$(date '+%F %T %Z')] orca-ide serve exited (1); restarting in 5s"; }
# xsetup NAME: setup with serve.log wired in (the pre watchdog ignores WATCHDOG_SERVE_LOG); serve.log is stale after 20s
xsetup(){ export WATCHDOG_SERVE_LOG=/run/drill/$LABEL/$1/serve.log WATCHDOG_SLOG_STALE=20; setup "$1"
  [ "$(pub)" = 200 ] || note "WARNING: world not healthy at start (public $(pub)); a previous scenario left something running"; }
xteardown(){ teardown; cp "$W/serve.log" "$OUT/$S/" 2>/dev/null; unset WATCHDOG_SERVE_LOG WATCHDOG_SLOG_STALE; }
# wait_count REGEX N TIMEOUT: wait until N watchdog lines after the mark match REGEX
wait_count(){ local end=$(( $(now)+$3 )); while [ "$(now)" -lt "$end" ]; do
    [ "$(awk -v from="$LOG_MARK" 'NR>from' "$W/watchdog.log" | grep -cE "$1")" -ge "$2" ] && return 0; sleep 0.2; done; return 1; }
first_restart(){ awk -v t="$1" '$1>t {print "+" $1-t "s"; exit}' "$W/restarts"; }

# X1 (W1): own mode. :4-style X connection error kills serve; serve-loop starts the next serve (own Xvfb), which is not ready
#   yet. After the watchdog's 2nd unhealthy round serve is ready again. The pre watchdog restarts at that 2nd round.
X1(){ xsetup X1; s_start own; s_ready; sleep 8
  mark_log; T0=$(now); s_xerr; echo down >"$W/orca_mode"; s_exit; sleep 1; s_start own; note "X connection error; serve-loop restarted serve (own), not ready yet"
  wait_count 'unhealthy local=' 2 60 || note "did not see 2 unhealthy rounds"; sleep 1
  s_ready; echo ok >"$W/orca_mode"; note "serve ready again"; sleep 15
  check "W1 no full restart while serve-loop self-heals (own)" $([ "$(restarts_after "$T0")" = 0 ]; echo $?) "orca restarts: $(restarts_after "$T0"); watchdog: $(awk -v from="$LOG_MARK" 'NR>from' "$W/watchdog.log" | grep -oE 'unhealthy local=[^ ]+ public=[^ ]+.{0,40}' | head -2 | tr '\n' '|')"
  check "public 200 at end" $([ "$(pub)" = 200 ]; echo $?) "public $(pub)"
  xteardown; }

# X2 (W2, W2b): same as X1, but serve never comes back (own Xvfb cannot start): the extra round must not block the restart,
#   and it is one round, not several.
X2(){ xsetup X2; s_start own; s_ready; sleep 8
  mark_log; T0=$(now); s_xerr; echo down >"$W/orca_mode"; s_exit; sleep 1; s_start own; note "X connection error, serve never ready again"
  for _ in $(seq 60); do [ "$(restarts_after "$T0")" -ge 1 ] && break; sleep 1; done; sleep 5  # let the fake restart finish (stop, start)
  check "W2 own display failure that does not heal still gets a full restart within 60s" $([ "$(restarts_after "$T0")" -ge 1 ]; echo $?) "first restart $(first_restart "$T0")"
  n=$(awk -v from="$LOG_MARK" 'NR>from' "$W/watchdog.log" | sed '/-> restart:/q' | grep -c 'display failure in own mode')
  check "W2b exactly one uncounted round before the restart" $([ "$n" = 1 ]; echo $?) "uncounted rounds before the first restart: $n"
  xteardown; }

# x3 MODE SECONDS: non-own display dead for SECONDS (every serve run dies with "not verifiably live"), then it comes back.
x3(){ local m=$1 secs=$2 disp=${1:-:4} end i=0
  s_start "$m"; s_ready; sleep 8
  T0=$(now); s_xerr; echo down >"$W/orca_mode"; s_exit; note "display $disp torn down"; end=$((T0+secs))
  while [ "$(now)" -lt "$end" ]; do sleep 5; s_start "$m"; s_nvl "$disp"; s_exit; i=$((i+1)); [ $i = 5 ] && snap_state dead; done
  T1=$(now); s_start "$m"; s_ready; echo ok >"$W/orca_mode"; note "display back, serve ready"; sleep 15; snap_state back
  check "W3 no full restart while display $disp is dead (${secs}s)" $([ "$(awk -v a="$T0" -v b="$T1" '$1>a && $1<=b' "$W/restarts" | wc -l)" = 0 ]; echo $?) "orca restarts while dead: $(awk -v a="$T0" -v b="$T1" '$1>a && $1<=b' "$W/restarts" | wc -l)"
  check "W3 state display_dead while dead" $(state_is dead display_dead; echo $?) "$(tr '\n' ' ' <"$W/state-dead" | cut -c1-90)"
  check "W4 state back to ok after the display returns" $(state_is back ok; echo $?) "$(tr '\n' ' ' <"$W/state-back" | cut -c1-60)"
  check "public 200 at end" $([ "$(pub)" = 200 ]; echo $?) "public $(pub)"; }
X3(){ xsetup X3; x3 :4 60; xteardown; }
# X3b (W5): the same with the old orca-remote's start line (no "display="): the old script pinned :4, so not own.
X3b(){ xsetup X3b; x3 "" 40; xteardown; }

# X4 (W6): own. A display error happened, serve was ready again afterwards; now Orca hangs for an unrelated reason.
X4(){ xsetup X4; s_start own; s_xerr; s_exit; s_start own; s_ready; sleep 8
  T0=$(now); echo hang >"$W/orca_mode"; cp "$W/orca_mode" "$W/orca_mode_after_restart"; note "Orca hung, no display error since the last ready"
  for _ in $(seq 60); do [ "$(restarts_after "$T0")" -ge 1 ] && break; sleep 1; done; sleep 5  # let the fake restart finish (stop, start)
  check "W6 old display error does not stop a restart for an unrelated hang (own, within 60s)" $([ "$(restarts_after "$T0")" -ge 1 ]; echo $?) "first restart $(first_restart "$T0")"
  xteardown; }

# X5 (W6): non-own. An earlier serve run died of the display; the last run has no display error but hangs before ready.
X5(){ xsetup X5; s_start :4; s_ready; s_xerr; s_exit; s_start :4; s_nvl :4; s_exit; s_start :4; sleep 8
  T0=$(now); echo hang >"$W/orca_mode"; cp "$W/orca_mode" "$W/orca_mode_after_restart"; note "last serve run hangs, no display error in it"
  for _ in $(seq 60); do [ "$(restarts_after "$T0")" -ge 1 ] && break; sleep 1; done; sleep 5  # let the fake restart finish (stop, start)
  check "W6 earlier display failure does not stop a restart when the last run has none (:4, within 60s)" $([ "$(restarts_after "$T0")" -ge 1 ]; echo $?) "first restart $(first_restart "$T0")"
  xteardown; }

# X6 (W8): non-own display dead, then it comes back: serve-loop starts a serve that is ready only after 2 more watchdog rounds.
#   Leaving display_dead must not count straight into strikes (pre: restarts already while dead; HEAD before W8: at strike 2).
X6(){ xsetup X6; s_start :4; s_ready; sleep 8
  T0=$(now); s_xerr; echo down >"$W/orca_mode"; s_exit; note "display :4 torn down"
  for _ in 1 2 3 4; do sleep 5; s_start :4; s_nvl :4; s_exit; done; snap_state dead
  mark_log; s_start :4; note "display back; serve-loop started serve, not ready yet"
  wait_count 'unhealthy local=' 2 60 || note "did not see 2 unhealthy rounds"; sleep 1
  s_ready; echo ok >"$W/orca_mode"; note "serve ready"; sleep 15
  check "W8 no full restart while serve starts after display_dead" $([ "$(restarts_after "$T0")" = 0 ]; echo $?) "orca restarts: $(restarts_after "$T0"); watchdog: $(awk -v from="$LOG_MARK" 'NR>from' "$W/watchdog.log" | grep -oE 'unhealthy local=[^ ]+ public=[^ ]+.{0,40}' | head -2 | tr '\n' '|')"
  check "W3 state display_dead while dead" $(state_is dead display_dead; echo $?) "$(tr '\n' ' ' <"$W/state-dead" | cut -c1-90)"
  check "public 200 at end" $([ "$(pub)" = 200 ]; echo $?) "public $(pub)"
  xteardown; }

# X7 (W9): non-own display error, then serve.log is not written any more (serve-loop gone, tmux session still there).
#   Once serve.log is stale (20s here) the old display error must not hold off the restart.
X7(){ xsetup X7; s_start :4; s_ready; sleep 8
  T0=$(now); s_xerr; echo down >"$W/orca_mode"; s_exit; s_start :4; s_nvl :4; s_exit; note "display error, then serve.log goes silent"
  for _ in $(seq 90); do [ "$(restarts_after "$T0")" -ge 1 ] && break; sleep 1; done; sleep 5  # let the fake restart finish (stop, start)
  check "W9 stale serve.log: an old display error does not block the restart (within 90s)" $([ "$(restarts_after "$T0")" -ge 1 ]; echo $?) "first restart $(first_restart "$T0")"
  xteardown; }
