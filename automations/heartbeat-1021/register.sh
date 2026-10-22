#!/bin/bash
# register.sh mba|imac [--stage parallel|final|rollback] [--mba-id <id>] [--apply]
# 把 defs.json 变成 orca automations create / edit 命令（B1：盯 iMac ops · 01 的跨机看守从 box 挪到 MBA↔iMac）。
# 默认只打印（dry-run），不调用 orca。
#   mba            新建「ops · 29 心跳互查 MBA（盯 iMac ops · 01）」，一律 --disabled；启用另走 README 第 3 步。
#   imac           改 iMac 5c2d0575 的预检：--stage parallel（默认，保留 box 目标、加 MBA 目标）、
#                  final（去掉 box 目标并改名）、rollback（还原成 2026-10-21 的现网配置）。
#   --mba-id <id>  MBA 新任务建好后的 id；没给时 parallel / final 打印占位「<MBA 新任务 id>」，--apply 拒绝。
#   --apply        在本机用 orca 执行打印的命令。每一步现网改动都要 Zack 卡片批准、由 ops bot 执行（README）；
#                  主机名和第一个参数不一致时拒绝；README 那一步的备份文件不存在时拒绝。
set -u
here=$(cd "$(dirname "$0")" && pwd)
usage() { echo "用法：register.sh mba|imac [--stage parallel|final|rollback] [--mba-id <id>] [--apply]" >&2; exit 2; }
m=${1:-}
[ $# -gt 0 ] && shift
stage=parallel stage_set=no mba_id='' apply=no
while [ $# -gt 0 ]; do
    case $1 in
        --stage) [ $# -ge 2 ] || usage; stage=$2 stage_set=yes; shift 2 ;;
        --mba-id) [ $# -ge 2 ] || usage; mba_id=$2; shift 2 ;;
        --apply) apply=yes; shift ;;
        *) usage ;;
    esac
done
case $m in mba | imac) ;; *) usage ;; esac
case $stage in parallel | final | rollback) ;; *) usage ;; esac
[ "$m" = mba ] && [ $stage_set = yes ] && usage
if [ -n "$mba_id" ] && ! printf '%s' "$mba_id" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    echo "register.sh: --mba-id 要完整的 id（8-4-4-4-12 位小写十六进制）：${mba_id}" >&2
    exit 2
fi
if [ $apply = yes ]; then
    h=$(hostname -s | tr 'A-Z' 'a-z')
    case "$m:$h" in mba:mba | imac:imac*) ;; *) echo "register.sh: --apply ${m}，但这台是 ${h}；到 ${m} 上跑" >&2; exit 2 ;; esac
fi
python3 -I - "$here" "$m" "$stage" "$mba_id" "$apply" <<'PY'
import json, os, shlex, subprocess, sys
here, m, stage, mba_id, apply = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] == "yes"
d = json.load(open(os.path.join(here, "defs.json"), encoding="utf-8"))
HOLD = "<MBA 新任务 id>"
ARCHIVE = "~/ops-archive/heartbeat-1021"
rel = os.path.relpath(here, os.path.join(here, "..", ".."))  # 仓库根目录起的相对路径，README 让人在仓库根目录跑
cmds = []  # (注释行, argv, 显示用的命令, 备份文件)
if m == "mba":
    for c in d["create"]:
        if c["machine"] != m:
            continue
        prompt = open(os.path.join(here, c["prompt"]), encoding="utf-8").read().rstrip("\n")
        argv = ["orca", "automations", "create", "--name", c["name"], "--trigger", c["rrule"], "--timezone", c["timezone"],
                "--provider", c["provider"], f"--extra-agent-args={c['extraAgentArgs']}",
                "--workspace", c["workspace"].replace("$HOME", os.environ["HOME"]),
                "--precheck", c["precheck"], "--precheck-timeout", str(c["precheckTimeout"]),
                "--missed-run-grace-minutes", str(c["grace"]), "--fresh-session", "--disabled", "--prompt", prompt]
        shown = " ".join(map(shlex.quote, argv[:-1])) + ' "$(cat %s)"' % os.path.join(rel, c["prompt"])
        bk = f"{ARCHIVE}/mba-list.before.json"
        note = [f"# 先备份：mkdir -p {ARCHIVE} && orca automations list --json > {bk}", f"# {c['key']}：{c['why']}"]
        cmds.append((note, argv, shown, bk))
    after = ["# 建好后：orca automations list --json 里按名字找新 id，orca automations show --id <新 id> --json 核对 enabled=false 和 precheck。",
             "# 启用是 README 第 3 步（另要 Zack 卡片）：orca automations edit <新 id> --enabled"]
else:
    e = next(x for x in d["edit"] if x["machine"] == m and x["stage"] == stage)
    s = dict(e["set"])
    if stage != "rollback" and mba_id:
        s["precheck"] = s["precheck"].replace(HOLD, mba_id)
    argv = ["orca", "automations", "edit", e["id"]] + (["--name", s["name"]] if "name" in s else []) + \
           ["--precheck", s["precheck"], "--precheck-timeout", str(s["precheckTimeout"])]
    suffix = {"parallel": "before", "final": "before-final", "rollback": "before-rollback"}[stage]
    bk = f"{ARCHIVE}/{e['id']}.{suffix}.json"
    note = [f"# 先备份：mkdir -p {ARCHIVE} && orca automations show --id {e['id']} --json > {bk}", f"# {e['key']}：{e['why']}"]
    if HOLD in s["precheck"]:
        note.append(f"# 没给 --mba-id：下面的命令里是占位「{HOLD}」，不能照抄执行")
    cmds.append((note, argv, " ".join(map(shlex.quote, argv)), bk))
    box, env = d["box"], " --environment " + d["box"]["environment_on_imac"]
    after = {"parallel": ["# 之后并行一晚（README 第 5 步），第二天看两边的运行记录再走 final。"],
             "final": [f"# 这一条生效后，在 iMac 上先备份、再停 box 的旧看守（README 第 6 步；在 box 上跑就去掉{env}）：",
                       f"#   orca automations show --id {box['id']}{env} --json > {ARCHIVE}/{box['id']}.before.json",
                       f"#   orca automations edit {box['id']}{env} --disabled"],
             "rollback": [f"# 跑这一条之前，先重新启用 box 的旧看守、等它第一次运行正常（README 回滚表）：",
                          f"#   orca automations edit {box['id']}{env} --enabled",
                          "# 跑完这一条，最后停用 MBA 新任务：orca automations edit <MBA 新任务 id> --environment mba --disabled"]}[stage]
print(f"# register.sh {m}" + (f" --stage {stage}" if m == "imac" else "") + f"：{len(cmds)} 条命令，"
      + ("APPLY" if apply else "dry-run，不调用 orca"))
rc = 0
for note, argv, shown, bk in cmds:
    print("\n".join(note))
    print(shown)
    if not apply:
        continue
    if HOLD in " ".join(argv):
        print("register.sh: 命令里还是占位，先给 --mba-id", file=sys.stderr)
        sys.exit(2)
    path = os.path.expanduser(bk)
    if not (os.path.isfile(path) and os.path.getsize(path) > 0):
        print(f"register.sh: 没有备份 {bk}，先跑上面「先备份」那一行", file=sys.stderr)
        sys.exit(2)
    rc |= subprocess.run(argv).returncode
print("\n".join(after))
sys.exit(rc)
PY
