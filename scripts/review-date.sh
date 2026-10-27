#!/bin/bash
# review-date.sh ago <hours> | next <YYYY-MM-DD>: SGT date arithmetic for the night reviews that runs on macOS
# (bash 3.2, BSD date has no -d, iMac has no gdate) and Linux alike, so it uses python3 only.
#   ago <hours>  -> the SGT calendar date <hours> before now (e.g. ago 13 at 00:30 -> yesterday)
#   next <D>     -> the day after D (for UNTIL="<next>T00:00:00+08:00")
# REVIEW_NOW=<epoch seconds> replaces "now" (drills). SGT is a fixed +08:00, no DST, so no tz database is needed.
set -u
case "${1:-}" in
  ago)  [ -n "${2:-}" ] || { echo "usage: review-date.sh ago <hours>" >&2; exit 2; } ;;
  next) [ -n "${2:-}" ] || { echo "usage: review-date.sh next YYYY-MM-DD" >&2; exit 2; } ;;
  *) echo "usage: review-date.sh ago <hours> | next YYYY-MM-DD" >&2; exit 2 ;;
esac
exec python3 -I -c '
import sys, time, datetime as dt
sgt = dt.timezone(dt.timedelta(hours=8))
op, arg, now = sys.argv[1], sys.argv[2], sys.argv[3]
if op == "ago":
    t = (float(now) if now else time.time()) - float(arg) * 3600
    print(dt.datetime.fromtimestamp(t, sgt).strftime("%Y-%m-%d"))
else:
    print((dt.date.fromisoformat(arg) + dt.timedelta(days=1)).isoformat())
' "$1" "$2" "${REVIEW_NOW:-}"
