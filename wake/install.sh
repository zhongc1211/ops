#!/bin/bash
# wake/install.sh：从 ops 仓库安装叫醒系统脚本（iMac / box 通用，可重复运行）。
#   装到 $HOME/.local/bin/：orca-wake、orca-wake-hooks、notify-run、orca-agent-launch、agent-stop（来自 wake/bin/）和 agent-probe（来自 scripts/）。
#   有 $HOME/.pi/agent/extensions/ 时同时装 Pi 扩展 dispatch-wake.ts。
#   内容相同的文件不动；要覆盖的旧文件先备份到 <目标>.bak-<时间戳>（同目录）。
#   不改 ~/.claude/settings.json、enabled-bots、webhook 配置；hook 条目请另跑 `orca-wake-hooks install --backup-dir ...`。
# 用法：wake/install.sh [--dry-run] [--check]
#   --dry-run  只列出会做什么，不写文件
#   --check    只比对已装文件和仓库版本；全部一致退出 0，有差异退出 1
# 测试时可以用 HOME=/tmp/xxx wake/install.sh 装到临时目录。
set -euo pipefail

MODE=install
case "${1:-}" in
  --dry-run) MODE=dry ;;
  --check) MODE=check ;;
  "") ;;
  *) echo "用法：$0 [--dry-run|--check]" >&2; exit 2 ;;
esac

WAKE_DIR=$(cd "$(dirname "$0")" && pwd)
OPS_DIR=$(cd "$WAKE_DIR/.." && pwd)
BIN="$HOME/.local/bin"
PI_EXT="$HOME/.pi/agent/extensions"
TS=$(date +%Y%m%dT%H%M%S)

# 源文件|目标文件|权限
ITEMS=(
  "$WAKE_DIR/bin/orca-wake|$BIN/orca-wake|755"
  "$WAKE_DIR/bin/orca-wake-hooks|$BIN/orca-wake-hooks|755"
  "$WAKE_DIR/bin/notify-run|$BIN/notify-run|755"
  "$WAKE_DIR/bin/orca-agent-launch|$BIN/orca-agent-launch|755"
  "$WAKE_DIR/bin/agent-stop|$BIN/agent-stop|755"
  "$OPS_DIR/scripts/agent-probe|$BIN/agent-probe|755"
)
if [ -d "$PI_EXT" ]; then
  ITEMS+=("$WAKE_DIR/pi/dispatch-wake.ts|$PI_EXT/dispatch-wake.ts|644")
fi

[ "$MODE" = install ] && mkdir -p "$BIN"
drift=0
for it in "${ITEMS[@]}"; do
  IFS='|' read -r src dst perm <<<"$it"
  [ -f "$src" ] || { echo "缺源文件：$src" >&2; exit 1; }
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "一致  $dst"
    if [ "$MODE" = install ]; then chmod "$perm" "$dst"; fi
    continue
  fi
  drift=1
  if [ -e "$dst" ]; then state="不同"; else state="缺失"; fi
  case "$MODE" in
    check) echo "$state  $dst" ;;
    dry) echo "$state  $dst（会$([ "$state" = 不同 ] && echo "备份后")覆盖）" ;;
    install)
      if [ -e "$dst" ]; then cp -p "$dst" "$dst.bak-$TS"; echo "备份  $dst -> $dst.bak-$TS"; fi
      tmp="$dst.tmp-$$"
      cp "$src" "$tmp" && chmod "$perm" "$tmp" && mv -f "$tmp" "$dst"
      echo "安装  $dst" ;;
  esac
done

if [ "$MODE" = check ]; then exit "$drift"; fi
if [ "$MODE" = install ]; then
  mkdir -p "$HOME/.config/orca-wake"
  [ -e "$HOME/.config/orca-wake/enabled-bots" ] || : > "$HOME/.config/orca-wake/enabled-bots"
  echo "完成。hook 条目检查：$BIN/orca-wake-hooks check"
fi
