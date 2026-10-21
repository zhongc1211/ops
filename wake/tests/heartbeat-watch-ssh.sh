#!/bin/bash
# B1（automations/heartbeat-1021/）的演练：盯 iMac ops · 01 的跨机看守从 box 挪到 MBA↔iMac。在 iMac 的仓库根目录跑：
#   wake/tests/heartbeat-watch-ssh.sh           跑全部场景，产物写到 reports/heartbeat-mba-imac-1021/（目录里有 .hb-drill 标记才清空重写）
#   wake/tests/heartbeat-watch-ssh.sh --record  从本机 Orca 重录回放数据 wake/tests/hb-replay/fixtures/（只留 @@HB 行），然后退出
#   HB_DRILL_OUT=<目录>                          产物换个目录
# 要求：本机是 iMac（Orca 有 environment mba、grok-bot），能 ssh mba，MBA 能 ssh imac。退出码：0 全部 PASS，1 有 FAIL，2 跑不起来。
# 场景编号和要防的失败方式见 automations/heartbeat-1021/FAILURE-MODES.md；结果和期望写进产物目录的 README.md。
# 安全：heartbeat-watch 一律 --dry-run、临时 HB_STATE_DIR、假 webhook 目录（127.0.0.1:9 的假地址），不发叫醒、不读真凭据；
# orca 只用 automations list / show / runs；不往 ~/.orca-state/bin 装文件；MBA 上只用 mktemp -d 建的临时目录，跑完删掉。
# 替身：S1、S3 用回放（假 HB_ORCA，S1 还固定时钟），S5 用假 ssh，S8 用假 orca，这几个不算 E2E。
# S2、S4、S5b、S6、S6b、S7、S9、S10 是真机器、真 ssh、真 Orca（只读）。
# 内部用法：--mba-side <MBA 上的临时目录> <标记>，由 iMac 这边拷到 MBA 上跑 MBA 的场景。
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
WATCHED=439cd438-cffe-44dd-bd2b-23b07bfa3d61      # iMac ops · 01 卡住工作检查
TARGET="iMac ops · 01 卡住工作检查||${WATCHED}|20"  # defs.json 里 MBA 新任务的目标；environment 空 = HB_ORCA 连到的那台
STANDIN=62d18b16-74ca-4c7f-a670-04197e7652fe      # MBA ops · 09，S6 / S6b 里代替还没建的 MBA 新任务
BOX=94e4b0bc-0f9d-4cf2-a1fd-2282a888fe80
IMAC_WATCH=5c2d0575-dddc-4d5c-8f73-e47b26ea9a11
NOID=00000000-0000-0000-0000-000000000000
FAKEID=11111111-2222-3333-4444-555555555555
NOW=1792584000                                    # S1 的固定时钟：2026-10-21 20:00:00 SGT
MINPATH=/usr/bin:/bin:/usr/sbin:/sbin             # 近似 Orca 预检的最少环境
CANARY=

rssh() { ssh -o BatchMode=yes -o ConnectTimeout=10 mba "$@"; }

# 真路径的现状：MBA 上这三个都不该有；主检出的 HEAD 前后要一样（只读 rev-parse）。
real_paths() {
    local p
    for p in .orca-state/bin/heartbeat-watch.sh .orca-state/heartbeat-watch orca/workspaces/ops/scripts/orca-via-ssh; do
        if [ -e "$HOME/$p" ]; then echo "有 ~/$p"; else echo "没有 ~/$p"; fi
    done
    echo "主检出 HEAD $(git -C "$HOME/orca/workspaces/ops" rev-parse HEAD 2>&1)"
}

# S5：包装该拒绝的都退出 2、不调 ssh。PATH 最前面是只记录参数的假 ssh；最后两条是放行的对照，假 ssh 要记到一次。
s5() {
    local wrap=$1 o=$2
    mkdir -p "$o/bin"
    cat >"$o/bin/ssh" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '[%s]' "$a"; done >>"$FAKE_SSH_LOG"
printf '\n' >>"$FAKE_SSH_LOG"
echo '{"ok": true, "result": {"runs": []}}'
EOF
    chmod +x "$o/bin/ssh"
    s5_one "$wrap" "$o" edit 2 imac automations edit "$NOID" --name hb-drill-rejected
    s5_one "$wrap" "$o" edit-id 2 imac automations edit --id "$NOID" --disabled
    s5_one "$wrap" "$o" run 2 imac automations run --id "$NOID"
    s5_one "$wrap" "$o" create 2 imac automations create --name hb-drill-rejected --disabled
    s5_one "$wrap" "$o" remove 2 imac automations remove --id "$NOID"
    s5_one "$wrap" "$o" show 2 imac automations show --id "$NOID" --json
    s5_one "$wrap" "$o" other-group 2 imac environment list --json
    s5_one "$wrap" "$o" only-automations 2 imac automations
    s5_one "$wrap" "$o" no-args 2 imac
    s5_one "$wrap" "$o" host-unset 2 -unset- automations runs --id "$NOID" --json
    s5_one "$wrap" "$o" host-empty 2 '' automations runs --id "$NOID" --json
    s5_one "$wrap" "$o" host-option 2 '-oProxyCommand=sh -c "echo HBPWN >&2"' automations runs --id "$NOID" --json
    s5_one "$wrap" "$o" allow-runs 0 imac automations runs --id "$NOID" --json
    s5_one "$wrap" "$o" allow-list 0 imac automations list --json
}

# s5_one <包装> <目录> <名字> <期望退出码> <ORCA_SSH_HOST，-unset- 表示不设> <参数...>
s5_one() {
    local wrap=$1 o=$2 name=$3 want=$4 host=$5 hostenv
    shift 5
    hostenv="ORCA_SSH_HOST=$host"
    [ "$host" = -unset- ] && hostenv=HB_DRILL_NOHOST=1
    : >"$o/$name.ssh-calls"
    echo "$want" >"$o/$name.want"
    { printf '%s orca-via-ssh' "$hostenv"; printf ' %s' "$@"; echo; } >"$o/$name.cmd"
    env -i HOME="$HOME" PATH="$o/bin:$MINPATH" LANG=en_US.UTF-8 HB_DRILL_CANARY="$CANARY" FAKE_SSH_LOG="$o/$name.ssh-calls" \
        "$hostenv" "$wrap" "$@" >"$o/$name.out" 2>"$o/$name.err"
    echo $? >"$o/$name.rc"
}

# ---------- MBA 这边（iMac 拷过来的临时目录 $1 里跑，输出写 $1/out，iMac 再拷回去判断）----------
mba_side() {
    local R=$1 O=$1/out sh pc weird t0
    CANARY=$2
    mkdir -p "$O"
    real_paths >"$O/S10-before.txt"
    run() {  # run <名字> <额外环境变量...> -- <命令...>：最少环境 + 临时状态目录 + 假 webhook 目录
        local n=$1
        local -a e
        e=()
        shift
        while [ "$1" != -- ]; do e+=("$1"); shift; done
        shift
        env -i HOME="$HOME" PATH="$MINPATH" LANG=en_US.UTF-8 PYTHONDONTWRITEBYTECODE=1 HB_DRILL_CANARY="$CANARY" \
            STUCK_WEBHOOK_DIR="$R/hooks" ${e[@]+"${e[@]}"} "$@" >"$O/$n.out" 2>"$O/$n.err"
        echo $? >"$O/$n.rc"
    }
    # S2：defs.json 里 MBA 新任务的 precheck 原文（只换两个脚本路径、加 --dry-run），分别经 /bin/sh 和 /bin/zsh 跑。
    pc=$(cat "$R/s2-precheck.txt")
    for sh in sh zsh; do
        mkdir -p "$R/s2-$sh/state"
        printf '%s\n' "$pc" >"$O/S2-$sh.cmd"
        run "S2-$sh" HB_STATE_DIR="$R/s2-$sh/state" -- "/bin/$sh" -c "$pc"
    done
    echo "MBA S2 跑完"
    # S3：同样跑 --dry-run，HB_ORCA 换成回放，最新心跳 30 分钟前。
    mkdir -p "$R/s3/state"
    run S3 HB_STATE_DIR="$R/s3/state" HB_ORCA="$R/hb-replay/orca" HB_REPLAY_AGE_S=1800 HB_REPLAY_LOG="$O/S3.orca-calls" -- \
        "$R/heartbeat-watch.sh" --precheck --dry-run --target "$TARGET"
    echo "MBA S3 跑完"
    # S4：ORCA_SSH_HOST 指向不存在的主机。S4b：state 里种「50 分钟前起就查不到」。
    mkdir -p "$R/s4/state" "$R/s4b/state"
    t0=$(date +%s)
    run S4 HB_STATE_DIR="$R/s4/state" HB_ORCA="$R/orca-via-ssh" ORCA_SSH_HOST=no-such-host.invalid -- \
        "$R/heartbeat-watch.sh" --precheck --dry-run --target "$TARGET"
    echo $(($(date +%s) - t0)) >"$O/S4.secs"
    run S4-wrapper ORCA_SSH_HOST=no-such-host.invalid -- "$R/orca-via-ssh" automations runs --id "$WATCHED" --json
    python3 -I -c 'import json, sys, time; json.dump({sys.argv[1]: {"fail_since": time.time() - 3000}}, open(sys.argv[2], "w"))' \
        "$WATCHED" "$R/s4b/state/state.json"
    shasum -a 256 "$R/s4b/state/state.json" | cut -d' ' -f1 >"$O/S4b.state-before"
    run S4b HB_STATE_DIR="$R/s4b/state" HB_ORCA="$R/orca-via-ssh" ORCA_SSH_HOST=no-such-host.invalid -- \
        "$R/heartbeat-watch.sh" --precheck --dry-run --target "$TARGET"
    shasum -a 256 "$R/s4b/state/state.json" | cut -d' ' -f1 >"$O/S4b.state-after"
    echo "MBA S4 跑完"
    # S5：包装的拒绝（假 ssh）。S5b：真 ssh 到 iMac，参数里带各种 shell 特殊字符，看 orca 收到的是不是原样。
    s5 "$R/orca-via-ssh" "$O/S5"
    weird=$(cat "$R/weird.txt"; printf x)
    weird=${weird%x}
    run S5b ORCA_SSH_HOST=imac -- "$R/orca-via-ssh" automations list --environment "$weird" --json
    echo "MBA S5 跑完"
    # S7：MBA 上直接用包装读 iMac ops · 01 的运行记录和自动任务列表（原文不留，只留摘要）。
    run S7-runs ORCA_SSH_HOST=imac -- "$R/orca-via-ssh" automations runs --id "$WATCHED" --json
    run S7-list ORCA_SSH_HOST=imac -- "$R/orca-via-ssh" automations list --json
    python3 -I - "$O/S7-runs.out" "$O/S7-list.out" "$WATCHED" >"$O/S7.json" <<'PY'
import json, re, sys, time
runs_p, list_p, wid = sys.argv[1:4]
res = {}
try:
    d = json.load(open(runs_p, encoding="utf-8"))
    runs = (d.get("result") or {}).get("runs") or []
    hbs = [json.loads(m.group(1)) for r in runs
           for m in re.finditer(r"^@@HB (\{.*\})\s*$", (r.get("precheckResult") or {}).get("stdout") or "", re.M)]
    newest = max(hbs, key=lambda h: h["ts"]) if hbs else None
    res.update(runs_ok=d.get("ok"), runs=len(runs), hb_lines=len(hbs), newest_hb=newest,
               newest_hb_age_min=round((time.time() - newest["ts"]) / 60, 1) if newest else None,
               newest_run_status=runs[0].get("status") if runs else None)
except (OSError, ValueError) as e:
    res["runs_error"] = type(e).__name__
try:
    d = json.load(open(list_p, encoding="utf-8"))
    autos = (d.get("result") or {}).get("automations") or []
    a = [x for x in autos if x.get("id") == wid]
    res.update(list_ok=d.get("ok"), list_count=len(autos),
               watched={k: a[0].get(k) for k in ("name", "createdAt", "enabled")} if a else None)
except (OSError, ValueError) as e:
    res["list_error"] = type(e).__name__
print(json.dumps(res, ensure_ascii=False))
PY
    rm -f "$O/S7-runs.out" "$O/S7-list.out"
    echo "MBA S7 跑完"
    find "$R" -path '*/state/*' -type f | sed "s|^$R/||" | sort >"$O/S10-statefiles.txt"
    real_paths >"$O/S10-after.txt"
}

if [ "${1:-}" = --mba-side ]; then
    mba_side "$2" "$3"
    exit 0
fi

# ---------- iMac 这边 ----------
case ${1:-} in
    "" | --record) ;;
    *) echo "用法：wake/tests/heartbeat-watch-ssh.sh [--record]" >&2; exit 2 ;;
esac
T=$(mktemp -d -t hb-drill)
trap 'rm -rf "$T"' EXIT

if [ "${1:-}" = --record ]; then
    orca automations runs --id "$WATCHED" --json >"$T/runs.json" && orca automations list --json >"$T/list.json" || {
        echo "录不到：本机 orca automations runs / list 失败" >&2
        exit 2
    }
    python3 -I - "$T/runs.json" "$T/list.json" "$WATCHED" "$here/hb-replay/fixtures" <<'PY'
import datetime, json, os, re, sys
runs_p, list_p, wid, out = sys.argv[1:5]
when = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).strftime("%F %T SGT")
keep = []
for r in json.load(open(runs_p, encoding="utf-8"))["result"]["runs"]:
    pr = r.get("precheckResult")
    if pr:
        hb = [l for l in (pr.get("stdout") or "").splitlines() if re.fullmatch(r"@@HB \{.*\}\s*", l)]
        pr = {"exitCode": pr.get("exitCode"), "timedOut": pr.get("timedOut"), "durationMs": pr.get("durationMs"),
              "stdout": "".join(l + "\n" for l in hb)}
    keep.append({"createdAt": r["createdAt"], "status": r["status"], "precheckResult": pr})
autos = [{k: a[k] for k in ("id", "name", "createdAt")}
         for a in json.load(open(list_p, encoding="utf-8"))["result"]["automations"] if a["id"] == wid]
os.makedirs(out, exist_ok=True)
note = "%s 在 iMac 上录：orca automations %s --json。只留 heartbeat-watch 用到的字段，stdout 只留 @@HB 行。"
json.dump({"_recorded": note % (when, "runs --id " + wid), "ok": True, "result": {"runs": keep}},
          open(os.path.join(out, "runs-439cd438.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
json.dump({"_recorded": note % (when, "list"), "ok": True, "result": {"automations": autos}},
          open(os.path.join(out, "list-imac.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("录好：%d 条运行记录、%d 个自动任务 → %s" % (len(keep), len(autos), out))
PY
    exit $?
fi

OUT=${HB_DRILL_OUT:-$root/reports/heartbeat-mba-imac-1021}
if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT")" ] && [ ! -e "$OUT/.hb-drill" ]; then
    echo "heartbeat-watch-ssh.sh：$OUT 不空、也没有 .hb-drill 标记，不动它；换 HB_DRILL_OUT" >&2
    exit 2
fi
rm -rf "$OUT"
mkdir -p "$OUT/raw"
: >"$OUT/.hb-drill"
: >"$OUT/results.tsv"
CANARY=hbcanary-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')
mkdir -p "$T/hooks"
printf 'URL=http://127.0.0.1:9/hb-drill\nKEY=hb-drill-dummy-key\n' >"$T/hooks/coding-assistant.env"

oneline() { printf '%s' "$1" | tr '\t\n' '  '; }
res() {  # res <编号> <PASS|FAIL> <期望> <实际>
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$(oneline "$3")" "$(oneline "$4")" >>"$OUT/results.tsv"
    printf '%-4s %-16s %s\n' "$2" "$1" "$(oneline "$4")"
}
has() { grep -Fq -- "$2" "$1" 2>/dev/null; }
snip() {  # snip <文件> <子串>：第一行含这个子串的，去掉开头的时间戳，最多 240 个字
    python3 -I - "$1" "$2" <<'PY'
import re, sys
try:
    lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    lines = []
for l in lines:
    if sys.argv[2] in l:
        l = re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l)
        print(l[:240] + ("…" if len(l) > 240 else ""))
        break
PY
}
# expect <编号> <期望> <输出文件> <期望退出码> <退出码文件> <子串...>：子串都要有；「!」开头的不能有。实际 = 第一个子串所在行 + 退出码。
# 调用前设 XTRA（接在实际后面的说明）、XFAIL（非空就记 FAIL），用完清空。
XTRA='' XFAIL=''
expect() {
    local id=$1 want=$2 f=$3 wrc=$4 rcf=$5 v=PASS p first='' rc
    shift 5
    rc=$(cat "$rcf" 2>/dev/null || echo 没有)
    [ "$rc" = "$wrc" ] || v=FAIL
    for p in "$@"; do
        case $p in
            '!'*) ! has "$f" "${p#!}" || v=FAIL ;;
            *) has "$f" "$p" || v=FAIL; [ -n "$first" ] || first=$p ;;
        esac
    done
    has "$f" "$CANARY" && v=FAIL
    [ -n "$XFAIL" ] && v=FAIL
    res "$id" "$v" "${want}；退出 ${wrc}" "$(snip "$f" "$first")；退出 ${rc}${XTRA}"
    XTRA='' XFAIL=''
}

{
    echo "时间 $(TZ=Asia/Singapore date '+%F %T SGT')"
    echo "命令 wake/tests/heartbeat-watch-ssh.sh"
    echo "commit $(git -C "$root" rev-parse HEAD)（分支 $(git -C "$root" rev-parse --abbrev-ref HEAD)）"
    echo "代码有没有未提交的改动（scripts automations wake）：$(git -C "$root" status --porcelain -- scripts automations wake | wc -l | tr -d ' ') 个文件"
    echo "base（和 origin/main 的分叉点）$(git -C "$root" merge-base HEAD origin/main)"
    echo "iMac：$(hostname -s)，macOS $(sw_vers -productVersion) $(uname -m)，$(/bin/bash --version | head -1)，$(/usr/bin/python3 --version 2>&1)，orca $(orca --version 2>&1 | head -1)，shellcheck $(shellcheck --version 2>/dev/null | sed -n 2p | cut -d' ' -f2)"
    echo "MBA：$(rssh 'echo "$(hostname -s)，macOS $(sw_vers -productVersion) $(uname -m)，$(/bin/bash --version | head -1)，$(/usr/bin/python3 --version 2>&1)，orca $(zsh -lc "orca --version" 2>&1 | head -1)"' 2>&1)"
} >"$OUT/env.txt"
cat "$OUT/env.txt"
BASE=$(git -C "$root" merge-base HEAD origin/main)
IMAC_BEFORE=$(shasum -a 256 "$HOME/.orca-state/bin/heartbeat-watch.sh" 2>&1 | cut -d' ' -f1)
real_paths >"$T/imac-paths-before.txt"

# ---------- S0 静态：三版 heartbeat-watch 只差注释 ----------
V=$T/versions
mkdir -p "$V" "$OUT/raw/S0"
git -C "$root" show "$BASE:scripts/heartbeat-watch.sh" >"$V/base.sh"
cp "$root/scripts/heartbeat-watch.sh" "$V/new.sh"
VERS="base new"
if [ -f "$HOME/.orca-state/bin/heartbeat-watch.sh" ]; then
    cp "$HOME/.orca-state/bin/heartbeat-watch.sh" "$V/installed.sh"
    VERS="base installed new"
fi
chmod +x "$V"/*.sh
for v in $VERS; do
    printf '%s 整个文件      %s\n' "$v" "$(shasum -a 256 <"$V/$v.sh" | cut -d' ' -f1)"
    printf '%s Python 部分   %s\n' "$v" "$(sed -n '/^exec "\$PY" - "\$@" <<.PYEOF.$/,/^PYEOF$/p' "$V/$v.sh" | shasum -a 256 | cut -d' ' -f1)"
    printf '%s 去掉注释行    %s\n' "$v" "$(grep -v '^[[:space:]]*#' "$V/$v.sh" | shasum -a 256 | cut -d' ' -f1)"
done >"$OUT/raw/S0/sha256.txt"
diff "$V/base.sh" "$V/new.sh" >"$OUT/raw/S0/diff-base-new.txt"
[ -f "$V/installed.sh" ] && diff "$V/installed.sh" "$V/new.sh" >"$OUT/raw/S0/diff-installed-new.txt"
v=PASS
[ "$(grep -c '^[0-9]' "$OUT/raw/S0/diff-base-new.txt")" = 1 ] && [ "$(head -1 "$OUT/raw/S0/diff-base-new.txt")" = 13c13 ] || v=FAIL
res S0.diff "$v" "和 base 比只改了第 13 行（一处 13c13）" "$(grep '^[0-9]' "$OUT/raw/S0/diff-base-new.txt" | tr '\n' ' ')"
v=PASS
for k in "Python 部分" "去掉注释行"; do
    [ "$(grep -F "$k" "$OUT/raw/S0/sha256.txt" | awk '{print $NF}' | sort -u | wc -l | tr -d ' ')" = 1 ] || v=FAIL
done
res S0.same "$v" "${VERS} 三版的 Python 部分、去掉 # 注释行后的全文 sha256 都一样" "$(grep -F 'Python 部分' "$OUT/raw/S0/sha256.txt" | awk '{print $1 "=" substr($NF,1,12)}' | tr '\n' ' ')"
v=PASS
[ "$(sed -n 33p "$V/new.sh")" = 'BOT = "coding-assistant"' ] && [ "$(sed -n 33p "$V/base.sh")" = 'BOT = "coding-assistant"' ] || v=FAIL
res S0.bot "$v" '第 33 行仍是 BOT = "coding-assistant"' "$(sed -n 33p "$V/new.sh")"

# ---------- S1 回放：三版对同一份录好的数据输出逐字节一致（替身：假 HB_ORCA + 固定时钟）----------
mkdir -p "$OUT/raw/S1" "$T/s1bin" "$T/s1home"
printf '#!/bin/sh\necho "$*" >>"%s"\nexit 7\n' "$T/curl-calls" >"$T/s1bin/curl"
chmod +x "$T/s1bin/curl"
: >"$T/curl-calls"
# s1 <例子> <回放的环境变量，空格隔开> <种进 state.json 的内容，- 表示不种> <heartbeat-watch 参数...>
s1() {
    local c=$1 spec=$2 seed=$3 v s kv e
    shift 3
    echo "$spec" >"$OUT/raw/S1/$c.env"
    { printf 'heartbeat-watch.sh'; printf ' "%s"' "$@"; echo; } >"$OUT/raw/S1/$c.cmd"
    [ "$seed" = - ] || echo "$seed" >"$OUT/raw/S1/$c.seed.json"
    for v in $VERS; do
        s=$T/s1/$c-$v/state
        mkdir -p "$s"
        [ "$seed" = - ] || echo "$seed" >"$s/state.json"
        e=()
        for kv in $spec; do e+=("$kv"); done
        env -i HOME="$T/s1home" PATH="$T/s1bin:$MINPATH" LANG=en_US.UTF-8 PYTHONPATH="$here/hb-replay/clock" \
            PYTHONDONTWRITEBYTECODE=1 HB_FAKE_NOW="$NOW" HB_ORCA="$here/hb-replay/orca" HB_REPLAY_LOG="$OUT/raw/S1/$c.$v.orca-calls" \
            HB_STATE_DIR="$s" STUCK_WEBHOOK_DIR="$T/hooks" ${e[@]+"${e[@]}"} \
            /bin/bash "$V/$v.sh" "$@" >"$OUT/raw/S1/$c.$v.out" 2>"$OUT/raw/S1/$c.$v.err"
        echo $? >"$OUT/raw/S1/$c.$v.rc"
    done
}
# s1_check <例子> <期望> <期望退出码> <子串...>：先比三版的 stdout、stderr、退出码，再看本分支这版的输出。
s1_check() {
    local c=$1 want=$2 wrc=$3 x k same=三版一致 f=$OUT/raw/S1/$1.new
    shift 3
    for x in $VERS; do
        [ "$x" = new ] && continue
        for k in out err rc; do
            cmp -s "$OUT/raw/S1/$c.$x.$k" "$f.$k" || same="和 ${x} 不一致（${k}）"
        done
    done
    cat "$f.out" "$f.err" >"$T/s1-$c.all"
    XTRA="；${same}"
    [ "$same" = 三版一致 ] || XFAIL=1
    expect "S1.$c" "${want}；三版一致" "$T/s1-$c.all" "$wrc" "$f.rc" "$@"
}
W=$WATCHED
s1 c01 "HB_REPLAY_AGE_S=120" - --precheck --dry-run --target "$TARGET"
s1 c02 "HB_REPLAY_AGE_S=1800" - --precheck --dry-run --target "$TARGET"
s1 c03 "HB_REPLAY_AGE_S=60 HB_REPLAY_MODE=scan-stale HB_REPLAY_SCAN_AGE_S=2400" - --precheck --dry-run --target "$TARGET"
s1 c04 "HB_REPLAY_MODE=nohb" - --precheck --dry-run --target "$TARGET"
s1 c05 "HB_REPLAY_AGE_S=120" "{\"$W\": {\"last_hb\": $((NOW - 3600)), \"alerted\": $((NOW - 3000)), \"why\": \"演练种的：60 分钟没有新心跳\"}}" \
    --precheck --dry-run --target "$TARGET"
s1 c06 "HB_REPLAY_MODE=unreachable" - --precheck --dry-run --target "$TARGET"
s1 c07 "HB_REPLAY_MODE=unreachable" "{\"$W\": {\"fail_since\": $((NOW - 3000))}}" --precheck --dry-run --target "$TARGET"
s1 c08 "HB_REPLAY_MODE=garbage" - --precheck --dry-run --target "$TARGET"
s1 c09 "HB_REPLAY_MODE=new HB_REPLAY_CREATED_AGE_S=300" - --precheck --dry-run --target "$TARGET"
s1 c10 "HB_REPLAY_AGE_S=1800" "{\"$W\": {\"last_hb\": $((NOW - 2400)), \"alerted\": $((NOW - 600)), \"why\": \"演练种的：已经报过\"}}" \
    --precheck --dry-run --target "$TARGET"
s1 c11 "" - --precheck --dry-run --target "坏的目标|没有 id"
s1 c12 "HB_REPLAY_MODE=error" - --precheck --dry-run --target "$TARGET"
s1 c13 "HB_REPLAY_AGE_S_94e4b0bc=60 HB_REPLAY_AGE_S_62d18b16=1800" - --precheck --dry-run \
    --target "box ops · 29 卡住检查心跳|grok-bot|${BOX}|20" --target "MBA ops · 29 心跳互查|mba|${STANDIN}|20"
s1 c14 "HB_REPLAY_AGE_S=120" - --dry-run --target "$TARGET"
ST='"kind": "heartbeat_stale"'
TO="dry-run，将 POST 给 coding-assistant："
s1_check c01 "正常：心跳 2 分钟前，不发" 1 "iMac ops · 01 卡住工作检查：正常（最新心跳" "!将 POST 给"
s1_check c02 "心跳过期 30 分钟：报 heartbeat_stale 给 coding-assistant" 1 "：中断：最新心跳在" "已 30 分钟没有新的（阈值 20 分钟）" "$TO" "$ST" '"bot": "coding-assistant"'
s1_check c03 "心跳还在、扫描 40 分钟没跑完：报 heartbeat_stale" 1 "：中断：心跳还在" "已 40 分钟没跑完" "$TO" "$ST"
s1_check c04 "运行记录里没有 @@HB：报 heartbeat_stale" 1 "次运行记录里没有心跳行（@@HB）" "$TO" "$ST"
s1_check c05 "之前报过中断、现在心跳正常：报一次 heartbeat_recovered" 1 "已恢复，报过一次" "：正常（最新心跳" "$TO" '"kind": "heartbeat_recovered"'
s1_check c06 "连不上（ssh 退出 255、stdout 空）：记「查不到」，45 分钟内不报" 1 "：运行记录查不到（JSONDecodeError），已连续 0 分钟" "!将 POST 给" "!脚本出错"
s1_check c07 "50 分钟前起就查不到：报 heartbeat_stale「连不上 本机 的 Orca」" 1 "：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（JSONDecodeError）" "$TO" "$ST"
s1_check c08 "输出不是 JSON：记「查不到」，不报" 1 "：运行记录查不到（JSONDecodeError），已连续 0 分钟" "!将 POST 给" "!脚本出错"
s1_check c09 "新建 5 分钟、还没有运行记录：不判断" 1 "：自动任务建好 5 分钟（不到 20 分钟），还没有心跳，这次不判断" "!将 POST 给"
s1_check c10 "还在中断、已经报过：不重复报" 1 "：还在中断（" "起已报过，不重复报）" "!将 POST 给"
s1_check c11 "目标写错：用法错误" 2 "用法：heartbeat-watch.sh" "!将 POST 给"
s1_check c12 "orca 回 ok:false：记「查不到」，不报" 1 '：运行记录查不到（{"code": "automation_not_found"' "!将 POST 给" "!脚本出错"
s1_check c13 "两个目标（5c2d0575 并行版的样子）：box 正常、MBA 那条过期只报 MBA" 1 "MBA ops · 29 心跳互查：中断：最新心跳在" "box ops · 29 卡住检查心跳：正常（最新心跳" "$TO" "检查任务没在跑：MBA ops · 29 心跳互查" "!检查任务没在跑：box"
s1_check c14 "不带 --precheck、正常：退出 0" 0 "：正常（最新心跳" "!将 POST 给"
v=PASS
[ -s "$T/curl-calls" ] && v=FAIL
res S1.curl "$v" "S1 全部 --dry-run：PATH 里的假 curl 一次都没被调用" "假 curl 被调用 $(wc -l <"$T/curl-calls" | tr -d ' ') 次"

# ---------- S5 包装拒绝（iMac 这边；MBA 那边在 MBA 上跑同一套）----------
s5 "$root/scripts/orca-via-ssh" "$T/s5-imac"
mkdir -p "$OUT/raw/S5-imac"
# s5_judge <目录> <机器>
s5_judge() {
    local o=$1 m=$2 n want rc calls v bad='' ok=0 total=0
    for f in "$o"/*.want; do
        n=$(basename "$f" .want)
        want=$(cat "$f")
        rc=$(cat "$o/$n.rc")
        calls=$(wc -l <"$o/$n.ssh-calls" | tr -d ' ')
        total=$((total + 1))
        v=ok
        [ "$rc" = "$want" ] || v=bad
        case $n in
            allow-*) [ "$calls" = 1 ] && grep -q '^\[-o\]\[BatchMode=yes\]\[-o\]\[ConnectTimeout=10\]\[imac\]\[zsh -lc ' "$o/$n.ssh-calls" || v=bad ;;
            *) [ "$calls" = 0 ] || v=bad ;;
        esac
        if grep -rqF -- "$CANARY" "$o/$n.out" "$o/$n.err"; then v=bad; fi
        if [ $v = ok ]; then ok=$((ok + 1)); else bad="$bad $n(退出 ${rc}，ssh ${calls} 次)"; fi
    done
    v=PASS
    [ "$ok" = "$total" ] && [ "$total" = 14 ] || v=FAIL
    res "S5.${m}" "$v" "${m}：edit / run / create / remove / show、别的命令组、参数不全、ORCA_SSH_HOST 没设 / 空 / 以 - 开头，共 12 条都退出 2、假 ssh 0 次；放行的 runs、list 两条对照假 ssh 各记到 1 次；输出里没有标记环境变量" \
        "${ok}/${total} 条符合${bad:+；不符：}${bad}；edit 那条：$(head -1 "$o/edit.err")"
}
s5_judge "$T/s5-imac" iMac
cp "$T/s5-imac"/*.cmd "$T/s5-imac"/*.rc "$T/s5-imac"/*.err "$T/s5-imac"/*.ssh-calls "$OUT/raw/S5-imac/"

# ---------- S9 现网配置和 defs.json 对得上（只读 show / list）----------
mkdir -p "$OUT/raw/S9"
python3 -I - "$root/automations/heartbeat-1021/defs.json" "$OUT/raw/S9" "$OUT/results.tsv" "$IMAC_WATCH" "$BOX" "$WATCHED" "$STANDIN" <<'PY'
import json, os, subprocess, sys, time
defs = json.load(open(sys.argv[1], encoding="utf-8"))
out, tsv, imac_watch, box, watched, standin = sys.argv[2:8]


def orca(*a):
    """只读的 orca 调用，连不上（box 的隧道常断几分钟）时最多 3 次、间隔 8 秒。"""
    err = None
    for n in range(3):
        if n:
            time.sleep(8)
        p = subprocess.run(["orca", *a, "--json"], capture_output=True, text=True, timeout=90)
        try:
            d = json.loads(p.stdout)
        except ValueError:
            err = "输出不是 JSON（退出 %s）" % p.returncode
            continue
        if d.get("ok"):
            return d["result"], n + 1, None
        err = json.dumps(d.get("error"), ensure_ascii=False)
    return None, 3, err


def pick(a):
    return {k: a.get(k) for k in ("id", "name", "enabled", "rrule", "timezone", "missedRunGraceMinutes", "precheck")}


def res(cid, ok, want, got):
    line = "%s\t%s\t%s\t%s" % (cid, "PASS" if ok else "FAIL", want, got)
    open(tsv, "a", encoding="utf-8").write(line.replace("\n", " ") + "\n")
    print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", cid, got))


shown = {}
for key, args in (("5c2d0575", ["--id", imac_watch]), ("94e4b0bc", ["--id", box, "--environment", "grok-bot"]),
                  ("439cd438", ["--id", watched])):
    r, tries, err = orca("automations", "show", *args)
    shown[key] = pick(r["automation"]) if r else None
    json.dump({"command": "orca automations show %s --json" % " ".join(args), "tries": tries, "error": err,
               "automation": shown[key]}, open(os.path.join(out, key + ".json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
before = next(e for e in defs["edit"] if e["stage"] == "parallel")["before"]
a = shown["5c2d0575"]
res("S9.5c2d0575", bool(a) and a["enabled"] and a["name"] == before["name"] and a["precheck"]["command"] == before["precheck"]
    and a["precheck"]["timeoutSeconds"] == before["precheckTimeout"],
    "iMac 5c2d0575 现网的名字、precheck、超时和 defs.json 的 before 一样（回滚就还原成这个），启用中",
    ("名字「%s」、超时 %s、启用 %s、precheck %s defs" % (a["name"], a["precheck"]["timeoutSeconds"], a["enabled"],
     "等于" if a["precheck"]["command"] == before["precheck"] else "不等于")) if a else "读不到")
b, bx = shown["94e4b0bc"], defs["box"]
res("S9.94e4b0bc", bool(b) and b["enabled"] == bx["enabled"] and b["name"] == bx["name"] and b["precheck"]["command"] == bx["precheck"]
    and b["precheck"]["timeoutSeconds"] == bx["precheckTimeout"] and b["rrule"] == "*/5 * * * *" and b["missedRunGraceMinutes"] == 720,
    "box 94e4b0bc（经 grok-bot）现网的名字、precheck、超时 240 和 defs.json 一样，启用中；每 5 分钟、grace 720（MBA 新任务照抄）",
    ("名字「%s」、rrule %s、超时 %s、grace %s、启用 %s、precheck %s defs" % (b["name"], b["rrule"], b["precheck"]["timeoutSeconds"],
     b["missedRunGraceMinutes"], b["enabled"], "等于" if b["precheck"]["command"] == bx["precheck"] else "不等于")) if b
    else "读不到：%s" % json.load(open(os.path.join(out, "94e4b0bc.json"), encoding="utf-8"))["error"])
c, wd = shown["439cd438"], defs["watched"]
res("S9.439cd438", bool(c) and c["enabled"] and c["name"] == wd["name"] and c["precheck"]["timeoutSeconds"] == wd["precheckTimeout"],
    "iMac ops · 01 439cd438 启用中，名字和 precheck 超时（600）和 defs.json 一样",
    ("名字「%s」、超时 %s、启用 %s、rrule %s" % (c["name"], c["precheck"]["timeoutSeconds"], c["enabled"], c["rrule"])) if c else "读不到")
r, tries, err = orca("automations", "list", "--environment", "mba")
autos = r["automations"] if r else []
new_name = defs["create"][0]["name"]
same = [x["id"] for x in autos if x["name"] == new_name]
st = [x["name"] for x in autos if x["id"] == standin]
json.dump({"command": "orca automations list --environment mba --json", "tries": tries, "error": err,
           "automations": [{k: x.get(k) for k in ("id", "name", "enabled")} for x in autos]},
          open(os.path.join(out, "mba-list.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
res("S9.mba", bool(r) and not same and bool(st),
    "MBA 上还没有「%s」（本 PR 没建任务）；S6 用的 ops · 09 %s 在" % (new_name, standin[:8]),
    ("%d 个自动任务，同名的 %d 个，ops · 09：%s" % (len(autos), len(same), st[0] if st else "没有")) if r else "读不到：%s" % err)
open(os.path.join(out, "live-5c2d0575-precheck.txt"), "w", encoding="utf-8").write(a["precheck"]["command"] if a else "")
PY

# ---------- S8 register.sh 只打印（替身：PATH 里只记录调用的假 orca）----------
mkdir -p "$OUT/raw/S8" "$T/s8bin"
printf '#!/bin/sh\necho "$*" >>"%s"\nexit 0\n' "$T/s8-orca-calls" >"$T/s8bin/orca"
chmod +x "$T/s8bin/orca"
: >"$T/s8-orca-calls"
s8() {  # s8 <名字> <期望退出码> <register.sh 参数...>
    local n=$1 want=$2
    shift 2
    echo "register.sh $*" >"$OUT/raw/S8/$n.cmd"
    PATH="$T/s8bin:$PATH" /bin/bash "$root/automations/heartbeat-1021/register.sh" "$@" >"$OUT/raw/S8/$n.out" 2>"$OUT/raw/S8/$n.err"
    echo $? >"$OUT/raw/S8/$n.rc"
    grep '^orca automations' "$OUT/raw/S8/$n.out" >"$T/s8-$n.cmdline"
}
s8 mba 0 mba
s8 imac 0 imac
s8 imac-parallel 0 imac --stage parallel --mba-id "$FAKEID"
s8 imac-final 0 imac --stage final --mba-id "$FAKEID"
s8 imac-rollback 0 imac --stage rollback
s8 bad-id 2 imac --mba-id 1234
s8 mba-stage 2 mba --stage final
s8 box 2 box
s8 stage-novalue 2 imac --stage
s8 unknown-flag 2 imac --force
PC_MBA="'HB_ORCA=\$HOME/orca/workspaces/ops/scripts/orca-via-ssh ORCA_SSH_HOST=imac \$HOME/.orca-state/bin/heartbeat-watch.sh --precheck --target \"iMac ops · 01 卡住工作检查||${WATCHED}|20\"'"
TB="--target \"box ops · 29 卡住检查心跳|grok-bot|${BOX}|20\""
TM="--target \"MBA ops · 29 心跳互查|mba|${FAKEID}|20\""
expect S8.mba "mba：create 带 --disabled、--fresh-session、每 5 分钟、超时 240、grace 720，precheck 是 defs 原文" "$T/s8-mba.cmdline" 0 "$OUT/raw/S8/mba.rc" \
    "orca automations create --name 'ops · 29 心跳互查 MBA（盯 iMac ops · 01）'" "--trigger '*/5 * * * *'" "--precheck $PC_MBA" \
    "--precheck-timeout 240" "--missed-run-grace-minutes 720" "--fresh-session" "--disabled"
cat "$OUT/raw/S8/imac.out" >"$T/s8-imac.all"
expect S8.imac-noid "imac 没给 --mba-id：命令里是占位，并提示不能照抄" "$T/s8-imac.all" 0 "$OUT/raw/S8/imac.rc" "没给 --mba-id" "|mba|<MBA 新任务 id>|20"
expect S8.parallel "parallel：保留 box 目标在前、加 MBA 目标，不改名" "$T/s8-imac-parallel.cmdline" 0 "$OUT/raw/S8/imac-parallel.rc" \
    "orca automations edit ${IMAC_WATCH} --precheck '\$HOME/.orca-state/bin/heartbeat-watch.sh --precheck ${TB} ${TM}' --precheck-timeout 240" "!--name" "!<MBA 新任务 id>"
expect S8.final "final：只剩 MBA 目标，改名「盯 MBA ops · 29」" "$T/s8-imac-final.cmdline" 0 "$OUT/raw/S8/imac-final.rc" \
    "orca automations edit ${IMAC_WATCH} --name 'ops · 29 心跳互查（盯 MBA ops · 29）' --precheck '\$HOME/.orca-state/bin/heartbeat-watch.sh --precheck ${TM}' --precheck-timeout 240" "!box ops · 29 卡住检查心跳"
LIVE=$(cat "$OUT/raw/S9/live-5c2d0575-precheck.txt" 2>/dev/null)
expect S8.rollback "rollback：还原成现网 5c2d0575 的名字和 precheck（S9 读到的原文）" "$T/s8-imac-rollback.cmdline" 0 "$OUT/raw/S8/imac-rollback.rc" \
    "orca automations edit ${IMAC_WATCH} --name 'ops · 29 心跳互查（盯 box ops · 29）' --precheck '${LIVE:-S9 没读到}' --precheck-timeout 240"
v=PASS
bad=''
for n in bad-id mba-stage box stage-novalue unknown-flag; do
    [ "$(cat "$OUT/raw/S8/$n.rc")" = 2 ] || { v=FAIL; bad="$bad $n"; }
done
[ -s "$T/s8-orca-calls" ] && v=FAIL
res S8.refuse "$v" "参数错（id 不完整、mba 带 --stage、机器名不对、--stage 没值、不认识的参数）都退出 2；整个 S8 假 orca 0 次调用（dry-run 不调 orca）" \
    "退出码不是 2 的：${bad:-没有}；假 orca 被调用 $(wc -l <"$T/s8-orca-calls" | tr -d ' ') 次；--apply 没跑（任务书禁止）"

# ---------- S6 iMac 经 environment mba 读 MBA 的一条现有任务；S6b 照 defs 原文跑 5c2d0575 的并行版、最终版 ----------
mkdir -p "$OUT/raw/S6" "$OUT/raw/S6b" "$T/s6/state"
TGT6="MBA ops · 09 内存与 CPU 负载清理|mba|${STANDIN}|20"
echo "heartbeat-watch.sh --dry-run --target \"$TGT6\"" >"$OUT/raw/S6/run.cmd"
env -u STUCK_FORCE_BOT -u HB_ORCA -u ORCA_SSH_HOST HB_STATE_DIR="$T/s6/state" STUCK_WEBHOOK_DIR="$T/hooks" PYTHONDONTWRITEBYTECODE=1 \
    /bin/bash "$V/new.sh" --dry-run --target "$TGT6" >"$OUT/raw/S6/run.out" 2>"$OUT/raw/S6/run.err"
echo $? >"$OUT/raw/S6/run.rc"
cat "$OUT/raw/S6/run.out" "$OUT/raw/S6/run.err" >"$T/s6.all"
expect S6 "iMac 经 environment mba 读到 MBA ops · 09 的运行记录：不是「查不到」，有运行记录和最新一次运行时间（它不打 @@HB，所以结论是没有心跳行）" \
    "$T/s6.all" 0 "$OUT/raw/S6/run.rc" "MBA ops · 09 内存与 CPU 负载清理：中断：最近 " "次运行记录里没有心跳行（@@HB），最新一次运行在 " "!运行记录查不到" "!最新一次运行在 从没有" "!最近 0 次"
# before-base：现网 5c2d0575 的 precheck（defs 里 before 的原文）用 base 版跑，紧接着并行版，给 S6b.box 当同一时刻的 base 对照。
for stage in parallel before-base final; do
    mkdir -p "$T/s6b-$stage/state"
    sv=$V/new.sh
    [ "$stage" = before-base ] && sv=$V/base.sh
    python3 -I - "$root/automations/heartbeat-1021/defs.json" "$stage" "$sv" "$STANDIN" >"$OUT/raw/S6b/$stage.cmd" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if sys.argv[2] == "before-base":
    p = next(x for x in d["edit"] if x["stage"] == "parallel")["before"]["precheck"]
else:
    p = next(x for x in d["edit"] if x["stage"] == sys.argv[2])["set"]["precheck"]
    assert p.count("<MBA 新任务 id>") == 1
old = "$HOME/.orca-state/bin/heartbeat-watch.sh"
assert p.count(old) == 1
print(p.replace(old, sys.argv[3]).replace("<MBA 新任务 id>", sys.argv[4]) + " --dry-run")
PY
    env -u STUCK_FORCE_BOT -u HB_ORCA -u ORCA_SSH_HOST HB_STATE_DIR="$T/s6b-$stage/state" STUCK_WEBHOOK_DIR="$T/hooks" PYTHONDONTWRITEBYTECODE=1 \
        /bin/sh -c "$(cat "$OUT/raw/S6b/$stage.cmd")" >"$OUT/raw/S6b/$stage.out" 2>"$OUT/raw/S6b/$stage.err"
    echo $? >"$OUT/raw/S6b/$stage.rc"
    cat "$OUT/raw/S6b/$stage.out" "$OUT/raw/S6b/$stage.err" >"$T/s6b-$stage.all"
done
# 对照：现网 5c2d0575 最近几次对 box 的结论（grok-bot 隧道常断几分钟，S6b.box 没过时看这里）。
python3 -I - "$IMAC_WATCH" >"$OUT/raw/S6b/live-5c2d0575-box.txt" <<'PY'
import datetime, json, subprocess, sys
p = subprocess.run(["orca", "automations", "runs", "--id", sys.argv[1], "--json"], capture_output=True, text=True, timeout=90)
try:
    runs = json.loads(p.stdout)["result"]["runs"]
except (ValueError, KeyError, TypeError):
    print("读不到（退出 %s）" % p.returncode)
    sys.exit(0)
for r in runs[:4]:
    box = [l for l in ((r.get("precheckResult") or {}).get("stdout") or "").splitlines() if "box ops · 29" in l]
    when = datetime.datetime.fromtimestamp(r["createdAt"] / 1000, datetime.timezone(datetime.timedelta(hours=8)))
    print(when.strftime("%H:%M"), (box[0][24:] if box else "（没有 box 那行，%s）" % r.get("status"))[:120])
PY
order=$(grep -n -e 'box ops · 29 卡住检查心跳：' -e 'MBA ops · 29 心跳互查：' "$T/s6b-parallel.all" | head -2 | cut -d' ' -f4 | cut -c1-3 | tr -d '\n')
XTRA="；box 那行：$(snip "$T/s6b-parallel.all" "box ops · 29 卡住检查心跳：")"
[ "$order" = boxMBA ] || { XFAIL=1; XTRA="${XTRA}；顺序不对（${order}）"; }
expect S6b.parallel "5c2d0575 并行版 precheck（defs 原文，MBA 新任务 id 用 ops · 09 代替）：box 目标在前、出一行结论，MBA 目标读到运行记录，没有脚本出错" \
    "$T/s6b-parallel.all" 1 "$OUT/raw/S6b/parallel.rc" "MBA ops · 29 心跳互查：中断：最近 " "box ops · 29 卡住检查心跳：" \
    "!MBA ops · 29 心跳互查：运行记录查不到" "!最近 0 次" "!脚本出错"
XTRA=''
has "$T/s6b-parallel.all" "box ops · 29 卡住检查心跳：正常（最新心跳" || XTRA="；本次 box 那行：$(snip "$T/s6b-parallel.all" "box ops · 29 卡住检查心跳：")"
XTRA="${XTRA}；紧接着用 base 版跑现网 precheck（raw/S6b/before-base.*）：$(snip "$T/s6b-before-base.all" "box ops · 29 卡住检查心跳：")"
XTRA="${XTRA}；现网 5c2d0575 最近几次对 box 的结论：$(tr '\n' ' ' <"$OUT/raw/S6b/live-5c2d0575-box.txt")"
expect S6b.box "并行版里的 box 目标正常。要 iMac 到 box 的 grok-bot 隧道当时是通的；没过时对照同一时刻 base 版跑现网 precheck 的结论和现网 5c2d0575 的运行记录（都在实际一栏）" \
    "$T/s6b-parallel.all" 1 "$OUT/raw/S6b/parallel.rc" "box ops · 29 卡住检查心跳：正常（最新心跳"
expect S6b.final "5c2d0575 最终版 precheck：只查 MBA 目标，读到运行记录" \
    "$T/s6b-final.all" 1 "$OUT/raw/S6b/final.rc" "MBA ops · 29 心跳互查：中断：最近 " "!box ops · 29" "!运行记录查不到" "!最近 0 次"

# ---------- MBA 这边：S2、S3、S4、S4b、S5、S5b、S7、S10 ----------
WEIRD="hb'drill \"q\" \$(echo HBX) \`echo HBY\` ; echo HBZ && echo HBW * \\ \$HOME 中文 · |
第二行"
M=$OUT/raw/mba
mkdir -p "$M" "$T/bundle/hooks" "$T/bundle/hb-replay"
R=$(rssh 'mktemp -d -t hb-drill' 2>"$T/mktemp.err")
case $R in
    /*/hb-drill.*) case $R in *[!A-Za-z0-9/._-]*) R= ;; esac ;;
    *) R= ;;
esac
if [ -z "$R" ]; then
    res S2 FAIL "MBA 上建临时目录" "ssh mba 失败：$(head -2 "$T/mktemp.err" | tr '\n' ' ')；MBA 的场景都没跑"
else
    echo "MBA 临时目录 $R" >"$M/tmpdir.txt"
    cp "$root/scripts/heartbeat-watch.sh" "$root/scripts/orca-via-ssh" "$T/bundle/"
    cp "$here/heartbeat-watch-ssh.sh" "$T/bundle/drill.sh"
    cp -R "$here/hb-replay/." "$T/bundle/hb-replay/"
    cp "$T/hooks/coding-assistant.env" "$T/bundle/hooks/"
    printf '%s' "$WEIRD" >"$T/bundle/weird.txt"
    python3 -I - "$root/automations/heartbeat-1021/defs.json" "$R" >"$T/bundle/s2-precheck.txt" <<'PY'
import json, sys
c = next(x for x in json.load(open(sys.argv[1], encoding="utf-8"))["create"] if x["machine"] == "mba")
p, r = c["precheck"], sys.argv[2]
for old, new in (("$HOME/orca/workspaces/ops/scripts/orca-via-ssh", r + "/orca-via-ssh"),
                 ("$HOME/.orca-state/bin/heartbeat-watch.sh", r + "/heartbeat-watch.sh")):
    assert p.count(old) == 1, old
    p = p.replace(old, new)
print(p + " --dry-run")
PY
    COPYFILE_DISABLE=1 tar -C "$T/bundle" -cf - . | rssh "tar -C '$R' -xf -"
    rssh "/bin/bash '$R/drill.sh' --mba-side '$R' '$CANARY'" >"$M/mba-side.log" 2>&1
    echo "MBA 那边退出 $?" >>"$M/mba-side.log"
    rssh "COPYFILE_DISABLE=1 tar -C '$R/out' -cf - ." | tar -C "$M" -xf -
    rssh "rm -rf '$R'; test -e '$R' && echo 还在 || echo 删掉了" >"$M/tmpdir-cleanup.txt" 2>&1
fi

if [ -n "$R" ]; then
    for sh in sh zsh; do
        cat "$M/S2-$sh.out" "$M/S2-$sh.err" >"$T/S2-$sh.all" 2>/dev/null
        expect "S2.$sh" "MBA 上经 /bin/${sh} 跑 defs 原文（env -i 最少环境，只换两个脚本路径，加 --dry-run）：经 ssh 读 iMac ops · 01，结果正常" \
            "$T/S2-$sh.all" 1 "$M/S2-$sh.rc" "iMac ops · 01 卡住工作检查：正常（最新心跳" "!运行记录查不到" "!脚本出错" "!将 POST 给"
    done
    cat "$M/S3.out" "$M/S3.err" >"$T/S3.all" 2>/dev/null
    expect S3 "MBA 上回放 30 分钟前的心跳：出 heartbeat_stale 待发内容，收件人 coding-assistant（STUCK_FORCE_BOT 没设）" \
        "$T/S3.all" 1 "$M/S3.rc" "$TO" "：中断：最新心跳在" "已 30 分钟没有新的" "$ST" '"bot": "coding-assistant"' '"machine": "本机"'
    cat "$M/S4.out" "$M/S4.err" >"$T/S4.all" 2>/dev/null
    XTRA="；用时 $(cat "$M/S4.secs" 2>/dev/null) 秒"
    expect S4 "ORCA_SSH_HOST=no-such-host.invalid：记「运行记录查不到」、不报、不算脚本出错，--precheck 退出 1" \
        "$T/S4.all" 1 "$M/S4.rc" "iMac ops · 01 卡住工作检查：运行记录查不到（JSONDecodeError），已连续 0 分钟" "!脚本出错" "!将 POST 给"
    v=PASS
    [ "$(cat "$M/S4-wrapper.rc" 2>/dev/null)" = 255 ] && [ ! -s "$M/S4-wrapper.out" ] || v=FAIL
    res S4.wrapper "$v" "包装连不上时退出 255（ssh 的）、stdout 空" "退出 $(cat "$M/S4-wrapper.rc" 2>/dev/null)，stdout $(wc -c <"$M/S4-wrapper.out" | tr -d ' ') 字节，stderr：$(head -1 "$M/S4-wrapper.err")"
    cat "$M/S4b.out" "$M/S4b.err" >"$T/S4b.all" 2>/dev/null
    XTRA="；state.json 没被改"
    cmp -s "$M/S4b.state-before" "$M/S4b.state-after" || { XTRA="；state.json 被改了"; XFAIL=1; }
    expect S4b "state 里记着 50 分钟前起查不到：报 heartbeat_stale「连不上 本机 的 Orca」给 coding-assistant；dry-run 不改 state" \
        "$T/S4b.all" 1 "$M/S4b.rc" "：中断：连不上 本机 的 Orca，50 分钟查不到「iMac ops · 01 卡住工作检查」的运行记录（JSONDecodeError）" "$TO" "$ST"
    s5_judge "$M/S5" MBA
    python3 -I - "$M/S5b.out" "$T/bundle/weird.txt" "$M/S5b.rc" "$CANARY" "$OUT/results.tsv" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
weird = open(sys.argv[2], encoding="utf-8").read()
rc = open(sys.argv[3]).read().strip()
try:
    d = json.loads(raw)
except ValueError:
    d = None
msg = ((d.get("error") or {}).get("message") or "") if isinstance(d, dict) else ""
ok = isinstance(d, dict) and d.get("ok") is False and weird in msg and sys.argv[4] not in raw and rc != "255"
got = "stdout %s；ok=%s；orca 收到的值%s原样；error.message：%s；退出 %s" % (
    "是一个 JSON" if d is not None else "不是 JSON", d.get("ok") if isinstance(d, dict) else "-",
    "是" if weird in msg else "不是", msg.replace("\n", "⏎")[:200], rc)
want = ("MBA 经包装真 ssh 到 iMac：--environment 的值带单双引号、$(…)、反引号、;、&&、*、反斜杠、$HOME 变量、中文、换行，"
        "orca 的报错里原样带回（没被展开或执行），stdout 只有一个 JSON")
open(sys.argv[5], "a", encoding="utf-8").write("S5b\t%s\t%s\t%s\n" % ("PASS" if ok else "FAIL", want, got))
print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", "S5b", got))
PY
    python3 -I - "$M/S7.json" "$M/S7-runs.rc" "$M/S7-list.rc" "$OUT/results.tsv" <<'PY'
import json, sys
try:
    s = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    s = {}
rc1, rc2 = open(sys.argv[2]).read().strip(), open(sys.argv[3]).read().strip()
hb = s.get("newest_hb") or {}
ok = (rc1 == "0" and rc2 == "0" and s.get("runs_ok") is True and (s.get("runs") or 0) >= 1 and (s.get("hb_lines") or 0) >= 1
      and s.get("list_ok") is True and bool(s.get("watched")) and bool((s.get("watched") or {}).get("createdAt")))
got = "runs 退出 %s、%s 条运行记录、%s 行 @@HB，最新心跳 %s 分钟前（rc %s）；list 退出 %s、%s 个自动任务，439cd438「%s」createdAt %s" % (
    rc1, s.get("runs"), s.get("hb_lines"), s.get("newest_hb_age_min"), hb.get("rc"), rc2, s.get("list_count"),
    (s.get("watched") or {}).get("name"), (s.get("watched") or {}).get("createdAt"))
want = "MBA 上直接跑 orca-via-ssh automations runs / list：ok，读到 ops · 01 的运行记录和 @@HB，list 里有 439cd438 和 createdAt"
open(sys.argv[4], "a", encoding="utf-8").write("S7\t%s\t%s\t%s\n" % ("PASS" if ok else "FAIL", want, got))
print("%-4s %-16s %s" % ("PASS" if ok else "FAIL", "S7", got))
PY
    v=PASS
    cmp -s "$M/S10-before.txt" "$M/S10-after.txt" || v=FAIL
    [ "$(grep -c '^没有 ' "$M/S10-after.txt")" = 3 ] || v=FAIL
    [ "$(cat "$M/S10-statefiles.txt")" = s4b/state/state.json ] || v=FAIL
    grep -q '^删掉了' "$M/tmpdir-cleanup.txt" || v=FAIL
    res S10.MBA "$v" "MBA 演练前后：~/.orca-state/bin/heartbeat-watch.sh、~/.orca-state/heartbeat-watch、主检出的 scripts/orca-via-ssh 都没有，主检出 HEAD 不变；临时状态目录里只有 S4b 种的 state.json；临时目录删掉了" \
        "$(tr '\n' ' ' <"$M/S10-after.txt")；状态文件：$(tr '\n' ' ' <"$M/S10-statefiles.txt")；临时目录$(cat "$M/tmpdir-cleanup.txt")"
fi

# ---------- S10 iMac：已装的 heartbeat-watch 没动；临时状态目录里 dry-run 没写东西 ----------
real_paths >"$T/imac-paths-after.txt"
IMAC_AFTER=$(shasum -a 256 "$HOME/.orca-state/bin/heartbeat-watch.sh" 2>&1 | cut -d' ' -f1)
(cd "$T" && find . -path '*/state/*' -type f | sort) >"$OUT/raw/S10-imac-statefiles.txt"
v=PASS
[ "$IMAC_BEFORE" = "$IMAC_AFTER" ] || v=FAIL
cmp -s "$T/imac-paths-before.txt" "$T/imac-paths-after.txt" || v=FAIL
grep -q '^没有 ~/orca/workspaces/ops/scripts/orca-via-ssh' "$T/imac-paths-after.txt" || v=FAIL
for c in c05 c07 c10; do
    for x in $VERS; do
        cmp -s "$OUT/raw/S1/$c.seed.json" "$T/s1/$c-$x/state/state.json" || v=FAIL
    done
done
[ "$(grep -vc -e '/s1/c05-' -e '/s1/c07-' -e '/s1/c10-' "$OUT/raw/S10-imac-statefiles.txt")" = 0 ] || v=FAIL
res S10.iMac "$v" "iMac 演练前后：~/.orca-state/bin/heartbeat-watch.sh 的 sha256 不变，主检出没有 scripts/orca-via-ssh、HEAD 不变；所有临时状态目录里只有种进去的 state.json，内容没变（dry-run 不写 state.json、watch.log、heartbeat.json）" \
    "已装版 ${IMAC_BEFORE:0:16} → ${IMAC_AFTER:0:16}；$(tr '\n' ' ' <"$T/imac-paths-after.txt")；状态文件 $(wc -l <"$OUT/raw/S10-imac-statefiles.txt" | tr -d ' ') 个"

# ---------- S11 静态：bash 3.2 语法、UTF-8 lint、shellcheck、包装最后一步是 exec ssh ----------
mkdir -p "$OUT/raw/S11"
SH_FILES="scripts/orca-via-ssh automations/heartbeat-1021/register.sh wake/tests/heartbeat-watch-ssh.sh wake/tests/hb-replay/orca"
v=PASS
for f in $SH_FILES; do
    /bin/bash -n "$root/$f" >>"$OUT/raw/S11/bash-n.txt" 2>&1 || v=FAIL
done
(cd "$root" && wake/tests/lint-bash32-utf8.sh $SH_FILES) >"$OUT/raw/S11/lint-bash32-utf8.txt" 2>&1 || v=FAIL
if command -v shellcheck >/dev/null; then
    (cd "$root" && shellcheck -S warning $SH_FILES) >"$OUT/raw/S11/shellcheck.txt" 2>&1 || v=FAIL
else
    echo "没装 shellcheck，没跑" >"$OUT/raw/S11/shellcheck.txt"
fi
for f in wake/tests/hb-replay/replay.py wake/tests/hb-replay/clock/sitecustomize.py; do
    python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$root/$f" >>"$OUT/raw/S11/python-ast.txt" 2>&1 || v=FAIL
done
[ "$(grep -v '^[[:space:]]*$' "$root/scripts/orca-via-ssh" | tail -1 | cut -c1-9)" = "exec ssh " ] || v=FAIL
res S11 "$v" "4 个 shell 文件 /bin/bash 3.2 -n、lint-bash32-utf8、shellcheck -S warning 都过；2 个 Python 文件能解析；orca-via-ssh 最后一步是 exec ssh（heartbeat-watch 超时杀的就是 ssh，不留孤儿）" \
    "bash -n $(wc -c <"$OUT/raw/S11/bash-n.txt" | tr -d ' ') 字节输出；lint $(wc -l <"$OUT/raw/S11/lint-bash32-utf8.txt" | tr -d ' ') 行；shellcheck $(wc -l <"$OUT/raw/S11/shellcheck.txt" | tr -d ' ') 行；最后一步：$(grep -v '^[[:space:]]*$' "$root/scripts/orca-via-ssh" | tail -1 | cut -c1-40)…"

# ---------- 报告 ----------
python3 -I - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(out, "results.tsv"), encoding="utf-8") if l.strip()]
npass, nfail = sum(r[1] == "PASS" for r in rows), sum(r[1] != "PASS" for r in rows)
env = open(os.path.join(out, "env.txt"), encoding="utf-8").read().strip().splitlines()
cell = lambda s: s.replace("|", "\\|").replace("`", "'")
scen = [
    ("S0", "三版 heartbeat-watch（base、iMac 已装、本分支）去掉注释后一致，第 33 行收件人不变", "iMac", "静态对比"),
    ("S1", "14 个回放例子 × 三版：输出和退出码逐字节一致，且符合期望", "iMac", "替身：假 HB_ORCA 回放录好的数据 + 固定时钟"),
    ("S2", "MBA 上照 defs 原文跑 precheck（/bin/sh、/bin/zsh 各一次）读真的 iMac ops · 01", "MBA → ssh iMac", "真"),
    ("S3", "MBA 上 --dry-run，目标换成心跳过期的回放数据", "MBA", "替身：假 HB_ORCA"),
    ("S4 / S4b", "ORCA_SSH_HOST 指向不存在的主机", "MBA", "真 ssh（主机名解析失败）"),
    ("S5", "orca-via-ssh 拒绝 edit 等子命令和坏的主机名", "iMac、MBA", "替身：假 ssh"),
    ("S5b", "orca-via-ssh 的参数转义", "MBA → ssh iMac", "真（orca 只读的 list，报错里带回参数）"),
    ("S6", "iMac 经 environment mba 读 MBA 一条现有任务（ops · 09）", "iMac → mba", "真"),
    ("S6b", "iMac 照 defs 原文跑 5c2d0575 的并行版、最终版 precheck；紧接着用 base 版跑现网 precheck 当对照", "iMac → grok-bot、mba", "真（MBA 新任务还没建，用 ops · 09 代替）"),
    ("S7", "MBA 上直接用 orca-via-ssh 读 iMac 的 runs、list", "MBA → ssh iMac", "真"),
    ("S8", "register.sh 只打印命令，不调用 orca", "iMac", "替身：假 orca"),
    ("S9", "现网配置和 defs.json 对得上（只读 show / list）", "iMac → grok-bot、mba", "真（只读）"),
    ("S10", "真路径没动：没装文件、主检出没动、dry-run 不写状态", "iMac、MBA", "真"),
    ("S11", "静态检查", "iMac", "—"),
]
L = ["# heartbeat-watch 跨机看守挪到 MBA↔iMac：演练结果", "",
     "B1（ops 审计）。代码和上线步骤见 [`automations/heartbeat-1021/`](../../automations/heartbeat-1021/README.md)，"
     "失败方式清单见 [`FAILURE-MODES.md`](../../automations/heartbeat-1021/FAILURE-MODES.md)。这个文件由演练脚本生成。", "",
     "**结果：%d 项 PASS，%d 项 FAIL。**" % (npass, nfail), "", "## 怎么重跑", "",
     "在 iMac 的仓库根目录：", "", "```bash", "wake/tests/heartbeat-watch-ssh.sh", "```", "",
     "要求本机 Orca 有 environment `mba`、`grok-bot`，能 `ssh mba`，MBA 能 `ssh imac`。整个目录会被重写"
     "（有 `.hb-drill` 标记才清空）。回放数据要重录时先跑 `wake/tests/heartbeat-watch-ssh.sh --record`。", "",
     "全部 heartbeat-watch 都带 `--dry-run`、临时 `HB_STATE_DIR`、假 webhook 目录（`127.0.0.1:9` 的假地址），不发叫醒、不读真凭据；"
     "orca 只用 `automations list / show / runs`；不往 `~/.orca-state/bin/` 装文件；MBA 上只用 `mktemp -d` 的临时目录，跑完删掉。", "",
     "## 这次运行", ""] + ["- " + cell(l) for l in env] + ["", "## 场景", "",
     "| 编号 | 场景 | 在哪跑 | 真机还是替身 |", "|---|---|---|---|"] + \
    ["| %s | %s | %s | %s |" % s for s in scen] + [
     "", "S1、S3、S5、S8 用了测试替身，不算 E2E。S2 是从 iMac `ssh mba` 起的进程，不是 Orca 在 MBA 上跑的预检；"
     "Orca 预检环境里能不能连 ssh，要到上线第 3 步第一次真实运行才算证实。", "",
     "## 期望和实际", "", "| 编号 | 期望 | 实际 | 结果 |", "|---|---|---|---|"] + \
    ["| %s | %s | %s | %s |" % (r[0], cell(r[2]), cell(r[3]), "PASS" if r[1] == "PASS" else "**%s**" % r[1]) for r in rows] + [
     "", "## 没跑的", "",
     "- `register.sh --apply`：任务书禁止。主机名检查、备份文件检查和真正调用 orca 的部分都没演练过。",
     "- 任何 `orca automations create / edit / run`：任务书禁止。MBA 新任务还没建，S6、S6b 用 MBA ops · 09 代替它。",
     "- TLC（`wake/tla/check.sh`）：本批只改了 `wake/tla/README.md` 的文字，模型和 `SOURCES.sha256` 留给后续 wake-tla 批次。",
     "- heartbeat-watch 90 秒超时杀掉包装时 ssh 会不会留下：不杀进程就没法实测，S11 只检查了包装最后一步是 `exec ssh`。",
     "", "## 文件", "",
     "- `results.tsv`：每项一行（编号、结果、期望、实际），`README.md` 由它生成。",
     "- `env.txt`：时间、commit、两台机器的系统和工具版本。",
     "- `raw/S0/`：三版的 sha256 和 diff。`raw/S1/`：每个例子的参数（`.cmd`）、回放设置（`.env`）、种的状态（`.seed.json`），"
     "三版各自的 stdout、stderr、退出码和假 orca 收到的调用。",
     "- `raw/S5-imac/`：iMac 上包装每条用例的命令、退出码、stderr、假 ssh 收到的参数。",
     "- `raw/S6/`、`raw/S6b/`：iMac 上的命令和原始输出。`raw/S8/`：register.sh 每次的参数和输出。`raw/S9/`：只读 show / list 摘下来的字段。",
     "- `raw/mba/`：MBA 那边的原始输出（S2、S3、S4、S4b、S5、S5b、S7 摘要、S10）。S7 只留摘要，不留运行记录原文。",
     "- `raw/S11/`：静态检查的输出。", "- `SHA256SUMS`：除它自己以外所有文件的 sha256（`shasum -a 256 -c SHA256SUMS` 校验）。"]
open(os.path.join(out, "README.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
print("\n%d 项 PASS，%d 项 FAIL" % (npass, nfail))
PY
(cd "$OUT" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r f; do shasum -a 256 "$f"; done >SHA256SUMS)
echo "产物：$OUT"
awk -F'\t' '$2 != "PASS" { bad = 1 } END { exit bad }' "$OUT/results.tsv"
