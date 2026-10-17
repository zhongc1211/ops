#!/bin/bash
# everos-mcp-<N>: start everos-mcp for one project (EverOS MCP wiring standard v2, launcher v2.1). Linux and macOS bash 3.2.
# All projects use this file byte for byte; only the N= line differs.
# Key, scope and endpoints come only from ~/.config/everos/$N.env (mode 600); nothing secret is printed.
# Scope is locked to that file: EVEROS_* values inherited from the caller are dropped, unless
# EVEROS_ALLOW_SCOPE_OVERRIDE=1 (isolation tests only) lets the caller's app/project/sender/user win.
# Endpoint: the env file must name the public URL as EVEROS_BASE_URL. At start the launcher probes
# $EVEROS_TAILNET_URL/health once (3s; default http://100.64.0.5, site nginx on the tailnet, 400s, no
# Cloudflare; the env file may set another http://100.64-127.x.y address, or "off"). If the probe connects,
# everos-mcp uses the tailnet URL; only if it cannot connect does it use the public URL. Each start
# appends endpoint=tailnet|public to ~/.local/state/everos-mcp/endpoint.log; public also goes to stderr.
# Every request carries Host: everos.deepvision.sg, so routing never depends on the Host-less tailnet block.
# Read-only: the server exposes only recall_agent_experience, search_memory and list_memories; the
# write tools and get_profile are removed before it starts (enabling writes needs a new template).
# EVEROS_MCP_SEARCH_METHOD (default keyword): everos-mcp 0.1.1 hard-codes method=hybrid, which the
# server rejects with 422 while embedding is off. Set it to "hybrid" for the stock behaviour.
set -euo pipefail
N=<N>
ENV_FILE="$HOME/.config/everos/$N.env"
BASE_URL_EXPECTED="https://everos.deepvision.sg"
TAILNET_DEFAULT="http://100.64.0.5"
TAILNET_RE='^http://100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}(:[0-9]{1,5})?$'
[ -r "$ENV_FILE" ] || { echo "everos-mcp-$N: $ENV_FILE missing" >&2; exit 1; }
pre_app="${EVEROS_APP_ID:-}"; pre_project="${EVEROS_PROJECT_ID:-}"
pre_sender="${EVEROS_ASSISTANT_SENDER_ID:-}"; pre_user="${EVEROS_USER_ID:-}"
unset EVEROS_BASE_URL EVER_OS_BASE_URL EVEROS_API_KEY EVEROS_APP_ID EVEROS_PROJECT_ID \
  EVEROS_ASSISTANT_SENDER_ID EVEROS_USER_ID EVEROS_SESSION_ID EVEROS_TAILNET_URL EVEROS_MCP_UPSTREAM_HOST
set -a; . "$ENV_FILE"; set +a
if [ "${EVEROS_ALLOW_SCOPE_OVERRIDE:-0}" = 1 ]; then
  [ -n "$pre_app" ] && export EVEROS_APP_ID="$pre_app"
  [ -n "$pre_project" ] && export EVEROS_PROJECT_ID="$pre_project"
  [ -n "$pre_sender" ] && export EVEROS_ASSISTANT_SENDER_ID="$pre_sender"
  [ -n "$pre_user" ] && export EVEROS_USER_ID="$pre_user"
fi
# Without these, everos-mcp would fall back to api.evermind.ai (sending our key there) or to the
# "default" scope, both silently.
[ "${EVEROS_BASE_URL:-}" = "$BASE_URL_EXPECTED" ] || { echo "everos-mcp-$N: EVEROS_BASE_URL must be $BASE_URL_EXPECTED" >&2; exit 1; }
[ -n "${EVEROS_API_KEY:-}" ] && [ -n "${EVEROS_APP_ID:-}" ] && [ -n "${EVEROS_PROJECT_ID:-}" ] &&
  [ -n "${EVEROS_ASSISTANT_SENDER_ID:-}" ] && [ -n "${EVEROS_USER_ID:-}" ] ||
  { echo "everos-mcp-$N: $ENV_FILE must set EVEROS_API_KEY, _APP_ID, _PROJECT_ID, _ASSISTANT_SENDER_ID, _USER_ID" >&2; exit 1; }
TAILNET_URL="${EVEROS_TAILNET_URL:-$TAILNET_DEFAULT}"
unset EVEROS_TAILNET_URL
[ "$TAILNET_URL" = off ] || [[ "$TAILNET_URL" =~ $TAILNET_RE ]] ||
  { echo "everos-mcp-$N: EVEROS_TAILNET_URL must be off or http://100.64-127.x.y[:port]" >&2; exit 1; }
HOST_HEADER="${BASE_URL_EXPECTED#https://}"
endpoint=public; probe="off"
if [ "$TAILNET_URL" != off ]; then
  # The probe sends no key. Connected = any HTTP answer, or a timeout after the TCP connect completed.
  out=$(curl -s -o /dev/null -w '%{http_code} %{time_connect}' --connect-timeout 3 --max-time 3 \
    -H "Host: $HOST_HEADER" "$TAILNET_URL/health" 2>/dev/null) && rc=0 || rc=$?
  code="${out%% *}"; tc="${out##* }"
  if [ "${code:-000}" != 000 ] || awk -v t="${tc:-0}" 'BEGIN { exit !(t > 0) }'; then
    endpoint=tailnet; export EVEROS_BASE_URL="$TAILNET_URL"
  fi
  probe="health=${code:-000} curl_rc=$rc connect=${tc:-0}s"
fi
[ "$endpoint" = public ] && echo "everos-mcp-$N: endpoint=public ($TAILNET_URL $probe), using $BASE_URL_EXPECTED" >&2
{ d="${XDG_STATE_HOME:-$HOME/.local/state}/everos-mcp"; mkdir -p "$d" &&
  printf '%s everos-mcp-%s endpoint=%s url=%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$N" "$endpoint" \
    "$EVEROS_BASE_URL" "$probe" >> "$d/endpoint.log"; } 2>/dev/null || true
export EVEROS_MCP_UPSTREAM_HOST="$HOST_HEADER"
export EVEROS_MCP_SEARCH_METHOD="${EVEROS_MCP_SEARCH_METHOD:-keyword}"
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
exec uvx --quiet --from 'everos-mcp==0.1.1' python -c '
import os, sys
from everos_mcp import client, server
m = os.environ["EVEROS_MCP_SEARCH_METHOD"]
if m != "hybrid":
    _orig = client.EverOSClient.search
    async def search(self, query, *, method="hybrid", **kw):
        return await _orig(self, query, method=m, **kw)
    client.EverOSClient.search = search
host = os.environ["EVEROS_MCP_UPSTREAM_HOST"]
_init = client.EverOSClient.__init__
def init(self, *a, **kw):
    _init(self, *a, **kw)
    self._headers["Host"] = host
client.EverOSClient.__init__ = init
keep = {"recall_agent_experience", "search_memory", "list_memories"}
for t in [t.name for t in server.mcp._tool_manager.list_tools()]:
    if t not in keep:
        server.mcp.remove_tool(t)
if {t.name for t in server.mcp._tool_manager.list_tools()} != keep:
    sys.exit("everos-mcp: read-only tool set mismatch, refusing to start")
server.main()
'
