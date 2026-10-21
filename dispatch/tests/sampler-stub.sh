#!/bin/bash
# dispatch/tests/sampler-stub.sh：ops-v5-sampler / ops-v5-sample-replay / install.sh 的桩测。
# 假的 orca、ps、sysctl、df、launchctl 放在 PATH 最前面；全部在 mktemp -d 的临时目录里跑，HOME 也指过去。
# 用例和 tests/FAILURE-MODES.md 的编号对应。用法：dispatch/tests/sampler-stub.sh [用例名...]
set -u
T=$(cd "$(dirname "$0")" && pwd)
D=$(cd "$T/.." && pwd)
SAMPLER="$D/bin/ops-v5-sampler"
REPLAY="$D/bin/ops-v5-sample-replay"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export FAKE_FIXTURES="$T/fixtures"
export PATH="$T/stubs:/usr/bin:/bin:/usr/sbin:/sbin"
PY=/usr/bin/python3
pass=0
fail=0
failed=""

ok() { pass=$((pass + 1)); echo "  ok   $1"; }
no() { fail=$((fail + 1)); failed="$failed $CASE"; echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

# 每个用例一个干净的 state 目录和配置
fresh() {
  CASE=$1
  echo "[$CASE]"
  S="$WORK/$CASE/state"
  C="$WORK/$CASE/sampler.env"
  mkdir -p "$WORK/$CASE"
  printf 'SAMPLER_CONFIG_VERSION=1\nSAMPLER_HOST=testhost\nORCA_TIMEOUT_SEC=2\n' > "$C"
  unset FAKE_ORCA_MODE FAKE_PS_MODE FAKE_SYSCTL_MODE FAKE_DF_MODE FAKE_PIDFILE
}
run() { HOME="$WORK/$CASE/home" "$SAMPLER" --once --state-dir "$S" --config "$C" "$@"; }
today() { date +%Y-%m-%d; }
lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
last() { tail -n 1 "$S/samples/testhost/$(today).jsonl"; }
# jq 风格取值：j '<python 表达式，r 是最后一行记录>'
j() { last | "$PY" -I -c "import json,sys; r=json.loads(sys.stdin.read()); print($1)"; }

t_normal() {
  fresh normal
  mkdir -p "$WORK/$CASE/home"
  # env -i：模拟 launchd 的空环境，靠脚本自己补 PATH；桩目录仍然放在最前
  env -i HOME="$WORK/$CASE/home" PATH="$T/stubs" FAKE_FIXTURES="$FAKE_FIXTURES" \
    "$SAMPLER" --once --state-dir "$S" --config "$C" > "$WORK/$CASE/out" 2>&1
  check "退出码 0" '[ $? -eq 0 ]'
  check "写了一行" '[ "$(lines "$S/samples/testhost/$(today).jsonl")" = 1 ]'
  check "schema/host/ok" '[ "$(j "r[\"schema\"], r[\"host\"], r[\"ok\"], r[\"orca_ok\"]")" = "ops-v5-sample/1 testhost True True" ]'
  check "ts 带时区" '[ "$(j "r[\"ts\"][19:20] in \"+-\"")" = True ]'
  check "机器级读数" '[ "$(j "r[\"machine\"][\"orca\"][\"availableMemory\"], r[\"machine\"][\"memorystatus_level\"], r[\"machine\"][\"vm_loadavg\"][0], r[\"machine\"][\"disk_home_avail_kb\"]")" = "2748779069 40 3.5 44539588" ]'
  check "三个会话" '[ "$(j "len(r[\"sessions\"])")" = 3 ]'
  check "会话 A 终端对上" '[ "$(j "r[\"sessions\"][0][\"terminal\"]")" = "{'"'"'handle'"'"': '"'"'term_A'"'"', '"'"'state'"'"': '"'"'working'"'"', '"'"'workingMode'"'"': '"'"'auto'"'"', '"'"'stateStartedAt'"'"': 1792554000000, '"'"'agentType'"'"': '"'"'claude'"'"', '"'"'linkedLinearIssue'"'"': '"'"'PER-1'"'"'}" ]'
  check "会话 A 进程树 rss=528+1968+200000+50000，顶层 agent 只有 claude" '[ "$(j "r[\"sessions\"][0][\"proc\"]")" = "{'"'"'found'"'"': True, '"'"'tree_rss_kb'"'"': 252496, '"'"'n_procs'"'"': 4, '"'"'agents'"'"': ['"'"'claude'"'"'], '"'"'agent_type'"'"': '"'"'claude'"'"'}" ]'
  check "会话 B agent 是 codex" '[ "$(j "r[\"sessions\"][1][\"proc\"][\"agent_type\"]")" = codex ]'
  check "会话 C（pid 300）找不到进程" '[ "$(j "r[\"sessions\"][2][\"proc\"]")" = "{'"'"'found'"'"': False}" ]'
  check "会话外 agent：400 claude、500 node（401 在 400 下面不算）" '[ "$(j "[(o[\"pid\"], o[\"comm\"]) for o in r[\"orphan_agents\"]]")" = "[(400, '"'"'claude'"'"'), (500, '"'"'node'"'"')]" ]'
  check "agent 计数" '[ "$(j "r[\"agent_count\"]")" = "{'"'"'in_sessions'"'"': 2, '"'"'orphan'"'"': 2, '"'"'total'"'"': 4}" ]'
  check "没存会话正文（F18）" '! grep -q SECRET_BODY_MARKER "$S/samples/testhost/$(today).jsonl"'
  check "self 耗时和 rss" '[ "$(j "r[\"self\"][\"duration_ms\"] >= 0 and r[\"self\"][\"maxrss_kb\"] > 0")" = True ]'
}

t_same_minute() {
  fresh same_minute
  run && run
  check "同一分钟两次只一行（F5）" '[ "$(lines "$S/samples/testhost/$(today).jsonl")" = 1 ]'
  check "日志写了跳过" 'grep -q "已有记录，跳过" "$S/ops-v5-sampler.log"'
}

t_config_missing() {
  fresh config_missing
  rm -f "$C"
  run 2>/dev/null
  check "退出码 3（F1）" '[ $? -eq 3 ]'
  check "日志写配置缺失" 'grep -q "配置缺失" "$S/ops-v5-sampler.log"'
  check "没有 samples" '[ ! -d "$S/samples" ]'
}

t_config_bad_version() {
  fresh config_bad_version
  printf 'SAMPLER_CONFIG_VERSION=2\n' > "$C"
  run 2>/dev/null
  check "版本 2 退出码 3（F2）" '[ $? -eq 3 ]'
  printf 'SAMPLER_HOST=x\n' > "$C"
  run 2>/dev/null
  check "没写版本退出码 3" '[ $? -eq 3 ]'
  check "日志写版本不对" '[ "$(grep -c "配置版本不对" "$S/ops-v5-sampler.log")" = 2 ]'
}

t_config_bad_value() {
  fresh config_bad_value
  printf 'SAMPLER_CONFIG_VERSION=1\nRETENTION_DAYS=two\n' > "$C"
  run 2>/dev/null
  check "数值项坏退出码 3（F3）" '[ $? -eq 3 ]'
  check "日志点名 RETENTION_DAYS" 'grep -q "RETENTION_DAYS" "$S/ops-v5-sampler.log"'
}

t_lock_held() {
  fresh lock_held
  mkdir -p "$S"
  # 另开一个进程拿住同一把 flock 锁 5 秒
  "$PY" -I -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(5)' \
    "$S/ops-v5-sampler.lock" "$WORK/$CASE/held" &
  holder=$!
  while [ ! -f "$WORK/$CASE/held" ]; do sleep 0.1; done
  run
  check "锁被占退出码 0（F4）" '[ $? -eq 0 ]'
  check "没写 samples" '[ "$(lines "$S/samples/testhost/$(today).jsonl")" = 0 ]'
  check "日志写锁被占" 'grep -q "锁被占" "$S/ops-v5-sampler.log"'
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
  run
  check "锁放开后能写" '[ "$(lines "$S/samples/testhost/$(today).jsonl")" = 1 ]'
}

t_orca_missing() {
  fresh orca_missing
  echo "ORCA_BIN=$WORK/no-such-orca" >> "$C"
  run
  check "退出码 0" '[ $? -eq 0 ]'
  check "orca_ok=false，错误 not_found（F6）" '[ "$(j "r[\"orca_ok\"], [e for e in r[\"errors\"] if e[\"step\"]==\"orca_diag\"][0][\"error\"]")" = "False not_found" ]'
  check "后备读数还在" '[ "$(j "r[\"machine\"][\"memorystatus_level\"], r[\"machine\"][\"hw_memsize\"]")" = "40 8589934592" ]'
  check "会话为空，会话外 agent 照记" '[ "$(j "len(r[\"sessions\"]), r[\"agent_count\"][\"orphan\"]")" = "0 4" ]'
}

t_orca_timeout() {
  fresh orca_timeout
  export FAKE_ORCA_MODE=timeout FAKE_PIDFILE="$WORK/$CASE/pids"
  start=$(date +%s)
  run
  el=$(( $(date +%s) - start ))
  check "ORCA_TIMEOUT_SEC=2，整次 < 6 秒（实际 ${el}s）（F7）" '[ "$el" -lt 6 ]'
  check "orca_ok=false，错误 timeout" '[ "$(j "r[\"orca_ok\"], r[\"errors\"][0][\"error\"]")" = "False timeout" ]'
  sleep 0.3
  alive=0
  while read -r p; do kill -0 "$p" 2>/dev/null && alive=1; done < "$FAKE_PIDFILE"
  check "假 orca 和它的 sleep 子进程都已被杀" '[ "$alive" = 0 ]'
  check "后备读数还在" '[ "$(j "r[\"machine\"][\"memorystatus_level\"]")" = 40 ]'
}

t_round_timeout() {
  fresh round_timeout
  printf 'SAMPLER_CONFIG_VERSION=1\nSAMPLER_HOST=testhost\nORCA_TIMEOUT_SEC=10\nROUND_TIMEOUT_SEC=2\n' > "$C"
  export FAKE_ORCA_MODE=timeout
  start=$(date +%s)
  run
  el=$(( $(date +%s) - start ))
  check "整轮上限 2 秒压住了 10 秒的 orca 上限（实际 ${el}s）（F13）" '[ "$el" -lt 5 ]'
  check "后面的步骤记 no_budget" '[ "$(j "any(e[\"error\"]==\"no_budget\" for e in r[\"errors\"])")" = True ]'
}

t_orca_bad_json() {
  fresh orca_bad_json
  export FAKE_ORCA_MODE=badjson
  run
  check "坏 JSON：orca_ok=false，bad_json（F8）" '[ "$(j "r[\"orca_ok\"], r[\"errors\"][0][\"error\"]")" = "False bad_json" ]'
}

t_orca_not_ok() {
  fresh orca_not_ok
  export FAKE_ORCA_MODE=notok
  run
  check "ok:false → not_ok（F9）" '[ "$(j "r[\"orca_ok\"], r[\"errors\"][0][\"error\"]")" = "False not_ok" ]'
  export FAKE_ORCA_MODE=exit1
  rm -rf "$S"
  run
  check "退出码 1 → exit:1 并带首行" '[ "$(j "r[\"errors\"][0][\"error\"]")" = "exit:1 orca: runtime unavailable" ]'
}

t_orca_enrich_fail() {
  fresh orca_enrich_fail
  export FAKE_ORCA_MODE=enrichfail
  run
  check "orca_ok 仍是 true（F10）" '[ "$(j "r[\"orca_ok\"]")" = True ]'
  check "两步补充都记错" '[ "$(j "sorted((e[\"step\"], e[\"error\"][:6]) for e in r[\"errors\"])")" = "[('"'"'orca_terminal_list'"'"', '"'"'exit:1'"'"'), ('"'"'orca_worktree_ps'"'"', '"'"'bad_js'"'"')]" ]'
  check "会话照记，terminal=null" '[ "$(j "len(r[\"sessions\"]), r[\"sessions\"][0][\"terminal\"]")" = "3 None" ]'
}

t_fallback_tools_fail() {
  fresh fallback_tools_fail
  export FAKE_PS_MODE=fail FAKE_SYSCTL_MODE=fail FAKE_DF_MODE=fail
  run
  check "退出码 0（F12）" '[ $? -eq 0 ]'
  check "错误记了 ps、3 个 sysctl、df" '[ "$(j "sorted(e[\"step\"].split(\":\")[0] for e in r[\"errors\"])")" = "['"'"'df'"'"', '"'"'ps'"'"', '"'"'sysctl'"'"', '"'"'sysctl'"'"', '"'"'sysctl'"'"']" ]'
  check "agent_count=null，会话没有 proc" '[ "$(j "r[\"agent_count\"], \"proc\" in r[\"sessions\"][0]")" = "None False" ]'
}

t_rotate_old() {
  fresh rotate_old
  echo "RETENTION_DAYS=3" >> "$C"
  H="$S/samples/testhost"
  mkdir -p "$H" "$S/samples/otherhost"
  for n in 1 2 3 5; do
    d=$("$PY" -I -c "import datetime,sys; print((datetime.date.today()-datetime.timedelta(days=int(sys.argv[1]))).isoformat())" "$n")
    echo '{}' > "$H/$d.jsonl"
    echo '{}' > "$S/samples/otherhost/$d.jsonl"
  done
  echo keep > "$H/notes.txt"
  echo keep > "$H/2000-01-01.jsonl.bak"
  run
  check "保留 3 天：今天、1、2 天前（F14）" '[ "$(ls "$H" | grep -c "^[0-9-]*\.jsonl$")" = 3 ]'
  check "别的主机目录不动（F16）" '[ "$(ls "$S/samples/otherhost" | wc -l | tr -d " ")" = 4 ]'
  check "非 YYYY-MM-DD.jsonl 不动" '[ -f "$H/notes.txt" ] && [ -f "$H/2000-01-01.jsonl.bak" ]'
}

t_size_cap() {
  fresh size_cap
  # 上限约 20KB；放两个 10KB 的旧文件
  echo "MAX_TOTAL_MB=0.02" >> "$C"
  H="$S/samples/testhost"
  mkdir -p "$H" "$S/samples/otherhost"
  for n in 1 2; do
    d=$("$PY" -I -c "import datetime,sys; print((datetime.date.today()-datetime.timedelta(days=int(sys.argv[1]))).isoformat())" "$n")
    head -c 10000 /dev/zero | tr '\0' 'x' > "$H/$d.jsonl"
    cp "$H/$d.jsonl" "$S/samples/otherhost/"
  done
  oldest=$(ls "$H" | sort | head -n 1)
  run
  check "删了最旧的一个（F15）" '[ ! -f "$H/$oldest" ] && [ "$(ls "$H" | wc -l | tr -d " ")" = 2 ]'
  check "别的主机目录不动（F16）" '[ "$(ls "$S/samples/otherhost" | wc -l | tr -d " ")" = 2 ]'
  # 当天文件单独撑到上限：停止追加
  head -c 30000 /dev/zero | tr '\0' 'x' > "$H/$(today).jsonl"
  echo >> "$H/$(today).jsonl"
  before=$(wc -c < "$H/$(today).jsonl")
  run
  check "当天文件超上限不追加" '[ "$(wc -c < "$H/$(today).jsonl")" = "$before" ]'
  check "日志写了上限" 'grep -q "本次不追加" "$S/ops-v5-sampler.log"'
  check "旧文件全删光，当天留着" '[ "$(ls "$H")" = "$(today).jsonl" ]'
}

t_log_cap() {
  fresh log_cap
  echo "LOG_MAX_KB=16" >> "$C"
  mkdir -p "$S"
  head -c 20000 /dev/zero | tr '\0' 'x' > "$S/ops-v5-sampler.log"
  head -c 20000 /dev/zero | tr '\0' 'x' > "$S/ops-v5-sampler.launchd.log"
  run
  check "日志轮转成 .1（F17）" '[ -f "$S/ops-v5-sampler.log.1" ] && [ "$(wc -c < "$S/ops-v5-sampler.log")" -lt 1000 ]'
  check "launchd 日志也轮转" '[ -f "$S/ops-v5-sampler.launchd.log.1" ] && [ ! -f "$S/ops-v5-sampler.launchd.log" ]'
}

# ---------------------------------------------------------------- 回放
# 造数据：一台 testhost，总内存 8GB，按分钟给 availableMemory（GB）序列
gen() {  # gen <输出文件> <python 表达式：分钟 i -> avail GB 或 None> <分钟数>
  "$PY" -I - "$1" "$2" "$3" <<'PY'
import datetime, json, sys
out, expr, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
t0 = datetime.datetime(2026, 10, 20, 0, 0).astimezone()
with open(out, "w") as f:
    for i in range(n):
        a = eval(expr, {"i": i})
        t = t0 + datetime.timedelta(minutes=i)
        if a is None:
            continue
        r = {"schema": "ops-v5-sample/1", "ts": t.isoformat(timespec="seconds"),
             "minute": t.strftime("%Y-%m-%dT%H:%M"), "host": "testhost", "ok": True, "orca_ok": True,
             "machine": {"orca": {"availableMemory": int(a * 1024 ** 3), "totalMemory": 8 * 1024 ** 3,
                                  "loadAverage1m": 2.0}, "disk_home_avail_kb": 50 * 1024 * 1024,
                         "memorystatus_level": 40, "hw_memsize": 8 * 1024 ** 3, "vm_loadavg": [2.0, 2.0, 2.0]},
             "sessions": [{"memory": 300 * 1024 ** 2, "proc": {"found": True, "tree_rss_kb": 400 * 1024}}],
             "agent_count": {"total": 3}}
        f.write(json.dumps(r) + "\n")
    f.write("not json\n\n")
PY
}
rj() { "$PY" -I -c "import json,sys; r=json.load(open(sys.argv[1])); print($1)" "$WORK/$CASE/res.json"; }

t_replay_gate1() {
  fresh replay_gate1
  mkdir -p "$WORK/$CASE/s/testhost"
  # 0-29 充足；30-90 共 61 分钟只剩 1.5GB（R=1、F=1 时起不了）；91 缺；92-120 不足 60 分钟；121-140 充足
  gen "$WORK/$CASE/s/testhost/2026-10-20.jsonl" \
    '4.0 if i < 30 else (1.5 if i <= 90 else (None if i == 91 else (1.5 if i <= 120 else 4.0)))' 141
  "$REPLAY" --dir "$WORK/$CASE/s" --reserve-gb 1 --floor-gb 1 --load-max 8 --free-pct 10 \
    --json "$WORK/$CASE/res.json" > "$WORK/$CASE/summary.txt"
  check "回放退出码 0" '[ $? -eq 0 ]'
  check "坏行计数（R1）" '[ "$(rj "r[\"bad_lines\"]")" = 1 ]'
  check "门槛 1：最长 61 分钟（R3）" '[ "$(rj "r[\"grid\"][0][\"hosts\"][\"testhost\"][\"gate1\"][\"max_blocked_min\"]")" = 61 ]'
  check "门槛 1：只报一个超过 60 分钟的窗口，从 00:30 开始" '[ "$(rj "[(w[\"start\"][11:16], w[\"minutes\"]) for w in r[\"grid\"][0][\"hosts\"][\"testhost\"][\"gate1\"][\"windows_over_limit\"]]")" = "[('"'"'00:30'"'"', 61)]" ]'
  check "缺数据 1 分钟单列，打断连续段（R2）" '[ "$(rj "r[\"grid\"][0][\"hosts\"][\"testhost\"][\"gate1\"][\"unknown_minutes\"]")" = 1 ]'
  check "摘要里有分位数" 'grep -q "availableMemory_gb" "$WORK/$CASE/summary.txt"'
  check "该组合不被推荐" '[ "$(rj "r[\"recommendation\"][\"by_free_pct\"][\"10\"]")" = None ]'
}

t_replay_gate2() {
  fresh replay_gate2
  mkdir -p "$WORK/$CASE/s/testhost"
  # 0 分钟 3GB（R=1、F=1 可放一个），之后 10 分钟跌到 1.5GB：扣掉 R 后 free%=0.5/8=6.25% < 10%
  gen "$WORK/$CASE/s/testhost/2026-10-20.jsonl" '3.0 if i < 10 else (1.5 if i < 20 else 3.0)' 40
  "$REPLAY" --dir "$WORK/$CASE/s" --reserve-gb 1 --floor-gb 1 --load-max 8 --free-pct 5,10 \
    --admit-gap-min 60 --json "$WORK/$CASE/res.json" > /dev/null
  g2='r["grid"][0]["hosts"]["testhost"]["gate2"]'
  check "放行 1 次" '[ "$(rj "$g2[\"admits\"]")" = 1 ]'
  check "X=10%：1 次违规，最低 6.25%（R4）" '[ "$(rj "$g2[\"by_free_pct\"][\"10\"][\"violations\"], $g2[\"by_free_pct\"][\"10\"][\"worst_free_pct\"]")" = "1 6.25" ]'
  check "X=5%：不违规" '[ "$(rj "$g2[\"by_free_pct\"][\"5\"][\"violations\"]")" = 0 ]'
  check "分位数：会话 rss p90 = 0.391GB" '[ "$(rj "r[\"hosts\"][\"testhost\"][\"stats\"][\"session_tree_rss_gb\"][\"p90\"]")" = 0.391 ]'
  check "X=5% 有推荐、X=10% 没有" '[ "$(rj "r[\"recommendation\"][\"by_free_pct\"][\"5\"] is not None, r[\"recommendation\"][\"by_free_pct\"][\"10\"]")" = "True None" ]'
}

# ---------------------------------------------------------------- install.sh
t_install() {
  fresh install
  H="$WORK/$CASE/home"
  mkdir -p "$H"
  export FAKE_LAUNCHCTL_LOG="$WORK/$CASE/launchctl.log"
  HOME="$H" "$D/install.sh" --check > "$WORK/$CASE/check0" 2>&1
  check "装前 --check 退出 1" '[ $? -eq 1 ]'
  HOME="$H" "$D/install.sh" --dry-run > "$WORK/$CASE/dry" 2>&1
  check "--dry-run 退出 0 且不写文件" '[ $? -eq 0 ] && [ -z "$(ls -A "$H")" ]'
  check "--dry-run 列出 plist 和配置" 'grep -q "com.zhongc1211.ops-v5-sampler.plist" "$WORK/$CASE/dry" && grep -q "sampler.env" "$WORK/$CASE/dry"'
  HOME="$H" "$D/install.sh" --install > "$WORK/$CASE/inst1" 2>&1
  check "临时 HOME 安装退出 0" '[ $? -eq 0 ]'
  check "临时 HOME 下没调 launchctl" '[ ! -s "$FAKE_LAUNCHCTL_LOG" ] && grep -q "跳过 *launchctl" "$WORK/$CASE/inst1"'
  check "plist 里 HOME 已替换且合法" 'grep -q "$H/.local/bin/ops-v5-sampler" "$H/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist" && plutil -lint "$H/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist" >/dev/null'
  HOME="$H" "$D/install.sh" --install > "$WORK/$CASE/inst2" 2>&1
  check "重复安装不备份、不重复建" '! grep -q "备份" "$WORK/$CASE/inst2" && [ "$(ls "$H/.local/bin" | wc -l | tr -d " ")" = 2 ]'
  HOME="$H" "$H/.local/bin/ops-v5-sampler" --once > /dev/null 2>&1
  HOME="$H" "$D/install.sh" --check > "$WORK/$CASE/check1" 2>&1
  check "装后 --check 报版本、配置、采样年龄、大小" 'grep -q "版本 1.0.0" "$WORK/$CASE/check1" && grep -q "SAMPLER_CONFIG_VERSION=1" "$WORK/$CASE/check1" && grep -q "最近一次采样" "$WORK/$CASE/check1" && grep -q "KB" "$WORK/$CASE/check1"'
  echo "# local" >> "$H/.config/dispatch/sampler.env"
  HOME="$H" "$D/install.sh" --install > "$WORK/$CASE/inst3" 2>&1
  check "已有配置不覆盖" 'grep -q "# local" "$H/.config/dispatch/sampler.env"'
}

ALL="normal same_minute config_missing config_bad_version config_bad_value lock_held orca_missing orca_timeout round_timeout orca_bad_json orca_not_ok orca_enrich_fail fallback_tools_fail rotate_old size_cap log_cap replay_gate1 replay_gate2 install"
[ $# -gt 0 ] && ALL="$*"
for c in $ALL; do "t_$c"; done
echo
echo "通过 ${pass}，失败 ${fail}${failed:+（${failed# }）}"
[ "$fail" = 0 ]
