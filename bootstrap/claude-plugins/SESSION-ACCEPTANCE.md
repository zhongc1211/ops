# 10-30 以后：S11 真实会话验收手册（尚未执行）

这不是现在运行 Claude 的授权。先确认额度/登录恢复、模型使用及 CE cross-model peer 的授权；明确取得**独立 HOME 沙箱安装**许可。当前 pin 不支持任意独立 CLAUDE_CONFIG_DIR，下面把两者一起绑定到新 HOME：`CLAUDE_CONFIG_DIR=$HOME/.claude`。未批这个方案就停，不改用默认用户目录。合并、两台安装仍另批。

全程不调用真实 notify-run、不发叫醒；下面是「真实安装 + 真实 Claude 会话 + launcher 参数/合并块」分段验收，不是完整 launcher→通知链路 E2E。完整链路需要另批演练通知通路，不能用替身冒充。MBA 加压两项另排队，load1<8、无其他 E2E、最多并发 4；不要和本手册并行。

## 1. 固定 sha、空项目和隔离环境

在 iMac 的独立工作副本运行，不在现网主检出操作。`repo` 必须指向该独立副本，含当前 PR head 对象；`out` 是事先批准的证据目录。所有片段在同一个 bash 中顺序执行。以下 `iso` 清空继承环境，只留下显式白名单，**每次** bootstrap、plugin CLI、模型 CLI 都走它；不要单独复制最后的 claude 命令。

```bash
set -eu
: "${repo:?先设置独立仓库副本绝对路径}"
: "${out:?先设置证据目录绝对路径}"
T=/usr/local/bin/timeout                  # MBA 则 /opt/homebrew/bin/timeout
"$T" 840 date
level=$(sysctl -n kern.memorystatus_level)
[ "$level" -ge 25 ] || exit 25           # 起会话还须满足当时 R9
head=$("$T" 840 gh pr view 48 --repo zhongc1211/ops --json headRefOid --jq .headRefOid)
"$T" 840 git -C "$repo" cat-file -e "$head^{commit}"
umask 077
sandbox=$(mktemp -d /tmp/s11-session.XXXXXX)
printf 'cleanup sandbox: %s\n' "$sandbox" >&2  # out 创建失败时也留确切路径
realhome=$HOME
CLAUDE="$realhome/.local/bin/claude"      # 核真实安装位置；不存在则停，不创建替身
[ -x "$CLAUDE" ] || exit 66
mkdir -p "$sandbox/home/.claude" "$sandbox/project" "$sandbox/src" "$out"
chmod 700 "$sandbox" "$out"
printf 'sandbox=%s\n' "$sandbox" > "$out/cleanup-paths.txt"
src="$sandbox/src"
"$T" 840 git -C "$repo" archive "$head" | tar -x -C "$src"
printf '%s\n' "$head" > "$out/head.txt"
for f in settings.json plugins/installed_plugins.json plugins/known_marketplaces.json; do
  "$T" 840 shasum -a 256 "$realhome/.claude/$f"
done > "$out/live-before.sha"
iso() {
  "$T" 840 env -i HOME="$sandbox/home" CLAUDE_CONFIG_DIR="$sandbox/home/.claude" \
    XDG_CONFIG_HOME="$sandbox/home/.config" TMPDIR=/tmp \
    PATH="$realhome/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    USER="$USER" LOGNAME="$LOGNAME" LANG=en_US.UTF-8 "$@"
}
cd "$sandbox/project"                    # 空目录，不是任何现有项目
iso python3 -c 'import os; from pathlib import Path; assert os.environ["CLAUDE_CONFIG_DIR"] == str(Path.home()/".claude"); assert not list(Path.cwd().iterdir()); print("isolated HOME/config + empty cwd OK")'
iso bash "$src/bootstrap/claude-plugins/pin-claude-plugins.sh" > "$out/install.log" 2>&1
iso bash "$src/bootstrap/claude-plugins/pin-claude-plugins.sh" --check > "$out/install-check.log" 2>&1
# 两条任一非零即停。不得改 installed_plugins.json 伪造 pin 通过。
# 正常会话对照必须真的装有 superpowers；在同一沙箱真实装，不用 --plugin-dir 替身。
iso "$CLAUDE" plugin marketplace add anthropics/claude-plugins-official > "$out/superpowers-marketplace.log" 2>&1
iso "$CLAUDE" plugin install --scope user superpowers@claude-plugins-official > "$out/superpowers-install.log" 2>&1
# 只确认登录状态，不把账号或凭据输出到证据；若未登录，停交操作者处理。
iso "$CLAUDE" auth status >/dev/null 2>&1 || { echo 'auth unavailable: STOP'; exit 1; }
```

上面可能因登录/下载/安装记录字段失败；失败保留原日志，不能挑失败项重跑掩盖。`set -e` 会中止当前 shell，但**没有通用 EXIT 自动清理**：确切路径已打印，并在 out 建好后记入 `cleanup-paths.txt`。前置失败也必须按第 5 节收尾；启动模型/peer 后不设无条件删目录的 EXIT trap，以免超时 shell 退出时仍活着的子进程失去设置文件。不要把真 HOME 的 settings、.claude.json 或 credentials 拷进沙箱。需要登录时由操作者单独处理，不在验收脚本里自动 login，不改变现有钥匙串。

### 安装记录、实际 manifest、deny 读回（先通过才跑模型）

```bash
iso python3 - "$src" <<'PY' > "$out/install-readback.txt"
import json, os, pathlib, sys
c=pathlib.Path(os.environ['CLAUDE_CONFIG_DIR']).resolve()
s=json.loads((c/'settings.json').read_text())
ip=json.loads((c/'plugins/installed_plugins.json').read_text())['plugins']
expected={
 'pstack@cursor-plugins':('0.15.29','88d47514b82e7c44f00f2b2a72ff6dd12158038c'),
 'compound-engineering@compound-engineering-plugin':('3.31.0','2e41b4490a37f53db0beb6d4904618da9af2f559')}
for key in (*expected, 'superpowers@claude-plugins-official'):
    entries=ip[key]; assert len(entries)==1, key
    e=entries[0]; p=pathlib.Path(e['installPath']).resolve()
    assert c in p.parents, (key,'installPath escaped sandbox')
    mf=next((x for x in (p/'.claude-plugin/plugin.json',p/'plugin.json') if x.is_file()),None)
    assert mf, (key,'manifest missing')
    m=json.loads(mf.read_text()); assert m['version']==e['version'],key
    if key in expected: assert (e['version'],e.get('gitCommitSha'))==expected[key],key
    assert s['enabledPlugins'][key] is True,key
    print(key,e['version'],e.get('gitCommitSha'),'manifest+path OK')
frag=json.loads((pathlib.Path(sys.argv[1])/'bootstrap/claude-deny/settings-fragment.json').read_text())
assert len(frag['permissions']['deny'])==29
assert all(x in s['permissions']['deny'] for x in frag['permissions']['deny'])
for name in ('ce-code-review','ce-noslop'):
    assert 'Skill(skill:compound-engineering:'+name+')' not in s['permissions']['deny']
print('29 denies; review/noslop retained')
PY
```

superpowers 版本不作新升级决策，只记录此次沙箱真实装到的版本/commit，所有候选/对照必须用同一份；不能把一次新版本对照当成两台现装旧版的保证。两台真正安装前还要核其实际插件键及版本。

## 2. 从 head 的实际合并块生成会话设置

不用复制真用户 settings，以下用该 head launcher 的**原样 Python 块**把空覆盖合成相同结果。完整 launcher 不能在无演练通知授权时执行；其参数分支仅做 DRY 检查，不因此把分段验收叫全链路。

```bash
session=$(mktemp /tmp/orca-claude-settings.XXXXXX)
printf 'cleanup session: %s\n' "$session" >&2
printf 'session=%s\n' "$session" >> "$out/cleanup-paths.txt"
"$T" 840 python3 - "$src/wake/bin/orca-agent-launch" "$session" <<'PY'
import pathlib,subprocess,sys,stat
text=pathlib.Path(sys.argv[1]).read_text()
mark='    python3 - "$session_settings" "$session_settings_file" <<\'PY\'\n'
assert text.count(mark)==1,'launcher changed: re-review extraction'
code=text.split(mark,1)[1].split('\nPY\n',1)[0]
subprocess.run([sys.executable,'-c',code,'{}',sys.argv[2]],check=True)
assert stat.S_IMODE(pathlib.Path(sys.argv[2]).stat().st_mode)==0o600
PY
"$T" 840 shasum -a 256 "$sandbox/home/.claude/settings.json" > "$out/sandbox-before.sha"
```

即使真实会话失败也保留其日志和 rc；**本轮验收结束、所有本轮会话退出后**删除 session。普通运行的成功 launcher 固定把文件放 /tmp（不接受 TMPDIR 重定向），macOS 系统 tmp_cleaner 每日清理过期内容；不是即时回收、没有固定回收时限。系统只按文件老化清理，不识别会话生命周期；超长会话可能在运行中失去该文件，是否影响 Claude 重读仍没查实。本手册不手动运行 tmp_cleaner，也不修改系统任务。

## 3. 初始化、24 条 deny、人工 slash、允许项、对照

基础探针只给 Skill 工具；防止未被挡的危险 skill 实际编辑/运行命令。真正流程检查在下一节使用真实本地 diff。`--setting-sources user` 排除项目/本地设置，`--strict-mcp-config` 加空 mcp 配置排除外部 MCP；不使用 --bare（会让插件根本不加载，失去验收意义）。每个样例都记录返回码，最后按表判，**rc=0 不等于通过，expected hook 拒绝也不能简单按非零判失败**。

```bash
printf '{"mcpServers":{}}\n' > "$sandbox/empty-mcp.json"
printf 'case\trc\n' > "$out/rc.tsv"
run_case() {
  mode=$1; label=$2; prompt=$3
  flags=()
  [ "$mode" = normal ] || flags=(--settings "$session")
  if iso "$CLAUDE" --setting-sources user --strict-mcp-config --mcp-config "$sandbox/empty-mcp.json" \
      ${flags[@]+"${flags[@]}"} --tools Skill --allowedTools Skill \
      --max-turns 4 --print --verbose --output-format stream-json -- "$prompt" \
      > "$out/$label.jsonl" 2> "$out/$label.stderr"; then rc=0; else rc=$?; fi
  printf '%s\t%s\n' "$label" "$rc" >> "$out/rc.tsv"
}
run_case dispatched init-dispatched 'Reply only OK. Do not invoke skills.'
run_case normal init-normal 'Reply only OK. Do not invoke skills.'
# 24 个完整名字，不只 ce-work；每条一个新会话，全部输出都保留。
for name in ce-babysit-pr ce-bakeoff ce-brainstorm ce-commit ce-commit-push-pr \
  ce-compound ce-compound-refresh ce-debug ce-doc-review ce-explain ce-handoff \
  ce-ideate ce-optimize ce-plan ce-pov ce-proof ce-prototype ce-resolve-pr-feedback \
  ce-riffrec-feedback-analysis ce-simplify-code ce-strategy ce-test-browser ce-work ce-worktree; do
  run_case dispatched "deny-$name" "Call Skill exactly once with skill=compound-engineering:$name and no args. Do not work around any refusal. Report the tool result."
done
# 原五命令，带 namespace 和不带 namespace 共十种人工 slash 输入。
for name in pstack:poteto-mode poteto-mode pstack:tdd tdd pstack:reflect reflect \
  pstack:setup-pstack setup-pstack compound-engineering:lfg lfg; do
  run_case dispatched "slash-${name//:/-}" "/$name S11 acceptance: do not execute a workflow"
done
run_case dispatched allow-pstack-how '/pstack:how S11 acceptance: explain only, do not change anything'
run_case dispatched allow-ce-noslop 'Call Skill with skill=compound-engineering:ce-noslop to rewrite this single sentence: This change prevents guard replacement before backups succeed. Do not use other tools.'
# 正常会话既要初始化真的包含 superpowers，也要正向证明其 Skill 可用。
run_case normal allow-superpowers 'Call Skill with skill=superpowers:using-superpowers exactly once; do not invoke other skills or execute workflows.'
```

### 每条记录的判据（由验收方逐条写入 verdict/结果表）

| 用例 | 必需证据 | 失败或没查实 |
|---|---|---|
| init-dispatched | `type=system,subtype=init` 的 plugins / slash_commands：pstack 和 CE 在，superpowers 及其 skills 不在 | 无 init、字段不存在、仍有 superpowers → 失败/没查实，不信模型口述 |
| init-normal | 同一隔离 HOME 的 init 包含 superpowers，pstack/CE 同时仍在；无需 session 覆盖 | 两组都没 superpowers 不是通过，可能根本没安装 |
| 24 个 deny | assistant 的真正 `tool_use` 是 Skill，input.skill 精确对上；对应 `tool_result.tool_use_id` 匹配，is_error 且明确 permissions deny | 没调用、调用别名无法对应、额度/登录错、找不到 skill、disable-model-invocation 拒绝或普通提示词声称拒绝，都不算 deny 通过 |
| 十种 slash | CLI/hook 返回包含 UserPromptSubmit/UserPromptExpansion 拦截原因；沙箱会话 transcript 无该禁用 skill 正文展开，无工作流执行 | 普通模型答不执行不算拦截；登录失败不算拦截；发现正文展开就失败 |
| pstack:how | 沙箱 transcript 显示命令解析/skill 正文已展开并完成正常回复，无 deny | 未找到/被拒/额度或登录错失败；这仅是允许入口，不是完整主流程 |
| ce-noslop | 真 Skill 调用+成功 tool_result，并有改写结果 | 无调用或权限拒绝/非零模型错误失败 |
| normal superpowers | 已确认钉到的插件含 using-superpowers 名称，真 Skill 成功且有正文 | 名称不存在则先核真实 manifest/name，不能擅自换假插件；两组共同缺失不能证明禁用 |

需要看 skill 正文时，仅从 `$sandbox/home/.claude/projects/` 读取本次会话 transcript；不读真 HOME 的会话。证据提取只留下 init、相关 tool_use/tool_result、hook 拦截信息和报告，不归档 credentials/settings 原件。CLI 版本若不输出必要字段，标没查实，先补只读取证办法，不放宽断言。所有 24 项、十种 slash 都须逐项记录 PASS/FAIL/没跑，不只汇总一个数字。

## 4. pstack 主流程与 CE review→noslop：真实本地 diff

只给 Skill 的探针无法证明完整流程。需要操作者再确认 CE peer 调用/报告生成权限与额度（可能调用 codex），否则本节写没跑。使用当前 PR 的真实 parent→head diff 的独立本地检出，不改原仓库。项目设置仍排除，不连接 MCP，不通知、不 push/PR/merge。所有允许写入只在沙箱检出，报告在检出内再拷脱敏产物到 out。

```bash
"$T" 840 git clone --shared --no-checkout "$repo" "$sandbox/review"
"$T" 840 git -C "$sandbox/review" checkout --detach "$head"
"$T" 840 git -C "$sandbox/review" diff "$head^" "$head" > "$out/review.diff"
cd "$sandbox/review"
# 基础条件失败即停，不把没有 diff 的评审当完成。
[ -s "$out/review.diff" ] || exit 1
# 只读方案主流程（pstack architect），不改仓库；原始输出保留。
if iso "$CLAUDE" --setting-sources user --settings "$session" --strict-mcp-config --mcp-config "$sandbox/empty-mcp.json" \
  --tools 'Skill,Read,Glob,Grep' --allowedTools 'Skill,Read,Glob,Grep' \
  --print --verbose --output-format stream-json -- \
  "/pstack:architect Review the design of the actual diff at $out/review.diff. Read-only: do not implement, invoke banned skills, use the network, or change files." \
  > "$out/pstack-workflow.jsonl" 2> "$out/pstack-workflow.stderr"; then rc=0; else rc=$?; fi
printf 'pstack-workflow\t%s\n' "$rc" >> "$out/rc.tsv"
# ce-code-review 在当前 head 本地模式跑真实 diff；不要用远程 PR 模式跳过 peer。
if iso "$CLAUDE" --setting-sources user --settings "$session" --strict-mcp-config --mcp-config "$sandbox/empty-mcp.json" \
  --allowedTools 'Skill,Read,Glob,Grep,Bash,Write,Edit,Agent' \
  --print --verbose --output-format stream-json -- \
  "Use compound-engineering:ce-code-review on local HEAD $head against its parent. Finish the real review and use ce-noslop for the findings. Write reports only inside this temporary checkout. Do not push, post comments, merge, install global tools, notify anyone or modify any external project. Record whether the cross-model peer ran; lack of authorization or a failed peer is not a pass." \
  > "$out/review-noslop.jsonl" 2> "$out/review-noslop.stderr"; then rc=0; else rc=$?; fi
printf 'review-noslop\t%s\n' "$rc" >> "$out/rc.tsv"
```

判据：pstack 真正展开 architect 并读实际 diff 给出方案，未调用禁用项；CE 真调用 ce-code-review，再真调用 ce-noslop，均有成功工具返回并产生具体文件/行号的 review 报告。仅说“已审”无证据失败。检查 peer 产物/是否跑及原因，没跑不伪称跑；工具权限不足导致流程中断也要记录失败。最终完整 pstack 开发流程若超出这个只读方案范围，明确写没跑，不把 architect 单步当所有开发动作都通过。

## 5. 收尾、hash 与临时文件

1. 正常跑完或因 `set -e` 提前退出，都必须收尾。从 `cleanup-paths.txt` 或创建时的 stderr 取本轮确切路径，不能用通配符，也不要直接 source 这个记录文件。前置安装失败且尚未起模型时，可以在取完脱敏日志后删本轮目录；起过模型/peer 时，先核所有本轮进程已结束（不停止别的会话），再删设置/沙箱。核 GitHub head 仍是本轮 head，否则这份证据不能用于新 head。
2. 逐行写结果表，包含登录/额度/timeout/缺字段/未获授权的所有失败及没跑，不挑重跑；需重跑必须保留失败首轮、说明原因并整轮执行。下面收尾块的检查结果以 `cleanup-paths.txt` 里的 `final_checks_fail` 和 stdout 打出的失败信息为准，逐项写进结果表。
3. 再跑隔离 `pin --check`；对真 settings / 两份 plugin metadata 和候选沙箱 settings 计算 hash，与前面比较。下面这块依赖前面同一个 shell 里的 `T`、`realhome`、`out`、`head`、`src`、`sandbox`、`session` 和 `iso`。shell 已经因 `set -e` 退出、要在新 shell 收尾时，先按第 1 节重新设 `T`、`realhome`、`out`、`head`（读 `$out/head.txt`），从 `cleanup-paths.txt` 手抄 `sandbox`、`session` 的确切路径，设 `src="$sandbox/src"`，再照第 1 节定义 `iso`，然后执行：

```bash
# 比较失败只记进 fail，不在 set -e 下提前退出，保证下面的清理一定执行到。
# 前面中途失败时这几个变量可能还没赋值；先给空值，免得 set -u 在清理前中止。
fail=0; src=${src:-}; sandbox=${sandbox:-}; session=${session:-}
iso bash "$src/bootstrap/claude-plugins/pin-claude-plugins.sh" --check > "$out/final-check.log" 2>&1 \
  || { echo 'FINAL PIN CHECK FAILED'; fail=1; }
for f in settings.json plugins/installed_plugins.json plugins/known_marketplaces.json; do
  "$T" 840 shasum -a 256 "$realhome/.claude/$f"
done > "$out/live-after.sha" || { echo 'LIVE HASH READ FAILED'; fail=1; }
"$T" 840 cmp "$out/live-before.sha" "$out/live-after.sha" || { echo 'LIVE FILES CHANGED'; fail=1; }
"$T" 840 shasum -a 256 "$sandbox/home/.claude/settings.json" > "$out/sandbox-after.sha" \
  || { echo 'SANDBOX HASH READ FAILED'; fail=1; }
"$T" 840 cmp "$out/sandbox-before.sha" "$out/sandbox-after.sha" || { echo 'SANDBOX SETTINGS CHANGED'; fail=1; }
current=$("$T" 840 gh pr view 48 --repo zhongc1211/ops --json headRefOid --jq .headRefOid) || current=unknown
[ "$current" = "$head" ] || { echo 'HEAD CHANGED: evidence stale'; fail=1; }
printf 'final_checks_fail=%s\n' "$fail" >> "$out/cleanup-paths.txt" || { echo 'RECORD WRITE FAILED'; fail=1; }
# 记录失败、取完脱敏证据且本轮会话退出后执行下面清理；比较失败也照样清理。
# 两个路径各自删、各自核，一个失败不影响另一个。
cleanup_fail=0
if [ -n "$session" ]; then
  { "$T" 840 rm -f -- "$session" && "$T" 840 test ! -e "$session"; } || { echo 'SESSION CLEANUP FAILED'; cleanup_fail=1; }
fi
if [ -n "$sandbox" ]; then
  { "$T" 840 rm -rf -- "$sandbox" && "$T" 840 test ! -e "$sandbox"; } || { echo 'SANDBOX CLEANUP FAILED'; cleanup_fail=1; }
fi
if [ "$cleanup_fail" -eq 0 ]; then
  printf 'cleanup=confirmed absent\n' >> "$out/cleanup-paths.txt" || { echo 'RECORD WRITE FAILED'; fail=1; }
else
  printf 'cleanup=FAILED, see stdout\n' >> "$out/cleanup-paths.txt" || echo 'RECORD WRITE FAILED'
  fail=1
fi
[ "$fail" -eq 0 ] || exit 1             # 清理完再按比较和清理结果返回非零
```

如果超时后 Claude/peer 仍活着，不提前删除它依赖的设置，不扩大到停止其他进程；交主会话收尾。本手册会话结束后确切路径删除是主动收尾，系统 tmp_cleaner 是无人值守/异常退出情况下的延迟兜底；**本轮没有等待几天证明系统实际删除，也没有证明真实成功 launcher 会话的加载/退出行为**，这些不能写成已通过。
