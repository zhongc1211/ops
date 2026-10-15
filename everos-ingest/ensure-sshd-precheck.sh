#!/bin/bash
# Always exit 1 after ensuring sshd (no model).
 /workspace/ops/everos-ingest/ensure-sshd.sh || true
exit 1
