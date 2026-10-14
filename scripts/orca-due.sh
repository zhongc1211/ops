#!/bin/bash
# orca-due.sh <name>: called at end of a PRIMARY precheck that decided to run; records the run as due.
S=$HOME/.orca-state/runs; mkdir -p $S; date +%s > $S/$1.due; rm -f $S/$1.fb; exit 0
