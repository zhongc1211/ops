#!/bin/bash
# e2e for orca-remote rev 2026-10-20 (serve owns its display; FAILURE-MODES-display.md E1-E7). Rerunnable.
# usage: e2e-serve-display.sh <orca-remote script> [--real]
# Written on box (ops reports/orca-serve-1020/e2e); B-loop and the container runner (run-serve-e2e.sh) added in the repo.
#  A (always): run `<script> serve-loop` with a fake orca-ide that records its env and exits 1 at once, while the
#     caller's DISPLAY points at a dead display (:77). PASS if the fake saw no DISPLAY, saw ORCA_SERVE_RUNTIME=electron
#     and a private XDG_RUNTIME_DIR, and the loop backed off (delay grows past 5s) instead of restarting every 5s.
#     Also runs the same with ORCA_SERVE_DISPLAY=:77 (rollback knob), and with :77 in $ORCA_REMOTE_STATE/serve-display (the
#     rollback that survives the watchdog's restarts), and expects DISPLAY=:77 to be passed (= old behaviour).
#  B (--real): the real orca-ide (ORCA_IDE_BIN, default the box path) serve on port 6799 with a throwaway HOME:
#     B0 control: DISPLAY=:77 (dead)  -> expect exit 1 with "not verifiably live" (the 10-20 failure)
#     B1 fix:     DISPLAY unset       -> expect orca_server_ready within 120s and an Xvfb :99 child; then stop it, expect Xvfb gone.
#  B-start (--real, throwaway container only): `<script> start` / `restart` in tmux, as the watchdog runs them. The display
#     choice must reach serve-loop: $STATE/serve-display :77 -> display=:77; ORCA_SERVE_DISPLAY=:78 wins over the file;
#     neither -> display=own. After `stop` no Xvfb is left. (The old orca-remote logs no display= and fails these.)
#  B-loop (--real, throwaway container only: it uses orca-remote's production paths /home/box and port 6768):
#     `<script> serve-loop` with the real orca-ide while the caller's DISPLAY=:4 is dead (no X server on :4, as on 10-20).
#     Expect orca_server_ready within 180s and one Xvfb :99; kill serve, expect serve-loop to bring it back within 180s
#     with the old Xvfb gone and again exactly one Xvfb. The old orca-remote (pinned :4) never gets ready here.
# Artifacts: $W (printed), plus b0.log, b1.log, bstart.out, bloop-serve.log copied to $E2E_ARTIFACTS when set.
set -u
S=$(readlink -f "$1"); REAL=${2:-}; W=$(mktemp -d /tmp/e2e-serve-display.XXXX); pass=0; fail=0
ok(){ echo "PASS $*"; pass=$((pass+1)); }; ko(){ echo "FAIL $*"; fail=$((fail+1)); }
cat >"$W/fake-orca-ide" <<'F'
#!/bin/bash
mkdir -p "$HOME"; env | sort >"$HOME/env.$(date +%s%N)"; echo fake-serve-start; exit 1
F
chmod +x "$W/fake-orca-ide"
runA(){ # $1 label, rest env
  local lbl=$1; shift; local o="$W/$lbl"; mkdir -p "$o"
  env "$@" DISPLAY=:77 ORCA_IDE="$W/fake-orca-ide" ORCA_REMOTE_STATE="$o/state" ORCA_REMOTE_HOME="$o/home" \
    ORCA_REMOTE_PORT=6799 timeout 40 "$S" serve-loop >/dev/null 2>&1
  echo "$o"
}
o=$(runA own)
n=$(ls "$o"/home/env.* 2>/dev/null | wc -l); first=$(ls "$o"/home/env.* 2>/dev/null | head -1); first=${first:-/dev/null}
[ "$n" -ge 2 ] && ok "A own: serve-loop restarted the fake $n times in 40s" || ko "A own: only $n starts"
grep -q '^DISPLAY=' "$first" && ko "A own: fake got $(grep ^DISPLAY= "$first")" || { [ "$n" -ge 1 ] && ok "A own: no DISPLAY passed (Orca starts its own Xvfb)" || ko "A own: fake never ran"; }
grep -q '^ORCA_SERVE_RUNTIME=electron$' "$first" && ok "A own: ORCA_SERVE_RUNTIME=electron" || ko "A own: ORCA_SERVE_RUNTIME missing"
grep -q '^XDG_RUNTIME_DIR=/tmp/xdg-runtime-orca-remote$' "$first" && ok "A own: private XDG_RUNTIME_DIR" || ko "A own: XDG_RUNTIME_DIR=$(grep ^XDG_RUNTIME_DIR= "$first")"
grep -q 'restarting in [1-9][0-9]s (fast failures' "$o/state/serve.log" 2>/dev/null && ok "A own: backoff grew past 5s: $(grep -o 'restarting in [0-9]*s' "$o/state/serve.log" | tr '\n' ' ')" || ko "A own: no backoff: $(grep -o 'restarting in [0-9]*s' "$o/state/serve.log" 2>/dev/null | tr '\n' ' ')"
[ "$n" -ge 1 ] && [ "$n" -le 5 ] && ok "A own: $n starts in 40s (old loop: ~7)" || ko "A own: $n starts in 40s, backoff not effective"
o=$(runA rollback ORCA_SERVE_DISPLAY=:77); first=$(ls "$o"/home/env.* 2>/dev/null | head -1); first=${first:-/dev/null}
grep -q '^DISPLAY=:77$' "$first" && ok "A rollback knob: ORCA_SERVE_DISPLAY=:77 passes DISPLAY=:77 (old behaviour)" || ko "A rollback: $(grep ^DISPLAY= "$first")"
mkdir -p "$W/rbfile/state"; echo :77 >"$W/rbfile/state/serve-display"
o=$(runA rbfile); first=$(ls "$o"/home/env.* 2>/dev/null | head -1); first=${first:-/dev/null}
grep -q '^DISPLAY=:77$' "$first" && ok "A rollback file: serve-display :77 passes DISPLAY=:77" || ko "A rollback file: $(grep ^DISPLAY= "$first")"
if [ "$REAL" = --real ]; then
  BIN=${ORCA_IDE_BIN:-/workspace/ops/orca-app/Orca/resources/bin/orca-ide}; H="$W/realhome"; mkdir -p "$H"
  # same coverage as orca-remote's FILTER: orca://pair?code=..., and ?/#/& pair*/code*/pairing*= (webClientUrl #pairing=...)
  red(){ sed -u -E 's#(orca://pair\?code=)[^"[:space:]]+#\1<redacted>#g; s#([?#&](pair|code|pairing)[^=[:space:]"]*=)[^[:space:]"]+#\1<redacted>#g; s#("code"|"token"|"secret")[^,}]*#\1:"<redacted>"#g'; }
  env -i HOME="$H" PATH=/usr/local/bin:/usr/bin:/bin DISPLAY=:77 ORCA_SERVE_RUNTIME=electron timeout 60 "$BIN" serve --port 6799 --json 2>&1 | red >"$W/b0.log"
  rc=${PIPESTATUS[0]}
  grep -q 'DISPLAY=:77 is not verifiably live' "$W/b0.log" && [ "$rc" != 0 ] && ok "B0 control: dead DISPLAY -> exit $rc 'not verifiably live' (10-20 failure reproduced)" || ko "B0 control: rc=$rc"
  [ -e /tmp/.X99-lock ] && echo "note: /tmp/.X99-lock already present before B1: $(cat /tmp/.X99-lock)"
  env -i HOME="$H" PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR="$W/xdg" ORCA_SERVE_RUNTIME=electron "$BIN" serve --port 6799 --json > >(red >"$W/b1.log") 2>&1 &
  bp=$!; mkdir -p "$W/xdg"; chmod 700 "$W/xdg"; ready=0
  for i in $(seq 1 60); do grep -q orca_server_ready "$W/b1.log" && { ready=1; break; }; kill -0 $bp 2>/dev/null || break; sleep 2; done
  [ $ready = 1 ] && ok "B1 fix: no DISPLAY -> orca_server_ready after ~$((i*2))s" || ko "B1 fix: not ready ($(tail -3 "$W/b1.log" | tr '\n' ' '))"
  xp=$(cat /tmp/.X99-lock 2>/dev/null | tr -d ' '); xa=$(ps -o args= -p "${xp:-0}" 2>/dev/null)
  echo "$xa" | grep -q 'Xvfb :99' && ok "B1 fix: Orca started its own Xvfb (pid $xp: $xa)" || ko "B1 fix: no Xvfb :99 (lock pid ${xp:-none})"
  curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:6799/ >"$W/b1.http"
  [ "$(cat "$W/b1.http")" = 200 ] && ok "B1 fix: local 6799 http 200" || ko "B1 fix: local 6799 http $(cat "$W/b1.http")"
  pkill -TERM -f "out/cli/index.js serve --port 6799" ; sleep 8; pkill -KILL -f "serve-port 6799|serve --port 6799" 2>/dev/null; sleep 2
  if [ -z "$xp" ]; then ko "B1 cleanup: no Xvfb pid to check"
  elif kill -0 "$xp" 2>/dev/null; then ko "B1 cleanup: Xvfb $xp still alive -> killing"; kill "$xp"
  else ok "B1 cleanup: own Xvfb exited with serve"; fi
  pgrep -f 'serve --port 6799|serve-port 6799' >/dev/null && ko "B1 cleanup: test serve still running" || ok "B1 cleanup: test serve gone"
  if [ -f /.dockerenv ] || [ -n "${E2E_THROWAWAY:-}" ]; then
    SL=/home/box/.local/state/orca-remote/serve.log; rm -f "$SL"; [ -e /tmp/.X11-unix/X4 ] && echo "note: an X server is on :4"
    xvfbs(){ pgrep -x Xvfb | tr '\n' ' '; }
    SD=/home/box/.local/state/orca-remote/serve-display; http(){ curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:6768/; }
    # bstart EXPECTED CMD [ENV...]: run `<script> CMD` (start|restart) with ENV, expect serve-loop's first line to say display=EXPECTED
    bstart(){ local exp=$1 cmd=$2 line; shift 2; rm -f "$SL"; env "$@" "$S" "$cmd" >>"$W/bstart.out" 2>&1
      for _ in $(seq 1 20); do grep -q 'starting orca-ide serve' "$SL" 2>/dev/null && break; sleep 1; done
      line=$(grep -m 1 'starting orca-ide serve' "$SL" 2>/dev/null)
      case $line in *"display=$exp)"*) ok "B-start $cmd ${*:-(no env)}, file '$(cat "$SD" 2>/dev/null)': display=$exp";;
        *) ko "B-start $cmd ${*:-(no env)}, file '$(cat "$SD" 2>/dev/null)': expected display=$exp, got: ${line:-no start line}";; esac
      "$S" stop >>"$W/bstart.out" 2>&1; sleep 8; pkill -KILL -f 'serve --port 6768|serve-port 6768' 2>/dev/null; sleep 1; }
    mkdir -p "$(dirname "$SD")"; echo :77 >"$SD"
    bstart :77 restart; bstart :78 start ORCA_SERVE_DISPLAY=:78; rm -f "$SD"; bstart own start
    x=$(xvfbs); [ -z "$x" ] && ok "B-start stop: no Xvfb left" || { ko "B-start stop: Xvfb left: $x"; kill $x; }
    DISPLAY=:4 setsid "$S" serve-loop >"$W/bloop.out" 2>&1 & lp=$!; ready=0
    for i in $(seq 1 90); do grep -q orca_server_ready "$SL" 2>/dev/null && { ready=1; break; }; sleep 2; done
    [ $ready = 1 ] && ok "B-loop: serve-loop with dead caller DISPLAY=:4 -> orca_server_ready after ~$((i*2))s" \
      || ko "B-loop: no orca_server_ready in 180s ($(grep -c 'not verifiably live' "$SL" 2>/dev/null) x 'not verifiably live', $(grep -c 'orca-ide serve exited' "$SL" 2>/dev/null) serve exits)"
    if [ $ready = 1 ]; then
      xp=$(xvfbs); xa=$(ps -o args= -p "$(echo $xp | cut -d' ' -f1)" 2>/dev/null)
      [ "$(echo $xp | wc -w)" = 1 ] && echo "$xa" | grep -q 'Xvfb :99' && ok "B-loop: one own Xvfb ($xp: $xa)" || ko "B-loop: Xvfb pids '$xp' ($xa)"
      h=$(http); [ "$h" = 200 ] && ok "B-loop: local 6768 http 200" || ko "B-loop: local 6768 http $h"
      n0=$(grep -c orca_server_ready "$SL"); pkill -TERM -f 'out/cli/index.js serve --port 6768'; ready=0
      for i in $(seq 1 90); do [ "$(grep -c orca_server_ready "$SL")" -gt "$n0" ] && { ready=1; break; }; sleep 2; done
      [ $ready = 1 ] && ok "B-loop restart: serve killed -> serve-loop brought it back, ready after ~$((i*2))s" || ko "B-loop restart: not ready again in 180s ($(tail -2 "$SL" | tr '\n' ' ' | cut -c1-200))"
      h=$(http); [ "$h" = 200 ] && ok "B-loop restart: local 6768 http 200" || ko "B-loop restart: local 6768 http $h"
      x2=$(xvfbs); kill -0 "$(echo $xp | cut -d' ' -f1)" 2>/dev/null && ko "B-loop restart: old Xvfb $xp still alive (now: $x2)" || ok "B-loop restart: old Xvfb $xp gone"
      [ "$(echo $x2 | wc -w)" = 1 ] && ok "B-loop restart: exactly one Xvfb ($x2)" || ko "B-loop restart: Xvfb pids '$x2'"
    fi
    kill -TERM -- -"$lp" 2>/dev/null; pkill -TERM -f 'out/cli/index.js serve --port 6768'; sleep 8
    pkill -KILL -f 'serve --port 6768|serve-port 6768' 2>/dev/null; sleep 2; echo "B-loop leftovers after stop: Xvfb '$(xvfbs)'"
    cp "$SL" "$W/bloop-serve.log" 2>/dev/null
  else echo "B-loop: not run (uses orca-remote's production paths; only in a throwaway container)"; fi
  [ -n "${E2E_ARTIFACTS:-}" ] && cp "$W"/b0.log "$W"/b1.log "$W"/bloop-serve.log "$W"/bloop.out "$W"/bstart.out "$E2E_ARTIFACTS/" 2>/dev/null
fi
echo "artifacts: $W"; echo "RESULT pass=$pass fail=$fail"; [ $fail = 0 ]
