#!/bin/bash
# S12 ② 第 1 步：在 iMac 装 paperclipai（钉死版本）并写新实例 ops 的配置。不起服务。
# 用法（在 iMac 上）：install.sh            只打印要做什么
#                     install.sh --apply    照做；可以重跑，已装好的步骤跳过
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${here}/config.sh"

apply=0
[ "${1:-}" = "--apply" ] && apply=1

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

say "== 计划 =="
say "版本: paperclipai@${PAPERCLIP_VERSION}（不用 @latest）"
say "node: ${NODE_BIN}/node（要求 ${NODE_VERSION}）"
say "程序目录: ${APP_DIR}"
say "实例: ${PAPERCLIP_INSTANCE_ID} -> ${INSTANCE_ROOT}"
say "配置: ${CONFIG_PATH}（local_trusted / private / loopback，${SERVER_HOST}:${SERVER_PORT}，内嵌 postgres ${PG_PORT}）"
say "不碰: ${PAPERCLIP_HOME_DIR}/instances/default、${PAPERCLIP_HOME_DIR}/cli、~/paperclip"

# --- 前提检查（只读）---
[ "${PAPERCLIP_INSTANCE_ID}" = ops ] || die "PAPERCLIP_INSTANCE_ID 不是 ops"
[ -x "${NODE_BIN}/node" ] || die "找不到 ${NODE_BIN}/node"
nv=$("${NODE_BIN}/node" -v)
[ "${nv}" = "${NODE_VERSION}" ] || die "node 版本是 ${nv}，不是 ${NODE_VERSION}"
say "node 读回: ${nv}"

mem=$(mem_level)
say "memorystatus_level: ${mem}"

if [ -f "${DEFAULT_CONFIG}" ]; then
    say "default 的 config.json sha256（只记前 12 位，用来核对没被改）: $(shasum -a 256 "${DEFAULT_CONFIG}" | cut -c1-12)"
fi

for port in "${SERVER_PORT}" "${PG_PORT}"; do
    if /usr/sbin/lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
        if [ -f "${INSTANCE_ROOT}/runtime-info.json" ]; then
            say "端口 ${port} 已被占（实例 ops 可能已在跑）"
        else
            die "端口 ${port} 已被别的程序占用"
        fi
    fi
done

installed_version() {
    [ -f "${APP_DIR}/node_modules/paperclipai/package.json" ] || { echo none; return; }
    "${NODE_BIN}/node" -p 'require(process.argv[1]).version' "${APP_DIR}/node_modules/paperclipai/package.json"
}

cur=$(installed_version)
say "已装版本: ${cur}"

if [ "${apply}" = 0 ]; then
    [ "${cur}" = "${PAPERCLIP_VERSION}" ] || say "将执行: npm install --prefix ${APP_DIR} --save-exact paperclipai@${PAPERCLIP_VERSION}"
    [ -f "${CONFIG_PATH}" ] || say "将写入: ${CONFIG_PATH}"
    say "将执行: paperclipai doctor --repair -c ${CONFIG_PATH}（生成实例自己的 .env 和本地密钥文件，不起服务）"
    say "（只打印，未执行。加 --apply 照做）"
    exit 0
fi

[ "${mem}" -ge 20 ] || die "memorystatus_level=${mem} 低于 20，不装"

# --- 安装 ---
if [ "${cur}" != "${PAPERCLIP_VERSION}" ]; then
    [ "${cur}" = none ] || die "程序目录里是 ${cur}，不是 ${PAPERCLIP_VERSION}；请先删掉 ${APP_DIR} 再装"
    mkdir -p "${APP_DIR}"
    [ -f "${APP_DIR}/package.json" ] || printf '{"name":"paperclip-ops-app","private":true}\n' >"${APP_DIR}/package.json"
    PATH="${NODE_BIN}:/usr/bin:/bin" "${TIMEOUT}" 800 "${NODE_BIN}/npm" install --prefix "${APP_DIR}" \
        --save-exact --no-fund --no-audit --prefer-offline "paperclipai@${PAPERCLIP_VERSION}"
fi
cur=$(installed_version)
[ "${cur}" = "${PAPERCLIP_VERSION}" ] || die "装完读回的版本是 ${cur}"
[ -f "${PAPERCLIP_CLI}" ] || die "找不到 ${PAPERCLIP_CLI}"
say "装好: paperclipai ${cur}"

# --- 实例配置 ---
mkdir -p "${INSTANCE_ROOT}"
chmod 700 "${INSTANCE_ROOT}"
if [ -f "${CONFIG_PATH}" ]; then
    say "配置已存在，不覆盖: ${CONFIG_PATH}"
else
    "${PY}" - "${CONFIG_PATH}" "${INSTANCE_ROOT}" "${SERVER_HOST}" "${SERVER_PORT}" "${PG_PORT}" <<'PYEOF'
import json, os, sys, datetime
path, root, host, port, pg_port = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
cfg = {
    "$meta": {"version": 1, "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(), "source": "onboard"},
    "database": {
        "mode": "embedded-postgres",
        "embeddedPostgresDataDir": os.path.join(root, "db"),
        "embeddedPostgresPort": pg_port,
        "backup": {"enabled": True, "intervalMinutes": 60, "retentionDays": 7,
                   "dir": os.path.join(root, "data", "backups")},
    },
    "logging": {"mode": "file", "logDir": os.path.join(root, "logs")},
    "server": {
        "deploymentMode": "local_trusted",
        "exposure": "private",
        "bind": "loopback",
        "host": host,
        "port": port,
        "allowedHostnames": [],
        "serveUi": True,
    },
    "telemetry": {"enabled": False},
    "updates": {"checkEnabled": False},
    "auth": {"baseUrlMode": "auto", "disableSignUp": False},
    "storage": {
        "provider": "local_disk",
        "localDisk": {"baseDir": os.path.join(root, "data", "storage")},
        "s3": {"bucket": "paperclip", "region": "us-east-1", "prefix": "", "forcePathStyle": False},
    },
    "secrets": {
        "provider": "local_encrypted",
        "strictMode": False,
        "localEncrypted": {"keyFilePath": os.path.join(root, "secrets", "master.key")},
    },
}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("写入配置:", path)
PYEOF
fi

# doctor 只做检查和修复（生成 .env 里的 agent JWT 密钥、本地密钥文件），不起服务、不起 postgres。
env -u ORCA_DISPATCH_BOT PAPERCLIP_INSTANCE_ID="${PAPERCLIP_INSTANCE_ID}" PATH="${NODE_BIN}:/usr/bin:/bin" \
    "${TIMEOUT}" 300 "${NODE_BIN}/node" "${PAPERCLIP_CLI}" doctor --repair -y -c "${CONFIG_PATH}" 2>&1 \
    | grep -v -i -E 'secret=|key=|token=' || true

if [ -f "${DEFAULT_CONFIG}" ]; then
    say "default 的 config.json sha256（装后）: $(shasum -a 256 "${DEFAULT_CONFIG}" | cut -c1-12)"
fi
say "install 完成。下一步: serve.sh"
