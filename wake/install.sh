#!/bin/bash
# wake/install.sh：从 ops 仓库安装叫醒系统脚本（iMac / box 通用，可重复运行）。
#   装到 $HOME/.local/bin/：orca-wake、orca-wake-hooks、notify-run、orca-agent-launch、agent-stop（来自 wake/bin/）和 agent-probe（来自 scripts/）。
#   有 $HOME/.pi/agent/extensions/ 时同时装 Pi 扩展 dispatch-wake.ts。
#   内容相同的文件不动；要覆盖的旧文件先备份到 <目标>.bak-<时间戳>（同目录）。
#   不改 ~/.claude/settings.json、enabled-bots、webhook 配置；hook 条目请另跑 `orca-wake-hooks install --backup-dir ...`。
# 用法：wake/install.sh [--dry-run] [--check]
#   --dry-run  只列出会做什么，不写文件
#   --check    只比对已装文件和仓库版本，再只读核对全局 AGENTS 三机一致（见文件末尾）；全部一致退出 0，有差异退出 1
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
    dry) echo "$state  ${dst}（会$([ "$state" = 不同 ] && echo "备份后")覆盖）" ;;
    install)
      if [ -e "$dst" ]; then cp -p "$dst" "$dst.bak-$TS"; echo "备份  $dst -> $dst.bak-$TS"; fi
      tmp="$dst.tmp-$$"
      cp "$src" "$tmp" && chmod "$perm" "$tmp" && mv -f "$tmp" "$dst"
      echo "安装  $dst" ;;
  esac
done

if [ "$MODE" = check ]; then
  # 全局 AGENTS 三机一致（PER-80）：本机和对端的 ~/.pi/agent/AGENTS.md sha256 相同，且各台 ~/.claude/CLAUDE.md
  # 用 @~/.pi/agent/AGENTS.md 引用它（Claude Code 默认不读 AGENTS.md，靠这一行读到全局规矩）。对端只读，ssh 连不上重试一次，
  # 还不行算 FAIL（无法核对）。对端默认 imac mba box 去掉本机；WAKE_CHECK_PEERS 可改（设成空就只看本机）。
  AGENTS_PROBE='f="$HOME/.pi/agent/AGENTS.md"; c="$HOME/.claude/CLAUDE.md"
if [ -r "$f" ]; then s=$( (shasum -a 256 "$f" 2>/dev/null || sha256sum "$f") | cut -c1-64); b=$(wc -c < "$f" | tr -d " "); else s=missing; b=0; fi
if [ ! -r "$c" ]; then r=nofile; elif grep -qE "(^|[[:space:]])@(~|$HOME)/[.]pi/agent/AGENTS[.]md([[:space:]]|$)" "$c"; then r=yes; else r=no; fi
echo "agents-probe sha=$s bytes=$b claude_ref=$r"'
  self=$(hostname 2>/dev/null | cut -d. -f1 | tr '[:upper:]' '[:lower:]')
  case "$self" in grok-bot-vm-*) self=box ;; esac
  hosts=("$self")
  probes=("$(sh -c "$AGENTS_PROBE" 2>/dev/null | grep '^agents-probe ' | tail -1 || true)")
  for peer in ${WAKE_CHECK_PEERS-imac mba box}; do
    [ "$peer" != "$self" ] || continue
    out=""
    for _ in 1 2; do
      out=$(ssh -o BatchMode=yes -o ConnectTimeout=20 "$peer" "$AGENTS_PROBE" 2>/dev/null | grep '^agents-probe ' | tail -1 || true)
      [ -z "$out" ] || break
    done
    hosts+=("$peer"); probes+=("$out")
  done
  echo "全局 AGENTS（~/.pi/agent/AGENTS.md）各台核对："
  shas="" unreach="" noref="" i=0
  while [ "$i" -lt "${#hosts[@]}" ]; do
    h=${hosts[$i]} p=${probes[$i]}
    i=$((i + 1))
    if [ -z "$p" ]; then
      echo "  ${h}  无法核对（ssh 两次都没拿到结果）"; unreach="$unreach $h"; continue
    fi
    sha=$(printf '%s\n' "$p" | sed -n 's/.* sha=\([^ ]*\).*/\1/p')
    bytes=$(printf '%s\n' "$p" | sed -n 's/.* bytes=\([^ ]*\).*/\1/p')
    ref=$(printf '%s\n' "$p" | sed -n 's/.* claude_ref=\([^ ]*\).*/\1/p')
    case "$sha" in
      missing) echo "  ${h}  没有这个文件"; sha=missing ;;
      *) echo "  ${h}  sha256=${sha:0:12}  ${bytes} 字节  ~/.claude/CLAUDE.md 引用：${ref}"; sha=${sha:0:12} ;;
    esac
    shas="$shas ${h}=${sha}"
    [ "$ref" = yes ] || noref="$noref $h"
  done
  distinct=$(printf '%s\n' $shas | sed 's/^[^=]*=//' | sort -u | wc -l | tr -d ' ')
  if [ -n "$unreach" ]; then
    for h in $unreach; do echo "FAIL  ${h} 无法核对：对端不可达，不算通过"; done
    drift=1
  fi
  if printf '%s\n' $shas | grep -q '=missing$'; then
    echo "FAIL  全局 AGENTS 有机器上不存在：${shas# }"; drift=1
  elif [ "$distinct" -gt 1 ]; then
    echo "FAIL  全局 AGENTS 不一致：${shas# }"; drift=1
  elif [ -z "$unreach" ]; then
    echo "PASS  全局 AGENTS 一致（${#hosts[@]} 台：${shas# }）"
  fi
  for h in $noref; do echo "FAIL  ${h} 的 ~/.claude/CLAUDE.md 没有引用 @~/.pi/agent/AGENTS.md，Claude Code 读不到全局规矩"; drift=1; done
  [ -n "$noref" ] || echo "PASS  核对到的各台 ~/.claude/CLAUDE.md 都引用了全局 AGENTS"
  exit "$drift"
fi
if [ "$MODE" = install ]; then
  mkdir -p "$HOME/.config/orca-wake"
  [ -e "$HOME/.config/orca-wake/enabled-bots" ] || : > "$HOME/.config/orca-wake/enabled-bots"
  echo "完成。hook 条目检查：$BIN/orca-wake-hooks check"
fi
