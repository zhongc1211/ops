#!/bin/bash
# agent-tooling/install.sh — 把唤醒系统（orca-wake、notify-run、Pi 扩展、Claude hooks）装到本机。
# box (Linux) 和 iMac (macOS, bash 3.2) 通用。
#
#   install.sh --check             只比对 sha，不改任何文件；全一致退出 0，否则退出 1
#   install.sh                     装：有差异的先备份到 ~/.agent-tooling-backup/<时间>/ 再覆盖；幂等
#   install.sh --rollback <目录>   用某次 install 的备份目录恢复
#
# settings.json 只经 bin/orca-wake-hooks 改（只动 orca-wake 自己的 hook 组），不整文件覆盖。
# 不碰任何 *.env（webhook、runpod、everos 的密钥文件不归本脚本管）。
set -u

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
SETTINGS="$HOME/.claude/settings.json"
FRAGMENT="$REPO_DIR/claude/orca-wake-hooks.settings-fragment.json"

# 仓库内路径|安装路径（相对 $HOME）|权限
MANIFEST="
bin/orca-wake|.local/bin/orca-wake|755
bin/orca-wake-hooks|.local/bin/orca-wake-hooks|755
bin/notify-run|.local/bin/notify-run|755
pi-extensions/dispatch-wake.ts|.pi/agent/extensions/dispatch-wake.ts|644
pi-extensions/orca-agent-status.ts|.pi/agent/extensions/orca-agent-status.ts|644
orca-wake/enabled-bots|.config/orca-wake/enabled-bots|644
"

sha() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# 从 settings.json 摘出 orca-wake 的 hook 组，和仓库里的片段比（规范化 JSON 后比 sha）。
# 输出一行：ok / differs / missing / no-settings
hooks_state() {
    python3 - "$SETTINGS" "$FRAGMENT" <<'EOF'
import hashlib, json, os, sys
settings, fragment = sys.argv[1], sys.argv[2]
def canon(d):
    return hashlib.sha256(json.dumps(d, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
if not os.path.isfile(settings):
    print("no-settings"); sys.exit(0)
d = json.load(open(settings, encoding="utf-8"))
out = {}
for ev, groups in (d.get("hooks") or {}).items():
    for g in groups or []:
        cmds = [h.get("command") or "" for h in g.get("hooks") or [] if isinstance(h, dict)]
        if any("orca-wake" in c and "claude-hook" in c for c in cmds):
            out.setdefault(ev, []).append(g)
want = json.load(open(fragment, encoding="utf-8"))
if not out:
    print("missing")
elif canon({"hooks": out}) == canon(want):
    print("ok")
else:
    print("differs")
EOF
}

do_check() {
    rc=0
    echo "host: $(uname -s) $(hostname 2>/dev/null)  repo: $REPO_DIR"
    for line in $MANIFEST; do
        src=${line%%|*}; rest=${line#*|}; dst=${rest%%|*}
        want=$(sha "$REPO_DIR/$src")
        if [ ! -f "$HOME/$dst" ]; then
            echo "missing  ~/$dst  (repo $want)"; rc=1
        else
            have=$(sha "$HOME/$dst")
            if [ "$have" = "$want" ]; then
                echo "ok       ~/$dst  $want"
            else
                echo "differs  ~/$dst  installed $have  repo $want"; rc=1
            fi
        fi
    done
    hs=$(hooks_state) || hs="error"
    case "$hs" in
        ok) echo "ok       ~/.claude/settings.json orca-wake hooks" ;;
        *)  echo "$hs  ~/.claude/settings.json orca-wake hooks"; rc=1 ;;
    esac
    [ $rc -eq 0 ] && echo "check: all ok" || echo "check: differences found"
    return $rc
}

do_install() {
    ts=$(date +%Y%m%d-%H%M%S)
    bk="$HOME/.agent-tooling-backup/$ts"
    changed=0
    for line in $MANIFEST; do
        src=${line%%|*}; rest=${line#*|}; dst=${rest%%|*}; mode=${rest#*|}
        target="$HOME/$dst"
        if [ -f "$target" ] && [ "$(sha "$target")" = "$(sha "$REPO_DIR/$src")" ]; then
            echo "same     ~/$dst"
            continue
        fi
        mkdir -p "$bk"
        if [ -f "$target" ]; then
            mkdir -p "$bk/$(dirname "$dst")"
            cp -p "$target" "$bk/$dst" || { echo "backup failed: ~/$dst" >&2; exit 1; }
        else
            echo "$dst" >> "$bk/new-files.txt"
        fi
        mkdir -p "$(dirname "$target")"
        cp "$REPO_DIR/$src" "$target.agent-tooling.tmp" && chmod "$mode" "$target.agent-tooling.tmp" \
            && mv "$target.agent-tooling.tmp" "$target" || { echo "install failed: ~/$dst" >&2; exit 1; }
        echo "install  ~/$dst"
        changed=1
    done
    hs=$(hooks_state) || { echo "cannot read $SETTINGS" >&2; exit 1; }
    case "$hs" in
        ok) echo "same     ~/.claude/settings.json orca-wake hooks" ;;
        no-settings) echo "skip     ~/.claude/settings.json 不存在，hooks 没装" ;;
        *)
            mkdir -p "$bk"
            echo "$hs" > "$bk/hooks-before.txt"
            "$REPO_DIR/bin/orca-wake-hooks" install --settings "$SETTINGS" --backup-dir "$bk" || exit 1
            changed=1
            ;;
    esac
    if [ $changed -eq 1 ]; then
        echo "backup: $bk"
    else
        echo "nothing to do"
    fi
    do_check
}

do_rollback() {
    bk=$1
    [ -d "$bk" ] || { echo "no such backup dir: $bk" >&2; exit 1; }
    for line in $MANIFEST; do
        rest=${line#*|}; dst=${rest%%|*}
        if [ -f "$bk/$dst" ]; then
            cp -p "$bk/$dst" "$HOME/$dst" && echo "restore  ~/$dst"
        fi
    done
    if [ -f "$bk/new-files.txt" ]; then
        while read -r dst; do
            [ -n "$dst" ] && rm -f "$HOME/$dst" && echo "remove   ~/$dst"
        done < "$bk/new-files.txt"
    fi
    if [ -f "$bk/hooks-before.txt" ]; then
        # 用恢复后的 orca-wake-hooks 改回：原来没有就 remove，原来有就按旧版本重装
        hooks_bin="$HOME/.local/bin/orca-wake-hooks"
        [ -x "$hooks_bin" ] || hooks_bin="$REPO_DIR/bin/orca-wake-hooks"
        if [ "$(cat "$bk/hooks-before.txt")" = "missing" ]; then
            "$hooks_bin" remove --settings "$SETTINGS" --backup-dir "$bk"
        else
            "$hooks_bin" install --settings "$SETTINGS" --backup-dir "$bk"
        fi
    fi
    echo "rollback done from $bk"
}

case "${1:-}" in
    --check) do_check; exit $? ;;
    --rollback) [ -n "${2:-}" ] || { echo "usage: $0 --rollback <backup-dir>" >&2; exit 2; }; do_rollback "$2" ;;
    "") do_install ;;
    -h|--help) sed -n '2,10p' "$0" ;;
    *) echo "usage: $0 [--check | --rollback <backup-dir>]" >&2; exit 2 ;;
esac
