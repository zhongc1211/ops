#!/bin/bash
# heavy-lock.sh acquire|refresh|release|status <name> [--force]: one heavy job (a scheduled claude run) per machine at a time
# (PER-79, automations/migration-1020). Every precheck that starts claude runs `acquire <name>` first: exit 0 = got the lock,
# 1 = busy (skip this run; the next trigger inside the missed-run window retries), 2 = usage. The run releases it as its last
# step (`release <name>`, wrapped in notify-run so the release and the wake are one step); a lock older than
# HEAVY_LOCK_STALE_MIN (default 40) minutes is taken as dead and the next acquire takes it over. A long run calls
# `refresh <name>` between steps to restart the clock. release of a lock held under another name exits 1 unless --force.
# status: prints the holder, exit 0 = held, 1 = free.
# Lock = directory $HEAVY_LOCK_DIR (default ~/.orca-state/heavy.lock), created with mkdir (atomic on Linux and macOS);
# owner file inside: name, epoch, host, pid of the acquiring process. Breaking a stale lock goes through a second mkdir
# lock (<dir>.break) so two prechecks that both see it stale cannot remove each other's fresh lock.
# bash 3.2 compatible (macOS /bin/bash). Log: <dir>.log, one line per acquire / busy / stale break / release.
set -u
L=${HEAVY_LOCK_DIR:-$HOME/.orca-state/heavy.lock}; STALE=$(( ${HEAVY_LOCK_STALE_MIN:-40} * 60 ))
cmd=${1:-}; name=${2:-}; force=${3:-}
case "$cmd" in acquire|refresh|release|status) ;; *) echo "usage: heavy-lock.sh acquire|refresh|release|status <name> [--force]" >&2; exit 2;; esac
[ "$cmd" = status ] || [ -n "$name" ] || { echo "heavy-lock.sh: $cmd needs a name" >&2; exit 2; }
mkdir -p "$(dirname "$L")"
now=$(date +%s)
log(){ echo "$(date '+%F %T') $*" >> "$L.log"; }
owner(){ cat "$L/owner" 2>/dev/null; }                      # "name=<n> since=<epoch> host=<h> pid=<p>"
field(){ owner | tr ' ' '\n' | sed -n "s/^$1=//p"; }
since(){ s=$(field since); [ -n "$s" ] || s=$(perl -e 'print((stat shift)[9])' "$L" 2>/dev/null); echo "${s:-$now}"; }
take(){ mkdir "$L" 2>/dev/null || return 1; echo "name=$name since=$now host=$(hostname -s) pid=$PPID" > "$L/owner"; }

case "$cmd" in
acquire)
  if take; then log "acquire $name"; echo "heavy-lock: acquired by $name"; exit 0; fi
  age=$(( now - $(since) ))
  if [ "$age" -ge "$STALE" ] && mkdir "$L.break" 2>/dev/null; then
    # re-read under the break lock: the holder may have been replaced in between
    age=$(( now - $(since) )); held=$(owner)
    if [ "$age" -ge "$STALE" ]; then rm -rf "$L"; log "stale break ($held, ${age}s) by $name"; fi
    rmdir "$L.break"
    if take; then log "acquire $name (after stale break)"; echo "heavy-lock: stale lock ($held, ${age}s old) broken, acquired by $name"; exit 0; fi
  elif [ -d "$L.break" ] && [ $(( now - $(perl -e 'print((stat shift)[9])' "$L.break" 2>/dev/null || echo "$now") )) -gt 60 ]; then
    rmdir "$L.break" 2>/dev/null                                 # a breaker that died mid-way; the next acquire retries
  fi
  log "busy $name (held: $(owner), ${age}s)"; echo "heavy-lock: busy, held by $(field name) for ${age}s; $name skipped"; exit 1;;
refresh)
  [ "$(field name)" = "$name" ] || { echo "heavy-lock: $name does not hold the lock (holder: $(field name))" >&2; exit 1; }
  sed "s/since=[0-9]*/since=$now/" "$L/owner" > "$L/owner.new" && mv "$L/owner.new" "$L/owner"; echo "heavy-lock: refreshed by $name";;
release)
  [ -d "$L" ] || { echo "heavy-lock: already free"; exit 0; }
  if [ "$(field name)" != "$name" ] && [ "$force" != --force ]; then
    echo "heavy-lock: held by $(field name), not $name; not released" >&2; exit 1; fi
  rm -rf "$L"; log "release $name"; echo "heavy-lock: released by $name";;
status)
  [ -d "$L" ] || { echo "free"; exit 1; }
  age=$(( now - $(since) )); echo "held $(owner) age=${age}s$([ "$age" -ge "$STALE" ] && echo ' (stale)')";;
esac
