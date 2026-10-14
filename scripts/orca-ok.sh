#!/bin/bash
# orca-ok.sh <name> [provider]: agent calls this as its LAST step on success.
S=$HOME/.orca-state/runs; mkdir -p $S; date +%s > $S/$1.ok; echo "${2:-?} $(date '+%F %T %Z')" > $S/$1.ok.by; rm -f $HOME/orca-alerts/$1.flag; exit 0
