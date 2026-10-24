# S12 ② 共用常量。被本目录其它脚本 source，不单独执行。
# 这里只放不敏感、不含地址和 ID 的值；tailnet 地址在 forwarder.js、forwarder/install.sh 运行时取。

PAPERCLIP_VERSION=2026.1012.0
NODE_VERSION=v24.22.1
NODE_BIN="${HOME}/.nvm/versions/node/${NODE_VERSION}/bin"

export PAPERCLIP_INSTANCE_ID=ops
PAPERCLIP_HOME_DIR="${HOME}/.paperclip"
INSTANCE_ROOT="${PAPERCLIP_HOME_DIR}/instances/${PAPERCLIP_INSTANCE_ID}"
CONFIG_PATH="${INSTANCE_ROOT}/config.json"
DEFAULT_CONFIG="${PAPERCLIP_HOME_DIR}/instances/default/config.json"

# 程序装在实例目录之外，回退时和实例目录一起删。
APP_ROOT="${HOME}/.local/share/paperclip-ops"
APP_DIR="${APP_ROOT}/app-${PAPERCLIP_VERSION}"
PAPERCLIP_CLI="${APP_DIR}/node_modules/paperclipai/dist/index.js"

SERVER_HOST=127.0.0.1
SERVER_PORT=3110
PG_PORT=54339
API_URL="http://${SERVER_HOST}:${SERVER_PORT}"

# 对外地址（PAPERCLIP_PUBLIC_URL）：现在由转发程序的 install.sh 写，launchagent.sh 读。
PUBLIC_URL_FILE="${INSTANCE_ROOT}/public-url"

# Serve（现在不用，见 README「对外怎么开」）：先试 HTTPS 443，不行走 HTTP 8110。只挂触发路径。
SERVE_HTTPS_PORT=443
SERVE_HTTP_PORT=8110
SERVE_PATH=/api/routine-triggers/public/

# 触发转发程序（代替 Serve，见 forwarder/）。端口和监听地址写死在 forwarder.js 里，这里的值只给脚本用。
TS=/usr/local/bin/tailscale
FWD_PORT=8110
FWD_LABEL=com.zhongc1211.paperclip-ops-forwarder
FWD_PLIST="${HOME}/Library/LaunchAgents/${FWD_LABEL}.plist"
FWD_DIR="${APP_ROOT}/forwarder"
FWD_JS="${FWD_DIR}/forwarder.js"
FWD_STATE="${FWD_DIR}/state"
FWD_LOG_DIR="${HOME}/Library/Logs/paperclip-ops-forwarder"
FWD_PATH_RE='^/api/routine-triggers/public/[0-9a-f]{24}/fire$'

LAUNCH_LABEL=com.zhongc1211.paperclip-ops
LAUNCH_PLIST="${HOME}/Library/LaunchAgents/${LAUNCH_LABEL}.plist"
LAUNCH_PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:${NODE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"

# ops 系统的 agent
COMPANY_NAME="ops 系统"
AGENT_NAME="ops-system"
AGENT_MODEL=claude-opus-5-5
AGENT_BUDGET_CENTS=20000
AGENT_CWD="${INSTANCE_ROOT}/agent-work/ops-system"
AGENT_SETTINGS="${AGENT_CWD}/.claude/ops-system-settings.json"
ROUTINE_OPS_TITLE="ops 系统叫醒"
ROUTINE_TEST_TITLE="S12 演练叫醒（测试）"

# 触发器 bearer：只存在 iMac，目录 700，文件 600。
SECRETS_DIR="${HOME}/.config/paperclip-ops/triggers"

TIMEOUT=/usr/local/bin/timeout
PY=/usr/bin/python3

mem_level() { sysctl -n kern.memorystatus_level; }
