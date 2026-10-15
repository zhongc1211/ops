#!/bin/bash
# Keep sshd listening on Tailscale IP so iMac can scp ingest files.
# Safe to run repeatedly. Exit 0 if listening; 1 if failed.
set -euo pipefail
TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
TS_IP=${TS_IP:-100.64.0.6}
CONF=/etc/ssh/sshd_config.d/everos-ingest.conf
if [ ! -f "$CONF" ]; then
  sudo tee "$CONF" >/dev/null <<CF
Port 22
ListenAddress ${TS_IP}
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers box
CF
fi
if ss -tlnp 2>/dev/null | grep -q "${TS_IP}:22"; then
  exit 0
fi
# not listening — start detached
sudo mkdir -p /var/run/sshd
# kill stale non-listening? only if no listener
if pgrep -x sshd >/dev/null 2>&1; then
  # already have sshd but not on TS IP — leave it; try start may fail
  true
fi
sudo setsid /usr/sbin/sshd
sleep 1
if ss -tlnp 2>/dev/null | grep -q ":22"; then
  exit 0
fi
echo "ensure-sshd: failed to bind :22" >&2
exit 1
