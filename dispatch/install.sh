#!/bin/bash
# dispatch/install.sh：安装 / 核对 PER-126 v5 前提 2 的被动采样器（iMac、MBA 通用，可重复运行）。
#   装到 $HOME/.local/bin/：ops-v5-sampler、ops-v5-sample-replay
#   配置 $HOME/.config/dispatch/sampler.env（已存在就不覆盖，只报告差异）
#   数据 $HOME/.local/state/dispatch/（samples/<host>/、日志、锁）
#   LaunchAgent $HOME/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist（StartInterval 60）
# 用法：dispatch/install.sh --check | --dry-run | --install
#   --check    只读核对：脚本、版本、配置版本、plist、LaunchAgent 是否已加载、最近一次采样年龄、数据目录大小。
#              全部正常退出 0，否则退出 1。
#   --dry-run  只打印会建什么、改什么，不写文件，不调 launchctl
#   --install  真安装（本 PR 不在线上跑；装线上要 dr eggbot 审 → ops bot 验收 → Zack 点卡）
# HOME 不是本账户的主目录时（测试用 HOME=/tmp/xxx），永远不调 launchctl。
set -euo pipefail

MODE=
case "${1:-}" in
  --check) MODE=check ;;
  --dry-run) MODE=dry ;;
  --install) MODE=install ;;
  *) echo "用法：$0 --check | --dry-run | --install" >&2; exit 2 ;;
esac

DIR=$(cd "$(dirname "$0")" && pwd)
LABEL=com.zhongc1211.ops-v5-sampler
BIN="$HOME/.local/bin"
CONF_DIR="$HOME/.config/dispatch"
CONF="$CONF_DIR/sampler.env"
STATE="$HOME/.local/state/dispatch"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
TS=$(date +%Y%m%dT%H%M%S)
DOMAIN="gui/$(id -u)"
STALE_SEC=180

real_home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
if [ -n "$real_home" ] && [ "$real_home" = "$HOME" ]; then USE_LAUNCHCTL=1; else USE_LAUNCHCTL=0; fi

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
sed "s|@HOME@|$HOME|g" "$DIR/launchd/$LABEL.plist.in" > "$TMPD/$LABEL.plist"

repo_version=$(/usr/bin/python3 -I "$DIR/bin/ops-v5-sampler" --version | awk '{print $2}')

# 源文件|目标文件|权限
ITEMS=(
  "$DIR/bin/ops-v5-sampler|$BIN/ops-v5-sampler|755"
  "$DIR/bin/ops-v5-sample-replay|$BIN/ops-v5-sample-replay|755"
  "$TMPD/$LABEL.plist|$PLIST|644"
)

loaded() {
  [ "$USE_LAUNCHCTL" = 1 ] && launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1
}

bad=0
say() { printf '%-6s %s\n' "$1" "$2"; }

# ---------------------------------------------------------------- 文件
changed_plist=0
for d in "$BIN" "$CONF_DIR" "$STATE" "$STATE/samples" "$AGENTS"; do
  if [ -d "$d" ]; then
    [ "$MODE" = check ] || say 已有 "${d}/"
    continue
  fi
  case "$MODE" in
    check) ;;
    dry) say 新建 "${d}/" ;;
    install) mkdir -p "$d"; say 新建 "${d}/" ;;
  esac
done

for it in "${ITEMS[@]}"; do
  IFS='|' read -r src dst perm <<<"$it"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    say 一致 "$dst"
    continue
  fi
  if [ -e "$dst" ]; then state=不同; else state=缺失; fi
  [ "$dst" = "$PLIST" ] && changed_plist=1
  case "$MODE" in
    check) say "$state" "$dst"; bad=1 ;;
    dry)
      if [ "$state" = 不同 ]; then say 覆盖 "${dst}（先备份到 ${dst}.bak-${TS}）"; else say 新建 "$dst"; fi ;;
    install)
      if [ -e "$dst" ]; then cp -p "$dst" "$dst.bak-$TS"; say 备份 "$dst -> $dst.bak-$TS"; fi
      tmp="$dst.tmp-$$"
      cp "$src" "$tmp" && chmod "$perm" "$tmp" && mv -f "$tmp" "$dst"
      say 安装 "$dst" ;;
  esac
done

# ---------------------------------------------------------------- 配置
if [ -f "$CONF" ]; then
  ver=$(sed -n 's/^[[:space:]]*SAMPLER_CONFIG_VERSION=//p' "$CONF" | tail -n 1 | tr -d "\"' ")
  if [ "$ver" = 1 ]; then say 一致 "${CONF}（SAMPLER_CONFIG_VERSION=1）"
  else say 版本错 "${CONF}（SAMPLER_CONFIG_VERSION=${ver:-缺}）"; bad=1; fi
  cmp -s "$DIR/config/sampler.env.in" "$CONF" || say 提示 "${CONF} 和仓库模板不同（不覆盖，按需手工合并）"
else
  case "$MODE" in
    check) say 缺失 "$CONF"; bad=1 ;;
    dry) say 新建 "${CONF}（从 dispatch/config/sampler.env.in 复制）" ;;
    install)
      cp "$DIR/config/sampler.env.in" "$CONF.tmp-$$" && chmod 644 "$CONF.tmp-$$" && mv -f "$CONF.tmp-$$" "$CONF"
      say 安装 "$CONF" ;;
  esac
fi

# ---------------------------------------------------------------- 已装脚本的版本
if [ "$MODE" = check ]; then
  if [ -x "$BIN/ops-v5-sampler" ]; then
    inst=$("$BIN/ops-v5-sampler" --version 2>/dev/null | awk '{print $2}' || true)
    if [ "$inst" = "$repo_version" ]; then say 一致 "版本 ${inst}"
    else say 版本错 "已装 ${inst:-读不出}，仓库 ${repo_version}"; bad=1; fi
  fi
fi

# ---------------------------------------------------------------- LaunchAgent
if [ "$USE_LAUNCHCTL" = 0 ]; then
  say 跳过 "launchctl（HOME=${HOME} 不是本账户主目录 ${real_home:-?}）"
elif loaded; then
  case "$MODE" in
    check) say 已加载 "$DOMAIN/$LABEL" ;;
    dry)
      if [ "$changed_plist" = 1 ]; then say 重载 "launchctl bootout $DOMAIN/$LABEL; launchctl bootstrap $DOMAIN $PLIST"
      else say 已加载 "${DOMAIN}/${LABEL}（不动）"; fi ;;
    install)
      if [ "$changed_plist" = 1 ]; then
        launchctl bootout "$DOMAIN/$LABEL" || true
        launchctl bootstrap "$DOMAIN" "$PLIST"
        say 重载 "$DOMAIN/$LABEL"
      else
        say 已加载 "${DOMAIN}/${LABEL}（不动）"
      fi ;;
  esac
else
  case "$MODE" in
    check) say 未加载 "$DOMAIN/$LABEL"; bad=1 ;;
    dry) say 加载 "launchctl bootstrap $DOMAIN $PLIST" ;;
    install) launchctl bootstrap "$DOMAIN" "$PLIST"; say 加载 "$DOMAIN/$LABEL" ;;
  esac
fi

# ---------------------------------------------------------------- 数据
if [ "$MODE" = check ]; then
  newest=$(ls -1 "$STATE"/samples/*/*.jsonl 2>/dev/null | awk -F/ '{print $NF "|" $0}' | sort | tail -n 1 | cut -d'|' -f2- || true)
  if [ -n "$newest" ]; then
    age=$(/usr/bin/python3 -I - "$newest" <<'PY'
import datetime, json, sys
with open(sys.argv[1], "rb") as f:
    f.seek(0, 2); f.seek(max(0, f.tell() - 262144))
    lines = [l for l in f.read().splitlines() if l.strip()]
try:
    ts = datetime.datetime.fromisoformat(json.loads(lines[-1])["ts"])
    print(int((datetime.datetime.now().astimezone() - ts).total_seconds()))
except Exception:
    print("?")
PY
)
    if [ "$age" != "?" ] && [ "$age" -le "$STALE_SEC" ]; then say 正常 "最近一次采样 ${age} 秒前（${newest}）"
    else say 过期 "最近一次采样 ${age} 秒前（${newest}），超过 ${STALE_SEC} 秒"; bad=1; fi
  else
    say 无数据 "${STATE}/samples/ 下还没有 .jsonl"; bad=1
  fi
  if [ -d "$STATE" ]; then say 大小 "${STATE}/ $(du -sk "$STATE" | awk '{print $1}') KB"
  else say 缺失 "${STATE}/"; fi
  exit "$bad"
fi
if [ "$MODE" = dry ]; then
  host=$(hostname -s | tr '[:upper:]' '[:lower:]')
  say 运行后 "采样器自己会建：${STATE}/samples/${host}/、${STATE}/samples/${host}/YYYY-MM-DD.jsonl"
  say 运行后 "${STATE}/ops-v5-sampler.lock、ops-v5-sampler.log(.1)、ops-v5-sampler.launchd.log(.1)"
fi
[ "$MODE" = install ] && echo "完成。核对：$0 --check"
exit 0
