#!/bin/bash
# S12 ② 第 2 步：tailscale serve 只把 /api/routine-triggers/public/ 转到本机 Paperclip。
# 先试 HTTPS，不行走 HTTP。配置用 --bg，写进 tailscaled 的状态，重启后还在。
# 用法（在 iMac 上）：serve.sh          只打印要做什么
#                     serve.sh --apply  照做
#                     serve.sh --off    关掉本脚本加的两条 serve（不动别的 serve 配置）
# tailnet 地址运行时取，不写进仓库；屏幕上只打印打码后的形式。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/config.sh"

TS=/usr/local/bin/tailscale
mode=${1:-plan}
target="http://${SERVER_HOST}:${SERVER_PORT}${SERVE_PATH}"

say() { printf '%s\n' "$*"; }
mask() { sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<tailnet-ip>/g; s/[A-Za-z0-9-]+\.[A-Za-z0-9.-]*ts\.net/<magicdns>/g'; }

serve_status() { "${TS}" serve status 2>&1 | mask; }

if [ "${mode}" = --off ]; then
    say "关 serve: https:${SERVE_HTTPS_PORT} 和 http:${SERVE_HTTP_PORT} 上的 ${SERVE_PATH}"
    "${TIMEOUT}" 60 "${TS}" serve --https="${SERVE_HTTPS_PORT}" --set-path "${SERVE_PATH}" off 2>&1 | mask || true
    "${TIMEOUT}" 60 "${TS}" serve --http="${SERVE_HTTP_PORT}" --set-path "${SERVE_PATH}" off 2>&1 | mask || true
    rm -f "${SERVE_URL_FILE}"
    serve_status
    exit 0
fi

ip4=$("${TS}" ip -4 | head -1)
[ -n "${ip4}" ] || { say "serve: 取不到 tailnet IPv4" >&2; exit 1; }
dns=$("${TS}" status --json | "${PY}" -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName","").rstrip("."))')

say "== 计划 =="
say "目标: ${target}"
say "1) tailscale serve --bg --https=${SERVE_HTTPS_PORT} --set-path ${SERVE_PATH} ${target}"
case "${dns}" in *.*) dns_note="有完整域名" ;; "") dns_note="为空" ;; *) dns_note="只有短名、没有域名（MagicDNS 关）" ;; esac
say "   成功则地址是 https://<本机 DNS 名>（本机 DNS 名${dns_note}）"
say "2) 不行就撤掉第 1 步，改 tailscale serve --bg --http=${SERVE_HTTP_PORT} --set-path ${SERVE_PATH} ${target}"
say "   地址是 http://<tailnet-ip>:${SERVE_HTTP_PORT}"
say "地址写进 ${SERVE_URL_FILE}（权限 600），launchagent.sh 读它设 PAPERCLIP_PUBLIC_URL 和 allowedHostnames"
say "现状:"; serve_status

[ "${mode}" = --apply ] || { say "（只打印，未执行。加 --apply 照做）"; exit 0; }

write_url() {
    umask 077
    printf '%s\n' "$1" >"${SERVE_URL_FILE}"
    chmod 600 "${SERVE_URL_FILE}"
}

https_off() { "${TIMEOUT}" 60 "${TS}" serve --https="${SERVE_HTTPS_PORT}" --set-path "${SERVE_PATH}" off >/dev/null 2>&1 || true; }

url=""
say "-- 试 HTTPS --"
# 没有证书域名时，tailscale 可能报错，也可能停下等人去后台开 HTTPS；60 秒没结果就算失败。
if out=$("${TIMEOUT}" 60 "${TS}" serve --bg --https="${SERVE_HTTPS_PORT}" --set-path "${SERVE_PATH}" "${target}" 2>&1); then
    say "${out}" | mask
    if [ "${dns#*.}" != "${dns}" ]; then
        url="https://${dns}"
    else
        say "HTTPS 配上了，但本机没有完整域名（MagicDNS 关），MBA 解析不了、也拿不到证书，撤掉改走 HTTP"
        https_off
    fi
else
    rc=$?
    say "HTTPS 失败（退出码 ${rc}）:"; say "${out}" | mask
    https_off
fi

if [ -z "${url}" ]; then
    say "-- 走 HTTP --"
    if out=$("${TIMEOUT}" 60 "${TS}" serve --bg --http="${SERVE_HTTP_PORT}" --set-path "${SERVE_PATH}" "${target}" 2>&1); then
        say "${out}" | mask
        url="http://${ip4}:${SERVE_HTTP_PORT}"
    else
        say "HTTP 也失败（退出码 $?）:"; say "${out}" | mask
        say "停下：headscale 下 Serve 用不了，要 Zack 定（见 README「要 Zack 定」）"
        exit 2
    fi
fi

write_url "${url}"
say "Serve 地址已写入 ${SERVE_URL_FILE}: $(printf '%s' "${url}" | mask)"
say "现状:"; serve_status
