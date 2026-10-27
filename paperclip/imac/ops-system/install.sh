#!/bin/bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
set -a
source "$HERE/../config.sh"
set +a
exec "$TIMEOUT" 840 "$PY" "$HERE/install.py" "$@"
