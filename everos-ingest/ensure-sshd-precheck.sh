#!/bin/bash
# Orca precheck for「ops · box tailscaled+sshd keep」. exit 1 = done, don't start the model.
# ensure-tailscaled.sh also runs ensure-sshd.sh when sshd is down. It needs a human for exit 2
# (NEEDS RE-REGISTER) and 3 (package install failed); pass those through so the run shows as failed.
/workspace/ops/everos-ingest/ensure-tailscaled.sh; rc=$?
case $rc in 2|3) exit $rc ;; esac
/workspace/ops/everos-ingest/ensure-sshd.sh || true
exit 1
