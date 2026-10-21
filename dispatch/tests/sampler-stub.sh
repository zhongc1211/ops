#!/bin/bash
# shellcheck disable=SC2034  # 有些变量只在 check 的 eval 字符串里用
# dispatch/tests/sampler-stub.sh：ops-v5-sampler / ops-v5-sample-replay / install.sh 的桩测。
# 假的 orca、ps、sysctl、df、launchctl、backup.sh 放在 PATH 最前面或临时 HOME 里；
# 全部在 mktemp -d 的临时目录里跑，HOME 也指过去。这是桩测，不是 E2E。
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
MACHINE=$(hostname -s | tr '[:upper:]' '[:lower:]')
pass=0
fail=0
failed=""

ok() { pass=$((pass + 1)); echo "  ok   $1"; }
no() { fail=$((fail + 1)); failed="$failed $CASE"; echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
# pyeq <名字> <输入文件> <python 表达式> <期望的 python 字面量>
#   输入文件按 JSON 读进 r（.jsonl 取最后一行）；相等算通过，不等时打印实际值
pyeq() {
  if "$PY" -I - "$2" "$3" "$4" <<'PY'
import json, sys
path, expr, want = sys.argv[1:4]
with open(path) as f:
    text = f.read()
r = json.loads([l for l in text.splitlines() if l.strip()][-1]) if path.endswith(".jsonl") else json.loads(text)
got = eval(expr, {"r": r})
if got != eval(want):
    print("    实际值：%r" % (got,))
    sys.exit(1)
PY
  then ok "$1"; else no "$1"; fi
}

# 每个用例一个干净的 state 目录和配置
fresh() {
  CASE=$1
  echo "[$CASE]"
  S="$WORK/$CASE/state"
  C="$WORK/$CASE/sampler.env"
  mkdir -p "$WORK/$CASE"
  printf 'SAMPLER_CONFIG_VERSION=1\nSAMPLER_HOST=testhost\nORCA_TIMEOUT_SEC=2\n' > "$C"
  unset FAKE_ORCA_MODE FAKE_PS_MODE FAKE_SYSCTL_MODE FAKE_DF_MODE FAKE_PIDFILE FAKE_BACKUP_MODE
}
run() { HOME="$WORK/$CASE/home" "$SAMPLER" --once --state-dir "$S" --config "$C"; }
today() { date +%Y-%m-%d; }
lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
DAY() { echo "$S/samples/testhost/$(today).jsonl"; }
DICT() { echo "$S/samples/testhost/$(today).sessions.jsonl"; }
ago() { "$PY" -I -c "import datetime,sys; print((datetime.date.today()-datetime.timedelta(days=int(sys.argv[1]))).isoformat())" "$1"; }
# 把最后一行的 minute 改成很早的一分钟，用来在同一分钟内模拟「下一分钟」
rewind() {
  "$PY" -I - "$(DAY)" <<'PY'
import json, sys
p = sys.argv[1]
ls = open(p).read().splitlines()
r = json.loads(ls[-1]); r["minute"] = "2000-01-01T00:00"; ls[-1] = json.dumps(r)
open(p, "w").write("\n".join(ls) + "\n")
PY
}
sizeof() { wc -c < "$1" | tr -d ' '; }

t_normal() {
  fresh normal
  mkdir -p "$WORK/$CASE/home"
  # env -i：模拟 launchd 的空环境，靠脚本自己补 PATH；桩目录仍然放在最前
  env -i HOME="$WORK/$CASE/home" PATH="$T/stubs" FAKE_FIXTURES="$FAKE_FIXTURES" \
    "$SAMPLER" --once --state-dir "$S" --config "$C" > "$WORK/$CASE/out" 2>&1
  check "退出码 0（F19 空环境）" '[ $? -eq 0 ]'
  check "写了一行" '[ "$(lines "$(DAY)")" = 1 ]'
  pyeq "schema/host/ok" "$(DAY)" '(r["schema"], r["host"], r["ok"], r["orca_ok"])' '("ops-v5-sample/2", "testhost", True, True)'
  pyeq "ts 带时区" "$(DAY)" 'r["ts"][19] in "+-"' 'True'
  pyeq "机器级读数" "$(DAY)" '(r["machine"]["orca"]["availableMemory"], r["machine"]["memorystatus_level"], r["machine"]["vm_loadavg"][0], r["machine"]["disk_home_avail_kb"])' '(2748779069, 40, 3.5, 44539588)'
  pyeq "三个会话" "$(DAY)" 'len(r["sessions"])' '3'
  pyeq "会话 A 每分钟字段：rss=528+1968+200000+50000，顶层 agent 只有 claude" "$(DAY)" \
    '{k: v for k, v in r["sessions"][0].items() if k != "sid"}' \
    '{"pid": 100, "memory": 300000000, "cpu": 1, "state": "working", "since": 1792554000000, "found": True, "tree_rss_kb": 252496, "n_procs": 4, "n_agents": 1, "agent_type": "claude"}'
  pyeq "会话 B agent 是 codex" "$(DAY)" 'r["sessions"][1]["agent_type"]' '"codex"'
  pyeq "会话 C（pid 300）找不到进程（F11）" "$(DAY)" 'r["sessions"][2]["found"]' 'False'
  pyeq "每分钟记录里没有静态字段" "$(DAY)" 'sorted(set(k for s in r["sessions"] for k in s) & {"worktreeName", "repoName", "worktreeId", "sessionId", "paneKey", "handle"})' '[]'
  pyeq "会话外 agent 只记个数、rss 合计：400 claude + 500 node（401 在 400 下面不算）" "$(DAY)" 'r["orphan_agents"]' '{"n": 2, "rss_kb": 110000, "by_comm": {"claude": 1, "node": 1}}'
  pyeq "agent 计数" "$(DAY)" 'r["agent_count"]' '{"in_sessions": 2, "orphan": 2, "total": 4}'
  check "字典写了 3 条" '[ "$(lines "$(DICT)")" = 3 ]'
  pyeq "字典最后一条（会话 C，对不上终端）" "$(DICT)" 'r["static"]' \
    '{"paneKey": "tabB:leafC", "sessionId": "repo1::/w/b@@2", "worktreeId": "repo1::/w/b", "worktreeName": "task B", "repoName": "ops", "handle": None, "agentType": None, "workingMode": None, "linkedLinearIssue": None}'
  check "字典第一条（会话 A）对上 term_A、claude、auto、PER-1" 'head -n 1 "$(DICT)" | grep -q "\"handle\":\"term_A\",\"agentType\":\"claude\",\"workingMode\":\"auto\",\"linkedLinearIssue\":\"PER-1\""'
  check "没存会话正文（F18）" '! grep -q SECRET_BODY_MARKER "$(DAY)" "$(DICT)"'
  pyeq "self 耗时和 rss" "$(DAY)" 'r["self"]["duration_ms"] >= 0 and r["self"]["maxrss_kb"] > 0' 'True'
  pyeq "状态文件 ok" "$S/ops-v5-sampler.status" 'r["state"]' '"ok"'
}

t_dict_dedup() {
  fresh dict_dedup
  run; rewind; run
  check "第二次采样追加了第 2 行（F21）" '[ "$(lines "$(DAY)")" = 2 ]'
  check "静态字段没变，字典不重复写" '[ "$(lines "$(DICT)")" = 3 ]'
  check "日志写 dict+0" 'grep -q "dict+0" "$S/ops-v5-sampler.log"'
}

t_same_minute() {
  fresh same_minute
  run && run
  check "同一分钟两次只一行（F5）" '[ "$(lines "$(DAY)")" = 1 ]'
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
  pyeq "状态文件 config_error" "$S/ops-v5-sampler.status" 'r["state"]' '"config_error"'
}

t_config_bad_value() {
  fresh config_bad_value
  printf 'SAMPLER_CONFIG_VERSION=1\nMAX_DAYS=two\n' > "$C"
  run 2>/dev/null
  check "数值项坏退出码 3（F3）" '[ $? -eq 3 ]'
  check "日志点名 MAX_DAYS" 'grep -q "MAX_DAYS" "$S/ops-v5-sampler.log"'
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
  check "没写 samples" '[ "$(lines "$(DAY)")" = 0 ]'
  check "日志写锁被占" 'grep -q "锁被占" "$S/ops-v5-sampler.log"'
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
  run
  check "锁放开后能写" '[ "$(lines "$(DAY)")" = 1 ]'
}

t_orca_missing() {
  fresh orca_missing
  echo "ORCA_BIN=$WORK/no-such-orca" >> "$C"
  run
  check "退出码 0" '[ $? -eq 0 ]'
  pyeq "orca_ok=false，错误 not_found（F6）" "$(DAY)" '(r["orca_ok"], [e["error"] for e in r["errors"] if e["step"] == "orca_diag"])' '(False, ["not_found"])'
  pyeq "后备读数还在" "$(DAY)" '(r["machine"]["memorystatus_level"], r["machine"]["hw_memsize"])' '(40, 8589934592)'
  pyeq "会话为空，会话外 agent 照记" "$(DAY)" '(len(r["sessions"]), r["agent_count"]["orphan"])' '(0, 4)'
}

t_orca_timeout() {
  fresh orca_timeout
  export FAKE_ORCA_MODE=timeout FAKE_PIDFILE="$WORK/$CASE/pids"
  start=$(date +%s)
  run
  el=$(( $(date +%s) - start ))
  check "ORCA_TIMEOUT_SEC=2，整次 < 6 秒（实际 ${el}s）（F7）" '[ "$el" -lt 6 ]'
  pyeq "orca_ok=false，错误 timeout" "$(DAY)" '(r["orca_ok"], r["errors"][0]["error"])' '(False, "timeout")'
  sleep 0.3
  alive=0
  while read -r p; do kill -0 "$p" 2>/dev/null && alive=1; done < "$FAKE_PIDFILE"
  check "假 orca 和它的 sleep 子进程都已被杀" '[ "$alive" = 0 ]'
  pyeq "后备读数还在" "$(DAY)" 'r["machine"]["memorystatus_level"]' '40'
}

t_round_timeout() {
  fresh round_timeout
  printf 'SAMPLER_CONFIG_VERSION=1\nSAMPLER_HOST=testhost\nORCA_TIMEOUT_SEC=10\nROUND_TIMEOUT_SEC=2\n' > "$C"
  export FAKE_ORCA_MODE=timeout
  start=$(date +%s)
  run
  el=$(( $(date +%s) - start ))
  check "整轮上限 2 秒压住了 10 秒的 orca 上限（实际 ${el}s）（F13）" '[ "$el" -lt 5 ]'
  pyeq "后面的步骤记 no_budget" "$(DAY)" 'any(e["error"] == "no_budget" for e in r["errors"])' 'True'
}

t_orca_bad_json() {
  fresh orca_bad_json
  export FAKE_ORCA_MODE=badjson
  run
  pyeq "坏 JSON：orca_ok=false，bad_json（F8）" "$(DAY)" '(r["orca_ok"], r["errors"][0]["error"])' '(False, "bad_json")'
}

t_orca_not_ok() {
  fresh orca_not_ok
  export FAKE_ORCA_MODE=notok
  run
  pyeq "ok:false → not_ok（F9）" "$(DAY)" '(r["orca_ok"], r["errors"][0]["error"])' '(False, "not_ok")'
  export FAKE_ORCA_MODE=exit1
  rm -rf "$S"
  run
  pyeq "退出码 1 → exit:1 并带首行" "$(DAY)" 'r["errors"][0]["error"]' '"exit:1 orca: runtime unavailable"'
}

t_orca_enrich_fail() {
  fresh orca_enrich_fail
  export FAKE_ORCA_MODE=enrichfail
  run
  pyeq "orca_ok 仍是 true（F10）" "$(DAY)" 'r["orca_ok"]' 'True'
  pyeq "两步补充都记错" "$(DAY)" 'sorted((e["step"], e["error"][:6]) for e in r["errors"])' '[("orca_terminal_list", "exit:1"), ("orca_worktree_ps", "bad_js")]'
  pyeq "会话照记，没有 state" "$(DAY)" '(len(r["sessions"]), "state" in r["sessions"][0])' '(3, False)'
  check "字典里 handle 为 null" 'head -n 1 "$(DICT)" | grep -q "\"handle\":null"'
}

t_fallback_tools_fail() {
  fresh fallback_tools_fail
  export FAKE_PS_MODE=fail FAKE_SYSCTL_MODE=fail FAKE_DF_MODE=fail
  run
  check "退出码 0（F12）" '[ $? -eq 0 ]'
  pyeq "错误记了 ps、3 个 sysctl、df" "$(DAY)" 'sorted(e["step"].split(":")[0] for e in r["errors"])' '["df", "ps", "sysctl", "sysctl", "sysctl"]'
  pyeq "agent_count、orphan_agents 为 null，会话没有 found" "$(DAY)" '(r["agent_count"], r["orphan_agents"], "found" in r["sessions"][0])' '(None, None, False)'
}

t_max_days() {
  fresh max_days
  echo "MAX_DAYS=3" >> "$C"
  H="$S/samples/testhost"
  mkdir -p "$H" "$S/samples/otherhost"
  for n in 1 2 3; do
    echo '{}' > "$H/$(ago "$n").jsonl"
  done
  echo '{}' > "$H/$(ago 1).sessions.jsonl"
  echo '{}' > "$S/samples/otherhost/$(ago 9).jsonl"
  run
  check "已有 3 天、到 MAX_DAYS=3：今天不写（F14）" '[ ! -f "$(DAY)" ]'
  check "旧文件一个没删（F14b）" '[ "$(ls "$H" | wc -l | tr -d " ")" = 4 ] && [ -f "$S/samples/otherhost/$(ago 9).jsonl" ]'
  check "日志 ERROR 写了停写原因" 'grep -q "ERROR 到上限，停写.*MAX_DAYS=3" "$S/ops-v5-sampler.log"'
  pyeq "状态文件 full" "$S/ops-v5-sampler.status" '(r["state"], "MAX_DAYS" in r["reason"])' '("full", True)'
  mkdir -p "$WORK/$CASE/moved" && mv "$H/$(ago 3).jsonl" "$WORK/$CASE/moved/"
  run
  check "ops 挪走一天后恢复写入" '[ "$(lines "$(DAY)")" = 1 ]'
  pyeq "状态文件回到 ok" "$S/ops-v5-sampler.status" 'r["state"]' '"ok"'
}

t_size_cap() {
  fresh size_cap
  # 上限约 20KB；放两个 10KB 的旧文件，加上本次记录超上限
  echo "MAX_TOTAL_MB=0.02" >> "$C"
  H="$S/samples/testhost"
  mkdir -p "$H"
  for n in 1 2; do
    head -c 10000 /dev/zero | tr '\0' 'x' > "$H/$(ago "$n").jsonl"
  done
  run
  check "超总大小：不写、不删（F15）" '[ ! -f "$(DAY)" ] && [ "$(ls "$H" | wc -l | tr -d " ")" = 2 ]'
  check "日志 ERROR 写了 MAX_TOTAL_MB" 'grep -q "ERROR 到上限，停写.*MAX_TOTAL_MB" "$S/ops-v5-sampler.log"'
  pyeq "状态文件 full" "$S/ops-v5-sampler.status" 'r["state"]' '"full"'
  # 挪走旧文件后能写；当天文件再撑到上限后停写，已有内容不动
  mv "$H/$(ago 1).jsonl" "$H/$(ago 2).jsonl" "$WORK/$CASE/"
  run
  check "挪走旧文件后写入 1 行" '[ "$(lines "$(DAY)")" = 1 ]'
  rec=$(tail -n 1 "$(DAY)")
  { head -c 25000 /dev/zero | tr '\0' 'x'; echo; printf '%s\n' "$rec"; } > "$(DAY)"
  rewind
  grown=$(sizeof "$(DAY)")
  run
  check "当天文件超上限后不再追加、不截断" '[ "$(sizeof "$(DAY)")" = "$grown" ]'
}

t_log_cap() {
  fresh log_cap
  printf 'LOG_MAX_KB=16\nLOG_ARCHIVE_MAX=2\n' >> "$C"
  mkdir -p "$S"
  head -c 20000 /dev/zero | tr '\0' 'x' > "$S/ops-v5-sampler.log"
  head -c 20000 /dev/zero | tr '\0' 'y' > "$S/ops-v5-sampler.launchd.log"
  run
  check "日志挪到 log-archive，新日志很小（F17）" '[ "$(ls "$S/log-archive" | grep -c "^ops-v5-sampler.log\.")" = 1 ] && [ "$(sizeof "$S/ops-v5-sampler.log")" -lt 1000 ]'
  check "launchd 日志也挪走" '[ "$(ls "$S/log-archive" | grep -c "^ops-v5-sampler.launchd.log\.")" = 1 ] && [ ! -f "$S/ops-v5-sampler.launchd.log" ]'
  # 再撑满一次：第二份归档不覆盖第一份（第一份的 2 万个 x 还在）
  head -c 20000 /dev/zero | tr '\0' 'z' >> "$S/ops-v5-sampler.log"
  rewind; run
  check "第二次挪走不覆盖第一份（共 2 份）" '[ "$(ls "$S/log-archive" | grep -c "^ops-v5-sampler.log\.")" = 2 ] && [ "$(cat "$S"/log-archive/ops-v5-sampler.log.* | tr -cd x | wc -c | tr -d " ")" = 20000 ]'
  # 归档满 2 份后：不再挪、不再写日志，数据照写
  head -c 20000 /dev/zero | tr '\0' 'w' >> "$S/ops-v5-sampler.log"
  sz=$(sizeof "$S/ops-v5-sampler.log")
  rewind; run
  check "归档满了：日志停写、不挪（F17b）" '[ "$(ls "$S/log-archive" | grep -c "^ops-v5-sampler.log\.")" = 2 ] && [ "$(sizeof "$S/ops-v5-sampler.log")" = "$sz" ]'
  check "数据照写" '[ "$(lines "$(DAY)")" = 3 ]'
}

# ---------------------------------------------------------------- 回放
# 造数据：一台 testhost，总内存 8GB，按分钟给 availableMemory（GB）序列；另写一份会话字典（回放应跳过）
gen() {  # gen <输出目录> <python 表达式：分钟 i -> avail GB 或 None> <分钟数>
  "$PY" -I - "$1" "$2" "$3" <<'PY'
import datetime, json, os, sys
out, expr, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
t0 = datetime.datetime(2026, 10, 20, 0, 0).astimezone()
with open(os.path.join(out, "2026-10-20.jsonl"), "w") as f:
    for i in range(n):
        a = eval(expr, {"i": i})
        t = t0 + datetime.timedelta(minutes=i)
        if a is None:
            continue
        r = {"schema": "ops-v5-sample/2", "ts": t.isoformat(timespec="seconds"),
             "minute": t.strftime("%Y-%m-%dT%H:%M"), "host": "testhost", "ok": True, "orca_ok": True,
             "machine": {"orca": {"availableMemory": int(a * 1024 ** 3), "totalMemory": 8 * 1024 ** 3,
                                  "loadAverage1m": 2.0}, "disk_home_avail_kb": 50 * 1024 * 1024,
                         "memorystatus_level": 40, "hw_memsize": 8 * 1024 ** 3, "vm_loadavg": [2.0, 2.0, 2.0]},
             "sessions": [{"sid": "a", "memory": 300 * 1024 ** 2, "found": True, "tree_rss_kb": 400 * 1024, "agent_type": "claude"},
                          {"sid": "b", "memory": 100 * 1024 ** 2, "found": True, "tree_rss_kb": 100 * 1024, "agent_type": "pi"}],
             "agent_count": {"total": 3}}
        f.write(json.dumps(r) + "\n")
    f.write("not json\n\n")
with open(os.path.join(out, "2026-10-20.sessions.jsonl"), "w") as f:
    f.write(json.dumps({"schema": "ops-v5-session-dict/1", "sid": "a", "static": {}}) + "\n")
PY
}

t_replay_gate1() {
  fresh replay_gate1
  mkdir -p "$WORK/$CASE/s/testhost"
  # 0-29 充足；30-90 共 61 分钟只剩 1.5GB（R=1、F=1 时起不了）；91 缺；92-120 不足 60 分钟；121-140 充足
  gen "$WORK/$CASE/s/testhost" \
    '4.0 if i < 30 else (1.5 if i <= 90 else (None if i == 91 else (1.5 if i <= 120 else 4.0)))' 141
  "$REPLAY" --dir "$WORK/$CASE/s" --reserve-gb 1 --floor-gb 1 --load-max 8 --free-pct 10 \
    --json "$WORK/$CASE/res.json" > "$WORK/$CASE/summary.txt"
  check "回放退出码 0" '[ $? -eq 0 ]'
  R="$WORK/$CASE/res.json"
  g1='r["grid"][0]["hosts"]["testhost"]["gate1"]'
  pyeq "坏行 1，会话字典跳过不算坏行（R1）" "$R" 'r["bad_lines"]' '1'
  pyeq "门槛 1：最长 61 分钟（R3）" "$R" "${g1}[\"max_blocked_min\"]" '61'
  pyeq "门槛 1：只报一个超过 60 分钟的窗口，从 00:30 开始" "$R" "[(w[\"start\"][11:16], w[\"minutes\"]) for w in ${g1}[\"windows_over_limit\"]]" '[("00:30", 61)]'
  pyeq "缺数据 1 分钟单列，打断连续段（R2）" "$R" "${g1}[\"unknown_minutes\"]" '1'
  check "摘要里有分位数和按 agent 类型的 rss" 'grep -q "availableMemory_gb" "$WORK/$CASE/summary.txt" && grep -q "tree_rss_gb\[claude\]" "$WORK/$CASE/summary.txt"'
  pyeq "该组合不被推荐" "$R" 'r["recommendation"]["by_free_pct"]["10"]' 'None'
}

t_replay_gate2() {
  fresh replay_gate2
  mkdir -p "$WORK/$CASE/s/testhost"
  # 0 分钟 3GB（R=1、F=1 可放一个），之后 10 分钟跌到 1.5GB：扣掉 R 后 free%=0.5/8=6.25% < 10%
  gen "$WORK/$CASE/s/testhost" '3.0 if i < 10 else (1.5 if i < 20 else 3.0)' 40
  "$REPLAY" --dir "$WORK/$CASE/s" --reserve-gb 1 --floor-gb 1 --load-max 8 --free-pct 5,10 \
    --admit-gap-min 60 --json "$WORK/$CASE/res.json" > /dev/null
  R="$WORK/$CASE/res.json"
  g2='r["grid"][0]["hosts"]["testhost"]["gate2"]'
  pyeq "放行 1 次" "$R" "${g2}[\"admits\"]" '1'
  pyeq "X=10%：1 次违规，最低 6.25%（R4）" "$R" "(${g2}[\"by_free_pct\"][\"10\"][\"violations\"], ${g2}[\"by_free_pct\"][\"10\"][\"worst_free_pct\"])" '(1, 6.25)'
  pyeq "X=5%：不违规" "$R" "${g2}[\"by_free_pct\"][\"5\"][\"violations\"]" '0'
  pyeq "分位数：会话 rss p90 = 0.391GB" "$R" 'r["hosts"]["testhost"]["stats"]["session_tree_rss_gb"]["p90"]' '0.391'
  pyeq "按 agent 类型：claude p90 0.391、pi p90 0.098（R6）" "$R" '{t: d["p90"] for t, d in r["recommendation"]["reserve_hint_gb_by_agent"].items()}' '{"claude": 0.391, "pi": 0.098}'
  pyeq "X=5% 有推荐、X=10% 没有" "$R" '(r["recommendation"]["by_free_pct"]["5"] is not None, r["recommendation"]["by_free_pct"]["10"])' '(True, None)'
}

# ---------------------------------------------------------------- install.sh
# 临时 HOME：放假 backup.sh（路径和真实的一样：~/ops-archive/per126-v5-backup-1021/<机器>/tools/backup.sh）
mkhome() {
  H="$WORK/$CASE/home"
  A="$H/ops-archive/per126-v5-backup-1021/$MACHINE"
  mkdir -p "$A/tools"
  cp "$T/stubs/fake-backup.sh" "$A/tools/backup.sh"
  export FAKE_LAUNCHCTL_LOG="$WORK/$CASE/launchctl.log" FAKE_BACKUP_CALLS="$WORK/$CASE/backup.calls"
}
inst() { HOME="$H" "$D/install.sh" "$@" > "$WORK/$CASE/out.$1" 2>&1; }
# 临时 HOME 里除了归档目录还有没有别的东西
nothing_installed() { [ -z "$(cd "$H" && find . -mindepth 1 -not -path './ops-archive*' | head -n 1)" ]; }

t_install() {
  fresh install
  mkhome
  inst --check
  check "装前 --check 退出 1" '[ $? -eq 1 ]'
  inst --dry-run
  check "--dry-run 退出 0，没写文件，没跑 backup.sh" '[ $? -eq 0 ] && nothing_installed && [ ! -f "$FAKE_BACKUP_CALLS" ]'
  check "--dry-run 列出快照步骤、plist、配置、ops-v5 数据目录" 'grep -q "backup.sh --label p2-sampler" "$WORK/$CASE/out.--dry-run" && grep -q "com.zhongc1211.ops-v5-sampler.plist" "$WORK/$CASE/out.--dry-run" && grep -q "sampler.env" "$WORK/$CASE/out.--dry-run" && grep -q "\.local/state/ops-v5/samples" "$WORK/$CASE/out.--dry-run"'
  inst --install
  check "临时 HOME 安装退出 0" '[ $? -eq 0 ]'
  check "先跑了 backup.sh --label p2-sampler（F22）" '[ "$(cat "$FAKE_BACKUP_CALLS")" = "fake backup.sh --label p2-sampler" ]'
  check "打印了快照目录和 MANIFEST sha256" 'grep -q "^快照 .*snapshots/20261021T120000-p2-sampler" "$WORK/$CASE/out.--install" && grep -q "^清单 *MANIFEST sha256 0*abc" "$WORK/$CASE/out.--install"'
  check "install-log.tsv 只有表头和 backup.sh 那一行，install.sh 没往里写" '[ "$(lines "$A/install-log.tsv")" = 2 ] && [ "$(tail -n 1 "$A/install-log.tsv" | cut -f3)" = p2-sampler ]'
  REC="$H/.local/state/ops-v5/install-records.tsv"
  check "安装记录写进 ~/.local/state/ops-v5/install-records.tsv：表头 + 4 个文件" '[ "$(lines "$REC")" = 5 ] && [ "$(sed 1d "$REC" | cut -f5 | sed "s|^$H/||" | tr "\n" " ")" = ".local/bin/ops-v5-sampler .local/bin/ops-v5-sample-replay Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist .config/dispatch/sampler.env " ]'
  check "记录里的 sha256 和已装文件一致，快照目录和 MANIFEST sha256 对上 backup.sh 那一行" '[ "$(sed -n 2p "$REC" | cut -f6)" = "$(shasum -a 256 "$H/.local/bin/ops-v5-sampler" | cut -d" " -f1)" ] && [ "$(sed -n 2p "$REC" | cut -f3)" = "$(tail -n 1 "$A/install-log.tsv" | cut -f4)" ] && [ "$(sed -n 2p "$REC" | cut -f4)" = "$(tail -n 1 "$A/install-log.tsv" | cut -f5)" ]'
  check "临时 HOME 下没调 launchctl" '[ ! -s "$FAKE_LAUNCHCTL_LOG" ] && grep -q "跳过 *launchctl" "$WORK/$CASE/out.--install"'
  check "plist 用 ops-v5 数据目录且合法" 'grep -q "$H/.local/state/ops-v5/ops-v5-sampler.launchd.log" "$H/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist" && plutil -lint "$H/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist" >/dev/null'
  inst --install
  check "重复安装：不备份、不重复建" '! grep -q "^备份" "$WORK/$CASE/out.--install" && [ "$(ls "$H/.local/bin" | wc -l | tr -d " ")" = 2 ]'
  # 改一下已装文件：重装时旧文件进归档，不放在 .local/bin 或 LaunchAgents 里
  echo "# drift" >> "$H/.local/bin/ops-v5-sample-replay"
  echo "<!-- drift -->" >> "$H/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist"
  inst --install
  check "覆盖前的旧文件进归档（不在 .local/bin、LaunchAgents）" '[ -f "$A"/p2-sampler-bak-*/.local/bin/ops-v5-sample-replay ] && [ -f "$A"/p2-sampler-bak-*/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist ] && [ "$(ls "$H/.local/bin" | wc -l | tr -d " ")" = 2 ] && [ "$(ls "$H/Library/LaunchAgents" | wc -l | tr -d " ")" = 1 ]'
  HOME="$H" "$H/.local/bin/ops-v5-sampler" --once > /dev/null 2>&1
  inst --check
  check "装后 --check 退出 0" '[ $? -eq 0 ]'
  check "装后 --check 报版本、配置、状态、采样年龄、大小" 'grep -q "版本 2.0.0" "$WORK/$CASE/out.--check" && grep -q "SAMPLER_CONFIG_VERSION=1" "$WORK/$CASE/out.--check" && grep -q "采样器状态 ok" "$WORK/$CASE/out.--check" && grep -q "最近一次采样" "$WORK/$CASE/out.--check" && grep -q "ops-v5/ [0-9]* KB" "$WORK/$CASE/out.--check"'
  echo '{"state": "full", "reason": "MAX_DAYS"}' > "$H/.local/state/ops-v5/ops-v5-sampler.status"
  inst --check
  check "采样器 full：--check 报警、退出 1" '[ $? -eq 1 ] && grep -q "^报警 *采样器状态 full" "$WORK/$CASE/out.--check"'
  echo "# local" >> "$H/.config/dispatch/sampler.env"
  inst --install
  check "已有配置不覆盖" 'grep -q "# local" "$H/.config/dispatch/sampler.env"'
}

t_install_backup_fail() {
  fresh install_backup_fail
  mkhome
  export FAKE_BACKUP_MODE=fail
  inst --install
  check "backup.sh 失败：退出非 0（F23）" '[ $? -ne 0 ] && grep -q "backup.sh 失败，什么都没装" "$WORK/$CASE/out.--install"'
  check "什么都没装" 'nothing_installed'
  export FAKE_BACKUP_MODE=noline
  inst --install
  check "backup.sh 没写 install-log：退出非 0，什么都没装" '[ $? -ne 0 ] && grep -q "不是多一行" "$WORK/$CASE/out.--install" && nothing_installed'
  export FAKE_BACKUP_MODE=wronglabel
  inst --install
  check "install-log 新行 label 不对：退出非 0，什么都没装" '[ $? -ne 0 ] && grep -q "label 不是 p2-sampler" "$WORK/$CASE/out.--install" && nothing_installed'
  rm -f "$A/tools/backup.sh"
  unset FAKE_BACKUP_MODE
  inst --install
  check "没有 backup.sh：退出非 0，什么都没装" '[ $? -ne 0 ] && grep -q "找不到本机快照脚本" "$WORK/$CASE/out.--install" && nothing_installed'
}

t_uninstall() {
  fresh uninstall
  mkhome
  inst --install
  HOME="$H" "$H/.local/bin/ops-v5-sampler" --once > /dev/null 2>&1
  inst --uninstall
  check "--uninstall 退出 0（F24）" '[ $? -eq 0 ]'
  check "plist、两个脚本、配置都挪到 removed-<时间>/，保留原层次" 'R=$(ls -d "$A"/removed-*); [ -f "$R/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist" ] && [ -f "$R/.local/bin/ops-v5-sampler" ] && [ -f "$R/.local/bin/ops-v5-sample-replay" ] && [ -f "$R/.config/dispatch/sampler.env" ] && [ "$(lines "$R/MOVED.tsv")" = 4 ]'
  check "原位置都没了" '[ ! -e "$H/Library/LaunchAgents/com.zhongc1211.ops-v5-sampler.plist" ] && [ ! -e "$H/.local/bin/ops-v5-sampler" ] && [ ! -e "$H/.config/dispatch/sampler.env" ]'
  check "数据目录默认留着" '[ -n "$(ls "$H/.local/state/ops-v5/samples/"*/*.jsonl 2>/dev/null)" ] && grep -q "^保留" "$WORK/$CASE/out.--uninstall"'
  check "临时 HOME 下没调 launchctl" '[ ! -s "$FAKE_LAUNCHCTL_LOG" ]'
  inst --check
  check "卸载后 --check 退出 1" '[ $? -eq 1 ]'
  inst --install
  sleep 1
  inst --uninstall --move-data
  check "--move-data：采样器的数据、日志、状态也挪走" 'R=$(ls -d "$A"/removed-* | tail -n 1); [ -d "$R/.local/state/ops-v5/samples" ] && [ -f "$R/.local/state/ops-v5/ops-v5-sampler.status" ] && [ ! -e "$H/.local/state/ops-v5/samples" ]'
}

t_install_not_macos() {
  fresh install_not_macos
  mkhome
  mkdir -p "$WORK/$CASE/bin"
  printf '#!/bin/sh\necho Linux\n' > "$WORK/$CASE/bin/uname"
  chmod +x "$WORK/$CASE/bin/uname"
  HOME="$H" PATH="$WORK/$CASE/bin:$PATH" "$D/install.sh" --check > "$WORK/$CASE/out" 2>&1
  check "不在 macOS：退出 2 并说明原因（F25）" '[ $? -eq 2 ] && grep -q "只支持 macOS（当前 Linux）" "$WORK/$CASE/out"'
  # 去掉 dscl：PATH 里只放 uname=Darwin 的桩
  mkdir -p "$WORK/$CASE/nodscl"
  printf '#!/bin/sh\necho Darwin\n' > "$WORK/$CASE/nodscl/uname"
  chmod +x "$WORK/$CASE/nodscl/uname"
  HOME="$H" PATH="$WORK/$CASE/nodscl" /bin/bash "$D/install.sh" --check > "$WORK/$CASE/out2" 2>&1
  check "缺 dscl：退出 2 并说明原因" '[ $? -eq 2 ] && grep -q "找不到 dscl" "$WORK/$CASE/out2"'
}

ALL="normal dict_dedup same_minute config_missing config_bad_version config_bad_value lock_held orca_missing orca_timeout round_timeout orca_bad_json orca_not_ok orca_enrich_fail fallback_tools_fail max_days size_cap log_cap replay_gate1 replay_gate2 install install_backup_fail uninstall install_not_macos"
[ $# -gt 0 ] && ALL="$*"
for c in $ALL; do "t_$c"; done
echo
echo "通过 ${pass}，失败 ${fail}${failed:+（${failed# }）}"
[ "$fail" = 0 ]
