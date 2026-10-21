#!/bin/bash
# dispatch/install.sh：安装 / 核对 / 卸载 PER-126 v5 前提 2 的被动采样器（iMac、MBA 通用，可重复运行）。
#   脚本   $HOME/.local/bin/ops-v5-sampler、ops-v5-sample-replay
#   配置   $HOME/.config/dispatch/sampler.env（已存在就不覆盖，只报告差异）
#   数据   $HOME/.local/state/ops-v5/（samples/<host>/、日志、锁、状态文件）
#   调度   $HOME/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist（StartInterval 60）
#   归档   $HOME/ops-archive/per126-v5-backup-1021/<机器>/（快照、安装记录、覆盖前的旧文件、卸载挪走的文件）
# 用法：dispatch/install.sh --check | --dry-run | --install | --uninstall [--move-data]
#   --check      只读核对：脚本、版本、配置版本、plist、LaunchAgent 是否已加载、采样器状态、
#                最近一次采样年龄、数据目录大小。全部正常退出 0，否则退出 1。
#   --dry-run    只打印会做什么，不写文件，不调 launchctl、不跑 backup.sh
#   --install    v5 上线约定：先跑本机 <归档>/tools/backup.sh --label p2-sampler，失败就退出、什么都不装；
#                核对 install-log.tsv 多了一行并打印快照目录和 MANIFEST sha256；再安装；
#                装完写 <归档>/p2-sampler-installed-<时间>.tsv（路径和 sha256）并在 install-log.tsv 追加一行。
#                本 PR 不在线上跑；装线上要 dr eggbot 审 → ops bot 验收 → Zack 点卡。
#   --uninstall  先 launchctl bootout，再把 plist、两个脚本、配置挪到 <归档>/removed-<时间>/（不删）。
#                数据目录默认留着；加 --move-data 时把采样器自己的数据和日志也挪过去。
# HOME 不是本账户的主目录时（测试用 HOME=/tmp/xxx），永远不调 launchctl。
set -euo pipefail

die() { echo "install.sh: $*" >&2; exit "${2:-1}"; }

MODE=
MOVE_DATA=0
case "${1:-}" in
  --check) MODE=check ;;
  --dry-run) MODE=dry ;;
  --install) MODE=install ;;
  --uninstall) MODE=uninstall; [ "${2:-}" = --move-data ] && MOVE_DATA=1 ;;
  *) echo "用法：$0 --check | --dry-run | --install | --uninstall [--move-data]" >&2; exit 2 ;;
esac

# 前置检查：只支持 macOS（launchd、dscl、BSD 工具）
[ "$(uname -s)" = Darwin ] || die "只支持 macOS（当前 $(uname -s)）：需要 launchd 和 dscl" 2
command -v dscl >/dev/null 2>&1 || die "找不到 dscl，无法确认本账户主目录" 2
command -v shasum >/dev/null 2>&1 || die "找不到 shasum" 2

DIR=$(cd "$(dirname "$0")" && pwd)
LABEL=com.zhongc1211.ops-v5-sampler
BIN="$HOME/.local/bin"
CONF_DIR="$HOME/.config/dispatch"
CONF="$CONF_DIR/sampler.env"
STATE="$HOME/.local/state/ops-v5"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
TS=$(date +%Y%m%dT%H%M%S)
DOMAIN="gui/$(id -u)"
STALE_SEC=180
MACHINE=$(hostname -s | tr '[:upper:]' '[:lower:]')
ARCH="$HOME/ops-archive/per126-v5-backup-1021/$MACHINE"
BACKUP="$ARCH/tools/backup.sh"
ILOG="$ARCH/install-log.tsv"

real_home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}') \
  || die "dscl 读不到 /Users/$(id -un) 的 NFSHomeDirectory" 2
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
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
# $HOME 下的相对路径，用于在归档目录里保留原来的层次
rel() { printf '%s' "${1#"$HOME"/}"; }
say() { printf '%-6s %s\n' "$1" "$2"; }
bad=0

# ---------------------------------------------------------------- 卸载
if [ "$MODE" = uninstall ]; then
  [ -d "$ARCH" ] || die "归档目录不存在：${ARCH}（机器名 ${MACHINE}），不卸载"
  DEST="$ARCH/removed-$TS"
  if loaded; then
    launchctl bootout "$DOMAIN/$LABEL"
    say 停止 "launchctl bootout $DOMAIN/$LABEL"
  elif [ "$USE_LAUNCHCTL" = 0 ]; then
    say 跳过 "launchctl（HOME=${HOME} 不是本账户主目录 ${real_home:-?}）"
  else
    say 未加载 "$DOMAIN/$LABEL"
  fi
  targets="$PLIST $BIN/ops-v5-sampler $BIN/ops-v5-sample-replay $CONF"
  if [ "$MOVE_DATA" = 1 ]; then
    targets="$targets $STATE/samples $STATE/log-archive"
    for f in "$STATE"/ops-v5-sampler.*; do [ -e "$f" ] && targets="$targets $f"; done
  fi
  moved=0
  for src in $targets; do
    [ -e "$src" ] || continue
    dst="$DEST/$(rel "$src")"
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
    printf '%s\t%s\n' "$src" "$dst" >> "$DEST/MOVED.tsv"
    say 挪走 "$src -> $dst"
    moved=$((moved + 1))
  done
  [ "$moved" = 0 ] && say 无 "没有要挪的文件"
  [ "$MOVE_DATA" = 1 ] || say 保留 "${STATE}/（数据目录；要挪加 --move-data）"
  echo "完成。核对：$0 --check（应报缺失/未加载）"
  exit 0
fi

# ---------------------------------------------------------------- 安装前快照（v5 上线约定）
SNAP_LINE=
if [ "$MODE" = dry ]; then
  if [ -x "$BACKUP" ]; then say 快照 "会先跑 $BACKUP --label p2-sampler，并核对 $ILOG 多一行"
  else say 缺失 "${BACKUP}（--install 会因此退出，什么都不装）"; fi
fi
# install-log.tsv 的记录行数（不算表头；backup.sh 第一次跑时会先写表头）
log_rows() { if [ -f "$ILOG" ]; then grep -vc '^time	' "$ILOG" || true; else echo 0; fi; }
if [ "$MODE" = install ]; then
  [ -x "$BACKUP" ] || die "找不到本机快照脚本：${BACKUP}（机器名 ${MACHINE}），什么都没装"
  before=$(log_rows)
  "$BACKUP" --label p2-sampler || die "backup.sh 失败，什么都没装"
  after=$(log_rows)
  [ "$after" -eq $((before + 1)) ] || die "install-log.tsv 记录行数 ${before} -> ${after}，不是多一行，什么都没装"
  SNAP_LINE=$(tail -n 1 "$ILOG")
  [ "$(printf '%s' "$SNAP_LINE" | cut -f3)" = p2-sampler ] || die "install-log.tsv 新增行的 label 不是 p2-sampler，什么都没装"
  say 快照 "$(printf '%s' "$SNAP_LINE" | cut -f4)"
  say 清单 "MANIFEST sha256 $(printf '%s' "$SNAP_LINE" | cut -f5)"
fi

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
  bak="$ARCH/p2-sampler-bak-$TS/$(rel "$dst")"
  case "$MODE" in
    check) say "$state" "$dst"; bad=1 ;;
    dry)
      if [ "$state" = 不同 ]; then say 覆盖 "${dst}（旧文件先挪到 ${bak}）"; else say 新建 "$dst"; fi ;;
    install)
      if [ -e "$dst" ]; then
        mkdir -p "$(dirname "$bak")"
        cp -p "$dst" "$bak"
        say 备份 "$dst -> $bak"
      fi
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
if [ "$MODE" = check ] && [ -x "$BIN/ops-v5-sampler" ]; then
  inst=$("$BIN/ops-v5-sampler" --version 2>/dev/null | awk '{print $2}' || true)
  if [ "$inst" = "$repo_version" ]; then say 一致 "版本 ${inst}"
  else say 版本错 "已装 ${inst:-读不出}，仓库 ${repo_version}"; bad=1; fi
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

# ---------------------------------------------------------------- 安装记录
if [ "$MODE" = install ]; then
  rec="$ARCH/p2-sampler-installed-$TS.tsv"
  {
    printf 'path\tsha256\n'
    for f in "$BIN/ops-v5-sampler" "$BIN/ops-v5-sample-replay" "$PLIST" "$CONF"; do
      printf '%s\t%s\n' "$f" "$(sha "$f")"
    done
  } > "$rec"
  # 和 backup.sh 的行同样 10 列：snapshot_dir 填记录文件，manifest_sha256 填记录文件的 sha256，rows 填文件数
  printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t-\t-\t-\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$MACHINE" \
    p2-sampler-installed "$rec" "$(sha "$rec")" 4 >> "$ILOG"
  say 记录 "$rec"
  sed 1d "$rec" | while IFS="$(printf '\t')" read -r f h; do say sha256 "$h  $f"; done
fi

# ---------------------------------------------------------------- 数据
if [ "$MODE" = check ]; then
  st="$STATE/ops-v5-sampler.status"
  if [ -f "$st" ]; then
    s_state=$(/usr/bin/python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("state","?"))' "$st" 2>/dev/null || echo "?")
    if [ "$s_state" = ok ]; then say 正常 "采样器状态 ok（${st}）"
    else say 报警 "采样器状态 ${s_state}：$(cat "$st")"; bad=1; fi
  else
    say 无状态 "${st} 不存在（采样器还没跑过）"; bad=1
  fi
  newest=$(ls -1 "$STATE"/samples/*/????-??-??.jsonl 2>/dev/null | awk -F/ '{print $NF "|" $0}' | sort | tail -n 1 | cut -d'|' -f2- || true)
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
  host=$MACHINE
  say 运行后 "采样器自己会建：${STATE}/samples/${host}/YYYY-MM-DD.jsonl、YYYY-MM-DD.sessions.jsonl"
  say 运行后 "${STATE}/ops-v5-sampler.lock、ops-v5-sampler.status、ops-v5-sampler.log、ops-v5-sampler.launchd.log、log-archive/"
  say 运行后 "${ARCH}/p2-sampler-installed-<时间>.tsv，install-log.tsv 追加 2 行（backup.sh 一行、安装记录一行）"
fi
[ "$MODE" = install ] && echo "完成。核对：$0 --check（装完 3 分钟后再跑，应有连续 3 个分钟的记录）"
exit 0
