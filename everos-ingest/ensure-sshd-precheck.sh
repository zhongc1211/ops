#!/bin/bash
# Always exit 1 after ensuring tailscaled + sshd (no model).
/workspace/ops/everos-ingest/ensure-tailscaled.sh || true
/workspace/ops/everos-ingest/ensure-sshd.sh || true
exit 1
