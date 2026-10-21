#!/bin/bash
# dispatch/tests/e2e-real-10min.sh：在真机上用仓库里的 ops-v5-sampler 每分钟采一次，共 N 分钟（默认 10）。
#   本机：  dispatch/tests/e2e-real-10min.sh --host imac
#   经 ssh：dispatch/tests/e2e-real-10min.sh --ssh mba     （采样器从 stdin 传过去：python3 -I - ...）
# 不装任何东西：HOME、数据目录、配置都放在 mktemp -d 的临时目录里，环境用 env -i 清空，
# 只带 HOME、PATH 和 ORCA_USER_DATA_PATH（Orca 运行目录的路径，orca CLI 靠它找到本机的 Orca；不读里面的文件）。
# 跑完把整份 jsonl、会话字典、日志、状态、每次的 /usr/bin/time -l 复制到
# reports/per126-p2-sampler/e2e-<host>/，扫一遍正文和密钥样式，核对真实 HOME 没被写，再删掉临时目录。
set -u
T=$(cd "$(dirname "$0")" && pwd)
D=$(cd "$T/.." && pwd)
REPO=$(cd "$D/.." && pwd)
SAMPLER="$D/bin/ops-v5-sampler"
MINUTES=10
HOST=""
SSH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST=$2; shift 2 ;;
    --ssh) SSH=$2; HOST=${HOST:-$2}; shift 2 ;;
    --minutes) MINUTES=$2; shift 2 ;;
    *) echo "用法：$0 --host <名字> | --ssh <主机> [--minutes N]" >&2; exit 2 ;;
  esac
done
[ -n "$HOST" ] || { echo "要给 --host 或 --ssh" >&2; exit 2; }
OUT="$REPO/reports/per126-p2-sampler/e2e-$HOST"
rm -rf "$OUT"
mkdir -p "$OUT/time"
# 在目标机器上跑一段 shell（本机直接跑，远端经 ssh 跑）
on() { if [ -n "$SSH" ]; then ssh -o BatchMode=yes "$SSH" "$1"; else /bin/sh -c "$1"; fi; }

# 真实 HOME 里 v5 采样器会用到的路径：跑前跑后都应该不存在
REAL_PATHS='$HOME/.local/bin/ops-v5-sampler $HOME/.local/bin/ops-v5-sample-replay $HOME/.config/dispatch $HOME/.local/state/ops-v5 $HOME/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist'
real_home_check() {
  on "for p in $REAL_PATHS; do if [ -e \"\$p\" ]; then echo \"存在 \$p\"; else echo \"不存在 \$p\"; fi; done"
}

{
  echo "host $HOST"
  echo "mode ${SSH:+ssh $SSH}${SSH:-local}"
  echo "commit $(git -C "$REPO" rev-parse HEAD)"
  echo "uncommitted_in_dispatch $(git -C "$REPO" status --porcelain -- dispatch | wc -l | tr -d " ")"
  echo "sampler_sha256 $(shasum -a 256 "$SAMPLER" | cut -d' ' -f1)"
  on 'echo "uname $(uname -sr)"; echo "macos $(sw_vers -productVersion)"; echo "python $(/usr/bin/python3 -V 2>&1)"; echo "orca $(/Applications/Orca.app/Contents/Resources/bin/orca --version 2>/dev/null | head -n 1)"'
  echo "minutes $MINUTES"
  echo "start $(date +%Y-%m-%dT%H:%M:%S%z)"
} > "$OUT/env.txt"
real_home_check > "$OUT/real-home-before.txt"

TMP=$(on 'mktemp -d')
case "$TMP" in /var/folders/*|/tmp/*|/private/*) ;; *) echo "mktemp 返回的路径不对：$TMP" >&2; exit 1 ;; esac
echo "tmp $TMP" >> "$OUT/env.txt"
on "mkdir -p '$TMP/home' && printf 'SAMPLER_CONFIG_VERSION=1\nSAMPLER_HOST=$HOST\n' > '$TMP/sampler.env'"
RUN_ENV="env -i HOME='$TMP/home' PATH=/usr/bin:/bin ORCA_USER_DATA_PATH=\"\$HOME/Library/Application Support/orca\""
ARGS="--once --state-dir '$TMP/state' --config '$TMP/sampler.env'"

start=$(date +%s)
i=0
fails=0
while [ "$i" -lt "$MINUTES" ]; do
  # 按开始时间排每一次，避免循环漂移让某一分钟落空
  wait_s=$((start + i * 60 - $(date +%s)))
  [ "$wait_s" -gt 0 ] && sleep "$wait_s"
  n=$(printf '%02d' "$i")
  if [ -n "$SSH" ]; then
    on "$RUN_ENV /usr/bin/time -l /usr/bin/python3 -I - $ARGS" < "$SAMPLER" > "$OUT/time/$n.txt" 2>&1
  else
    on "$RUN_ENV /usr/bin/time -l '$SAMPLER' $ARGS" > "$OUT/time/$n.txt" 2>&1
  fi
  rc=$?
  echo "$n $(date +%H:%M:%S) rc=$rc" >> "$OUT/runs.txt"
  [ "$rc" = 0 ] || fails=$((fails + 1))
  i=$((i + 1))
done

# 取回数据：samples、字典、日志、状态（不取锁文件）
mkdir -p "$OUT/state"
on "cd '$TMP/state' && tar cf - --exclude ops-v5-sampler.lock ." | tar xf - -C "$OUT/state"
on "rm -rf '$TMP'; if [ -e '$TMP' ]; then echo '临时目录还在 $TMP'; else echo '临时目录已删 $TMP'; fi" > "$OUT/cleanup.txt"
real_home_check > "$OUT/real-home-after.txt"
echo "end $(date +%Y-%m-%dT%H:%M:%S%z)" >> "$OUT/env.txt"

# 汇总和扫描
/usr/bin/python3 -I - "$OUT" "$HOST" "$MINUTES" <<'PY' > "$OUT/summary.txt"
import glob, json, os, re, sys
out, host, minutes = sys.argv[1], sys.argv[2], int(sys.argv[3])
days = sorted(glob.glob(os.path.join(out, "state/samples", host, "????-??-??.jsonl")))
dicts = sorted(glob.glob(os.path.join(out, "state/samples", host, "????-??-??.sessions.jsonl")))
recs = [json.loads(l) for p in days for l in open(p) if l.strip()]
print("records %d / %d" % (len(recs), minutes))
print("minutes_distinct %d" % len({r["minute"] for r in recs}))
print("orca_ok %d" % sum(1 for r in recs if r["orca_ok"]))
print("errors_total %d" % sum(len(r["errors"]) for r in recs))
for r in recs:
    print("  %s sessions=%d found=%d agents=%s orphan=%s avail_gb=%.2f load1=%s dur_ms=%s rss_kb=%s errors=%s" % (
        r["minute"], len(r["sessions"]), sum(1 for s in r["sessions"] if s.get("found")),
        (r["agent_count"] or {}).get("total"), (r["orphan_agents"] or {}).get("n"),
        (r["machine"].get("orca") or {}).get("availableMemory", 0) / 1024 ** 3,
        (r["machine"].get("orca") or {}).get("loadAverage1m"), r["self"]["duration_ms"], r["self"]["maxrss_kb"],
        [e["step"] + ":" + e["error"] for e in r["errors"]]))
size = sum(os.path.getsize(p) for p in days)
dsize = sum(os.path.getsize(p) for p in dicts)
dict_lines = sum(1 for p in dicts for l in open(p) if l.strip())
print("bytes_samples %d (%.0f B/record)" % (size, size / max(1, len(recs))))
print("bytes_dict %d (%d lines)" % (dsize, dict_lines))
print("est_bytes_per_day %.1f MB (samples*1440 + dict)" % ((size / max(1, len(recs)) * 1440 + dsize) / 1e6))
# 扫描：正文字段名、密钥样式、真实路径以外的长串；任何命中都算失败
pat = {
    "body_field": re.compile(r'"(prompt|preview|lastAssistantMessage|comment|message|body|content|text|env|argv|cmdline|command)"'),
    "key_like": re.compile(r'(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|xox[bpa]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|Bearer\s+[A-Za-z0-9._-]{10,}|-----BEGIN)'),
    "secret_word": re.compile(r'(?i)(password|passwd|secret|token|cookie|api[_-]?key)'),
}
hits = 0
for p in days + dicts:
    for no, line in enumerate(open(p), 1):
        for name, rx in pat.items():
            for m in rx.finditer(line):
                hits += 1
                print("HIT %s %s:%d %s" % (name, os.path.relpath(p, out), no, m.group(0)[:12]))
print("scan_hits %d" % hits)
PY
cat "$OUT/summary.txt"
echo "失败次数 ${fails}；产物 ${OUT}"
grep -q '^scan_hits 0$' "$OUT/summary.txt" && grep -q "^records $MINUTES / $MINUTES$" "$OUT/summary.txt" && [ "$fails" = 0 ] \
  && ! grep -q '^存在' "$OUT/real-home-after.txt" && grep -q '^临时目录已删' "$OUT/cleanup.txt"
