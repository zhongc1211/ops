# pstack 新版每日监测：设计（PER-94）

关联：PER-67（交接第 12 项）、PER-83（#48 bootstrap 钉版）、PER-89（禁用命令 deny + UserPromptExpansion）、PER-92（#28 ops-verify）。
口径：Zack 10-20 18:53「出新版就做兼容检查（5 个禁用命令、verify-dv-site、wake-tla-verify、bootstrap），兼容才升级三台」。执行 ops 系统，验收 dr eggbot。

本文只是设计。本 PR 不装任何东西、不注册自动任务、不新建 Grok routine 或 Orca automation、不改线上文件。要装或要注册的项都列在第 7 节「待批」。

## 0. 总流程

```
每天 ops-verify 跑 U-pstack-upstream（便宜检查，纯 shell，约 1–25 秒，不调模型）
 ├─ 没出新版 → PASS，结束
 ├─ 新版已判不兼容 → PASS（证据写报告路径），结束
 ├─ 出新版、没有兼容报告 → FAIL → ops 系统先过 apiKeySource 闸（5.1）
 │     ├─ 闸不过（不是订阅 / 额度不够 / 读不到）→ 停，不跑，给 Zack 弹花钱卡；批了才往下
 │     └─ 闸过了 → 在 iMac 起一个兼容检查 agent（第 2 节）
 │     agent 写 box /workspace/ops/briefs/pstack-<版本>-compat-REPORT.md，末尾写「总判定：兼容 / 不兼容」
 │     ├─ 兼容 → 改 PSTACK_SHA 的 draft PR + 叫醒 ops 系统 → ops 系统给 Zack 弹升级卡（第 3 节）
 │     └─ 不兼容 → 记 Linear、留旧版、告 dr eggbot（第 3 节）
 └─ 新版已判兼容、钉版还没改 → FAIL → 提醒 ops 系统：升级卡还没批或还没升级
```

「新版」= cursor/plugins main 上 pstack 的 `plugin.json` 版本号，和钉住的 commit 里的版本号不同。只改别的插件、或改了 pstack 文件但没升版本号，都不算新版。

## 1. 发现：便宜检查

### 1.1 命令

脚本内容如下。落地时放在 `scripts/pstack-upstream-check.sh`（另开 PR，见第 7 节；本 PR 只拥有这份文档）。只读：不写文件、不起 claude、不 fetch 本地仓库。

```bash
#!/usr/bin/env bash
# pstack 上游便宜检查（PER-94）：只读，不写文件、不起 claude、不 fetch 本地仓库。
# 钉版 = ops 仓库 PIN_BRANCH 上 bootstrap/claude-plugins/pin-claude-plugins.sh 的 PSTACK_SHA（gh api 读，不依赖本地检出新旧）。
# 退出码：0 没出新版；1 出新版、还没兼容报告（要起兼容检查）；3 新版已判兼容、钉版还没改（要弹升级卡）；
#         4 新版已判不兼容（留旧版，什么都不做）；2 出错（网络 / gh / 取不到钉版或版本号）。
# 环境变量：PIN_BRANCH（默认 main）；PIN_SHA=<40 位>（演练用，直接给钉版）；
#           REPORTS（兼容报告目录，默认 box:/workspace/ops/briefs，本机目录也行）。
set -uo pipefail
PIN_BRANCH=${PIN_BRANCH:-main}
REPORTS=${REPORTS:-box:/workspace/ops/briefs}
MANIFEST=harness/pstack/claude-code/.claude-plugin/plugin.json
P=${PIN_SHA:-$(gh api -H 'Accept: application/vnd.github.raw' "repos/zhongc1211/ops/contents/bootstrap/claude-plugins/pin-claude-plugins.sh?ref=$PIN_BRANCH" 2>/dev/null | sed -n 's/^PSTACK_SHA=\([0-9a-f]\{40\}\).*/\1/p')}
M=$(git ls-remote https://github.com/cursor/plugins.git refs/heads/main 2>/dev/null | cut -f1)
[ -n "$P" ] && [ -n "$M" ] || { echo "ERR pinned=${P:-?} main=${M:-?}（取不到钉版或 ls-remote 失败）"; exit 2; }
if [ "$M" = "$P" ]; then echo "SAME pinned=$P main=$M"; exit 0; fi
ver() { curl -fsS --max-time 20 "https://raw.githubusercontent.com/cursor/plugins/$1/$MANIFEST" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])' 2>/dev/null; }
VP=$(ver "$P"); VM=$(ver "$M")
[ -n "$VP" ] && [ -n "$VM" ] || { echo "ERR 取不到 plugin.json 版本 pinned=$P(${VP:-?}) main=$M(${VM:-?})"; exit 2; }
N=$(gh api "repos/cursor/plugins/compare/$P...$M" --jq '"\(.status) ahead_by=\(.ahead_by) pstack_files=\([.files[].filename|select(startswith("harness/pstack/"))]|length)"' 2>/dev/null || echo "compare=失败")
line="pinned=$P($VP) main=$M($VM) $N"
if [ "$VP" = "$VM" ]; then echo "SAME-VERSION $line"; exit 0; fi
R="pstack-$VM-compat-REPORT.md"
case "$REPORTS" in
  box:*) V=$(ssh -o BatchMode=yes -o ConnectTimeout=8 box "grep -m1 '^总判定：' '${REPORTS#box:}/$R' 2>/dev/null" 2>/dev/null) ;;
  *)     V=$(grep -m1 '^总判定：' "$REPORTS/$R" 2>/dev/null) ;;
esac
case "$V" in
  总判定：兼容*)   echo "NEW-COMPATIBLE $line report=$REPORTS/$R"; exit 3 ;;
  总判定：不兼容*) echo "NEW-INCOMPATIBLE $line report=$REPORTS/$R"; exit 4 ;;
  *)               echo "NEW $line report=$REPORTS/$R（没有或还没写总判定）"; exit 1 ;;
esac
```

要点：

- 先比 commit（一次 `git ls-remote`，不要 token）。相同就当场结束，不发别的请求。
- commit 不同才取两边 `plugin.json` 的版本号（raw.githubusercontent.com，两次 curl）和 compare 摘要（一次 `gh api`，只当证据，不参与判断）。
- 「已经评估过」不另存状态文件，以 box `/workspace/ops/briefs/pstack-<版本>-compat-REPORT.md` 里有没有 `总判定：` 开头的行为准。同一版本只评估一次；上游当天又出新版，第二天的检查会看到新版本号、没有报告，再起一次。
- 版本号文件取 `.claude-plugin/plugin.json`。88d4751 里 `harness/pstack/claude-code/plugin.json` 和 `.claude-plugin/plugin.json` 都在（10-20 20:17 核对，两个都 HTTP 200）；#48 的 `--check` 读的是前者。哪天上游删掉其中一个，第 2 节的 bootstrap 检查会报出来。
- 报告命名从这次起按版本号。现有的 `pstack-88d4751-compat-REPORT.md` 不改名；88d4751 已经钉进 #48，便宜检查会走 `SAME` 分支，不去找它的报告。

### 1.2 本次实跑（只读，2026-10-20 iMac 和 box）

证据原文：box `/workspace/ops/reports/parallel-1020/PER-94-cheap-check-run.txt`。

| 时间（+08） | 机器 | 环境变量 | 输出 | 退出码 | 耗时 |
|---|---|---|---|---|---|
| 20:23:11 | iMac | `PIN_BRANCH=per83-claude-plugins-bootstrap`（#48 还没合，main 上没有钉版脚本） | `SAME pinned=88d47514b82e7c44f00f2b2a72ff6dd12158038c main=88d47514b82e7c44f00f2b2a72ff6dd12158038c` | 0 | 7.9 s |
| 20:23:19 | iMac | `PIN_BRANCH=main` | `ERR pinned=? main=88d4751…（取不到钉版或 ls-remote 失败）`：main 上还没有 `bootstrap/claude-plugins/`，符合预期 | 2 | 6.7 s |
| 20:23:26 | iMac | `PIN_SHA=0148b78c…`（演练：假装还钉旧版） | `NEW pinned=0148b78…(0.15.27) main=88d4751…(0.15.29) ahead ahead_by=12 pstack_files=16 report=box:/workspace/ops/briefs/pstack-0.15.29-compat-REPORT.md（没有或还没写总判定）` | 1 | 23.2 s |
| 20:23:49 | iMac | 同上 + `REPORTS=<scratch>/fake-reports`，里面放一份只有 `总判定：不兼容（演练）` 的假报告 | `NEW-INCOMPATIBLE …` | 4 | 22.5 s |
| 20:24:12 | iMac | 同上，假报告改成 `总判定：兼容（演练）` | `NEW-COMPATIBLE …` | 3 | 18.1 s |
| 20:24:53 | box | `PIN_BRANCH=per83-claude-plugins-bootstrap REPORTS=/workspace/ops/briefs` | `SAME …` | 0 | 1 s |
| 20:24:57 | box | `PIN_SHA=0148b78c… REPORTS=/workspace/ops/briefs` | `NEW … pstack_files=16 …` | 1 | 1 s |

1.3 的 ops-verify 改法也在 box 上试过：取 #28 当时的 head `c3ebd525601a7fca32bae8b3320dc0a3dd4f82af` 的 `scripts/ops-verify`（20:41 #28 已推到 `c70b487`，补丁用到的 `HERE`、`short`、`SKIPPED` 和 `dispatch()` 末尾那行都还在，打上后 `python3 -m py_compile` 通过；在 c70b487 上没有实跑），按 1.3 加函数和分派，配一张只有 `U-pstack-upstream` 一行的临时地图，放在 box `/tmp/per94-verify/`（不是线上路径，跑完已删），`python3 scripts/ops-verify --map SYSTEM_MAP.md --only U-pstack-upstream --out <临时目录>`：

| 时间（+08） | 环境变量 | ops-verify 输出 | ops-verify 退出码 |
|---|---|---|---|
| 20:35:38 | `PIN_BRANCH=per83-claude-plugins-bootstrap` | `PASS U-pstack-upstream rc=0 SAME …` | 0 |
| 20:35:39 | `PIN_SHA=0148b78c…` | `FAIL U-pstack-upstream rc=1 NEW … 0.15.27 … 0.15.29 …` | 1 |
| 20:35:40 | `PIN_BRANCH=main` | `SKIP U-pstack-upstream rc=2 ERR …` | 3（只有这一条且是 SKIP，0 条 PASS） |

第一版函数把 stderr 拼进证据，box 上 bash 的 `setlocale` 警告混了进去；已改成只取 stdout（stdout 为空才用 stderr），20:38 重跑三种情况，证据行干净。

`ahead_by=12`、`pstack_files=16` 和 PER-83 兼容报告里记的「中间 12 个提交，5 个改 harness/pstack，16 个文件」一致。第一张表 20:23:49、20:24:12 两行用的假报告是 iMac 临时目录里的演练文件（不是 box 上的真报告），只用来证明退出码 3 和 4 两个分支能走到。

### 1.3 挂在哪：ops-verify 新增一条 `U-pstack-upstream`

不挂夜审：五条夜审（心月 · 18/19、dv运维 · 20、dv广告 · 21、vllm · 22）是项目 bot 的模型 prompt，项目 bot 不该替 ops 判断插件版本；夜审 prompt 也正由 PER-86 改。ops-verify 是 ops 自己的只读巡检，便宜检查只读、不调模型，正好放在这里。

改动（在 #28 / PER-92 合并之后另开 PR，见第 7 节）：

1. `SYSTEM_MAP.md` 加一节、一行（#28 在 c70b487 已用到「## 9. 待合」，所以这里是第 10 节；编号以合并时为准。c70b487 的「待合」一节里 #48 那行写着「如果加了三台插件版本检查，同步加 ID」，就是这一条）：

   ```markdown
   ## 10. 插件版本

   | ID | 功能 | 入口 | 怎么验证 | 验证命令 |
   |---|---|---|---|---|
   | U-pstack-upstream | pstack 上游有没有出新版、出了有没有评估（PER-94） | `scripts/pstack-upstream-check.sh` | 退出码 0/4 PASS；1（新版未评估）、3（已判兼容未升级）FAIL；2（网络/gh）SKIP | `scripts/ops-verify --only U-pstack-upstream` |
   ```

2. `scripts/ops-verify` 加 11 行函数、2 行分派（放在 `dispatch()` 最后那个 `FAIL(...)` 之前）：

   ```python
   def c_pstack_upstream():
       env = dict(os.environ, REPORTS=ENV("OPS_VERIFY_PSTACK_REPORTS") or "/workspace/ops/briefs")
       try:
           p = subprocess.run([os.path.join(HERE, "pstack-upstream-check.sh")], capture_output=True, text=True, timeout=90, env=env)
       except (subprocess.TimeoutExpired, OSError) as e:
           SKIPPED("便宜检查没跑完：%s" % e)
       ev = "rc=%d %s" % (p.returncode, short(p.stdout or p.stderr, 400))
       if p.returncode in (0, 4):
           PASS(ev)
       (FAIL if p.returncode in (1, 3) else SKIPPED)(ev)
   ```

   ```python
       if cid == "U-pstack-upstream":
           return c_pstack_upstream()
   ```

   ops-verify 在 box 跑，报告目录就是本机 `/workspace/ops/briefs`，不用 ssh。网络失败记 SKIP（不是 FAIL），因为上游连不上不代表 ops 坏了；连续 3 天 SKIP 由读报告的人（ops 系统）发现并开 Linear。

### 1.4 频率

每天一次，跟 ops-verify 的日常运行一起跑。

现状（10-20 20:20 核对 iMac `orca automations list --json`，16 条；box、MBA 按 SYSTEM_MAP）：**ops-verify 目前没有任何定时运行**，是人或 bot 手跑。所以「每天」要靠下面二选一，都在第 7 节待批：

- A（推荐）：ops 系统每天开工第一件事跑 `scripts/ops-verify`（或只跑 `--only U-pstack-upstream`），看 FAIL 处理。不注册任何任务，0 成本，代价是 ops 系统哪天没开工就漏一天；漏一天的后果只是晚一天发现新版。
- B：等 PER-92 给 ops-verify 定了日常运行方式，`U-pstack-upstream` 自动跟着跑。

pstack 近期大约 1–2 天发一个版本，每天查一次足够。

## 2. 兼容检查（有新版才跑）

### 2.0 谁跑、在哪跑

- ops 系统看到 `U-pstack-upstream` FAIL（rc=1）后，先开一张 Linear（PER 团队，标题「pstack <版本> 兼容检查」），再在 **iMac** 起一个兼容检查 agent。不在 box 跑（box 是 bot 派活的机器，负载和权限都不合适）。MBA 只在 iMac 不可用时代替，命令相同。
- agent 本身用线上 pstack；每一项检查里另起子 claude，带候选参数，只在那个子进程里换成新版。候选不装进 `~/.claude`。
- 证据目录：iMac `~/orca/workspaces/ops/e2e-out/pstack-<版本>/`；报告写 box `/workspace/ops/briefs/pstack-<版本>-compat-REPORT.md`，关键日志 scp 到 box `/workspace/ops/reports/pstack-<版本>/`。
- 同一步最多试 2 次，不行就停，报告里写「没判定」，不写 `总判定：`（这样第二天便宜检查还会报 FAIL，不会漏）。
- **apiKeySource 闸（5.1），起 agent 之前**：ops 系统先跑闸 A（不调 claude）；过了再在 iMac 做 2.1 的准备和 init 探测（一次 Haiku、1 轮），把 `$OUT/0-init.jsonl` 交给闸 B。任何一步不过：不起 agent，按 5.1 弹花钱卡，Linear 卡上记一条评论。2.1 的 init 探测由 ops 系统在这里跑过，agent 不再重复。

起 agent（iMac，ops 系统执行；PER-xx 是上面新开的 Linear 号；闸 A、闸 B 都过了才执行）：

```bash
WT=$(orca worktree create --repo id:e9b33f9c-7218-4f6c-b03a-3b85fd8933ac --no-parent --name ops-pstack-<版本>-compat --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["worktree"]["id"])')
orca terminal create --worktree "$WT" --command "orca-agent-launch --bot ops-system --task 'PER-xx pstack <版本> 兼容检查' --issue PER-xx --eta '<YYYY-MM-DD HH:MM>' -- claude --model sonnet --dangerously-skip-permissions '读 ~/orca/briefs/pstack-<版本>-compat-BRIEF.md 并照做'"
```

（`orca worktree create --json` 的返回结构以实跑为准；brief 内容就是本节 2.1–2.6，ops 系统按本文拷一份填好版本号。）

### 2.1 准备候选（iMac，只写 `~/pstack-compat/`）

```bash
V=<新版本号>; M=<main 的 40 位 sha>; D=~/pstack-compat/cursor-plugins-${M:0:7}
OUT=~/orca/workspaces/ops/e2e-out/pstack-$V; mkdir -p "$OUT"
[ -d "$D/.git" ] || git clone --quiet https://github.com/cursor/plugins.git "$D"
git -C "$D" -c advice.detachedHead=false checkout --quiet --detach "$M"
git -C "$D" rev-parse HEAD | tee "$OUT/candidate-sha.txt"
CAND=(--settings '{"enabledPlugins":{"pstack@cursor-plugins":false}}' --plugin-dir "$D/harness/pstack/claude-code")
NOHOOK=(--settings '{"enabledPlugins":{"pstack@cursor-plugins":false},"disableAllHooks":true}' --plugin-dir "$D/harness/pstack/claude-code")
```

确认候选真的加载了（每个子 claude 的 init 事件都要看，这里先单独测一次）：

```bash
cd "$(mktemp -d)" && claude -p "回复 OK" --model haiku --max-turns 1 --output-format stream-json --verbose "${CAND[@]}" > "$OUT/0-init.jsonl"
python3 - "$OUT/0-init.jsonl" "$D/harness/pstack/claude-code" "$V" <<'PY'
import json, sys
init = next(json.loads(l) for l in open(sys.argv[1]) if '"subtype":"init"' in l)
ps = [p for p in init["plugins"] if p["name"] == "pstack"]
ok = len(ps) == 1 and ps[0]["path"] == sys.argv[2] and ps[0].get("version") == sys.argv[3]
print("init", "OK" if ok else "FAIL", init.get("claude_code_version"), ps)
sys.exit(0 if ok else 1)
PY
```

判过：只有一个 pstack，路径是候选目录，版本是 `$V`。不过：后面全部不跑，`总判定：不兼容（候选加载不上）`。

### 2.2 检查一：5 个禁用命令真禁

现网机制：`permissions.deny` 挡模型调用；人手输入由 hook 挡（#48 是 UserPromptSubmit `block-disabled-skills.sh`；PER-89 合并后换成 UserPromptExpansion + `onFailure: block`，补充 UserPromptSubmit `disabled-cmd-prompt-guard.sh`）。候选会话用 `--settings` 叠加在 user settings 上，线上的 deny 和 hook 照样生效，测的正是「新版 + 现网防线」。

(a) skill 目录名没变（名字一变，deny 和 hook 就对不上，等于没禁）：

```bash
for s in poteto-mode tdd reflect setup-pstack; do test -f "$D/harness/pstack/claude-code/skills/$s/SKILL.md" && echo "有 $s" || echo "缺 $s"; done | tee "$OUT/1a-skill-dirs.txt"
grep -l '^disable-model-invocation: true' "$D"/harness/pstack/claude-code/skills/{poteto-mode,tdd,reflect}/SKILL.md | tee -a "$OUT/1a-skill-dirs.txt"
```

另外人工看 `git -C "$D" diff --stat <钉版>..$M -- harness/pstack/` 有没有新增功能相同、名字不同的 skill（例如新出一个会 push/合并的流程），写进报告第（4）（5）项（沿用 `pstack-88d4751-compat-REPORT.md` 的五项格式）。

(b) 人手输入、模型调用、放行对照。iMac，空目录，Haiku，一次 1 轮：

```bash
T=$(mktemp -d); cd "$T"
CMDS=(/pstack:poteto-mode /poteto-mode /pstack:tdd /tdd /pstack:reflect /reflect /pstack:setup-pstack /setup-pstack /compound-engineering:lfg /lfg)
tag() { printf %s "$1" | tr -c 'a-z0-9' _; }
for c in "${CMDS[@]}"; do
  claude -p "$c hi" --model haiku --max-turns 1 --output-format stream-json --verbose "${NOHOOK[@]}" > "$OUT/1b-before-$(tag "$c").jsonl" 2>&1
  claude -p "$c hi" --model haiku --max-turns 1 --output-format stream-json --verbose "${CAND[@]}"   > "$OUT/1b-after-$(tag "$c").jsonl"  2>&1
done
for s in pstack:poteto-mode pstack:tdd pstack:reflect pstack:setup-pstack compound-engineering:lfg; do
  claude -p "用 Skill 工具调用 $s，不要做别的事。调用失败就原样说出报错。" --model haiku --max-turns 3 --output-format stream-json --verbose "${CAND[@]}" > "$OUT/1b-model-$(tag "$s").jsonl" 2>&1
done
claude -p "/pstack:how hi" --model haiku --max-turns 1 --output-format stream-json --verbose "${CAND[@]}" > "$OUT/1b-pass-pstack_how.jsonl" 2>&1
python3 ~/orca/workspaces/ops/e2e-out/pstack-judge.py "$OUT"/1b-*.jsonl | tee "$OUT/1b-summary.txt"
uptime | tee -a "$OUT/1b-summary.txt"
```

`pstack-judge.py`（ops 系统第一次用时从本文拷出来放到 `~/orca/workspaces/ops/e2e-out/`；落地 PR 里放 `scripts/`）：

```python
# 用法：python3 pstack-judge.py <stream-json 文件>...
# 每个文件一行：expanded（会话 transcript 里有 skill 正文）、blocked（没展开且花费 0）、refused（模型调 Skill 被拒）、cost。
# transcript 在 ~/.claude/projects/*/<session_id>.jsonl（只读）；找不到记 transcript=缺，expanded 只按 stream 判断。
import glob, json, os, sys
MARK = "Base directory for this skill"
for f in sys.argv[1:]:
    raw = open(f, errors="replace").read()
    res, sid = {}, None
    for l in raw.splitlines():
        try: d = json.loads(l)
        except ValueError: continue
        sid = sid or d.get("session_id")
        if d.get("type") == "result": res = d
    tr = glob.glob(os.path.expanduser("~/.claude/projects/*/%s.jsonl" % sid)) if sid else []
    text = raw + "".join(open(t, errors="replace").read() for t in tr)
    expanded = MARK in text
    cost = res.get("total_cost_usd", 0) or 0
    denials = len(res.get("permission_denials") or [])
    refused = denials > 0 or "disable-model-invocation" in text or "blocked by permission rules" in text
    print("%s expanded=%d blocked=%d refused=%d denials=%d cost=%.5f transcript=%s" % (
        os.path.basename(f), expanded, (not expanded) and cost == 0, refused, denials, cost, "有" if tr else "缺"))
```

`claude -p` 的 stream-json 里看不到展开的 skill 正文，要读会话 transcript 才能判断「展开了没有」。这个判定脚本 10-20 20:3x 在 iMac 上对 PER-83 的 18 个证据文件（box `/workspace/ops/reports/handover-item5-1020/imac/compat-88d4751/*.jsonl`）跑过，结果和报告一致：after 7/7 `blocked=1`，before 7/7 `expanded=1`，模型调用 3/3 `refused=1`。

判过（全部满足）：

| 项 | 期望 |
|---|---|
| 1a | 4 个目录都在；poteto-mode、tdd、reflect 仍是 `disable-model-invocation: true`（setup-pstack 不是，靠 deny 挡，和 0.15.29 相同；变了要写进报告） |
| before（关 hook） | 带前缀的 5 条 `expanded=1`（证明这组测试不是空转）。不带前缀的写法本机解析不到就照实写，不算失败 |
| after（候选 + 现网 hook） | 10 条全部 `blocked=1`、`expanded=0` |
| 模型调用 | 5 条全部 `refused=1` |
| 放行对照 `/pstack:how` | `expanded=1`、没被挡 |
| transcript | 所有文件 `transcript=有`；有「缺」的那条判定不可信，重跑一次 |

after 有漏挡时：看 `uptime`。load 超过 16（iMac 8 核的 2 倍）就等负载降下来重跑一次（PER-89 的教训：高负载下 UserPromptSubmit hook 5 秒超时会放行）。仍然漏挡，再用线上版本（去掉 `CAND`，其他不变）跑同一条：线上也漏 → 是现网防线的问题，和这次版本无关，另开 Linear 挂 PER-89，本项记「与版本无关」；只有候选漏 → 不兼容。

花费：约 26 次 Haiku 调用，PER-83 同类演示每次 US$0.004–0.006，合计约 US$0.15（估算）。

### 2.3 检查二：verify-dv-site（同 commit 对照组）

PER-83 的教训（`e2e-out/per83/A-candidate-summary.md`、`A-control-summary.md`）：iMac load 24–34 时候选组 7/9、8/9，对照组 5/9，失败都是 20 秒等待超时；对照组没在同一 commit、同样负载下跑之前，候选的失败没法归因。所以这里规定：

- 两组在**同一个 dv 官网 commit、同一个工作区、先后跑**（不并行，端口和 CPU 会互相影响）。
- 开跑前 `uptime` 的 1 分钟 load ≤ 12，否则每 10 分钟看一次，等满 2 小时还高就停，报告写「负载过高没跑」，不写总判定，第二天重来。
- pstack 只影响「claude 会话能不能找到并照着 skill 跑」，`verify.mjs` 本身不读 pstack。所以两组都由子 claude 通过 `/verify-dv-site` 触发，差别只在带不带 `CAND`。

```bash
DV=$(orca worktree create --repo id:f1681260-cc5c-456d-9b97-e9cd21e07e94 --no-parent --name ops-pstack-$V-verify-dv-site --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["worktree"]["path"])')
cd "$DV" && git rev-parse HEAD | tee "$OUT/2-dv-sha.txt" && git status --short | tee -a "$OUT/2-dv-sha.txt"
export PATH=~/.local/node22/bin:$PATH; npm ci > "$OUT/2-npm-ci.log" 2>&1; echo "npm ci rc=$?" >> "$OUT/2-npm-ci.log"
P='/verify-dv-site 只做本地只读验证：up --fresh、doctor、run --all、runs、check <这次的 run 目录> --sha HEAD、down --wipe-data，每条命令记退出码。禁止 --remote、部署、生产写入、发邮件、付费 API、写 D1/R2 生产；要密钥或写生产的步骤跳过并记「没跑」。不改代码、不 commit、不 push。最后输出这次 run 目录的绝对路径。'
for g in candidate control; do
  uptime | tee "$OUT/2-$g-uptime.txt"
  extra=(); [ $g = candidate ] && extra=("${CAND[@]}")
  notify-run --bot ops-system --task "PER-xx verify-dv-site $g" -- \
    claude -p "$P" --model sonnet --dangerously-skip-permissions --output-format stream-json --verbose "${extra[@]}" > "$OUT/2-$g.jsonl" 2>&1
  uptime | tee -a "$OUT/2-$g-uptime.txt"
done
```

每组跑完，从 `$OUT/2-<组>.jsonl` 末尾找 run 目录，拷 `run.json` 到 `$OUT/2-<组>-run.json`，再比：

```bash
python3 - "$OUT/2-candidate-run.json" "$OUT/2-control-run.json" <<'PY'
import json, sys
def fails(f):
    r = json.load(open(f))
    return r["sha"], r["status"], set(r.get("failed_tests", []))   # failed_tests 是「文件:行 标题」字符串
cs, cst, cf = fails(sys.argv[1]); ks, kst, kf = fails(sys.argv[2])
print("candidate", cst, sorted(cf)); print("control", kst, sorted(kf)); print("同 sha", cs == ks)
print("只在候选里挂的", sorted(cf - kf))
PY
grep -c "Base directory for this skill" ~/.claude/projects/*/$(python3 -c 'import json,sys;print(next(json.loads(l)["session_id"] for l in open(sys.argv[1]) if l.startswith("{")))' "$OUT/2-candidate.jsonl").jsonl
```

（字段按 PER-83 实际的 run.json：`sha`、`status`、`tests`、`failed_tests`，`failed_tests` 每项是 `admin.spec.ts:7 admin: …` 这样的字符串。报错原文在同一 run 目录的 `playwright.log`。）

判过：

| 结果 | 判定 |
|---|---|
| 候选 transcript 里没有 verify-dv-site 的 skill 正文（skill 没被触发） | 不兼容（新版抢了「verify」意图或 skill 没注册），先按「同一步最多 2 次」重跑一次确认 |
| 候选 `status=passed` | 过 |
| 候选挂，两组同 sha，候选的失败用例 ⊆ 对照的失败用例，且报错原文（文件:行、Expected/Received）相同 | 过，记「与 pstack 版本无关」，附用例名和报错原文 |
| 有只在候选里挂的用例 | 两组按同样顺序整轮重跑一次（不只重跑失败用例）；仍然只在候选里挂 → 不兼容 |

收尾：`down --wipe-data` 退出 0、端口释放、`git status --short` 为空，工作区 `orca worktree set --worktree <它> --workspace-status completed`。

花费：两个 Sonnet 会话，各约 25–55 分钟（PER-83 实测：对照组 23 分钟，候选组含重跑 55 分钟）。

### 2.4 检查三：wake-tla-verify

和 verify-dv-site 一样，TLC 的结果本身不依赖 pstack；要验证的是「新版下 `/wake-tla-verify` 这个 skill 能注册、能被 slash 触发、照着跑出和期望一致的结果」。

前提：iMac 要有 Java 17 和 tla2tools.jar v1.7.4（`wake/tla/README.md`「安装」，装在 `~/.local/opt/`，不用 sudo）。**10-20 20:20 核对：iMac 只有 Java 1.8.0_292，MBA 没有 Java**。PER-83 是 ssh 到 box 上跑的，不符合「不在 box 跑」。所以这项在 Java 17 装好之前跑不了，安装列在第 7 节待批。

默认跑**全量 36 项**（`check.sh` 不带名字前缀）。缩减版不在默认流程里，见第 7 节待批第 6 条。

```bash
cd ~/orca/workspaces/ops/ops-pstack-$V-compat   # 2.0 建的工作区，origin/main 最新
git rev-parse HEAD | tee "$OUT/3-ops-sha.txt"
notify-run --bot ops-system --task "PER-xx wake-tla-verify 候选（全量）" -- \
  claude -p "/wake-tla-verify 跑全量：wake/tla/check.sh --out $OUT/3-candidate-tla（不带名字前缀），不改模型、不改代码，最后原样贴出 check.sh 的最后 20 行和退出码。" \
  --model sonnet --dangerously-skip-permissions --output-format stream-json --verbose "${CAND[@]}" > "$OUT/3-candidate.jsonl" 2>&1
python3 - "$OUT/3-candidate-tla/summary.tsv" <<'PY2'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
bad = [r["name"] for r in rows if r["match"] != "ok"]
print("rows", len(rows), "不一致", bad)
sys.exit(0 if len(rows) == 36 and not bad else 1)
PY2
```

判过（全部满足）：候选 transcript 里有 wake-tla-verify 的 skill 正文；`check.sh` 退出 0，输出「全部和期望一致。」，没有「模型对应的代码和建模时不一样了」提示；`summary.tsv` 36 行、每行 `match=ok`（PER-83 10-20 在 box 上 a27ece5 的结果就是 36/36 ok，见 `e2e-out/per83/B-candidate-out/summary.tsv`）。36 是 10-20 `check.sh` 表里的条数；以后 `wake/tla/` 加减了检查，以当时 `check.sh` 表里的行数为准，并在报告里写出来。

对照组只在候选不过时跑（和 verify-dv-site 同法）：`check.sh` 自己的期望表就是基线，候选全绿时不必再跑一遍 25 分钟以上的全量。候选不过时，在同一 commit、不带 `CAND` 直接跑全量：

```bash
notify-run --bot ops-system --task "PER-xx wake-tla-verify 对照（全量）" -- wake/tla/check.sh --out "$OUT/3-direct-tla"; echo "check.sh rc=$?" | tee "$OUT/3-direct-rc.txt"
diff <(cut -f1-5 "$OUT/3-candidate-tla/summary.tsv") <(cut -f1-5 "$OUT/3-direct-tla/summary.tsv") && echo 一致 | tee -a "$OUT/3-direct-rc.txt"
```

- 候选没触发 skill → 重跑一次，仍不触发 → 不兼容。
- 候选不过、对照过 → 不兼容。
- 两组都不过且 `summary.tsv` 前 5 列（name、module、expect、result、match）相同 → 和版本无关（代码或环境问题），另开 Linear，本项记「与版本无关」。

耗时：PER-83 在 box 跑全量是 24.5 分钟（36 项 TLC 时间合计 1471 秒，最长 w15 190 秒、w16 189 秒）。iMac 没跑过。`check.sh` 在 load > 8 时先等 5 分钟、最多等 3 次，iMac 平时 load 20 以上，所以按 25–45 分钟估；要跑对照再加一倍。

### 2.5 检查四：bootstrap `--check`（沙箱，不碰线上 `~/.claude`）

验证钉版脚本对新版还能用：新 commit 能检出、`plugin.json` 路径还在、装完 `--check` 全部一致。只改临时目录。

```bash
cd ~/orca/workspaces/ops/ops-pstack-$V-compat
B=$(mktemp -d); cp -R bootstrap/claude-plugins "$B/"
sed -i '' "s/^PSTACK_SHA=[0-9a-f]\{40\}/PSTACK_SHA=$M/" "$B/claude-plugins/pin-claude-plugins.sh"
H=$(mktemp -d); mkdir -p "$H/.claude/plugins"; echo '{}' > "$H/.claude/settings.json"; echo '{}' > "$H/.claude/plugins/known_marketplaces.json"
"$B/claude-plugins/pin-claude-plugins.sh" --home "$H" > "$OUT/4-install.txt" 2>&1; echo "install rc=$?" >> "$OUT/4-install.txt"
"$B/claude-plugins/pin-claude-plugins.sh" --home "$H" --check > "$OUT/4-check.txt" 2>&1; echo "check rc=$?" >> "$OUT/4-check.txt"
git -C "$H/.claude/pinned-marketplaces/cursor-plugins" rev-parse HEAD >> "$OUT/4-check.txt"
```

判过：install rc=0，check rc=0，检出 HEAD = `$M`，`installed_plugins.json` 里 pstack 版本 = `$V`。不过且原因是脚本读不到新版的文件（例如 `plugin.json` 挪了位置）→ 不兼容，同时在 Linear 写「#48 脚本要改」。

注意：`pin-claude-plugins.sh` 装完会跑 `claude plugin marketplace update/install`，HOME 是沙箱，不碰线上 `~/.claude`；它会从 GitHub 克隆两个插件仓库（各几十 MB）。

### 2.6 报告与总判定

报告 `pstack-<版本>-compat-REPORT.md` 沿用 `pstack-88d4751-compat-REPORT.md` 的格式，四项检查各写：命令、机器、commit、结果、证据路径、耗时、花费，再加原来的（4）skill 冲突对照和（5）新增花钱/push/合并行为。最后一行写且只写一次：

- `总判定：兼容` —— 2.1–2.5 全部「过」或「与版本无关」，并且（4）（5）没有新增需要另禁的命令；
- `总判定：不兼容（<哪一项>）` —— 任何一项「不兼容」；
- 有项「没跑」或「没判定」→ **不写**总判定行，便宜检查第二天继续报 FAIL。

agent 写完报告后退出，notify-run 叫醒 ops 系统。

## 3. 结果处理

### 兼容

1. 兼容检查 agent 在 ops 仓库开 **draft** PR：只改 `bootstrap/claude-plugins/pin-claude-plugins.sh` 顶部 `PSTACK_SHA` 和 README 的版本表；PR 描述写候选 sha、版本、四项检查的结果表和证据路径（按测试规矩五项）。不合并、不转 ready。
2. ops 系统给 Zack 弹升级卡，卡上附：版本 `<旧>` → `<新>`、两个 sha、报告路径、PR 链接、四项结果一行一项、预计升级时间（三台约 15 分钟）、回滚命令（第 4 节）。自动任务和兼容 agent 都不直接找 Zack。
3. Zack 批了才合 PR、才升级三台。没批之前，便宜检查每天报 `NEW-COMPATIBLE`（rc=3，FAIL），提醒这张卡还挂着。

### 不兼容

1. 在 2.0 开的 Linear 卡上写评论：哪一项不过、报错原文、证据路径；卡留 open，挂 PER-83。
   `orca linear comment add PER-xx --body-file <摘要文件>`
2. 留旧版：不开 PR，三台什么都不动。报告写了 `总判定：不兼容`，之后便宜检查对这个版本返回 rc=4（PASS），不再重复评估；上游出下一个版本时自动重新评估。
3. 告 dr eggbot：iMac 上没有直接给 dr eggbot 发消息的渠道（没有它的 webhook，Slack 找不到，Telegram 没连）。ops 系统按惯例叫醒 coding-assistant 转达，消息里附一段可以直接转发的摘要（版本、哪项不过、Linear 号、报告路径）。

## 4. 升级与回滚

前提：Zack 批了升级卡，PR 已合进 ops main。#48 合并前的机器状态见 `handover-item5-pstack-ssh-RESULT.md`。

### 4.1 顺序

iMac → MBA → box。iMac 先升，因为兼容检查就是在它上面跑的；box 最后，因为它跑着最多 bot 派活的会话。每台 `--check` 退出 0、冒烟通过，才升下一台；任何一台不过就停，回滚这一台，其他台不动。

正在跑的 claude 会话不受影响（插件只在新会话或 `/reload-plugins` 时重读），不重启、不 kill 任何会话。

### 4.2 每台的命令

iMac、MBA（MBA 用 `ssh mba '<同样命令>'`，仓库路径是 MBA 上的 ops 主工作区）；box 用 `ssh box`，仓库是 `/workspace/repos/ops`：

```bash
R=<ops 主工作区>; E=<证据目录，如 ~/orca/workspaces/ops/e2e-out/pstack-$V/upgrade-$(hostname -s)>; mkdir -p "$E"
# 前：备份 + 证据
TS=$(date +%Y%m%d-%H%M); mkdir -p ~/claude-backups/cfg-$TS/plugins
cp -p ~/.claude/settings.json ~/.claude/CLAUDE.md ~/claude-backups/cfg-$TS/
cp -p ~/.claude/plugins/{known_marketplaces,installed_plugins}.json ~/claude-backups/cfg-$TS/plugins/
git -C ~/.claude/pinned-marketplaces/cursor-plugins rev-parse HEAD > "$E/before-sha.txt"
(cd /tmp && claude plugin list 2>&1 | grep -A2 'pstack@cursor-plugins') > "$E/before-plugin-list.txt"
shasum -a 256 ~/.claude/settings.json > "$E/before-settings.sha256"
# 升
git -C "$R" fetch -q origin && git -C "$R" checkout -q --detach origin/main
git -C "$R" rev-parse HEAD > "$E/ops-sha.txt"
"$R/bootstrap/claude-plugins/pin-claude-plugins.sh" > "$E/install.txt" 2>&1; echo "rc=$?" >> "$E/install.txt"
# 后：证据
"$R/bootstrap/claude-plugins/pin-claude-plugins.sh" --check > "$E/after-check.txt" 2>&1; echo "rc=$?" >> "$E/after-check.txt"
git -C ~/.claude/pinned-marketplaces/cursor-plugins rev-parse HEAD > "$E/after-sha.txt"
(cd /tmp && claude plugin list 2>&1 | grep -A2 'pstack@cursor-plugins') > "$E/after-plugin-list.txt"
# 冒烟（新会话，Haiku，空目录）：被禁的挡住、放行的照常、init 是新版本
cd "$(mktemp -d)"
claude -p "/pstack:tdd hi"  --model haiku --max-turns 1 --output-format stream-json --verbose > "$E/smoke-tdd.jsonl" 2>&1
claude -p "/pstack:how hi"  --model haiku --max-turns 1 --output-format stream-json --verbose > "$E/smoke-how.jsonl" 2>&1
python3 ~/orca/workspaces/ops/e2e-out/pstack-judge.py "$E"/smoke-*.jsonl | tee "$E/smoke-summary.txt"
grep -o '"name":"pstack","path":"[^"]*","source":"[^"]*","version":"[^"]*"' "$E/smoke-how.jsonl" | head -1 | tee -a "$E/smoke-summary.txt"
```

注意：

- ops 主工作区可能有别人的未提交改动。上面 `checkout --detach origin/main` 之前先 `git -C "$R" status --short`，不干净就不要动它，改成 `git -C "$R" worktree add /tmp/ops-pstack-$V origin/main` 在临时 worktree 里跑脚本，跑完 `git worktree remove`。
- box 和 MBA 上 `pstack-judge.py` 不在那个路径，就把冒烟两条的判断改成看 `smoke-tdd.jsonl` 的 result 里 `total_cost_usd` 是 0、`smoke-how.jsonl` 不是 0。

每台判过：`after-check.txt` rc=0；`after-sha.txt` = 新 sha；`claude plugin list` 显示新版本；`smoke-tdd` `blocked=1`、`smoke-how` `expanded=1`；init 里 pstack 版本 = 新版本。

证据汇总：三台的 before/after sha、版本、`--check` 结果写进 box `/workspace/ops/reports/pstack-<版本>/upgrade-RESULT.md`，并贴到 Linear 卡和升级卡的回复里。

### 4.3 回滚

单台出问题（不等 PR，先恢复这台）：

```bash
OLD=<升级前的 sha，见 before-sha.txt>
git -C ~/.claude/pinned-marketplaces/cursor-plugins -c advice.detachedHead=false checkout --quiet --detach "$OLD"
cd /tmp && claude plugin marketplace update cursor-plugins && claude plugin update pstack@cursor-plugins
git -C ~/.claude/pinned-marketplaces/cursor-plugins rev-parse HEAD; claude plugin list | grep -A2 'pstack@cursor-plugins'
```

这时 `--check` 会报不符（main 上钉的是新版），这是预期的，直到下面的 revert 合并。

全部回滚（正式）：

```bash
git -C <ops 工作区> revert <改 PSTACK_SHA 的那个提交>   # 开 draft PR，Zack 批后合并
# 合并后三台各跑一次：
<ops 主工作区>/bootstrap/claude-plugins/pin-claude-plugins.sh && <ops 主工作区>/bootstrap/claude-plugins/pin-claude-plugins.sh --check
```

配置文件被改坏时（不该发生：脚本只改 deny、市场源、启用插件、hook 四类键）：先 `diff` 备份和现在的 `~/.claude/settings.json`，确认只差本次改动，再 `cp -p ~/claude-backups/cfg-<TS>/settings.json ~/.claude/settings.json`；`plugins/*.json` 同理。不要整包解回 `~/.claude` 的 tgz（会覆盖期间所有会话记录）。

## 5. 成本与花钱闸

### 5.1 apiKeySource 闸（开跑前硬闸）

兼容检查要起 4 个 Sonnet 会话和约 30 次 Haiku 调用。只有在走登录订阅、额度够、不会按量计费时才跑。闸由 ops 系统在起兼容 agent 之前执行（2.0），任何一项读不到都按「不是订阅」处理。

**闸 A：不调 claude**，只看变量名和键名，不读值（在 iMac 跑）：

```bash
# 闸 A：不调 claude，只看变量名和键名，不读值。有任何一项 → 按量计费的可能，停。
bad=0
for v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX; do
  if [ -n "${!v+x}" ]; then echo "STOP 环境变量 $v 存在"; bad=1; fi
done
python3 - <<'PY' || bad=1
import json, os, sys
p = os.path.expanduser("~/.claude/settings.json")
try: s = json.load(open(p))
except Exception as e: print("STOP 读不了 settings.json：%s" % type(e).__name__); sys.exit(1)
hits = (["apiKeyHelper"] if "apiKeyHelper" in s else []) + [k for k in s.get("env", {}) if k.startswith(("ANTHROPIC_", "CLAUDE_CODE_USE_"))]
print(("STOP settings.json 有 " + ", ".join(hits)) if hits else "OK settings.json 没有 apiKeyHelper / ANTHROPIC_* / CLAUDE_CODE_USE_*")
sys.exit(1 if hits else 0)
PY
[ $bad = 0 ] && echo "闸 A 通过" || echo "闸 A 不通过：弹花钱卡，不起 agent"
exit $bad
```

**闸 B：读 init 消息和用量**。`apiKeySource` 和 5 小时 / 7 天用量只出现在 `claude -p --output-format stream-json --verbose` 的输出里：init 消息（`"subtype":"init"`）带 `apiKeySource`，`"type":"rate_limit_event"` 带 `rate_limit_info.unifiedWindows.five_hour/seven_day.utilization` 和 `overageStatus`、`isUsingOverage`。普通会话 transcript（`~/.claude/projects/*/*.jsonl`）里没有这两样（10-20 21:1x 查了 iMac 最近 30 个 transcript，都没有）。所以闸 B 用 2.1 的 init 探测（一次 Haiku、1 轮）的输出 `$OUT/0-init.jsonl`：

```python
# 闸 B：读一次 claude -p --output-format stream-json --verbose 的输出（init 消息 + rate_limit_event）。
# 用法：python3 gate-probe.py <stream-json 文件> [5h 上限，默认 0.5] [7d 上限，默认 0.7]
# 退出 0 = 订阅且额度够；1 = 停下弹花钱卡。读不到任何一项都按「不是订阅 / 额度不明」处理。
import json, sys, time
f = sys.argv[1]; max5 = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5; max7 = float(sys.argv[3]) if len(sys.argv) > 3 else 0.7
init = rl = None
for l in open(f, errors="replace"):
    try: d = json.loads(l)
    except ValueError: continue
    if d.get("subtype") == "init" and init is None: init = d
    if d.get("type") == "rate_limit_event": rl = d.get("rate_limit_info") or {}
why = []
src = init.get("apiKeySource") if init else None
if src != "none": why.append("apiKeySource=%r（只有 none = 登录订阅；读不到也算不是订阅）" % src)
w = (rl or {}).get("unifiedWindows") or {}
u5 = (w.get("five_hour") or {}).get("utilization"); u7 = (w.get("seven_day") or {}).get("utilization")
if u5 is None or u7 is None: why.append("没有 rate_limit_event 的 5h/7d 用量")
else:
    if u5 > max5: why.append("5h 用量 %.2f > %.2f" % (u5, max5))
    if u7 > max7: why.append("7d 用量 %.2f > %.2f" % (u7, max7))
if rl and rl.get("isUsingOverage"): why.append("isUsingOverage=true（已在用超额，按量计费）")
if rl and rl.get("overageStatus") != "rejected": why.append("overageStatus=%r（超额没关，用超了会计费）" % rl.get("overageStatus"))
fmt = lambda t: time.strftime("%m-%d %H:%M", time.localtime(t)) if t else "?"
print("apiKeySource=%s 5h=%s（%s 重置） 7d=%s（%s 重置） overage=%s/%s" % (src, u5, fmt((w.get("five_hour") or {}).get("resetsAt")),
      u7, fmt((w.get("seven_day") or {}).get("resetsAt")), (rl or {}).get("overageStatus"), (rl or {}).get("isUsingOverage")))
print("闸 B 通过" if not why else "闸 B 不通过：" + "；".join(why))
sys.exit(1 if why else 0)
```

两段都由 ops 系统第一次用时从本文拷出来，放到 `~/orca/workspaces/ops/e2e-out/pstack-gate-static.sh` 和 `pstack-gate-probe.py`（和 `pstack-judge.py` 同目录；落地 PR 里放 `scripts/`）：

```bash
bash ~/orca/workspaces/ops/e2e-out/pstack-gate-static.sh || { echo 弹花钱卡; exit 1; }
# 2.1 准备候选 + init 探测之后：
python3 ~/orca/workspaces/ops/e2e-out/pstack-gate-probe.py "$OUT/0-init.jsonl"   # 默认 5h ≤ 0.5、7d ≤ 0.7；退出 1 = 弹花钱卡
```

不过的条件（任一项）：

| 条件 | 为什么 |
|---|---|
| 闸 A：有 `ANTHROPIC_API_KEY`、`ANTHROPIC_AUTH_TOKEN`、`CLAUDE_CODE_USE_BEDROCK`、`CLAUDE_CODE_USE_VERTEX` 环境变量，或 `settings.json` 有 `apiKeyHelper`、`env` 里有 `ANTHROPIC_*` / `CLAUDE_CODE_USE_*` | 这些会让 Claude Code 改走 API key、Bedrock 或 Vertex，按量计费 |
| `apiKeySource` 不是 `"none"`，或读不到 | `none` = 没用 API key，走登录订阅（三台 10-20 的 init 都是 `none`）；其他值（如 `ANTHROPIC_API_KEY`、`apiKeyHelper`）按量计费 |
| 没有 `rate_limit_event`，或缺 5h / 7d 用量 | 读不到额度，按不够处理 |
| `five_hour.utilization` > 0.5 | 兼容检查要连续跑 1.5–3 小时，会跨进下一个 5 小时窗口；起点过半就可能在中途撞上限 |
| `seven_day.utilization` > 0.7 | 留 30% 给三台日常派活 |
| `isUsingOverage` 是 true，或 `overageStatus` 不是 `"rejected"` | 超额开着时，用超了会按量计费 |

阈值 0.5 / 0.7 是估算：现在没有「一次完整兼容检查用掉多少额度」的实测。每次跑完，在报告里记开跑前和每项检查后 `rate_limit_event` 的两个用量（每个子 claude 的 stream-json 里都有），攒 2–3 次后按实测改阈值。

**跑的中途也看**：每项检查跑完，对这一项的子 claude 输出再跑一次 `pstack-gate-probe.py <那个文件> 0.85 0.85`。不过就停在这里，报告写「额度不够，没跑完」，不写总判定，等额度重置后第二天重来；不改成按量继续跑。

**闸 B 本身的花费**：闸 A 过了，闸 B 那次 Haiku 调用走订阅，不花现金。如果闸 A 漏判、实际在按量计费，这一次最多花约 US$0.006（PER-83 同样一次 1 轮 Haiku 的 `total_cost_usd` 是 0.00558）。

**不过时：停下，弹花钱卡**。ops 系统给 Zack 单独弹一张卡（不和升级卡合并），卡上写：

- Linear 编号（2.0 开的那张）、pstack 新版本号和 sha；
- 哪一条没过、实际值（例如「apiKeySource=ANTHROPIC_API_KEY」「5h 用量 0.62 > 0.5，21:50 重置」），不贴任何 key；
- 按量计费时的估算花费：见 5.2「出新版那天」一行，按 API 价格约 US$7–20（估算）；
- 两个选项：批准按量跑这一次；或等额度重置 / 等订阅恢复后再跑（不花钱，晚一到几天）。

Zack 批了才跑；没批之前便宜检查每天照常报 FAIL（rc=1），不会漏。

本机实测（10-20 21:18，iMac，没为这个新起 claude 调用）：闸 A 在 iMac 上通过（4 个变量名都不存在，`settings.json` 没有相关键）；设一个空的 `ANTHROPIC_API_KEY` 演练，闸 A 报 STOP、rc=1。闸 B 读的是 PER-83 10-20 19:10 在 iMac 写的 `init-check.jsonl`（box `/workspace/ops/reports/handover-item5-1020/imac/compat-88d4751/`，本地副本），输出 `apiKeySource=none 5h=0.14（10-20 21:50 重置） 7d=0.45（10-23 00:00 重置） overage=rejected/False`，闸 B 通过；阈值改成 5h 0.10 时报不通过；去掉 init 和 rate_limit_event 两行后报「读不到」不通过。原始输出：box `/workspace/ops/reports/parallel-1020/PER-94-apikey-gate-run.txt`。

### 5.2 成本（估算，wake-tla-verify 按全量 36 项）

| 场景 | 模型调用 | 机器时间 | 现金 |
|---|---|---|---|
| 没出新版的日子 | 0 | 一次 ops-verify 里多 1–25 秒（实测：box 1 秒，iMac 7–23 秒，大头是网络） | 0 |
| 出新版那天，闸过了 | Haiku 约 30 次（闸 B / 2.1、2.2、冒烟）；Sonnet 会话 4 个（兼容 agent 本身、verify-dv-site 两组、wake-tla-verify 全量一次）；wake-tla-verify 候选不过时，再直接跑一次 `check.sh` 全量（不调模型） | 兼容检查约 2–3.5 小时：2.1–2.2 约 10 分钟，verify-dv-site 两组 50–110 分钟，wake-tla-verify 全量 25–45 分钟（要跑对照再加 25–45 分钟），bootstrap 沙箱约 5 分钟；升级三台约 15 分钟 | 0：走 Claude Max 订阅（`apiKeySource: none`，`overageStatus: rejected`） |
| 出新版那天，闸没过 | 闸 B 那 1 次 Haiku | 几秒 | 0；按量跑要等 Zack 批花钱卡，批了按下面估算 |

- 按 API 价格折算（只是估算，用来看订阅额度占用，或闸没过时写进花钱卡）：Haiku 部分约 US$0.15（PER-83 同类演示每次 US$0.004–0.006）；Sonnet 部分约 US$7–20 一次。比上一版（US$5–15）高，是因为 wake-tla-verify 改成全量后，那个 Sonnet 会话要守着 `check.sh` 跑 25–45 分钟，中间会多次读输出。
- pstack 近期约 1–2 天一个版本，最坏一周 3–4 次完整兼容检查。嫌多的话，可以规定「两次兼容检查至少隔 3 天」，中间出的版本合到下一次评估最新版；本文先不加这条。
- GitHub 请求：没变化时 1 次 `ls-remote`（不占 API 配额）；有变化时再加 1 次 `gh api compare`、1 次读钉版（各占 1 次配额，5000 次/小时）和 2 次 raw 下载。

## 6. 防误报、防漏报

- 网络或 gh 出错：rc=2，ops-verify 记 SKIP，不起 agent。连续 3 天 SKIP，ops 系统开 Linear。
- 一个版本只评估一次：靠报告里的 `总判定：` 行。没写总判定（没跑完、负载太高、没判定）就会每天继续报，不会静默漏掉。
- 上游改写历史（compare `status=diverged`）：只当证据打印，判断只看版本号，照常评估新版。
- 候选目录 `~/pstack-compat/cursor-plugins-<短 sha>` 每个版本一个，留着做复现；超过 5 个时删最旧的（ops 系统手动）。
- 兼容 agent 卡住：它由 `orca-agent-launch` 起、包在 notify-run 里，卡住检查 ops · 01 会报，不需要另加监控。

## 7. 待批（本 PR 不做）

| # | 内容 | 需要谁 | 为什么不在本 PR 做 |
|---|---|---|---|
| 1 | 每天谁跑 ops-verify：A ops 系统每天开工手跑（推荐，不注册任务）；B 等 PER-92 定 ops-verify 的日常运行 | Zack 选 A 或 B | ops-verify 现在没有定时运行；本 PR 不许注册任务 |
| 2 | 新增 `scripts/pstack-upstream-check.sh`（1.1 原文），`SYSTEM_MAP.md` 加 1 行、`scripts/ops-verify` 加 13 行（1.3） | ops 系统派活，#28（PER-92）合并后另开 PR | 这两个文件归 PER-92；本 PR 只拥有本文 |
| 3 | iMac 装 Java 17 + tla2tools.jar v1.7.4 到 `~/.local/opt/`（按 `wake/tla/README.md`「安装」，不用 sudo） | Zack 卡（装东西） | 不装就跑不了 2.4；本 PR 不装 |
| 4 | #48 合并：便宜检查默认读 main 上的 `PSTACK_SHA`，合并前 `PIN_BRANCH=main` 会返回 rc=2 | Zack | #48 是另一个 agent 的 PR |
| 5 | 兼容检查 agent 的 brief 模板（本文 2.0–2.6 填版本号即可） | ops 系统第一次用时生成 | 没有新版之前用不到 |
| 6 | wake-tla-verify 缩减版：只跑 `check.sh --out <目录> w0 h0`，即 P2（notify-run / orca-wake / stuck-check 非 2xx 不记成功）、P3（卡住检查停了一定告警）、P4 共 17 项（含改坏变体）。省下：TLC 时间 1471 秒 → 161 秒（box 实测数据），每次少约 20 分钟机器时间，那个 Sonnet 会话的额度也少一截（没实测，估算少一半以上）。漏检：P1（派活 bot 一直坏也最终有人收到）、P1h（webhook 恢复后每个停下都有人收到）、P5（一个 bot 坏了只挡它自己）、P6（agent 没起来也叫醒）共 19 项不跑。这 19 项只依赖 `wake/**` 和 `stuck-check.sh` 的代码，pstack 本身改不了它们；真正的风险是新版 pstack 改变了 agent 执行 skill 的方式（例如去改 cfg 或期望表），而这只会在被跳过的那几项里表现出来 | Zack 定：默认全量（现在的写法），还是改成缩减版 | 缩减会降低覆盖面，要 Zack 决定 |
