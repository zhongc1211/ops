#!/bin/bash
# everos-mcp-<N>: start everos-mcp for one project (EverOS MCP wiring standard v2). Linux and macOS bash 3.2.
# Based on the shared v2 launcher; this copy adds the tailnet switch below (2026-10-17), so it is
# no longer byte-identical to the other projects' copies.
# Endpoint: the env file still has to name the public URL (checked below). At start the launcher
# probes the tailnet path's /health for 3s; on 200 everos-mcp is pointed at http://100.64.0.5
# (site nginx on the tailnet, 400s timeout, no Cloudflare), otherwise at the public URL.
# Key and scope come only from ~/.config/everos/$N.env (mode 600); nothing is printed.
# Scope is locked to that file: EVEROS_* values inherited from the caller are dropped, unless
# EVEROS_ALLOW_SCOPE_OVERRIDE=1 (isolation tests only) lets the caller's app/project/sender/user win.
# EVEROS_MCP_SEARCH_METHOD (default keyword): everos-mcp 0.1.1 hard-codes method=hybrid, which the
# server rejects with 422 while embedding is off. Set it to "hybrid" for the stock behaviour.
set -euo pipefail
N=xinyue
ENV_FILE="$HOME/.config/everos/$N.env"
BASE_URL_EXPECTED="https://everos.deepvision.sg"
TAILNET_URL="http://100.64.0.5"
[ -r "$ENV_FILE" ] || { echo "everos-mcp-$N: $ENV_FILE missing" >&2; exit 1; }
pre_app="${EVEROS_APP_ID:-}"; pre_project="${EVEROS_PROJECT_ID:-}"
pre_sender="${EVEROS_ASSISTANT_SENDER_ID:-}"; pre_user="${EVEROS_USER_ID:-}"
unset EVEROS_BASE_URL EVER_OS_BASE_URL EVEROS_API_KEY EVEROS_APP_ID EVEROS_PROJECT_ID \
  EVEROS_ASSISTANT_SENDER_ID EVEROS_USER_ID EVEROS_SESSION_ID
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
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H "Host: ${BASE_URL_EXPECTED#https://}" \
  "$TAILNET_URL/health" 2>/dev/null) || true
if [ "$code" = 200 ]; then
  export EVEROS_BASE_URL="$TAILNET_URL"
else
  echo "everos-mcp-$N: tailnet health ${code:-none}, using $BASE_URL_EXPECTED" >&2
fi
export EVEROS_MCP_SEARCH_METHOD="${EVEROS_MCP_SEARCH_METHOD:-keyword}"
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
exec uvx --quiet --from 'everos-mcp==0.1.1' python -c '
import os
from everos_mcp import client, server
m = os.environ["EVEROS_MCP_SEARCH_METHOD"]
if m != "hybrid":
    _orig = client.EverOSClient.search
    async def search(self, query, *, method="hybrid", **kw):
        return await _orig(self, query, method=m, **kw)
    client.EverOSClient.search = search
server.main()
'
