#!/bin/bash
# S12 ② 第 3 步：渲染 LaunchAgent，经 launchctl bootstrap gui/<uid> 加载（开机自启）。
# 有对外地址文件（public-url）时设 PAPERCLIP_PUBLIC_URL。现在只有 serve.sh 会写它（现在不用）；转发程序不设 PUBLIC_URL，
# forwarder/install.sh 见到这个文件会停下。
# 不往 config.json 登记 allowedHostnames：转发程序把 Host 改成本机地址，PUBLIC_URL 的主机名运行时也会自动并进去
# （1012.0 server/src/config.ts:231-246），config.json 保持不动。
# 用法（在 iMac 上）：launchagent.sh            只打印要做什么
#                     launchagent.sh --apply    照做（已加载就先 bootout 再 bootstrap）
#                     launchagent.sh --bootout  停掉并卸载 LaunchAgent（plist 留着，删要手动）
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/config.sh"

mode=${1:-plan}
uid=$(id -u)
domain="gui/${uid}"
say() { printf '%s\n' "$*"; }
die() { printf 'launchagent: %s\n' "$*" >&2; exit 1; }
mask() { sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<tailnet-ip>/g; s/[A-Za-z0-9-]+\.[A-Za-z0-9.-]*ts\.net/<magicdns>/g'; }

loaded() { launchctl print "${domain}/${LAUNCH_LABEL}" >/dev/null 2>&1; }

if [ "${mode}" = --bootout ]; then
    if loaded; then
        launchctl bootout "${domain}/${LAUNCH_LABEL}" && say "已 bootout ${domain}/${LAUNCH_LABEL}"
    else
        say "${domain}/${LAUNCH_LABEL} 没加载"
    fi
    exit 0
fi

say "== 计划 =="
say "label: ${LAUNCH_LABEL}"
say "plist: ${LAUNCH_PLIST}（由 $(basename "${here}")/${LAUNCH_LABEL}.plist.template 渲染）"
say "程序: ${NODE_BIN}/node ${PAPERCLIP_CLI} run --instance ${PAPERCLIP_INSTANCE_ID} --config ${CONFIG_PATH}"
say "监听: ${SERVER_HOST}:${SERVER_PORT}；PAPERCLIP_API_URL=${API_URL}；PAPERCLIP_PUBLIC_URL=<读 ${PUBLIC_URL_FILE}>"
say "PATH: ${LAUNCH_PATH}"
say "加载: launchctl bootstrap ${domain} ${LAUNCH_PLIST}"

[ -f "${PAPERCLIP_CLI}" ] || die "还没装（找不到 ${PAPERCLIP_CLI}），先跑 install.sh --apply"
[ -f "${CONFIG_PATH}" ] || die "找不到 ${CONFIG_PATH}"
# 没有对外地址文件时也能起服务：不设 PAPERCLIP_PUBLIC_URL。
public_url=""
public_host=""
if [ -s "${PUBLIC_URL_FILE}" ]; then
    public_url=$(head -1 "${PUBLIC_URL_FILE}")
    public_host=$("${PY}" -c 'import sys,urllib.parse as u; print(u.urlsplit(sys.argv[1]).hostname or "")' "${public_url}")
    [ -n "${public_host}" ] || die "对外地址解析不出主机名"
else
    say "注意: 没有 ${PUBLIC_URL_FILE}，这次不设 PAPERCLIP_PUBLIC_URL"
fi

# LaunchAgent 的 PATH 下要找得到这些工具。
for tool in orca notify-run claude node; do
    p=$(env -i PATH="${LAUNCH_PATH}" /bin/sh -c "command -v ${tool}" || true)
    [ -n "${p}" ] || die "LaunchAgent 的 PATH 里找不到 ${tool}"
    say "PATH 检查: ${tool} -> ${p}"
done

mem=$(mem_level)
say "memorystatus_level: ${mem}"

if [ "${mode}" != --apply ]; then
    [ -z "${public_url}" ] || say "将设 PAPERCLIP_PUBLIC_URL=$(printf '%s' "${public_url}" | mask)"
    loaded && say "将先 bootout 已加载的 ${LAUNCH_LABEL}"
    say "（只打印，未执行。加 --apply 照做）"
    exit 0
fi

[ "${mem}" -ge 20 ] || die "memorystatus_level=${mem} 低于 20，不起服务"

# 渲染 plist。
tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT
sed -e "s#@LABEL@#${LAUNCH_LABEL}#g" \
    -e "s#@NODE@#${NODE_BIN}/node#g" \
    -e "s#@CLI@#${PAPERCLIP_CLI}#g" \
    -e "s#@INSTANCE@#${PAPERCLIP_INSTANCE_ID}#g" \
    -e "s#@CONFIG@#${CONFIG_PATH}#g" \
    -e "s#@HOME@#${HOME}#g" \
    -e "s#@PATH@#${LAUNCH_PATH}#g" \
    -e "s#@PAPERCLIP_HOME@#${PAPERCLIP_HOME_DIR}#g" \
    -e "s#@HOST@#${SERVER_HOST}#g" \
    -e "s#@PORT@#${SERVER_PORT}#g" \
    -e "s#@API_URL@#${API_URL}#g" \
    -e "s#@PUBLIC_URL@#${public_url}#g" \
    -e "s#@INSTANCE_ROOT@#${INSTANCE_ROOT}#g" \
    "${here}/${LAUNCH_LABEL}.plist.template" >"${tmp}"
# 没有对外地址时整行去掉 PAPERCLIP_PUBLIC_URL。
[ -n "${public_url}" ] || sed -i '' '/<key>PAPERCLIP_PUBLIC_URL<\/key><string><\/string>/d' "${tmp}"
grep -q '@[A-Z_]*@' "${tmp}" && die "plist 里还有没替换的占位符"
plutil -lint "${tmp}" >/dev/null || die "plist 格式不对"
"${PY}" - "${tmp}" <<'PYEOF'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
env = d["EnvironmentVariables"]
bad = [k for k in env if k.startswith("ORCA_")]
assert not bad, "EnvironmentVariables 里有 Orca 变量: %s" % bad
assert env["HOST"] == "127.0.0.1", "HOST 不是 127.0.0.1"
assert env["PAPERCLIP_API_URL"].startswith("http://127.0.0.1:"), "PAPERCLIP_API_URL 不是本机地址"
assert env["PAPERCLIP_INSTANCE_ID"] != "default"
print("plist 检查通过：没有 ORCA_ 变量，HOST=127.0.0.1，API_URL 是本机，实例 =", env["PAPERCLIP_INSTANCE_ID"])
PYEOF

mkdir -p "${INSTANCE_ROOT}/logs" "$(dirname "${LAUNCH_PLIST}")"
if loaded; then
    launchctl bootout "${domain}/${LAUNCH_LABEL}" || true
    sleep 3
fi
install -m 644 "${tmp}" "${LAUNCH_PLIST}"
launchctl bootstrap "${domain}" "${LAUNCH_PLIST}"
say "已 bootstrap ${domain} ${LAUNCH_PLIST}（$(date '+%F %T %z')）"
