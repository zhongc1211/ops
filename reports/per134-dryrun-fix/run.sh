#!/bin/bash
# PER-134 对照：base（有 bug 的 main）和 head（本分支）在同一份状态快照、同一盘录下来的外部命令输出上跑 stuck-check，
# 比较各模式的输出和跑完后的状态文件。
#   bash reports/per134-dryrun-fix/run.sh record   # 录：真跑 iMac 的 orca / gh / agent-probe 等（只读模式，见下），写进 $IN
#   bash reports/per134-dryrun-fix/run.sh replay   # 回放：不跑任何外部命令，产出写到 reports/per134-dryrun-fix/out/
# 录制时：快照取自 ~/.orca-state/stuck-check（只读复制），box（grok-bot）调用一律拦下，curl 一律拦下；
#   --dry-run 本身不发；--run / --scan 录制时加 STUCK_NO_SEND=1（脚本自带开关：照常扫描、写状态，不 POST，orca-wake 只 --list）。
# 回放时多跑一组「正式路径」：--run 不加 STUCK_NO_SEND，发送走 curl，被 harness 截住并回 200。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
IN=${PER134_IN:-$HOME/.cache/per134-dryrun-fix}   # 快照和磁带含终端内容，不进仓库
OUT=$HERE/out
BASE=${PER134_BASE:-a1d9a68f47e8f6cccd5d06b3beb3ccdc7a5162a2}
HEAD_REF=${PER134_HEAD:-$(git -C "$REPO" rev-parse HEAD)}
SAFE=$HERE/harness
mkdir -p "$IN/bin" "$OUT"

extract() {  # extract <sha> → 那个 commit 的 stuck-check.sh
    git -C "$REPO" show "$1:scripts/stuck-check.sh" > "$IN/bin/stuck-check-$1.sh"
    echo "$IN/bin/stuck-check-$1.sh"
}

fake_env() {  # 假的 webhook 配置：真密钥不进来；文件名照抄真目录，让 bot_cfg 走同样的分支
    rm -rf "$IN/webhooks" && mkdir -p "$IN/webhooks"
    for f in "$HOME"/.config/grokbot/webhooks/*.env; do
        n=$(basename "$f" .env)
        printf 'URL=https://per134.invalid/%s\nKEY=per134-dummy-%s\n' "$n" "$n" > "$IN/webhooks/$n.env"
    done
    printf 'URL=https://per134.invalid/default\nKEY=per134-dummy-default\n' > "$IN/stuck-webhook.env"
}

fresh_state() {  # fresh_state <dir>：从冻结快照复制一份，每次运行各用各的
    rm -rf "$1" && mkdir -p "$1" && cp -R "$IN/state0/." "$1/" && mkdir -p "$1.runs"
}

seq_of() {  # seq_of <calls 文件>：调用序列，每行「命令前三段 → 返回码」（不含 record/replay 标记，录制和回放可比）
    python3 -I -c 'import json,sys
for l in open(sys.argv[1], encoding="utf-8"):
    d = json.loads(l)
    print(json.dumps(d["cmd"], ensure_ascii=False), "->", d["rc"], "(%s)" % d["kind"] if d["kind"] not in ("record", "replay") else "")' "$1"
}

go() {  # go <mode record|replay> <tape> <script> <state> <stdout> <args...>；额外环境变量由调用方 export
    local mode=$1 tape=$2 script=$3 st=$4 so=$5; shift 5
    rm -f "$so.calls"  # harness 是追加写；不清掉会把上一次的调用记录接在前面
    env PYTHONPATH="$SAFE" PER134_MODE="$mode" PER134_TAPE="$tape" PER134_CALLS="$so.calls" \
        STUCK_STATE_DIR="$st" STUCK_RUNS_DIR="$st.runs" STUCK_ENV_FILE="$IN/stuck-webhook.env" \
        STUCK_WEBHOOK_DIR="$IN/webhooks" STUCK_BOX_ENV=__no_box__ STUCK_NO_GATE=1 \
        bash "$script" "$@" > "$so" 2>&1
    echo $? > "$so.rc"
}

# 名字 | 录制用哪个版本 | 录制时额外环境 | 参数
CASES=(
  "dry|head||--dry-run"
  "dryfull|head||--dry-run --full"
  "run|base|STUCK_NO_SEND=1|"
  "runfull|base|STUCK_NO_SEND=1|--full"
  "scan|base|STUCK_NO_SEND=1|--scan"
)

# 同一时间只许一个对照在跑：上次被打断时留下的 stuck-check 进程会继续往同名的调用记录和状态目录里写（PER134-FIX2 查到过一次）
if pgrep -f "$IN/bin/stuck-check-" >/dev/null; then
    echo "还有上次留下的 stuck-check 进程在跑，先停掉再来："; pgrep -lf "$IN/bin/stuck-check-"; exit 1
fi
trap 'pkill -f "$IN/bin/stuck-check-"; exit 130' INT TERM

case "${1:-}" in
record)
    rm -f "$IN"/*.tape "$IN"/*.tape.calls
    rm -rf "$IN/state0" && mkdir -p "$IN/state0"
    cp -R "$HOME/.orca-state/stuck-check/." "$IN/state0/"
    rm -rf "$IN/state0"/manual-* "$IN/state0/run.lock"
    : > "$IN/state0/stuck-check.log"   # 2MB 的旧日志脚本不读，只追加；清空方便比
    fake_env
    b=$(extract "$BASE"); h=$(extract "$HEAD_REF")
    for c in "${CASES[@]}"; do
        IFS='|' read -r name who extra args <<<"$c"
        s=$b; [ "$who" = head ] && s=$h
        fresh_state "$IN/rec-$name"
        ( [ -n "$extra" ] && export $extra; go record "$IN/$name.tape" "$s" "$IN/rec-$name" "$IN/rec-$name.out" $args )
        echo "record $name（$who）rc=$(cat "$IN/rec-$name.out.rc")"
    done
    echo "base=$BASE head=$HEAD_REF recorded=$(date '+%F %T %Z')" > "$IN/RECORDED"
    (cd "$IN" && shasum -a 256 state0/* *.tape > SHA256SUMS)
    ;;
replay)
    (cd "$IN" && shasum -a 256 -c SHA256SUMS >/dev/null) || { echo "输入和录制时不一致"; exit 1; }
    rm -rf "$OUT" && mkdir -p "$OUT"
    b=$(extract "$BASE"); h=$(extract "$HEAD_REF")
    for c in "${CASES[@]}" "runformal|base||" "runfullformal|base||--full"; do
        IFS='|' read -r name who extra args <<<"$c"
        tape=$IN/${name%formal}.tape
        for side in base head; do
            s=$b; [ $side = head ] && s=$h
            st=$IN/rep-$name-$side
            fresh_state "$st"
            ( [ -n "$extra" ] && export $extra; go replay "$tape" "$s" "$st" "$OUT/$name-$side.out" $args )
            python3 -I "$HERE/normalize.py" "$OUT/$name-$side.out" "$st" > "$OUT/$name-$side.norm"
            seq_of "$OUT/$name-$side.out.calls" > "$OUT/$name-$side.seq"
        done
        if cmp -s "$OUT/$name-base.norm" "$OUT/$name-head.norm"; then same=一致; else same=不一致; fi
        if cmp -s "$OUT/$name-base.seq" "$OUT/$name-head.seq"; then sq=一致; else sq=不一致; fi
        diff "$OUT/$name-base.norm" "$OUT/$name-head.norm" > "$OUT/$name.diff"
        diff "$OUT/$name-base.seq" "$OUT/$name-head.seq" > "$OUT/$name.seq.diff"
        printf '%-13s base rc=%s head rc=%s  判定和状态：%s（diff %s 行）  调用序列：%s（base %s 条 / head %s 条）  head 未命中磁带 %s 条，截住 curl %s 次、box %s 次\n' \
            "$name" "$(cat "$OUT/$name-base.out.rc")" "$(cat "$OUT/$name-head.out.rc")" "$same" \
            "$(wc -l < "$OUT/$name.diff" | tr -d ' ')" "$sq" \
            "$(wc -l < "$OUT/$name-base.seq" | tr -d ' ')" "$(wc -l < "$OUT/$name-head.seq" | tr -d ' ')" \
            "$(grep -c '"miss"' "$OUT/$name-head.out.calls" 2>/dev/null || true)" \
            "$(grep -c 'blocked-curl' "$OUT/$name-head.out.calls" 2>/dev/null || true)" \
            "$(grep -c 'blocked-box' "$OUT/$name-head.out.calls" 2>/dev/null || true)"
    done | tee "$OUT/SUMMARY.txt"
    # 回放可信度：base 的回放和 base 的录制（真跑）比
    for name in run runfull scan; do
        python3 -I "$HERE/normalize.py" "$IN/rec-$name.out" "$IN/rec-$name" > "$OUT/$name-base-recorded.norm"
        if cmp -s "$OUT/$name-base-recorded.norm" "$OUT/$name-base.norm"; then f=一致; else f=不一致; fi
        diff "$OUT/$name-base-recorded.norm" "$OUT/$name-base.norm" > "$OUT/$name-fidelity.diff"
        # 录制那次的调用序列从磁带取：磁带每次录制整份重写，rec-*.out.calls 在 FIX2 之前是追加写的，重录过的用例里叠着两次
        python3 -I -c 'import json,sys
for c in json.load(open(sys.argv[1], encoding="utf-8"))["calls"]:
    print(json.dumps(json.loads(c["key"])[:3], ensure_ascii=False), "->", c["rc"], "")' "$IN/$name.tape" > "$OUT/$name-base-recorded.seq"
        if cmp -s "$OUT/$name-base-recorded.seq" "$OUT/$name-base.seq"; then q=一致; else q=不一致; fi
        diff "$OUT/$name-base-recorded.seq" "$OUT/$name-base.seq" > "$OUT/$name-fidelity.seq.diff"
        echo "回放可信度：base $name 录制（真跑）vs 回放：判定和状态 $f，调用序列 $q" | tee -a "$OUT/SUMMARY.txt"
    done
    cp "$IN/RECORDED" "$IN/SHA256SUMS" "$OUT/"
    ;;
*) echo "用法：$0 record|replay"; exit 2 ;;
esac
