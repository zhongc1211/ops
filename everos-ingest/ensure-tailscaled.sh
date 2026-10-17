#!/bin/bash
# Keep the box on the tailnet and sshd reachable for the iMac collector. Never uses or creates keys.
#
# Steps (all idempotent, safe every 15 min):
#   1. /etc/hosts entry for headscale
#   2. tailscale/tailscaled missing -> reinstall from the official Tailscale apt repo (re-add repo + key if missing)
#   3. no tailscaled state (/var/lib/tailscale/tailscaled.state) or backend NeedsLogin
#        -> log "NEEDS RE-REGISTER" and exit 2. Never tries to auth; a human registers the node on headscale.
#   4. tailscaled not running -> start; health = real dataplane ping to site/imac; restart once if unhealthy
#   5. openssh-server missing -> reinstall; sshd not running or not listening on $TS_IP:22 -> ensure-sshd.sh
#
# Exit codes: 0 healthy | 2 NEEDS RE-REGISTER | 3 package install failed | 4 tailnet still offline | 5 sshd not up
LOG=/tmp/ensure-tailscaled.log
SOCK=/var/run/tailscale/tailscaled.sock
STATE=/var/lib/tailscale/tailscaled.state
TS_IP=100.64.0.6
PATH=$PATH:/usr/sbin:/sbin
HERE=$(cd "$(dirname "$0")" && pwd)
ts(){ echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

apt_install(){ # $@ = packages
  sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 install -y -qq "$@" >>"$LOG" 2>&1
}

ensure_tailscale_pkg(){
  # tailscaled lives in /usr/sbin, which is not on the box user's PATH; check the package paths directly.
  [ -x /usr/bin/tailscale ] && [ -x /usr/sbin/tailscaled ] && return 0
  ts "tailscale binaries missing, reinstalling from pkgs.tailscale.com"
  local codename; codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")
  local key=/usr/share/keyrings/tailscale-archive-keyring.gpg list=/etc/apt/sources.list.d/tailscale.list
  if [ ! -s "$key" ]; then
    sudo mkdir -p -m 0755 /usr/share/keyrings
    curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" | sudo tee "$key" >/dev/null || { ts "ERROR fetching tailscale apt key"; return 1; }
    ts "re-added tailscale apt key"
  fi
  if [ ! -s "$list" ]; then
    curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" | sudo tee "$list" >/dev/null || { ts "ERROR fetching tailscale apt list"; return 1; }
    ts "re-added tailscale apt repo"
  fi
  sudo apt-get -o DPkg::Lock::Timeout=60 update -qq >>"$LOG" 2>&1
  apt_install tailscale || { ts "ERROR apt install tailscale failed"; return 1; }
  ts "installed tailscale $(tailscale version | head -1)"
}

ensure_sshd_pkg(){
  [ -x /usr/sbin/sshd ] && return 0
  ts "openssh-server missing, reinstalling"
  apt_install openssh-server || { ts "ERROR apt install openssh-server failed"; return 1; }
  ts "installed openssh-server"
}

grep -q 'headscale.deepvision.sg' /etc/hosts || { echo '157.230.194.108 headscale.deepvision.sg' | sudo tee -a /etc/hosts >/dev/null; ts "restored /etc/hosts entry"; }

ensure_tailscale_pkg || exit 3
ensure_sshd_pkg || exit 3

if ! sudo test -s "$STATE"; then
  ts "NEEDS RE-REGISTER: $STATE missing (box state was reset). Not attempting auth; register the box node on headscale by hand."
  exit 2
fi

start(){ sudo mkdir -p /var/run/tailscale; sudo sh -c "setsid tailscaled --state=$STATE --socket=$SOCK --port=41641 >>/tmp/tailscaled.log 2>&1 </dev/null &"; sleep 6; }
backend(){ timeout 10 tailscale status --json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("BackendState",""))' 2>/dev/null; }
# Self.Online from headscale is unreliable for this node (reports false while healthy),
# so judge health by the data plane: a real tailscale ping to site or imac.
running(){ [ "$(backend)" = Running ]; }
dataplane(){ for p in 100.64.0.5 100.64.0.4; do timeout 12 tailscale ping --c 2 --timeout 4s "$p" 2>/dev/null | grep -q '^pong' && return 0; done; return 1; }
online(){ running && dataplane; }
needs_login(){ [ "$(backend)" = NeedsLogin ] && { ts "NEEDS RE-REGISTER: tailscaled backend is NeedsLogin. Not attempting auth."; return 0; }; return 1; }

if ! pgrep -x tailscaled >/dev/null; then ts "tailscaled not running, starting"; start; fi
needs_login && exit 2
if ! online; then
  sleep 15   # give control a moment after a wake
  if ! online; then
    needs_login && exit 2
    ts "not online, restarting tailscaled"
    sudo pkill -x tailscaled; sleep 2; start
    needs_login && exit 2
    # Node is already registered (state exists): this only reconnects, no key involved.
    sudo timeout 40 tailscale up --login-server=https://headscale.deepvision.sg:8443 --hostname=box --accept-dns=false --timeout=30s >>"$LOG" 2>&1
    if online; then ts "online after restart"; else ts "STILL OFFLINE after restart"; exit 4; fi
  fi
fi

sshd_ok(){ pgrep -x sshd >/dev/null && ss -tln 2>/dev/null | grep -q "${TS_IP}:22 "; }
if ! sshd_ok; then
  ts "sshd not running/listening on ${TS_IP}:22, running ensure-sshd.sh"
  "$HERE/ensure-sshd.sh" >>"$LOG" 2>&1
  sshd_ok && ts "sshd up on ${TS_IP}:22" || { ts "ERROR sshd still not listening on ${TS_IP}:22"; exit 5; }
fi
exit 0
