#!/bin/bash
# S12 ② 转发程序装好以后，从 MBA 读回（在 MBA 的仓库里跑）。只用错的 bearer 或不带 bearer，从不用正确的 bearer。
# 1) 经 ssh 数 company 下的 heartbeat runs，必须是 0，不是 0 就不发任何请求。
# 2) 经 ssh 取「S12 演练叫醒（测试）」触发器的 publicId，只放在本进程的环境变量里，不落盘、不打印。
# 3) probe.py --mode readback：从 MBA 经 tailnet 打 iMac:8110，拒绝测试全套（见 FAILURE-MODES.md F5–F15）。
# 4) 经 ssh 跑 iMac 上的 forwarder/readback-imac.sh checks：监听、本机和局域网地址连不上、LaunchAgent、日志、.url 文件。
# 5) 再数一次 heartbeat runs，必须还是 0。
# 副作用：带错 bearer 和不带 bearer 的请求会让 Paperclip 记 routine.webhook_test_rejected 活动，不起运行。
# 用法：readback-from-mba.sh [输出文件]   输出里 IP、publicId 已打码
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/../config.sh"
out=${1:-/dev/null}
R='bash ~/.local/share/paperclip-ops/scripts/forwarder/readback-imac.sh'
TSM=$(command -v tailscale || echo /usr/local/bin/tailscale)
ip=$("${TSM}" ip -4 imac 2>/dev/null | head -1)
[ -n "${ip}" ] || { echo "取不到 iMac 的 tailnet 地址" >&2; exit 1; }
# 24 位十六进制只在前后都不是十六进制字符时才打码，40 位的 commit sha 不会被截掉；48 位（bearer 的长度）整串打码。
mask() { sed -E "s/${ip//./\\.}/<imac-tailnet-ip>/g; s/[0-9a-f]{48}/<hex48>/g; s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<ip>/g; s/(^|[^0-9a-f])[0-9a-f]{24}([^0-9a-f]|$)/\1<publicId>\2/g"; }

{
    date '+%F %T %z'
    echo "仓库 commit: $(git -C "${here}" rev-parse HEAD)"
    before=$(timeout 120 ssh imac "${R} runs")
    echo "heartbeat runs（读回前）: ${before}"
    if [ "${before}" != 0 ]; then
        echo "FAIL  读回前 heartbeat runs 不是 0，停下，不发任何请求"
        exit 1
    fi
    PROBE_PUBLIC_ID=$(timeout 120 ssh imac "${R} publicid")
    export PROBE_PUBLIC_ID
    echo "== probe.py（MBA -> iMac tailnet :${FWD_PORT}）=="
    timeout 600 python3 -I "${here}/probe.py" --host "${ip}" --port "${FWD_PORT}" --mode readback
    echo "probe 退出码: $?"
    unset PROBE_PUBLIC_ID
    echo "== 别的端口从 tailnet 打不到 =="
    for port in "${SERVER_PORT}" "${PG_PORT}" 443; do
        c=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://${ip}:${port}/api/health")
        [ "${c}" = 000 ] && echo "PASS  tailnet :${port} 连不上" || echo "FAIL  tailnet :${port} -> ${c}"
    done
    echo "== iMac 上的检查 =="
    timeout 300 ssh imac "${R} checks"
    after=$(timeout 120 ssh imac "${R} runs")
    echo "heartbeat runs（读回后）: ${after}"
    [ "${after}" = 0 ] && echo "PASS  读回前后 heartbeat runs 都是 0" || echo "FAIL  读回后 heartbeat runs = ${after}"
} 2>&1 | mask | tee "${out}"
