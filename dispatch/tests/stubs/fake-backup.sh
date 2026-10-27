#!/bin/bash
# 假 backup.sh：测试时复制到 $HOME/ops-archive/per126-v5-backup-1021/<机器>/tools/backup.sh。
# FAKE_BACKUP_MODE：ok（默认，追加一行）、fail（退出 1）、noline（退出 0 但不追加）、wronglabel（追加的 label 不对）。
set -u
BASE=$(cd "$(dirname "$0")/.." && pwd)
LOG=$BASE/install-log.tsv
[ "$1" = --label ] || { echo "usage: $0 --label <step>" >&2; exit 2; }
label=$2
echo "fake backup.sh --label $label" >> "${FAKE_BACKUP_CALLS:-/dev/null}"
case "${FAKE_BACKUP_MODE:-ok}" in
  fail) echo "fake backup failed" >&2; exit 1 ;;
  noline) exit 0 ;;
  wronglabel) label=other ;;
esac
[ -f "$LOG" ] || printf 'time\tmachine\tlabel\tsnapshot_dir\tmanifest_sha256\trows\tcopied_files\tpath_only\tsymlink\tautomations\n' > "$LOG"
snap="$BASE/snapshots/20261021T120000-$label"
mkdir -p "$snap"
printf '%s\t%s\t%s\t%s\t%s\t1\t1\t0\t0\t0\n' "2026-10-21T12:00:00+0800" "$(basename "$BASE")" "$label" "$snap" \
  "0000000000000000000000000000000000000000000000000000000000000abc" >> "$LOG"
echo "snapshot=$snap manifest_sha256=...abc"
