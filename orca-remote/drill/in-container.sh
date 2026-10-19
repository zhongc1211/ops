#!/bin/bash
# in-container.sh LABEL WATCHDOG_SCRIPT OUT_DIR [SCENARIO...]
# Runs the drill scenarios (FAILURE-MODES.md) against one watchdog.sh inside the drill container and writes
# OUT_DIR/results.tsv (label, scenario, check, PASS/FAIL, detail) plus each scenario's raw files under OUT_DIR/<scenario>/.
# Stand-ins: cloudflared, orca-remote, Orca's 6768, the public URL and the uptime clock (see world.py, fake-bin/).
# A guest stall is a real SIGSTOP of the watchdog (wall clock and uptime keep running, as on 10-19);
# a VM pause is SIGSTOP plus a frozen uptime file.
set -u
LABEL=$1; SCRIPT=$2; OUT=$3; shift 3
SCEN=${*:-S1 S2 S3 S4 S5 S5b S6 S6b}
FB=/drill-src/drill/fake-bin; LP=16768; PP=18443
mkdir -p "$OUT"; RES=$OUT/results.tsv; : >"$RES"
# Same timing for pre and post. Production defaults are in watchdog.sh; drill values are scaled down (INT 45 -> 5).
export WATCHDOG_INT=5 WATCHDOG_MINGAP=40 WATCHDOG_MAXGAP=320 WATCHDOG_GRACE=20 WATCHDOG_STALL_SLACK=10 WATCHDOG_STALL_GRACE=30 \
  WATCHDOG_CF_FRESH=15 WATCHDOG_PSI_MAX=10 WATCHDOG_DEFER_MAX=30 \
  WATCHDOG_LOCAL_URL=http://127.0.0.1:$LP/ WATCHDOG_PUBLIC_URL=http://127.0.0.1:$PP/ WATCHDOG_SESSION=orca-remote-drill \
  ORCA_REMOTE_BIN=$FB/orca-remote
PSI_LOW='some avg10=0.00 avg60=0.00 avg300=0.00 total=0
full avg10=0.00 avg60=0.00 avg300=0.00 total=0'
PSI_HIGH='some avg10=90.47 avg60=80.00 avg300=40.00 total=0
full avg10=69.74 avg60=60.00 avg300=30.00 total=0'

now(){ date +%s; }
note(){ echo "[$(date '+%T')] $LABEL $S: $*"; }
check(){ # check NAME CONDITION_EXIT_CODE DETAIL
  local r=FAIL; [ "$2" = 0 ] && r=PASS
  printf '%s\t%s\t%s\t%s\t%s\n' "$LABEL" "$S" "$1" "$r" "$3" >>"$RES"; note "$r $1 ($3)"; }

setup(){
  S=$1; W=/run/drill/$LABEL/$S; rm -rf "$W"; mkdir -p "$W/app/resources/app.asar.unpacked/out/cli" "$W/app/resources/bin"
  touch "$W/app/resources/app.asar.unpacked/out/cli/index.js" "$W/app/chrome-sandbox" "$W/cf.yml" "$W/tunnel.log" "$W/cf_events" "$W/restarts"
  printf '#!/bin/sh\n' >"$W/app/resources/bin/orca-ide"; chmod +x "$W/app/resources/bin/orca-ide"
  echo ok >"$W/orca_mode"; echo "$PSI_LOW" >"$W/psi"
  export DRILL_W=$W ORCA_APP_DIR=$W/app WATCHDOG_LOG=$W/watchdog.log WATCHDOG_STATE=$W/watchdog.state WATCHDOG_TUNNEL_LOG=$W/tunnel.log \
    WATCHDOG_UPTIME_FILE=$W/uptime WATCHDOG_PSI_MEM=$W/psi WATCHDOG_LOCK=$W/lock WATCHDOG_PBODY=$W/public-body \
    WATCHDOG_CF_MATCH="cloudflared tunnel --config $W/cf.yml"
  python3 /drill-src/drill/world.py "$W" $LP $PP & WORLD=$!
  for _ in $(seq 50); do [ -s "$W/uptime" ] && curl -s -o /dev/null -m 1 "http://127.0.0.1:$LP/" && break; sleep 0.2; done
  "$FB/orca-remote" start >/dev/null
  setsid bash "$SCRIPT" </dev/null >>"$W/watchdog.stdout" 2>&1 &
  for _ in $(seq 50); do WD=$(pgrep -f "^bash $SCRIPT" | head -1); [ -n "$WD" ] && break; sleep 0.1; done
  for _ in $(seq 100); do [ "$(pub)" = 200 ] && break; sleep 0.2; done
  note "world up (watchdog pid $WD, public $(pub))"; T_START=$(now)
}
teardown(){
  kill -CONT -- "-$WD" 2>/dev/null; kill -- "-$WD" 2>/dev/null; "$FB/orca-remote" stop >/dev/null 2>&1; kill "$WORLD" 2>/dev/null
  sleep 1; pkill -f "cloudflared tunnel --config $W/cf.yml" 2>/dev/null; wait 2>/dev/null
  mkdir -p "$OUT/$S"; cp "$W"/{watchdog.log,cf_events,restarts,tunnel.log} "$OUT/$S/" 2>/dev/null
  [ -f "$W/watchdog.state" ] && cp "$W/watchdog.state" "$OUT/$S/watchdog.state.final"
  cp "$W"/state-* "$OUT/$S/" 2>/dev/null; cp "$W/watchdog.stdout" "$OUT/$S/" 2>/dev/null; true
}
pub(){ curl -s -o /dev/null -w '%{http_code}' -m 3 "http://127.0.0.1:$PP/"; }
cf_starts_after(){ awk -v t="$1" '$2=="start" && $1>t' "$W/cf_events" | wc -l; }
first_cf_start_after(){ awk -v t="$1" '$2=="start" && $1>t {print $1; exit}' "$W/cf_events"; }
restarts_after(){ awk -v t="$1" '$1>t' "$W/restarts" | wc -l; }
wait_log(){ # wait_log REGEX TIMEOUT -> 0 when a line matching REGEX appears after T_MARK
  local end=$(( $(now)+$2 )); while [ "$(now)" -lt "$end" ]; do
    awk -v from="$LOG_MARK" 'NR>from' "$W/watchdog.log" 2>/dev/null | grep -qE "$1" && return 0; sleep 0.2; done; return 1; }
mark_log(){ LOG_MARK=$(wc -l <"$W/watchdog.log" 2>/dev/null || echo 0); }
snap_state(){ cp "$W/watchdog.state" "$W/state-$1" 2>/dev/null || echo "missing" >"$W/state-$1"; }
state_is(){ grep -qx "state=$2" "$W/state-$1"; }
register(){ printf '{"level":"info","event":0,"connIndex":0,"protocol":"http2","time":"%s","message":"Registered tunnel connection"}\n' "$(date -u +%FT%TZ)" >>"$W/tunnel.log"; }
# Wait until the watchdog is inside its local probe: make 6768 slow (8s) so curl-local is long enough to catch.
wait_in_curl_local(){ echo slow >"$W/orca_mode"; for _ in $(seq 150); do pgrep -P "$WD" -f "curl.*:$LP/" >/dev/null && { sleep 0.5; return 0; }; sleep 0.1; done; return 1; }
wait_in_sleep(){ for _ in $(seq 150); do pgrep -P "$WD" -x sleep >/dev/null && return 0; sleep 0.1; done; return 1; }

# S1 (A1 A2 A3 A6): stale strike 1 -> box freezes inside curl-local for 40s with the tunnel down ->
#   cloudflared re-registers at the end of the freeze, public stays 530 for 6 more seconds (13:02 -> 13:22 on 10-19).
S1(){ setup S1; sleep 12
  touch "$W/cf_stale"; mark_log; wait_log 'strike 1' 20 || note "no strike 1 seen"
  wait_in_curl_local || note "did not catch curl-local"; T0=$(now)
  kill -STOP "$WD"; note "watchdog frozen in curl-local (curl itself keeps running)"; echo ok >"$W/orca_mode"; sleep 39
  register; sleep 1; kill -CONT "$WD"; T1=$(now); note "unfrozen; cloudflared re-registered 1s ago, public 530 for 6s more"
  ( sleep 6; rm -f "$W/cf_stale" ) & sleep 3; snap_state after-freeze; sleep 37
  check "A1/A2 cloudflared not killed after the freeze" $([ "$(cf_starts_after "$T0")" = 0 ]; echo $?) "cloudflared restarts after freeze: $(cf_starts_after "$T0")"
  check "Orca not restarted" $([ "$(restarts_after "$T_START")" = 0 ]; echo $?) "orca restarts: $(restarts_after "$T_START")"
  check "public 200 at end" $([ "$(pub)" = 200 ]; echo $?) "public $(pub)"
  check "A6 state file says stalled right after the freeze" $(state_is after-freeze stalled; echo $?) "$(tr '\n' ' ' <"$W/state-after-freeze" | cut -c1-80)"
  teardown; }

# S2 (A4): box freezes 40s while the watchdog sleeps (guest clock keeps running); tunnel connections drop during it;
#   cloudflared re-registers 3s after the freeze, public 200 at +6s (13:44 -> 13:49 on 10-19).
S2(){ setup S2; sleep 12
  wait_in_sleep; T0=$(now); touch "$W/cf_stale"; kill -STOP -- "-$WD"; note "watchdog frozen in sleep (guest clock runs)"; sleep 40
  kill -CONT -- "-$WD"; T1=$(now); ( sleep 3; register; sleep 3; rm -f "$W/cf_stale" ) & sleep 2; snap_state after-freeze; sleep 40
  check "A4 cloudflared not killed after an in-guest freeze" $([ "$(cf_starts_after "$T0")" = 0 ]; echo $?) "cloudflared restarts after freeze: $(cf_starts_after "$T0")"
  check "Orca not restarted" $([ "$(restarts_after "$T_START")" = 0 ]; echo $?) "orca restarts: $(restarts_after "$T_START")"
  check "public 200 at end" $([ "$(pub)" = 200 ]; echo $?) "public $(pub)"
  check "A6 state file says stalled right after the freeze" $(state_is after-freeze stalled; echo $?) "$(tr '\n' ' ' <"$W/state-after-freeze" | cut -c1-80)"
  teardown; }

# S3 (B1): real VM pause (guest clock stopped 40s); tunnel stuck on dead connections (CF 1033) and does not heal itself (13:55).
S3(){ setup S3; sleep 12
  wait_in_sleep; T0=$(now); touch "$W/cf_stale" "$W/paused"; kill -STOP -- "-$WD"; note "VM pause: watchdog frozen, uptime frozen"; sleep 40
  rm -f "$W/paused"; sleep 0.5; kill -CONT -- "-$WD"; T1=$(now); sleep 2; snap_state after-pause
  for _ in $(seq 60); do [ "$(pub)" = 200 ] && break; sleep 1; done; T200=$(now); sleep 10
  fc=$(first_cf_start_after "$T1")
  check "B1 cloudflared restarted within 15s after the pause" $([ -n "$fc" ] && [ $((fc-T1)) -le 15 ]; echo $?) "first cloudflared start $([ -n "$fc" ] && echo "+$((fc-T1))s" || echo none) after resume"
  check "B1 public 200 within 60s" $([ $((T200-T1)) -lt 60 ] && [ "$(pub)" = 200 ]; echo $?) "public 200 after $((T200-T1))s"
  check "Orca not restarted" $([ "$(restarts_after "$T_START")" = 0 ]; echo $?) "orca restarts: $(restarts_after "$T_START")"
  check "A6 state file says paused right after the pause" $(state_is after-pause paused; echo $?) "$(tr '\n' ' ' <"$W/state-after-pause" | cut -c1-80)"
  teardown; }

# S4 (A5): freeze inside curl-local 40s; afterwards Orca is still recovering (local 000) for 45s and memory pressure is high
#   (PSI full 70%), then Orca is fine again by itself (11:54 -> 11:56:45 on 10-19).
S4(){ setup S4; sleep 12
  wait_in_curl_local; T0=$(now); kill -STOP "$WD"; echo down >"$W/orca_mode"; echo "$PSI_HIGH" >"$W/psi"; note "frozen in curl-local; Orca down, PSI high"; sleep 40
  kill -CONT "$WD"; T1=$(now); sleep 45; echo ok >"$W/orca_mode"; echo "$PSI_LOW" >"$W/psi"; note "Orca back by itself"; sleep 20
  check "A5 no full Orca restart while it recovers after a freeze" $([ "$(restarts_after "$T_START")" = 0 ]; echo $?) "orca restarts: $(restarts_after "$T_START")"
  check "public 200 at end" $([ "$(pub)" = 200 ]; echo $?) "public $(pub)"
  teardown; }

# S5 (B2 B4 B6): Orca really dead: 6768 accepts but never answers (curl hangs until -m), restarts do not fix it. PSI low.
S5(){ setup S5; sleep 10
  echo hang >"$W/orca_mode"; cp "$W/orca_mode" "$W/orca_mode_after_restart"; T0=$(now); note "Orca hung for good"; sleep 220
  mapfile -t R < <(awk -v t="$T0" '$1>t {print $1}' "$W/restarts")
  check "B2 first full restart within 60s" $([ ${#R[@]} -ge 1 ] && [ $((R[0]-T0)) -le 60 ]; echo $?) "restarts at: $(for r in "${R[@]}"; do printf '+%ss ' $((r-T0)); done)"
  gaps=""; for i in $(seq 1 $((${#R[@]}-1))); do gaps+="$((R[i]-R[i-1]))s "; done
  check "B4 gap before 3rd restart >= 2x MINGAP (backoff doubles)" $([ ${#R[@]} -ge 3 ] && [ $((R[2]-R[1])) -ge $((2*WATCHDOG_MINGAP)) ] || { [ ${#R[@]} -eq 2 ] && [ $((T0+220-R[1])) -ge $((2*WATCHDOG_MINGAP)) ]; }; echo $?) "restart gaps: ${gaps:-none}"
  mx=$(grep -E 'unhealthy local=000|-> restart|grace|deferred|backoff' "$W/watchdog.log" | awk -v t0="$(date -d @"$T0" '+%F %T')" '{ts=substr($0,2,19)} ts>=t0 {cmd="date -d \""ts"\" +%s"; cmd|getline e; close(cmd); if(p) {d=e-p; if(d>m) m=d}; p=e} END{print m+0}')
  check "B6 watchdog keeps looping while 6768 hangs (max log gap <= 60s)" $([ "$mx" -le 60 ]; echo $?) "max gap between watchdog lines: ${mx}s"
  teardown; }

# S5b (B3): Orca really dead and memory pressure stays high: deferral must end, restart must still happen.
S5b(){ setup S5b; sleep 10
  echo hang >"$W/orca_mode"; cp "$W/orca_mode" "$W/orca_mode_after_restart"; echo "$PSI_HIGH" >"$W/psi"; T0=$(now); note "Orca hung, PSI high for good"; sleep 100
  n=$(restarts_after "$T0"); fr=$(awk -v t="$T0" '$1>t {print $1-t; exit}' "$W/restarts")
  check "B3 full restart still happens under constant memory pressure (<=100s)" $([ "$n" -ge 1 ]; echo $?) "restarts: $n, first at +${fr:-none}s"
  teardown; }

# S6 (A2): no freeze. Stale strike 1, then cloudflared re-registers by itself but public stays 530 for 12 more seconds.
S6(){ setup S6; sleep 18
  touch "$W/cf_stale"; mark_log; wait_log 'strike 1' 20; register; T0=$(now); note "cloudflared re-registered after strike 1"
  ( sleep 12; rm -f "$W/cf_stale" ) & sleep 35
  check "A2 freshly re-registered cloudflared not killed" $([ "$(cf_starts_after "$T0")" = 0 ]; echo $?) "cloudflared restarts: $(cf_starts_after "$T0")"
  check "public 200 at end" $([ "$(pub)" = 200 ]; echo $?) "public $(pub)"
  teardown; }

# S6b (B5): no freeze, cloudflared really broken (stale, never re-registers): tunnel-only restart, Orca untouched.
S6b(){ setup S6b; sleep 18
  T0=$(now); touch "$W/cf_stale"; note "tunnel stale for good"; for _ in $(seq 60); do [ "$(cf_starts_after "$T0")" -ge 1 ] && break; sleep 1; done; sleep 15
  fc=$(first_cf_start_after "$T0")
  check "B5 cloudflared restarted within 40s" $([ -n "$fc" ] && [ $((fc-T0)) -le 40 ]; echo $?) "first cloudflared start $([ -n "$fc" ] && echo "+$((fc-T0))s" || echo none)"
  check "Orca not restarted" $([ "$(restarts_after "$T_START")" = 0 ]; echo $?) "orca restarts: $(restarts_after "$T_START")"
  check "public 200 at end" $([ "$(pub)" = 200 ]; echo $?) "public $(pub)"
  teardown; }

echo "drill $LABEL: $(sha256sum "$SCRIPT" | cut -c1-12) scenarios: $SCEN"
for s in $SCEN; do $s; done
echo "drill $LABEL done: $(grep -c $'\tPASS\t' "$RES") PASS, $(grep -c $'\tFAIL\t' "$RES") FAIL"
