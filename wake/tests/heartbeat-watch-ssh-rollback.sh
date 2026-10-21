#!/bin/bash
# B1 的回退测试：把本 PR 的代码换回 base，用本分支的演练整轮跑一次 wake/tests/heartbeat-watch-ssh.sh，看本 PR 会改变结果的
# 场景是不是真的挂了、本 PR 不改变结果的场景是不是照样过。期望先写在 automations/heartbeat-1021/FAILURE-MODES.md
# 「回退测试的期望」一节，下面的表照抄它。在 iMac 的仓库根目录跑：
#   wake/tests/heartbeat-watch-ssh-rollback.sh [<base commit>]   默认 f828d452；产物写到 reports/heartbeat-mba-imac-1021-rollback-<base 前 7 位>/
#   HB_ROLLBACK_OUT=<目录>                                       产物换个目录（目录里有 .hb-drill 标记才清空重写）
# 旧代码怎么放回去：临时目录里 git clone --shared 本仓库，检出 base（没有 scripts/orca-via-ssh 和 register.sh，heartbeat-watch.sh
# 是 base 那份），放进 HEAD 的演练脚本、回放数据和一份现网版 defs.json：MBA 那条的 precheck 用现网 box 94e4b0bc 的原文
# （environment iMac，不经 ssh），5c2d0575 各阶段都用它的现网原文。演练的安全措施照旧：heartbeat-watch 一律 --dry-run、
# 临时状态目录、假 webhook，orca 只读。
# 退出码：0 每项都和期望一致；1 有不一致的；2 跑不起来。
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
if ! base=$(git -C "$root" rev-parse --verify -q "${1:-f828d452345f16898d6c9d133984e170d98d9f83}^{commit}"); then
    echo "heartbeat-watch-ssh-rollback.sh：找不到 commit ${1:-}" >&2
    exit 2
fi
head=$(git -C "$root" rev-parse HEAD)
OUT=${HB_ROLLBACK_OUT:-$root/reports/heartbeat-mba-imac-1021-rollback-${base:0:7}}
T=$(mktemp -d -t hb-rollback)
trap 'rm -rf "$T"' EXIT
tree=$T/tree

# 旧代码：base 的干净检出。git clone --shared 只读本仓库的对象，不改本仓库。
common=$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd)
git clone -q --no-checkout --shared "$common" "$tree" || exit 2
git -C "$tree" -c advice.detachedHead=false checkout -q --detach "$base" || exit 2
git -C "$tree" update-ref refs/remotes/origin/main "$base"  # 演练用 merge-base HEAD origin/main 找 base
# 本分支的测试：HEAD 里的演练脚本和回放数据（不取工作区里没提交的改动）
git -C "$root" archive "$head" wake/tests/heartbeat-watch-ssh.sh wake/tests/hb-replay | tar -x -C "$tree" || exit 2
git -C "$root" show "$head:automations/heartbeat-1021/defs.json" >"$T/defs-head.json" || exit 2
mkdir -p "$tree/automations/heartbeat-1021"
python3 -I - "$T/defs-head.json" "$tree/automations/heartbeat-1021/defs.json" <<'PY' || exit 2
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
box = d["box"]
for c in d["create"]:  # MBA 那条：现网 box 94e4b0bc 盯 iMac ops · 01 的原文（environment iMac，不经 ssh）
    c["precheck"], c["precheckTimeout"] = box["precheck"], box["precheckTimeout"]
live = next(e for e in d["edit"] if e["stage"] == "parallel")["before"]  # 5c2d0575 的现网原文
for e in d["edit"]:
    keys = ("precheck", "precheckTimeout") if e["stage"] == "parallel" else ("name", "precheck", "precheckTimeout")
    e["set"] = {k: live[k] for k in keys}
d["_doc"] = ("回退测试用的现网版 defs（wake/tests/heartbeat-watch-ssh-rollback.sh 生成）：create 的 precheck 是现网 box 94e4b0bc "
             "的原文，5c2d0575 各阶段的 set 都是它的现网原文。")
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
PY
{
    echo "旧代码：${base}（git clone --shared 后 checkout --detach）"
    echo "测试取自：${head}"
    for f in scripts/orca-via-ssh automations/heartbeat-1021/register.sh scripts/heartbeat-watch.sh; do
        if [ -e "$tree/$f" ]; then echo "有 ${f}（sha256 $(shasum -a 256 "$tree/$f" | cut -c1-16)）"; else echo "没有 ${f}"; fi
    done
    echo "base 之外放进去的（git status --porcelain --untracked-files=all）："
    git -C "$tree" status --porcelain --untracked-files=all
} >"$T/tree.txt"
cat "$T/tree.txt"

HB_DRILL_OUT=$OUT HB_DRILL_NOTE="这是回退测试：代码是 base ${base:0:7}，演练脚本和回放数据取自 ${head:0:7}，defs 是现网版。和期望的对照见 ROLLBACK.md。" \
    /bin/bash "$tree/wake/tests/heartbeat-watch-ssh.sh" >"$T/drill.log" 2>&1
drc=$?
if [ $drc -gt 1 ] || [ ! -s "$OUT/results.tsv" ]; then
    echo "heartbeat-watch-ssh-rollback.sh：演练没跑起来（退出 ${drc}）：" >&2
    tail -20 "$T/drill.log" >&2
    exit 2
fi
mkdir -p "$OUT/rollback"
cp "$T/tree.txt" "$T/drill.log" "$OUT/rollback/"
cp "$tree/automations/heartbeat-1021/defs.json" "$OUT/rollback/defs-live.json"

python3 -I - "$OUT" "$base" "$head" <<'PY'
import json, os, sys
out, base, head = sys.argv[1:4]
# 照抄 automations/heartbeat-1021/FAILURE-MODES.md「回退测试的期望」：本 PR 会改变结果的 19 项该挂，其余 26 项照样过
FAIL = {}
for ids, why in (("S0.diff", "base 和「本分支」是同一份，没有第 13 行的改动"),
                 ("S2.sh S2.zsh", "现网版 precheck 在 MBA 上读不到 iMac ops · 01：MBA 的 Orca 没有 environment iMac"),
                 ("S4 S4b", "没有包装，heartbeat-watch 报的是 FileNotFoundError，不是 ssh 连不上的 JSONDecodeError"),
                 ("S4.wrapper S5.iMac S5.MBA S5b S7", "没有 scripts/orca-via-ssh"),
                 ("S6b.parallel S6b.final", "现网 5c2d0575 只有 box 目标，没有 MBA 目标"),
                 ("S8.mba S8.imac-noid S8.parallel S8.final S8.rollback S8.refuse", "没有 register.sh"),
                 ("S11", "orca-via-ssh、register.sh 不存在")):
    for i in ids.split():
        FAIL[i] = why
PASS = ("S0.same S0.bot " + " ".join("S1.c%02d" % n for n in range(1, 15)) + " S1.curl S3 S6 S6b.box "
        "S9.5c2d0575 S9.94e4b0bc S9.439cd438 S9.mba S10.MBA S10.iMac").split()
assert len(FAIL) == 19 and len(PASS) == 26
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(out, "results.tsv"), encoding="utf-8") if l.strip()]
got = {r[0]: r for r in rows}
order = [r[0] for r in rows] + [i for i in list(FAIL) + PASS if i not in got]
tab = []
for i in order:
    want = "FAIL" if i in FAIL else "PASS" if i in PASS else "不在期望表里"
    act = got[i][1] if i in got else "没有这一项"
    tab.append((i, want, act, "一致" if act == want else "不一致", FAIL.get(i, ""), got[i][3] if i in got else ""))
bad = sum(t[3] != "一致" for t in tab)
with open(os.path.join(out, "rollback.tsv"), "w", encoding="utf-8") as f:
    f.write("编号\t回退后期望\t实际\t和期望\t为什么该挂\t实际原文\n")
    for t in tab:
        f.write("\t".join(t) + "\n")

cell = lambda s, n=0: ((s[:n] + "…") if n and len(s) > n else s).replace("|", "\\|").replace("`", "'")
d = json.load(open(os.path.join(out, "rollback", "defs-live.json"), encoding="utf-8"))
mba_pc = next(c for c in d["create"] if c["machine"] == "mba")["precheck"]
imac_pc = next(e for e in d["edit"] if e["stage"] == "parallel")["set"]["precheck"]
env = open(os.path.join(out, "env.txt"), encoding="utf-8").read().strip().splitlines()
tree = open(os.path.join(out, "rollback", "tree.txt"), encoding="utf-8").read().strip().splitlines()
nf = sum(t[1] == "FAIL" and t[2] == "FAIL" for t in tab)
np_ = sum(t[1] == "PASS" and t[2] == "PASS" for t in tab)
L = ["# B1 回退测试：旧代码（base %s）上跑同一套演练" % base[:7], "",
     "**结果：%d 项里 %d 项和期望一致，%d 项不一致。期望挂的 19 项挂了 %d 项；期望过的 26 项过了 %d 项。**"
     % (len(tab), len(tab) - bad, bad, nf, np_), "",
     "把本 PR 的代码换回 base `%s`，用本分支 `%s` 的演练脚本和回放数据整轮跑 `wake/tests/heartbeat-watch-ssh.sh`。" % (base, head),
     "期望先写在 `automations/heartbeat-1021/FAILURE-MODES.md`「回退测试的期望」一节，再跑。这个文件由回退脚本生成。", "",
     "## 怎么重跑", "", "在 iMac 的仓库根目录：", "", "```bash", "wake/tests/heartbeat-watch-ssh-rollback.sh", "```", "",
     "要求和 `wake/tests/heartbeat-watch-ssh.sh` 一样。整个目录会被重写（有 `.hb-drill` 标记才清空）。", "",
     "## 旧代码怎么放回去", "",
     "- 在临时目录里 `git clone --shared` 本仓库，`checkout --detach` 到 base。base 里没有 `scripts/orca-via-ssh` 和 "
     "`automations/heartbeat-1021/register.sh`，`scripts/heartbeat-watch.sh` 是 base 那份。",
     "- 放进去的只有测试和定义：HEAD 的 `wake/tests/heartbeat-watch-ssh.sh`、`wake/tests/hb-replay/`，加一份现网版 "
     "`automations/heartbeat-1021/defs.json`（`rollback/defs-live.json`）。",
     "- 现网版 defs：MBA 那条的 precheck 是现网 box `94e4b0bc` 的原文 `%s`（environment `iMac`，不经 ssh）；`5c2d0575` 的并行版、"
     "最终版都是它的现网原文 `%s`。" % (mba_pc, imac_pc),
     "- 这个目录里的 `README.md`、`results.tsv`、`env.txt`、`raw/` 是演练脚本照常生成的：`env.txt` 的 commit 是 base，"
     "「未提交的改动」数的是上面放进去的文件。", "",
     "旧代码检出的情况（`rollback/tree.txt`）：", "", "```"] + tree + ["```", "",
     "## 这次运行", ""] + ["- " + cell(l) for l in env] + ["",
     "## 期望挂的 19 项（本 PR 会改变结果）", "",
     "| 编号 | 为什么该挂 | 实际 | 和期望 | 实际原文（截到 200 字） |", "|---|---|---|---|---|"]
L += ["| %s | %s | %s | %s | %s |" % (t[0], cell(t[4]), t[2], t[3], cell(t[5], 200)) for t in tab if t[1] == "FAIL"]
L += ["", "## 期望过的 26 项（本 PR 不改变结果，用来排除「是环境坏了才挂」）", "",
      "| 编号 | 实际 | 和期望 | 实际原文（截到 200 字） |", "|---|---|---|---|"]
L += ["| %s | %s | %s | %s |" % (t[0], t[2], t[3], cell(t[5], 200)) for t in tab if t[1] == "PASS"]
other = [t for t in tab if t[1] not in ("FAIL", "PASS")]
if other:
    L += ["", "## 不在期望表里的", "", "| 编号 | 实际 | 实际原文 |", "|---|---|---|"]
    L += ["| %s | %s | %s |" % (t[0], t[2], cell(t[5], 200)) for t in other]
L += ["", "## 文件", "",
      "- `rollback.tsv`：每项一行：编号、回退后期望、实际、和期望一不一致、为什么该挂、实际原文。",
      "- `rollback/tree.txt`：旧代码检出的情况。`rollback/defs-live.json`：现网版 defs。`rollback/drill.log`：演练的屏幕输出。",
      "- `README.md`、`results.tsv`、`env.txt`、`raw/`：演练脚本在旧代码上生成的，格式同 `reports/heartbeat-mba-imac-1021/`。",
      "- `SHA256SUMS`：除它自己以外所有文件的 sha256（`shasum -a 256 -c SHA256SUMS` 校验）。", ""]
open(os.path.join(out, "ROLLBACK.md"), "w", encoding="utf-8").write("\n".join(L))
for t in tab:
    print("%-6s %-16s 期望 %-4s 实际 %-4s %s" % (t[3], t[0], t[1], t[2], t[5][:120]))
print("回退测试：%d 项里 %d 项和期望一致，%d 项不一致" % (len(tab), len(tab) - bad, bad))
sys.exit(1 if bad else 0)
PY
rc=$?
(cd "$OUT" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r f; do shasum -a 256 "$f"; done >SHA256SUMS)
echo "产物：$OUT"
exit $rc
