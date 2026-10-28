#!/bin/bash
# S12 ② 从 MBA 读回 iMac 上 Paperclip 对 tailnet 露出了什么（只读，不带 bearer）。
# 用法（在 MBA 上）：readback-from-mba.sh
# iMac 的 tailnet 地址运行时取，屏幕上打码。
# Serve 开着时预期：触发路径不带 bearer 401；/、/api/health、/api/companies 不通（404 或连不上）。
# Serve 关着时预期：所有端口、所有路径都不通。
# 不用正确 bearer，也不读 iMac 上的密钥文件。
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/config.sh"

TS=$(command -v tailscale || echo /usr/local/bin/tailscale)
ip=$("${TS}" ip -4 imac 2>/dev/null | head -1)
[ -n "${ip}" ] || { echo "取不到 iMac 的 tailnet 地址" >&2; exit 1; }
mask() { sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<imac-tailnet-ip>/g'; }
code() { curl -s -o /dev/null -w '%{http_code}' -m 8 "$@" 2>/dev/null; }

date '+%F %T %z'
# 24 位十六进制的假 publicId：格式对得上 auth 白名单，但不是任何真实触发器。
fake=$(printf '0%.0s' $(seq 24))
for base in "http://${ip}:${SERVE_HTTP_PORT}" "https://${ip}:${SERVE_HTTPS_PORT}" "http://${ip}:${SERVER_PORT}" "http://${ip}:${PG_PORT}"; do
    for path in / /api/health /api/companies; do
        echo "GET ${base}${path} -> $(code -k "${base}${path}")" | mask
    done
    echo "POST ${base}${SERVE_PATH}${fake}/fire（不带 bearer）-> $(code -k -X POST -H 'Content-Type: application/json' -d '{}' "${base}${SERVE_PATH}${fake}/fire")" | mask
    echo "GET ${base}${SERVE_PATH}../../health（路径穿越）-> $(code -k --path-as-is "${base}${SERVE_PATH}../../health")" | mask
done
echo "（000 = 连不上；404 = 对端在但没有这个路径）"
# 对照：确认 000 不是网络整体不通。
nc -z -G 5 "${ip}" 22 >/dev/null 2>&1 && echo "对照：iMac tailnet 22 端口通" || echo "对照：iMac tailnet 22 端口也不通（网络问题，上面的结果不算数）"
