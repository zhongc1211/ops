#!/usr/bin/env bash
# 把 Claude Code 的 pstack 和 compound-engineering 插件钉在固定 commit（PER-83；起步版是 2026-10-20 交接第 5 项在三台机器上用过的脚本）。
#   本地目录源 ~/.claude/pinned-marketplaces/<名字>（detached HEAD）+ autoUpdate false + 10 条 deny 规则 + 挡人手输入的 UserPromptSubmit hook。
#   可重复运行；不重启正在跑的 claude 会话（新会话才生效）。说明、升级和回滚见同目录 README.md。
# 用法：pin-claude-plugins.sh [--check] [--home <dir>]
#   --check       只比对，不写任何文件；全部一致退出 0，任何一项不符退出 1
#   --home <dir>  当作 HOME 用（沙箱测试）；不给就用 $HOME
set -euo pipefail

PSTACK_SHA=88d47514b82e7c44f00f2b2a72ff6dd12158038c   # pstack 0.15.29（cursor/plugins）
CE_SHA=2e41b4490a37f53db0beb6d4904618da9af2f559       # compound-engineering 3.31.0

MODE=install
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check; shift ;;
    --home) [ $# -ge 2 ] || { echo "--home 要跟目录" >&2; exit 2; }; HOME=$(cd "$2" && pwd); export HOME; shift 2 ;;
    *) echo "用法：$0 [--check] [--home <dir>]" >&2; exit 2 ;;
  esac
done

HERE=$(cd "$(dirname "$0")" && pwd)
C="$HOME/.claude"; P="$C/pinned-marketplaces"
# 名字|仓库|commit|commit 里插件清单的路径（取期望版本号）|插件 id
PINS=(
  "cursor-plugins|https://github.com/cursor/plugins.git|$PSTACK_SHA|harness/pstack/claude-code/plugin.json|pstack@cursor-plugins"
  "compound-engineering-plugin|https://github.com/EveryInc/compound-engineering-plugin.git|$CE_SHA|.claude-plugin/plugin.json|compound-engineering@compound-engineering-plugin"
)
RULE='- 插件流程（compound-engineering、pstack 等）里的 push、开 PR、合并、部署一律按派活授权执行，派活没写就停在本地提交；测试按「测试规矩」（以 E2E 为准），插件的 tdd 和测试原则不覆盖它。（Zack 批，PER-67，2026-10-19）'
RULE_KEY='Zack 批，PER-67，2026-10-19'

# box / MBA 上可能没有 timeout，就不限时
t() { local s=$1; shift; if command -v timeout >/dev/null; then timeout "$s" "$@"; else "$@"; fi; }

if [ "$MODE" = check ]; then
  bad=0
  for it in "${PINS[@]}"; do
    IFS='|' read -r name url sha manifest id <<<"$it"
    d="$P/$name"
    head=$(git -C "$d" rev-parse HEAD 2>/dev/null || echo 缺失)
    if [ "$head" = "$sha" ]; then echo "一致  $name HEAD $sha"; else echo "不符  $name HEAD $head（期望 $sha）"; bad=1; fi
  done
  python3 - "$C" "$P" "$HERE/block-disabled-skills.sh" "$RULE_KEY" "${PINS[@]}" <<'PY' || bad=1
import json, os, subprocess, sys, filecmp
C, P, hook_src, rule_key, pins = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
bad = 0
def say(ok, what):
    global bad
    print(("一致  " if ok else "不符  ") + what)
    bad |= not ok
def load(f):
    try: return json.load(open(f))
    except Exception: return None
s = load(os.path.join(C, "settings.json")) or {}
km = load(os.path.join(C, "plugins", "known_marketplaces.json")) or {}
ip = (load(os.path.join(C, "plugins", "installed_plugins.json")) or {}).get("plugins", {})
deny = s.get("permissions", {}).get("deny", [])
for sk in ["pstack:poteto-mode", "pstack:tdd", "pstack:reflect", "pstack:setup-pstack", "compound-engineering:lfg"]:
    for r in (f"Skill({sk})", f"Skill({sk} *)"):
        say(r in deny, f"settings.json deny {r}")
for it in pins:
    name, url, sha, manifest, pid = it.split("|")
    path = os.path.join(P, name)
    want = {"source": {"source": "directory", "path": path}, "autoUpdate": False}
    say(s.get("extraKnownMarketplaces", {}).get(name) == want, f"settings.json extraKnownMarketplaces.{name} = 目录源 + autoUpdate false")
    say(s.get("enabledPlugins", {}).get(pid) is True, f"settings.json enabledPlugins.{pid} = true")
    e = km.get(name, {})
    say(e.get("source") == want["source"] and e.get("installLocation") == path and e.get("autoUpdate") is False,
        f"known_marketplaces.json {name} = 目录源 + autoUpdate false")
    try:
        ver = json.loads(subprocess.run(["git", "-C", path, "show", f"{sha}:{manifest}"], capture_output=True, check=True).stdout)["version"]
    except Exception:
        ver = None
    got = [x.get("version") for x in ip.get(pid, [])]
    say(ver is not None and got == [ver], f"installed_plugins.json {pid} 版本 {got}（期望 {ver}）")
hook = os.path.join(C, "hooks", "block-disabled-skills.sh")
say(os.path.isfile(hook) and filecmp.cmp(hook, hook_src, shallow=False), f"{hook} 和仓库里的一样")
cmd = 'bash "$HOME/.claude/hooks/block-disabled-skills.sh"'
ups = s.get("hooks", {}).get("UserPromptSubmit", [])
say(any(h.get("command") == cmd for e in ups for h in e.get("hooks", [])), "settings.json UserPromptSubmit 有 block-disabled-skills hook")
try: rule_ok = rule_key in open(os.path.join(C, "CLAUDE.md")).read()
except OSError: rule_ok = False
say(rule_ok, "CLAUDE.md 有 PER-67 插件授权规矩")
sys.exit(bad)
PY
  [ $bad = 0 ] && echo "全部一致。" || echo "有不符：不带 --check 再跑一次就会改成上面的期望（见 README）。"
  exit $bad
fi

mkdir -p "$P"
changed=0   # 检出切了 commit，或已装插件版本不是钉的版本，才需要跑 claude plugin（它每次都会改 lastUpdated）
for it in "${PINS[@]}"; do
  IFS='|' read -r name url sha manifest id <<<"$it"
  d="$P/$name"
  [ -d "$d/.git" ] || git clone --quiet "$url" "$d"
  git -C "$d" cat-file -e "$sha^{commit}" 2>/dev/null || git -C "$d" fetch --quiet origin
  [ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" = "$sha" ] || changed=1
  git -C "$d" -c advice.detachedHead=false checkout --quiet --detach "$sha"
  echo "$name $(git -C "$d" rev-parse HEAD)"
  python3 - "$C/plugins/installed_plugins.json" "$id" "$(git -C "$d" show "$sha:$manifest")" <<'PY' || changed=1
import json, sys
try: got = [x.get("version") for x in json.load(open(sys.argv[1]))["plugins"][sys.argv[2]]]
except Exception: got = None
sys.exit(got != [json.loads(sys.argv[3])["version"]])
PY
done
python3 - "$C" "$P" <<'PY'
import json,sys,os,datetime
C,P=sys.argv[1],sys.argv[2]
def load(f): return json.load(open(f)) if os.path.exists(f) else {}
def save(f,d,old):  # 内容没变就不写，重复运行不动文件
    if d==old: return
    with open(f+".tmp","w") as o: json.dump(d,o,indent=2,ensure_ascii=False); o.write("\n")
    os.replace(f+".tmp",f)
DENY=[f"Skill({s}{x})" for s in ["pstack:poteto-mode","pstack:tdd","pstack:reflect","pstack:setup-pstack","compound-engineering:lfg"] for x in ["", " *"]]
f=os.path.join(C,"settings.json"); d=load(f); old=json.loads(json.dumps(d))
perm=d.setdefault("permissions",{}); deny=perm.setdefault("deny",[])
for r in DENY:
    if r not in deny: deny.append(r)
ekm=d.setdefault("extraKnownMarketplaces",{})
for n in ["cursor-plugins","compound-engineering-plugin"]:
    ekm[n]={"source":{"source":"directory","path":os.path.join(P,n)},"autoUpdate":False}
ep=d.setdefault("enabledPlugins",{})
ep["pstack@cursor-plugins"]=True; ep["compound-engineering@compound-engineering-plugin"]=True
save(f,d,old)
k=os.path.join(C,"plugins","known_marketplaces.json"); os.makedirs(os.path.dirname(k),exist_ok=True)
km=load(k); old=json.loads(json.dumps(km))
for n in ["cursor-plugins","compound-engineering-plugin"]:
    e=km.get(n,{}); e.update({"source":{"source":"directory","path":os.path.join(P,n)},"installLocation":os.path.join(P,n),"autoUpdate":False}); e.setdefault("lastUpdated",datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")); km[n]=e
save(k,km,old)
print("settings ok")
PY
grep -qF "$RULE_KEY" "$C/CLAUDE.md" 2>/dev/null || printf '\n%s\n' "$RULE" >> "$C/CLAUDE.md"
bash "$HERE/install-block-hook.sh" "$HERE/block-disabled-skills.sh"
if [ $changed = 0 ]; then echo "插件已是钉的版本，跳过 claude plugin update"; exit 0; fi
cd /tmp
t 180 claude plugin marketplace update cursor-plugins || true
t 180 claude plugin marketplace update compound-engineering-plugin || true
if t 60 claude plugin list 2>/dev/null | grep -q 'pstack@cursor-plugins'; then t 180 claude plugin update pstack@cursor-plugins || true
else t 180 claude plugin install pstack@cursor-plugins; fi
if t 60 claude plugin list 2>/dev/null | grep -q 'compound-engineering@compound-engineering-plugin'; then t 180 claude plugin update compound-engineering@compound-engineering-plugin || true
else t 180 claude plugin install compound-engineering@compound-engineering-plugin; fi
