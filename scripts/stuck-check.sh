#!/bin/bash
# stuck-check.sh [--scan | --list | --send [--dismiss S<n>=原因 ...] | --dry-run] [--full]
# 卡住工作检查（Orca 自动化「卡住工作检查」每 15 分钟调用）。兜底用：agent 做完或卡住本来会自己叫醒派活的 bot
# （webhook 或 notify-run），这里只查漏掉的。查 iMac、box、MBA 三套 Orca（box、MBA 走 orca --environment）。
#
# 一、卡住的 agent（每次都查，纯脚本，不用模型）。只看 workspace-status=in-progress 的任务工作区
#   （git 工作区，非主目录、非归档、不在 /tmp 下、不是 agent 临时建的 <工作区>/.orca-task/ 子 worktree）；
#   todo / in-review / completed / sleeping 一律跳过。
#   要歇着的工作区标看板状态 Sleep（sleep），不查。
#   例外：STUCK_MAIN_REPOS（默认 ops）的主目录也查——brief agent 都在 ops 主目录里跑（10-19 前被跳过）。主目录里同时有很多
#   agent，按 agent 终端（paneKey）逐个查，key 是「机器:路径#paneKey」，进程靠 agent-probe 读到的 ORCA_PANE_KEY 对上；
#   不看 workspaceStatus，没有 ws_broken；Orca 自动任务起的、agent 状态超过 STUCK_MAIN_MAX_AGE_H（默认 24）小时没变的不查。
#     ws_broken    in-progress 但一个终端都没有（断了：Orca 重启、终端被关），已安静 STUCK_GONE_MIN 分钟。没有屏幕可复核，
#                  不经复核直接叫醒负责的 bot。（10-18 前这种按 Sleep 跳过，Zack 10-18 13:18 改成要报。）
#   agent 进程按 cwd 认工作区，也按终端认：跑在这个工作区终端里、cd 到工作区外面的 agent 照样算在（10-18 13:48 误报过）。
#   主动停掉的 agent 不报 agent_gone / ws_broken：停的一方先用 wake/bin/agent-stop 写「主动停止」标记
#   （~/.orca-state/agent-stops/，agent-probe 带回来），标记和这个终端或工作区对得上、写在 agent 最后一次动作之后就跳过。
#   工作区里有 notify-run 在跑长命令时不算卡住（包住整个 agent 的那层 notify-run 不算在内）。只报三种：
#     agent_gone   agent 进程已经不在（退出、崩溃、断线，终端还开着），工作区还没标完成，且已安静 STUCK_GONE_MIN（默认 10）分钟。
#     agent_idle   agent 停在输入框等输入（tui-idle）超过 STUCK_IDLE_MIN（默认 30）分钟。
#                  先交给 orca-wake（~/.local/bin/orca-wake recheck --agent-pid，box 上走临时终端）：派活时用
#                  notify-run --tty 起的会话由它补叫醒一次，和它的 hook 叫醒共用 wake.log 和去重键，同一次停顿只叫一次；
#                  派活 bot 不在 enabled-bots 里时它只写 wake.log（影子模式，不算叫醒过）：这时转报 coding-assistant（经复核），
#                  不再当成已处理（10-16～10-17 影子模式漏了 58 次）。交给 orca-wake 发的只记「已交出」，下次扫描再 recheck，它说 already_woken（送达过）才算叫醒过（PER-67 F1）。
#                  orca-wake 没有这个进程的记录（no_state_for_pid，比如不是经 notify-run --tty 起的）或 agent 已不是
#                  notify-run 的直接子进程（parent_changed）时，才按下面的老办法写进 pending 发出去。
#                  orca-wake 说刚有动静（recent_activity）或调用失败时这次不报，下次再查。
#                  Esc 中断没有 Stop，Orca 的 agent 状态可能一直是 working：状态 30 分钟没变、终端停在输入框时
#                  也交给 orca-wake 核对；它不认识的这类会话照旧不报（旧逻辑本来也不报）。
#                  停在对话框：主 agent 的 Orca 状态是 waiting 已 STUCK_IDLE_MIN 分钟时，用 orca-wake recheck
#                  --waiting-pid 核对（tui-idle 认不出 Pi 的对话框；Claude 的对话框和 Esc 之后的输入框 tui-idle 都是
#                  True、Orca 状态都还是 waiting，分不出来，由 orca-wake 读 transcript 判断）。对话框还开着：用 hook 那次
#                  needs_input 的同一个去重键补发，hook 送达过就返回 already_asked，不发；不补 idle（Claude 的 idle 键在
#                  回合中途被占掉，回答后真正的回合结束叫醒会被当成重复）。对话框已关（Esc）：按停在输入框补 idle。
#                  orca-wake 没有记录的这类会话不报。
#     agent_silent agent 进程还在、不在等输入，但终端超过 STUCK_IDLE_MIN 分钟没有新输出。
#   进程情况由 ~/.local/bin/agent-probe 提供（box 上通过一个临时 Orca 终端跑，跑完关掉；只在有新的可疑工作区时才跑）。
#   嫌疑先写进 pending.json，由自动化里的 Claude 复核（读终端屏幕）后再发；--dismiss 的不发。
#   发给派活的 bot：按 orca-projects.md 映射到 ~/.config/grokbot/webhooks/<bot>.env，没有对应文件的发给 coding-assistant。
#   payload：{bot, task, worktree, status:"stuck", kind, note, machine, source:"stuck-check"}。
#   同一工作区报过（或复核后排除）就不再报，直到 agent 有新动作（agent_silent 还包括终端有新输出）。
#   agent 的动作时间取 Orca 的 agent 状态记录；没有记录时（以及 box 上的输出时间）用终端屏幕指纹，由每次检查比对得出。
#
# 一 a、没经 notify-run 起的 agent（每次都查，脚本直接发）：agent-probe 看到 claude / pi / codex 在 Orca 终端里跑、是顶层 agent、
#   父链里没有 notify-run（做完不会叫醒任何人），而且不是 Orca 自动任务起的（运行记录里的 paneKey，或命令行 / Orca 记的 prompt
#   和某个自动任务的 prompt 对得上）→ 报给工作区对应的 bot，认不出的报 coding-assistant（kind agent_unwrapped）。
#   每个进程报一次（进程不退出就一直记着，在 Orca 工作区外面的也一样，10-19 MBA pid 36142），同一个 bot 的合成一条。
#   起 agent 用 wake/bin/orca-agent-launch（不带 --bot 就拒绝）。
#
# 一 b、due date 对账（每次都查，脚本直接发）。有 due 的 Linear issue：In Progress 超过 STUCK_DUE_GRACE_MIN（默认 30）
#   分钟，没有工作区或工作区里没有 agent 在跑 → 叫醒负责的 bot（due_no_agent）；过了 due 当天还没进 In Review →
#   叫醒 coding-assistant（due_overdue）。负责 bot：issue 标签 bot:<名字> → 描述里「负责 bot：<名字>」→ 关联工作区 →
#   orca-projects.md → coding-assistant。每种情况每个 due 只报一次。box 或 MBA 没查到时不对。
#
# 二、报了没人验收（约每小时查一次，脚本直接发，不经模型）。只看 completed / in-review 的任务工作区：
#   reported_not_accepted：已开 PR 超过 1 小时没有 review 和人工评论；或没有 PR、标完成超过 1 小时。
#   「已验收」= PR 有 review 或人工评论、已合并或关闭（含 Orca 记着的关联 PR 已合并/关闭），工作区已归档，Linear 卡片
#   canceled。agent 又在工作时不报。completed、工作区干净、比远端默认分支没有多出提交、也没有 PR 的直接放行。
#   in-review 且 Linear 卡（关联的，或显示名、分支名里的 PER-/FDV- 编号）挂着「等 Zack」标签、卡没完成没取消的不报：
#   已验收，在等 Zack 拍板（10-19 03:34 PER-56 MBA 卡）。
#   repo list 查不到时这台这次不查（不再当成「仓库没有 GitHub 远端」）。
#   多条合并成一条发给 Coding助手（~/.config/grokbot/stuck-webhook.env）。同一件事只报一次，
#   连续 STUCK_FORGET_HOURS（默认 24）小时没再出现才忘掉。
#
# 三、别的自动任务有没有跑完（每次都查，脚本直接发给 coding-assistant）。~/.orca-state/runs/ 下
#   cf-usage、seo-weekly、mem-cpu-cleanup 的 .due 比 .ok 新，且超过 STUCK_MARKER_GRACE_MIN（默认 60）分钟，报一次。
#
# 四、box / MBA 的 Orca 连不上：每次查询重试 3 次，还不行就等 STUCK_BOX_RETRY_WAIT（默认 30）秒再查一轮（box 刚从暂停恢复时
#   常有几十秒连不上）；两轮都失败才算这次连不上。连续 2 次检查都连不上，报一次给 coding-assistant（kind box_unreachable /
#   mba_unreachable），恢复后复位。MBA 按常开机器算（Zack 10-18），环境名 mba（STUCK_MBA_ENV 可改，设成空串不查）；
#   MBA 上的临时终端开在 STUCK_MBA_PROBE_WT（默认 MBA 的 ops 主目录）。远端的 agent-probe 临时终端失败时也等 15 秒再试一次。
# 派活 bot 的判断顺序：orca-projects.md 里的 Linear 编号 → 工作区显示名前缀（「营销 · 」「dv营销 · 」→ deepvision-marketing，
#   见 NAME_BOT）→ 仓库映射；第一类里 agent 外面包的 notify-run --bot（agent-probe 的 dispatch_bot）优先于以上全部；
#   都没有的发给 coding-assistant。
# 心跳：每次跑完（含闸门关着直接退出）写 STATE_DIR/heartbeat.json，并在 stdout 打一行「@@HB {"ts","mode","rc","last_scan"}」。
#   last_scan = 上次跑完的扫描。运行记录存 precheck 的 stdout，另一台机器上的 scripts/heartbeat-watch.sh 读它，太久没有新的就报警。
# 同一时间只跑一个：~/.orca-state/stuck-check/run.lock（flock），上一次还没跑完时这次直接退出（--scan 返回 1，不启动 agent）。
# webhook 返回非 2xx 时，日志里带响应体的前 160 个字符（去掉 URL/KEY 和长串，压成一行）。
#
# 用法：
#   --scan     自动化的 precheck（自动任务每分钟调一次）。闸门：距上次扫描满 STUCK_INTERVAL_MIN（默认 15）分钟，或 iMac / box / MBA
#              的 Orca 重启过（orca status 的进程号或 runtimeId 变了，记在 gate.json），才往下查，否则直接返回 1；
#              Orca 重启后这次连第二类一起查。STUCK_NO_GATE=1 跳过闸门。
#              查一遍；ws_broken、due、二、三、四类直接发；其余一类写进 pending.json。
#              退出码 0 = 有嫌疑要复核或有东西没发出去（同时写 .due 标记），1 = 没事，自动化跳过这次。
#   --list     打印 pending.json 里的嫌疑（S1、S2…）和每条的复核办法。
#   --send     把 pending.json 里没被 --dismiss 的嫌疑发给各自的 bot，并补发之前没发出去的。
#   不带参数   查一遍并把所有东西直接发掉，不经复核（codex 备用任务和手动运行用）。
#   --dry-run  查一遍只打印，不发、不写状态。--full 强制把第二类也查了（否则按每小时一次的节奏）。
# 每次 POST 之间至少隔 6 秒。POST 失败（非 2xx 或没响应）按 STUCK_BACKOFF（默认 5,15,45 秒）重试 3 次，
# 全部失败才算失败，这次运行里发给同一个目标的不再发（别的照发），下次再试；发给派活 bot 的从第一次失败起满 STUCK_ESCALATE_MIN（默认 45）分钟改发 coding-assistant。URL 和 KEY 不会出现在输出和日志里。
# 退出码：0 正常（--scan 见上）；2 iMac Orca 查询失败；3 有 webhook 重试后仍然失败；4 脚本自己出错
#   （--scan 时出错或 iMac Orca 查询失败也返回 0，让自动化启动 agent 把错误报出来）。
# 测试用环境变量：STUCK_STATE_DIR、STUCK_ENV_FILE、STUCK_WEBHOOK_DIR、STUCK_RUNS_DIR、STUCK_FORCE_BOT（所有 bot 改发到它；演练用 ops-system；只换收件 bot，task 不加「[演练 叫醒通路]」前缀）、
#   STUCK_ONLY（正则，只查路径匹配的工作区；没包 notify-run 的 agent 按 cwd 匹配）、STUCK_BOX_ENV、STUCK_MBA_ENV、STUCK_ORCA_WAKE（本机 orca-wake 路径）、
#   STUCK_BOX_WAKE_CONFIG_DIR（box 上 orca-wake 的 ORCA_WAKE_CONFIG_DIR；本机的直接继承环境变量）。
set -u
PY=$(command -v python3 || echo /usr/bin/python3)
exec "$PY" - "$@" <<'PYEOF'
import base64, datetime, fcntl, gzip, hashlib, json, os, re, shlex, shutil, subprocess, sys, tempfile, time

HOME = os.path.expanduser("~")
ARGS = sys.argv[1:]
MODE = next((a for a in ARGS if a in ("--scan", "--list", "--send", "--dry-run")), "--run")
DRY = MODE == "--dry-run"
FULL = "--full" in ARGS
DISMISS = {}
for i, a in enumerate(ARGS):
    if a == "--dismiss" and i + 1 < len(ARGS):
        k, _, why = ARGS[i + 1].partition("=")
        DISMISS[k.strip().upper()] = why.strip() or "复核后排除"
THRESH_H = float(os.environ.get("STUCK_THRESHOLD_HOURS", "1"))
FORGET_H = float(os.environ.get("STUCK_FORGET_HOURS", "24"))
IDLE_MIN = float(os.environ.get("STUCK_IDLE_MIN", "30"))
GONE_MIN = float(os.environ.get("STUCK_GONE_MIN", "10"))
MARKER_GRACE_MIN = float(os.environ.get("STUCK_MARKER_GRACE_MIN", "60"))
BACKOFF = [float(x) for x in os.environ.get("STUCK_BACKOFF", "5,15,45").split(",") if x.strip()]
POST_GAP = float(os.environ.get("STUCK_POST_GAP", "6"))
# 发给派活 bot 一直没送达这么久就改报 coding-assistant（PER-67 F4）。从这次停下算（有停下时间时；没有的从第一次失败算），
# 要求之前至少失败过 / 交出过一次（PER-67 F6：以前从第一次失败 / 交出算，加上前面的 10～30 分钟，1 小时内到不了）
ESCALATE_MIN = float(os.environ.get("STUCK_ESCALATE_MIN", "45"))
FORCE_BOT = os.environ.get("STUCK_FORCE_BOT")
ONLY = re.compile(os.environ["STUCK_ONLY"]) if os.environ.get("STUCK_ONLY") else None
MAPPING = os.path.join(HOME, "orca/workspaces/ops/orca-projects.md")
ENV_FILE = os.environ.get("STUCK_ENV_FILE") or os.path.join(HOME, ".config/grokbot/stuck-webhook.env")
WEBHOOK_DIR = os.environ.get("STUCK_WEBHOOK_DIR") or os.path.join(HOME, ".config/grokbot/webhooks")
STATE_DIR = os.environ.get("STUCK_STATE_DIR") or os.path.join(HOME, ".orca-state/stuck-check")
RUNS_DIR = os.environ.get("STUCK_RUNS_DIR") or os.path.join(HOME, ".orca-state/runs")
PROBE = os.environ.get("STUCK_PROBE") or os.path.join(HOME, ".local/bin/agent-probe")
BOX_PROBE_WT = os.environ.get("STUCK_BOX_PROBE_WT", "path:/workspace/repos/deepvision-site")
MBA_PROBE_WT = os.environ.get("STUCK_MBA_PROBE_WT", "path:/Users/jiawenwang/orca/workspaces/ops")
PROBE_WT = {}  # environment 名 → 临时终端开在哪个工作区，查到环境名时填
ORCA_WAKE = os.environ.get("STUCK_ORCA_WAKE") or os.path.join(HOME, ".local/bin/orca-wake")
BOX_WAKE_CONFIG = os.environ.get("STUCK_BOX_WAKE_CONFIG_DIR")
LOG_FILE = os.path.join(STATE_DIR, "stuck-check.log")
SEEN_FILE = os.path.join(STATE_DIR, "notified.json")   # 第二类的已通知记录
AGENTS_FILE = os.path.join(STATE_DIR, "agents.json")   # 第一类：报过或排除过的工作区
PENDING_FILE = os.path.join(STATE_DIR, "pending.json")  # 等复核的嫌疑、没发出去的直发消息
TRACK_FILE = os.path.join(STATE_DIR, "track.json")
GATE_FILE = os.path.join(STATE_DIR, "gate.json")      # --scan 闸门：上次扫描时间和两台 Orca 的启动身份
INTERVAL_MIN = float(os.environ.get("STUCK_INTERVAL_MIN", "15"))     # 屏幕指纹、box 连不上的次数、上次全量检查时间、标记告警
MARKERS = {"cf-usage": "CF usage watch", "seo-weekly": "SEO weekly check", "mem-cpu-cleanup": "内存与 CPU 日常清理"}
FALLBACK_BOT = "coding-assistant"
SGT = datetime.timezone(datetime.timedelta(hours=8))
NOW = time.time()
os.makedirs(STATE_DIR, exist_ok=True)
SECRETS = []  # webhook 的 URL 和 KEY，任何输出里都替换掉
REPORTED, GONE, IDLE, SILENT = "reported_not_accepted", "agent_gone", "agent_idle", "agent_silent"
BROKEN, DUE_IDLE, DUE_LATE = "ws_broken", "due_no_agent", "due_overdue"
UNWRAPPED = "agent_unwrapped"
WATCH_AGENTS = {"claude", "pi", "codex"}  # 要求经 notify-run 起的 agent
# 主目录里也查卡住的仓库（brief agent 都在 ops 主目录里跑，10-19 前被当成主目录跳过）：按 agent 终端逐个查
MAIN_REPOS = {x.strip() for x in os.environ.get("STUCK_MAIN_REPOS", "ops").split(",") if x.strip()}
MAIN_MAX_AGE_H = float(os.environ.get("STUCK_MAIN_MAX_AGE_H", "24"))  # 主目录里 agent 状态超过这么久没变的不查
HB_FILE = os.path.join(STATE_DIR, "heartbeat.json")  # 每次跑完写一次；另一台机器的 heartbeat-watch 盯它（经自动任务运行记录）
# orca-projects.md 里的 bot 名 → ~/.config/grokbot/webhooks/ 下的文件名
BOT_SLUG = {"心月网站 运维": "xinyue", "deepvision 运维": "deepvision-ops", "deepvision 广告产品": "deepvision-ads",
            "vllm-omni 开发": "vllm-omni", "定时任务": "ops", "deepvision 营销": "deepvision-marketing",
            "营销": "deepvision-marketing"}
# 工作区显示名前缀 → bot（营销没有自己的仓库和 Linear 团队，FDV 编号和广告、运维混用，只能靠显示名或 notify-run --bot 认）
NAME_BOT = [(re.compile(r"^\s*(?:dv\s*)?营销\s*·|^\s*deepvision[\s-]*marketing\b|^\s*marketing\s*·", re.I),
             "deepvision-marketing")]
BOX_RETRY_WAIT = float(os.environ.get("STUCK_BOX_RETRY_WAIT", "30"))
# 工作区备注里算「agent 已报完成或卡住」的写法
REPORT_RE = re.compile(r"^\s*(?:done|partial|blocked|完成|已完成|做完|卡住|阻塞|受阻)|等\s*\S{0,12}?(?:拍板|验收|确认|决定)", re.I)


def log(msg):
    for sec in SECRETS:
        msg = msg.replace(sec, "<已隐藏>")
    line = "%s %s" % (datetime.datetime.now(SGT).strftime("%F %T SGT"), msg)
    print(line, flush=True)
    if not DRY and MODE != "--list":
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")


def run(cmd, timeout=90):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "", str(e)


ORCA = (shutil.which("orca-ide") or shutil.which("orca")
        or "/Applications/Orca.app/Contents/Resources/bin/orca")


def orca_json(args, env=None, tries=1, timeout=90):
    """tries > 1 时失败后隔 8 秒重试：box 的 Orca 经常有十几秒连不上。"""
    cmd = [ORCA] + args + (["--environment", env] if env else []) + ["--json"]
    err = None
    for n in range(tries):
        if n:
            time.sleep(8)
        rc, out, err = run(cmd, timeout)
        try:
            d = json.loads(out)
        except ValueError:
            err = err or "非 JSON 输出"
            continue
        if d.get("ok"):
            return d["result"], None
        err = json.dumps(d.get("error"), ensure_ascii=False)[:200]
    return None, err


def hours(ms_or_s, ms=True):
    if not ms_or_s:
        return None
    return (NOW - (ms_or_s / 1000.0 if ms else ms_or_s)) / 3600.0


def iso_ts(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


def load_json(path, default):
    try:
        d = json.load(open(path, encoding="utf-8"))
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


def save_json(path, data):
    if DRY:
        return
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def read_env(path):
    cfg = {}
    try:
        for ln in open(path):
            m = re.match(r"\s*(?:export\s+)?(URL|KEY)\s*=\s*(.*?)\s*$", ln)
            if m:
                cfg[m.group(1)] = m.group(2).strip("'\"")
    except OSError:
        return None
    SECRETS.extend(v for v in cfg.values() if v and v not in SECRETS)
    return cfg if cfg.get("URL") and cfg.get("KEY") else None


def post_once(cfg, payload):
    """用 curl 发：python.org 的 Python 没有系统根证书，自带的 HTTP 库发 https 会失败。
    URL 和 KEY 经 stdin 传给 curl，不出现在进程参数里。返回 HTTP 状态码，或失败说明。"""
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as body:
        json.dump(payload, body, ensure_ascii=False)
        body.flush()
        esc = lambda v: v.replace("\\", "\\\\").replace('"', '\\"')
        conf = 'url = "%s"\nheader = "Content-Type: application/json"\nheader = "Authorization: Bearer %s"\n' % (
            esc(cfg["URL"]), esc(cfg["KEY"]))
        resp = body.name + ".resp"
        try:
            p = subprocess.run(["curl", "-sS", "-o", resp, "-w", "%{http_code}", "--max-time", "20", "-X", "POST",
                                "--data-binary", "@" + body.name, "-K", "-"],
                               input=conf, capture_output=True, text=True, timeout=40)
        except (OSError, subprocess.TimeoutExpired) as e:
            return type(e).__name__
        finally:
            try:
                with open(resp, "rb") as f:
                    _last_resp[0] = f.read(400).decode("utf-8", "replace")
                os.remove(resp)
            except OSError:
                _last_resp[0] = ""
    if p.returncode != 0:
        return "curl 退出码 %d" % p.returncode
    return int(p.stdout) if p.stdout.strip().isdigit() else "无状态码"


_last_post = [0.0]
_last_resp = [""]


def resp_snippet():
    """上一次 POST 的响应体：去掉 URL/KEY 和看着像令牌的长串，压成一行，最多 160 个字符。"""
    t = _last_resp[0] or ""
    for sec in SECRETS:
        t = t.replace(sec, "<已隐藏>")
    t = re.sub(r"(?i)(bearer\s+|(?:key|token|secret)[\"']?\s*[:=]\s*[\"']?)[^\s\"',}]+", r"\1<已隐藏>", t)
    t = re.sub(r"[A-Za-z0-9_\-]{32,}", "<长串已隐藏>", t)
    t = " ".join(t.split())
    return t[:160] + ("…" if len(t) > 160 else "")


def post(cfg, payload, what):
    """发一条，失败按 BACKOFF 重试。两次 POST（含重试）之间至少隔 POST_GAP 秒。返回是否成功。"""
    for n in range(len(BACKOFF) + 1):
        wait = max(BACKOFF[n - 1] if n else 0, POST_GAP - (time.time() - _last_post[0]))
        if wait > 0:
            time.sleep(wait)
        code = post_once(cfg, payload)
        _last_post[0] = time.time()
        ok = isinstance(code, int) and 200 <= code < 300
        snip = "" if ok else resp_snippet()
        log("POST %s → %s（第 %d 次）%s" % (what, code, n + 1, "" if ok else "，失败" + ("，响应：%s" % snip if snip else "")))
        if ok:
            return True
    return False


# ---- bot 映射：orca-projects.md 的「Repo → 项目 ID」表和「Bot → 工作区」表 ----
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
SLUG = re.compile(r"[\w.-]+/[\w.-]+")
LINEAR_RUN = re.compile(r"\b([A-Z]{2,6})-(\d+(?:\s*/\s*\d+)*)")


def load_mapping():
    by_id, by_name, by_linear = {}, {}, {}
    try:
        lines = open(MAPPING, encoding="utf-8").read().splitlines()
    except OSError as e:
        log("映射文件读不到（%s），bot 一律记为「未映射」" % e)
        return by_id, by_name, by_linear
    for ln in lines:
        if not ln.startswith("|") or set(ln) <= set("|-: "):
            continue
        c = [x.strip() for x in ln.strip().strip("|").split("|")]
        if len(c) != 4:
            continue
        m = UUID.fullmatch(c[2])
        if m:  # Repo | Orca 项目 | 项目 ID | 路径
            s = SLUG.match(c[0])
            by_id[c[2]] = {"slug": s.group(0) if s else None, "name": c[1]}
            continue
        bot = c[0]
        if bot in ("Bot", "") or bot.startswith("（"):
            continue
        name = re.sub(r"\(.*?\)", "", c[2]).strip()
        if name and name != "—":
            by_name.setdefault(name, bot)
        for pre, nums in LINEAR_RUN.findall(c[1] + " " + c[3]):
            for n in re.split(r"\s*/\s*", nums):
                by_linear.setdefault("%s-%s" % (pre, n), bot)
    return by_id, by_name, by_linear


MAP_ID, MAP_NAME, MAP_LINEAR = load_mapping()


def bot_for(repo_id, repo_name, slug, linear, display=None):
    if linear and linear in MAP_LINEAR:
        return BOT_SLUG.get(MAP_LINEAR[linear], MAP_LINEAR[linear])
    for rx, b in NAME_BOT:
        if display and rx.search(display):
            return b
    info = MAP_ID.get(repo_id, {})
    slug = slug or info.get("slug")
    names = [info.get("name"), repo_name, slug.split("/")[-1] if slug else None]
    names += [v["name"] for v in MAP_ID.values() if slug and v["slug"] == slug]
    for n in names:
        if n and n in MAP_NAME:
            return BOT_SLUG.get(MAP_NAME[n], MAP_NAME[n])
    return "未映射"


# ---- GitHub PR / Linear 查询（都在 iMac 上跑，带缓存） ----
_pr_cache, _linear_cache = {}, {}
GH_USER = None
PR_FIELDS = "number,state,headRefName,createdAt,reviewDecision,reviews,comments,url"
# 这些账号的评论是自动回链，不算有人看过 PR
AUTO_COMMENTERS = {"linear", "github-actions", "vercel", "cloudflare-workers-and-pages", "codecov", "dependabot"}


def gh_prs(slug, extra):
    """slug + 过滤条件 → PR 列表；查询失败返回 None。"""
    k = (slug,) + tuple(extra)
    if k not in _pr_cache:
        rc, out, err = run(["gh", "pr", "list", "-R", slug, "--state", "all", "--limit", "200",
                            "--json", PR_FIELDS] + list(extra))
        try:
            _pr_cache[k] = json.loads(out) if rc == 0 else None
        except ValueError:
            _pr_cache[k] = None
        if _pr_cache[k] is None and "Could not resolve to a Repository" not in err:
            log("gh pr list %s 失败：%s" % (slug, err[:120]))
    return _pr_cache[k]


def prs_for(slug, branch):
    """先用自己账号开的 PR（一次查完），没命中再按分支名单独查。"""
    mine = gh_prs(slug, ["--author", "@me"])
    if mine and any(p["headRefName"] == branch for p in mine):
        return mine
    return gh_prs(slug, ["--head", branch])


def reviewed(pr):
    human = [c for c in pr.get("comments") or []
             if (c.get("author") or {}).get("login") not in AUTO_COMMENTERS
             and not ((c.get("author") or {}).get("login") or "").endswith("[bot]")]
    return bool(pr.get("reviews") or pr.get("reviewDecision") or human)


def find_pr(slugs, branch, linked_number):
    """返回 (pr 或 None, 是否查询成功)。"""
    ok = False
    for slug in slugs:
        prs = prs_for(slug, branch)
        if prs is None:
            continue
        ok = True
        hits = [p for p in prs if p["headRefName"] == branch]
        if not hits and linked_number and slug == slugs[0]:
            hits = [p for p in gh_prs(slug, ["--author", "@me"]) or [] if p["number"] == linked_number]
        if hits:
            hits.sort(key=lambda p: (p["state"] != "OPEN", -p["number"]))
            return hits[0], True
    return None, ok


def linear_state(ident):
    return linear_info(ident)[:2]


def linear_info(ident):
    """(状态类型, 更新时间, 标签名集合)；查不到时是 (None, None, set())。"""
    if ident not in _linear_cache:
        res, _ = orca_json(["linear", "issue", ident])
        iss = (res or {}).get("issue") or {}
        labels = {(lb.get("name") if isinstance(lb, dict) else str(lb)).strip() for lb in iss.get("labels") or []}
        _linear_cache[ident] = ((iss.get("state") or {}).get("type"), iso_ts(iss.get("updatedAt")), labels)
    return _linear_cache[ident]


WAIT_ZACK = re.compile(r"^等\s*zack$", re.I)
LINEAR_ID = re.compile(r"(?<![A-Za-z0-9])((?:PER|FDV)-\d+)(?![0-9])", re.I)


def waiting_zack(w):
    """in-review 工作区的 Linear 卡挂着「等 Zack」标签、卡还没完成或取消：已验收，在等 Zack 拍板，不算没人验收。
    卡号取工作区关联的 Linear，没有就从显示名、分支名里找。返回卡号或 None。"""
    ids = [w["linkedLinearIssue"]] if w.get("linkedLinearIssue") else []
    ids += [m.upper() for m in LINEAR_ID.findall("%s %s" % (w.get("displayName") or "", w.get("branch") or ""))]
    for ident in dict.fromkeys(ids):
        st, _, labels = linear_info(ident)
        if st not in (None, "completed", "canceled") and any(WAIT_ZACK.match(x) for x in labels):
            return ident
    return None


def done_marker(path):
    """本机工作区里最新的 *.done 标记（3 层以内，跳过 node_modules/.git）。"""
    best = None
    base = path.rstrip("/").count("/")
    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if d not in ("node_modules", ".git", ".wrangler", ".next", "dist")]
        if root.count("/") - base >= 2:
            dirs[:] = []
        for f in files:
            if f.endswith(".done"):
                try:
                    mt = os.path.getmtime(os.path.join(root, f))
                except OSError:
                    continue
                if best is None or mt > best[1]:
                    best = (os.path.relpath(os.path.join(root, f), path), mt)
    return best


# ---- 读一台 Orca 的数据 ----
def sub_task(path):
    """agent 在任务工作区里临时建的子 worktree（<工作区>/.orca-task/xxx），Orca 也列出来，不是任务工作区
    （10-19 00:16 FDV-70 的 revert-wt、base-wt 被报 ws_broken）。里面的进程算在外层工作区上。"""
    return "/.orca-task/" in (path or "") + "/"


def is_task_ws(w):
    if w.get("workspaceKind") != "git" or w.get("isMainWorktree") or w.get("isArchived"):
        return False
    path = w.get("path") or ""
    if path.startswith(("/tmp/", "/private/tmp/", "/var/folders/")) or sub_task(path):
        return False  # agent 在临时目录或 .orca-task 下建的 git worktree，不是任务工作区
    return not (ONLY and not ONLY.search(path))


def load_host(label, env):
    """返回 ({"label","env","worktrees","terms","repos"}, None) 或 (None, 错误)。"""
    ps, err = orca_json(["worktree", "ps", "--limit", "500"], env, tries=3)
    if ps is None:
        return None, err
    tl, _ = orca_json(["terminal", "list", "--limit", "500"], env, tries=2)
    terms = {}
    for t in (tl or {}).get("terminals") or []:
        if t.get("connected") is False:
            continue  # 工作区 Sleep 或终端进程停掉后留下的记录，不是活的终端
        terms.setdefault(t.get("worktreePath"), []).append(t)
    return {"label": label, "env": env, "worktrees": ps.get("worktrees", []), "terms": terms,
            "terms_ok": tl is not None}, None


def decode_probe(text):
    m = re.findall(r"@@PROBE-BEGIN(.*?)@@PROBE-END", text, re.S)
    for blob in reversed(m):
        try:
            return json.loads(gzip.decompress(base64.b64decode("".join(blob.split()))))
        except (ValueError, OSError):
            continue
    return None


def run_probe(host):
    """本机直接跑 agent-probe；box 上开一个临时 Orca 终端跑，读完关掉。失败返回 None。"""
    if host["env"] is None:
        rc, out, err = run([sys.executable, PROBE], 60)
        doc = decode_probe(out) if rc == 0 else None
        if doc is None:
            log("%s：agent-probe 失败（%s），这次不判断进程是否还在" % (host["label"], (err or "无输出")[:120]))
        return doc
    text, err = box_run(host["env"], "~/.local/bin/agent-probe; echo @@PROBE-RC$?", "stuck-check probe", r"^@@PROBE-RC\d")
    if text is None:
        log("%s：agent-probe 第一次失败（%s），15 秒后再试一次" % (host["label"], err))
        time.sleep(15)
        text, err = box_run(host["env"], "~/.local/bin/agent-probe; echo @@PROBE-RC$?", "stuck-check probe", r"^@@PROBE-RC\d")
    if text is None:
        log("%s：%s，这次不判断进程是否还在" % (host["label"], err))
        return None
    doc = decode_probe(text)
    if doc is None:
        log("%s：agent-probe 没有返回结果（box 上是否装了 ~/.local/bin/agent-probe？），这次不判断进程是否还在" % host["label"])
    return doc


def box_run(env, command, title, done_re, polls=12):
    """在 box 上开一个临时 Orca 终端跑 command，等屏幕上出现 done_re，返回 (屏幕文本, None)，读完关掉终端。
    失败返回 (None, 错误)。"""
    res, err = orca_json(["terminal", "create", "--worktree", PROBE_WT.get(env, BOX_PROBE_WT), "--title", title,
                          "--command", command], env, tries=2)
    handle = ((res or {}).get("terminal") or {}).get("handle")
    if not handle:
        return None, "开不了临时终端（%s）" % err
    try:
        for _ in range(polls):
            time.sleep(1.5)
            rd, _ = orca_json(["terminal", "read", "--terminal", handle, "--limit", "400"], env)
            text = "\n".join(((rd or {}).get("terminal") or {}).get("tail") or [])
            if re.search(done_re, text, re.M):
                return text, None
    finally:
        orca_json(["terminal", "close", "--terminal", handle], env, tries=2)
    return None, "临时终端里的命令没有跑完"


def wake_recheck(host, pids, waiting=None):
    """调 orca-wake recheck 给这些 agent 进程补叫醒（box 上走临时终端）。调用失败返回 None，否则返回
    {"res": {pid: "send" 或跳过原因}, "bot": {pid: 派活 bot}, "enabled": 放行名单}。
    跳过原因来自 orca-wake：no_state_for_pid、already_woken、recent_activity、agent_gone、parent_changed。
    bot 只对这次会补叫醒的进程有（取自 recheck --list）。dry-run 只跑 --list，不发。
    waiting = {pid: Orca stateStartedAt 毫秒}：停在对话框的进程，走 --waiting-pid（结果多 already_asked、inflight）。"""
    waiting = waiting or {}
    n = "%g" % IDLE_MIN
    if host["env"] is None:
        head = "W=%s" % shlex.quote(ORCA_WAKE)
    else:
        head = ("export ORCA_WAKE_CONFIG_DIR=%s; " % shlex.quote(BOX_WAKE_CONFIG) if BOX_WAKE_CONFIG else "") + \
            'W="$HOME/.local/bin/orca-wake"'
    body = (head + '; C="${ORCA_WAKE_CONFIG_DIR:-$HOME/.config/orca-wake}"\n'
            '"$W" recheck --list --idle-min %s 2>/dev/null | sed "s/^/L /"\n'
            '[ -r "$C/enabled-bots" ] && sed "s/^/E /" "$C/enabled-bots"\n' % n)
    if not DRY:
        body += '"$W" recheck --idle-min %s %s 2>&1 | sed "s/^/R /"\necho "X ${PIPESTATUS[0]}"\n' % (
            n, " ".join(("--waiting-pid %d:%d" % (p, waiting[p])) if p in waiting else ("--agent-pid %d" % p)
                        for p in pids))
    script = 'echo @@WAKE""-BEGIN; { %s} 2>&1 | gzip -c | base64; echo @@WAKE""-END\n' % body
    if host["env"] is None:
        rc, text, err = run(["bash", "-c", script], 60)
        if rc != 0:
            text = None
    else:
        cmd = "echo %s | base64 -d | bash" % base64.b64encode(script.encode()).decode()
        text, err = box_run(host["env"], cmd, "stuck-check wake", r"^@@WAKE-END", 20)
    m = re.findall(r"@@WAKE-BEGIN(.*?)@@WAKE-END", text or "", re.S)
    try:
        out = gzip.decompress(base64.b64decode("".join(m[-1].split()))).decode("utf-8", "replace")
    except (IndexError, ValueError, OSError):
        log("%s：调用 orca-wake recheck 失败（%s）" % (host["label"], (err or "没有输出")[:160]))
        return None
    r = {"res": {}, "bot": {}, "enabled": set(), "rc": None}
    for ln in out.splitlines():
        tag, _, rest = ln.partition(" ")
        if tag == "L":
            try:
                d = json.loads(rest)
                r["bot"][int(d["agent_pid"])] = d.get("bot")
                if DRY:
                    r["res"][int(d["agent_pid"])] = "send"
            except (ValueError, KeyError, TypeError):
                pass
        elif tag == "E" and rest.strip() and not rest.lstrip().startswith("#"):
            r["enabled"].add(rest.strip())
        elif tag == "R":
            mm = re.match(r"recheck: pid (\d+) (?:send (?:idle|needs_input)|skip \((\w+)\))", rest)
            if mm:
                r["res"][int(mm.group(1))] = mm.group(2) or "send"
        elif tag == "X":
            r["rc"] = rest.strip()
    if not DRY and r["rc"] != "0":
        log("%s：orca-wake recheck 退出码 %s：%s" % (host["label"], r["rc"], out[-300:]))
        return None
    return r


def ws_of(path, ws_paths):
    """进程 cwd → 所在工作区（最长前缀）。"""
    best = None
    for p in ws_paths:
        if path == p or path.startswith(p.rstrip("/") + "/"):
            if best is None or len(p) > len(best):
                best = p
    return best


def tui_idle(handle, env):
    """True/False；查不到返回 None。"""
    cmd = [ORCA, "terminal", "wait", "--terminal", handle, "--for", "tui-idle", "--timeout-ms", "800"]
    rc, out, _ = run(cmd + (["--environment", env] if env else []) + ["--json"], 30)
    try:
        d = json.loads(out)
    except ValueError:
        return None
    if d.get("ok"):
        return bool(((d.get("result") or {}).get("wait") or {}).get("satisfied"))
    return False if (d.get("error") or {}).get("code") == "timeout" else None


def screen_since(handle, env, track, seed=0):
    """终端屏幕内容从什么时候起没变过（两次检查之间比指纹）。用在拿不到 agent 状态或 lastOutputAt 的地方。
    指纹不含最后 3 行：那是 agent 的状态栏（用量百分比之类），agent 闲着它也会变。第一次见到时从 seed 算起。"""
    rd, _ = orca_json(["terminal", "read", "--terminal", handle, "--screen", "--limit", "60"], env)
    tail = ((rd or {}).get("terminal") or {}).get("tail")
    if tail is None:
        return None
    body = [ln.rstrip() for ln in tail if ln.strip()][:-3]
    h = hashlib.sha1("\n".join(body).encode()).hexdigest()
    rec = track["screens"].get(handle)
    if not rec:
        rec = {"hash": h, "since": seed or NOW}
    elif rec.get("hash") != h:
        rec = {"hash": h, "since": NOW}
    rec["seen"] = NOW
    track["screens"][handle] = rec
    return rec["since"]


def task_name(w):
    linear = w.get("linkedLinearIssue")
    if linear and linear in (w.get("displayName") or ""):
        return w["displayName"]
    return ("%s %s" % (linear or "", w.get("displayName") or "")).strip()


def automation_of(w, env):
    """自动任务每次运行自己建的工作区，没有 bot 在等它，跑完留着是正常的。是的话返回自动任务名。"""
    show, _ = orca_json(["worktree", "show", "--worktree", "path:" + w["path"]], env)
    prov = ((show or {}).get("worktree") or show or {}).get("automationProvenance") or {}
    if prov.get("kind") == "created-by-automation":
        return prov.get("automationNameSnapshot") or "?"
    return None


def norm(t):
    return " ".join((t or "").split())


def automation_prompts(host):
    """这台 Orca 各自动任务 prompt 的开头（压成一行，至少 20 个字）。查不到返回空列表。"""
    if "auto_prompts" not in host:
        al, _ = orca_json(["automations", "list"], host["env"], tries=2)
        host["auto_prompts"] = [pp for pp in (norm(a.get("prompt"))[:80] for a in (al or {}).get("automations") or [])
                                if len(pp) >= 20]
    return host["auto_prompts"]


def automation_panes(host):
    """自动任务运行记录里的终端 paneKey（记录较大，只在 prompt 对不上时才查）。"""
    if "auto_panes" not in host:
        rl, _ = orca_json(["automations", "runs"], host["env"], tries=2, timeout=120)
        host["auto_panes"] = {r["terminalPaneKey"] for r in (rl or {}).get("runs") or [] if r.get("terminalPaneKey")}
    return host["auto_panes"]


def by_automation(host, pane=None, args=None, prompt=None):
    """agent 是不是 Orca 自动任务起的：命令行 / Orca 记的 prompt 是某个自动任务的 prompt，或终端 paneKey 在运行记录里。"""
    a, pr = norm(args), norm(prompt)
    if any((a and pp in a) or (pr and pr.startswith(pp[:60])) for pp in automation_prompts(host)):
        return True
    return bool(pane) and pane in automation_panes(host)


PAUSE_EVENTS = {"Stop", "StopFailure", "Notification/idle_prompt", "send/idle", "send/error", "send/blocked"}


def wrapped_exit(host, key, ms):
    """主目录里包了 notify-run 的 agent 退出了：notify-run.log 里这个终端（pane）最后一次「包住 agent 那层」的发送（agent-probe 带回来）。
    返回 None（送达了，或分不清：没有记录、agent-probe 是旧版），"retrying"（还在重试），或那一行（明确失败了，PER-67 F2）。"""
    wk = (get_probe(host) or {}).get("wake")
    if wk is None:
        log("主目录 agent 退出 | %s | agent-probe 没带 notify-run 记录（旧版？），按包了 notify-run 不报" % key)
        return None
    since = (ms.get("hook") or ms.get("seen") or NOW) - 120
    lines = [n for n in wk.get("nr") or [] if n.get("agent") and n.get("pane") == key.rsplit("#", 1)[-1] and n["ts"] >= since]
    if not lines:
        log("主目录 agent 退出 | %s | notify-run.log 里没有这个终端的退出发送，分不清，不报" % key)
        return None
    n = max(lines, key=lambda x: x["ts"])
    if re.fullmatch(r"2\d\d", n.get("http") or ""):
        return None
    if NOW - n["ts"] < 120 and str(n.get("try")) != "3":
        return "retrying"
    log("主目录 agent 退出 | %s | notify-run 退出时发送失败（http=%s，第 %s 次）" % (key, n.get("http"), n.get("try")))
    return n


def check_undelivered(host, track):
    """completed / in-review 的任务工作区：最后一次停下（orca-wake 会话的当前回合，或之后 notify-run 包住 agent 那层的退出发送）
    没送达过叫醒，已经 ESCALATE_MIN 分钟 → 直接报 coding-assistant（stop_not_delivered）。第二类要标完成 1 小时、约每小时查一次，
    最坏近 2 小时才到；这里每次扫描都查（PER-67 F6）。数据来自 agent-probe（旧版没有就不查）。每次停下只报一次。"""
    wk = (get_probe(host) or {}).get("wake")
    if wk is None:
        return []
    label, done, out, live = host["label"], track.setdefault("undelivered", {}), [], set()
    for w in host["worktrees"]:
        status = w.get("workspaceStatus")
        if not is_task_ws(w) or status not in ("completed", "in-review"):
            continue
        if any(a.get("state") == "working" for a in w.get("agents") or []):
            continue
        p = w["path"].rstrip("/") + "/"
        inside = lambda c: bool(c) and (c.rstrip("/") + "/").startswith(p)
        s = max((x for x in wk.get("sessions") or [] if inside(x.get("cwd"))), key=lambda x: x.get("last_event_ts") or 0, default=None)
        n = max((x for x in wk.get("nr") or [] if x.get("agent") and inside(x.get("ws"))), key=lambda x: x["ts"], default=None)
        ts_s = (s or {}).get("last_event_ts") or 0
        if n and n["ts"] >= ts_s:  # 最后一次是退出
            ok, stop = bool(re.fullmatch(r"2\d\d", n.get("http") or "")), n["ts"]
            why = "agent 退出时 notify-run 发送没成功（http=%s，第 %s 次）" % (n.get("http"), n.get("try"))
        elif s and s.get("last_event") in PAUSE_EVENTS:
            ok, stop = bool(s.get("woken")), ts_s
            why = "%s 会话最后一次停下（第 %s 回合）没有送达的叫醒" % (s.get("agent"), s.get("turn"))
        else:
            continue  # 没有记录，或回合还没结束
        if ok or NOW - stop < ESCALATE_MIN * 60:
            continue
        iid = "undelivered:%s:%s:%d" % (label, w["path"], int(stop))
        live.add(iid)
        if iid in done:
            continue
        bot = (s or {}).get("bot") or (n or {}).get("bot") or "?"
        log("没送达 | %s:%s | %s，%s 停下（%.0f 分钟前）" % (label, w["path"], why, hm(stop), (NOW - stop) / 60.0))
        out.append({"id": iid, "cfg": "fallback", "after": {"undelivered": iid}, "payload": {
            "bot": FALLBACK_BOT, "task": task_name(w), "worktree": "%s:%s" % (label, w["path"]), "status": "stuck",
            "kind": "stop_not_delivered", "machine": label, "source": "stuck-check",
            "note": "工作区标 %s，%s，%s 停下已 %.0f 分钟：派活 bot %s 不知道它停了。看看它做完没有、结果在哪，转达 %s" % (
                status, why, hm(stop), (NOW - stop) / 60.0, bot, bot)}})
    for k in [k for k in done if k.startswith("undelivered:%s:" % label) and k not in live]:
        del done[k]
    return out


def get_probe(host):
    if "probe" not in host:
        host["probe"] = run_probe(host)
    return host["probe"]


def stop_mark(host, since, pane=None, panes=(), ws=None, ws_paths=()):
    """agent-stop 写的「主动停止」标记（agent-probe 带回来，48 小时内的）：同一个终端（paneKey），或 cwd 在这个工作区里，
    且写在 agent 最后一次动作之后（宽限 2 分钟）。有就返回标记，这个 agent 退出不报（10-19 03:05 主动停掉 7 个 agent 后被报了 6 次）。"""
    for m in (get_probe(host) or {}).get("stops") or []:
        if (m.get("ts") or 0) < (since or 0) - 120:
            continue
        if (pane and m.get("pane") == pane) or (m.get("pane") and m["pane"] in panes) or \
                (ws and m.get("cwd") and ws_of(m["cwd"], ws_paths) == ws):
            return m
    return None


def check_unwrapped(host, track, pend=()):
    """活着的 claude / pi / codex，父链里没有 notify-run：做完或停下没人叫醒（10-18 box 上 8 个 brief agent 这样漏掉）。
    只看 Orca 终端里的顶层 agent（agent 自己起的子 agent、Orca 外面人开的终端不算），Orca 自动任务起的不算。
    每个进程报一次，发给工作区对应的 bot，认不出的发 coding-assistant。返回直发列表。"""
    label, env = host["label"], host["env"]
    probe = get_probe(host)
    if probe is None:
        return []
    seen = track.setdefault("unwrapped", {})
    ws_paths = [w["path"] for w in host["worktrees"] if w.get("path") and not sub_task(w["path"])]
    wmap = {w["path"]: w for w in host["worktrees"] if w.get("path")}
    per_bot = {}
    # 报过的记录只在进程真的没了才删（ONLY 过滤掉的、这次不算的照样留着），同一个进程只报一次（10-19 MBA pid 36142）
    alive = {"%s:%d" % (label, p["pid"]) for p in probe.get("procs", [])}
    for p in probe.get("procs", []):
        if p["kind"] != "agent" or p.get("name") not in WATCH_AGENTS or p.get("agent_anc_cwds") or \
                p.get("notify_anc") or not p.get("in_orca") or (ONLY and not ONLY.search(p.get("cwd") or "")):
            continue
        k = "%s:%d" % (label, p["pid"])
        start = int(probe.get("ts", NOW) - p.get("etime_s", 0))
        if k in pend or (k in seen and abs(seen[k].get("start", 0) - start) < 120):
            continue  # 报过，或上次没发出去、还在 pending 里
        if by_automation(host, p.get("pane"), p.get("args_head")):
            seen[k] = {"start": start, "automation": True}
            continue
        wp = ws_of(p.get("cwd") or "", ws_paths)
        w = wmap.get(wp) or {}
        bot = bot_for(w.get("repoId"), w.get("repo"), MAP_ID.get(w.get("repoId"), {}).get("slug"),
                      w.get("linkedLinearIssue"), w.get("displayName")) if w else "未映射"
        if bot == "未映射":
            bot = FALLBACK_BOT
        what = "%s pid %d（%s，已跑 %.0f 分钟，cwd %s）：%s" % (
            p["name"], p["pid"], label, p.get("etime_s", 0) / 60.0, p.get("cwd") or "?",
            ("工作区「%s」" % (w.get("displayName") or wp)) if w else "不在任何 Orca 工作区里")
        log("没包 notify-run | %s | %s" % (bot, what))
        per_bot.setdefault(bot, []).append((k, start, what))
    for k in [k for k in seen if k.split(":", 1)[0] == label and k not in alive]:
        del seen[k]
    out = []
    for bot, items in per_bot.items():
        ids = ",".join(sorted(k for k, _, _ in items))
        out.append({"id": "unwrapped:%s:%s" % (bot, hashlib.sha1(ids.encode()).hexdigest()[:10]), "cfg": "bot:" + bot,
                    "after": {"unwrapped": [[k, {"start": st, "notified": NOW}] for k, st, _ in items]},
                    "payload": {"bot": bot, "task": "有 %d 个 agent 没经 notify-run 起（%s）" % (len(items), label),
                                "worktree": "；".join(sorted({w.split("：")[0] for _, _, w in items}))[:300],
                                "status": "stuck", "kind": UNWRAPPED, "machine": label, "source": "stuck-check",
                                "note": "这些 agent 的父链里没有 notify-run，做完或停下不会叫醒派活的 bot（dev-bot-rules 要求一律用 "
                                        "notify-run 包，起 agent 请用 orca-agent-launch）。还在做的盯着点，做完的看结果并关掉：\n" +
                                        "\n".join("%d. %s" % (i, w) for i, (_, _, w) in enumerate(items, 1))}})
    return out


def is_main_watch(w):
    return bool(w.get("isMainWorktree")) and not w.get("isArchived") and w.get("repo") in MAIN_REPOS and \
        not (ONLY and not ONLY.search(w.get("path") or ""))


# ---- 一、卡住的 agent ----
def check_agents(host, known, track):
    """返回 (嫌疑列表, 这次看过的 key 集合, 查了几个工作区)。known = agents.json 里的记录。
    两个时间：agent_t = agent 最近一次动作（Orca 的 agent 状态记录；没有记录时用屏幕指纹），
    out_t = 终端最近一次输出（lastOutputAt；box 上没有这个值，用屏幕指纹）。
    工作区的 lastActivityAt 不用来判断「有新活动」：在 Orca 界面里点开工作区它也会变。"""
    label, env = host["label"], host["env"]
    ws_paths = [w["path"] for w in host["worktrees"] if w.get("path") and not sub_task(w["path"])]
    cands, eligible, found = [], set(), []
    main_seen = track.setdefault("main_seen", {})  # 主目录里上次见到的 agent 终端：agent 退出后 Orca 连记录一起删掉，只能靠这里
    main_now = set()

    def broken(w, key):
        last = (w.get("lastActivityAt") or 0) / 1000.0
        rec = known.get(key)
        if rec:
            if rec.get("kind") == BROKEN and last <= rec.get("marker", 0) + 60:
                return  # 报过，之后没有新活动
            del known[key]
        quiet = (NOW - last) / 60.0 if last else None
        if quiet is not None and quiet < GONE_MIN:
            return
        made_by = automation_of(w, env)
        if made_by:
            known[key] = {"kind": BROKEN, "marker": last, "dismissed": NOW, "reason": "自动任务「%s」建的工作区" % made_by}
            return
        hook = max([max(a.get("updatedAt") or 0, a.get("stateStartedAt") or 0) for a in w.get("agents") or []] or [0]) / 1000.0
        sm = stop_mark(host, hook, ws=w["path"], ws_paths=ws_paths)
        if sm:
            log("断了 | %s | 有主动停止标记（%s 停的：%s），不报" % (key, sm.get("by"), sm.get("reason")))
            known[key] = {"kind": BROKEN, "marker": last, "dismissed": NOW, "reason": "主动停止：%s" % sm.get("reason")}
            return
        linear = w.get("linkedLinearIssue")
        found.append({"key": key, "kind": BROKEN, "bot": bot_for(w.get("repoId"), w.get("repo"), MAP_ID.get(
            w.get("repoId"), {}).get("slug"), linear, w.get("displayName")), "task": task_name(w), "worktree": key,
            "machine": label, "env": env, "terminals": [], "marker": last,
            "note": "工作区标着 in-progress，但一个终端都没有（断了：agent 和终端都不在），%s。还要做就重新起 agent；"
                    "等别人就改 in-review 或 Sleep，做完改 completed" % (
                        "最近一次活动在 %.0f 分钟前" % quiet if quiet is not None else "没有活动记录")})

    def main_panes(w):
        """主目录（ops）里同时跑着很多 agent，按 agent 终端逐个当成一个「工作区」查，key 带 paneKey。
        自动任务起的、状态超过 MAIN_MAX_AGE_H 小时没变的不查；不看 workspaceStatus，没有 ws_broken。"""
        recs = {}
        for a in w.get("agents") or []:
            recs.setdefault(a.get("paneKey"), []).append(a)
        for t in host["terms"].get(w["path"]) or []:
            if not t.get("agentIdentity") or not t.get("tabId"):
                continue
            pk = "%s:%s" % (t["tabId"], t.get("leafId"))
            agents = recs.get(pk) or []
            if not agents:
                continue  # Orca 没有这个终端的 agent 记录，判断不了
            hook = max(max(a.get("updatedAt") or 0, a.get("stateStartedAt") or 0) for a in agents) / 1000.0
            if (NOW - hook) / 3600.0 > MAIN_MAX_AGE_H:
                continue
            first = next((a.get("prompt") for a in agents if a.get("prompt")), "")
            if by_automation(host, pk, prompt=first):
                continue
            key = "%s:%s#%s" % (label, w["path"], pk)
            eligible.add(key)
            main_now.add(key)
            ms = main_seen.setdefault(key, {})
            ms.update(hook=hook, seen=NOW, handle=t["handle"], task="%s 主目录 · %s" % (w.get("repo"), norm(first)[:40] or pk[:8]),
                      bot=bot_for(w.get("repoId"), w.get("repo"), MAP_ID.get(w.get("repoId"), {}).get("slug"), None, None))
            out = (t.get("lastOutputAt") or 0) / 1000.0
            scr = 0 if out else (screen_since(t["handle"], env, track, 0) or 0)
            agent_t, out_t = hook, out or scr
            rec = known.get(key) or {}
            if rec:
                newer = agent_t if rec.get("kind") != SILENT else max(agent_t, out_t)
                if newer <= rec.get("marker", 0) + 60 and not rec.get("handed"):
                    continue  # 只交给了 orca-wake 的（handed）每次再 recheck（PER-67 F1，第 3 组漏了主目录这一处）
                del known[key]
            pw = dict(w, agents=agents, liveTerminalCount=1, linkedLinearIssue=None,
                      displayName="%s 主目录 · %s" % (w.get("repo"), norm(first)[:40] or t.get("title") or pk[:8]))
            cands.append({"w": pw, "key": key, "agents": agents, "hook": hook, "scr": scr, "agent_t": agent_t,
                          "out_t": out_t, "out": out, "handles": [t["handle"]], "act": 0, "pane": pk,
                          "since": rec.get("handed_since") or rec.get("handed")})

    for w in host["worktrees"]:
        if is_main_watch(w):
            main_panes(w)
            continue
        if not is_task_ws(w) or w.get("workspaceStatus") != "in-progress":
            continue
        key = "%s:%s" % (label, w["path"])
        if not (w.get("liveTerminalCount") or 0) and not host["terms"].get(w["path"]):
            # 一个终端都没有：工作区断了（Orca 重启、终端被关、agent 连同终端一起没了）。要歇着的工作区标 Sleep
            # （看板状态 sleep），走不到这里。终端列表没查到时分不清，不报。
            if host["terms_ok"]:
                eligible.add(key)
                broken(w, key)
            continue
        eligible.add(key)
        agents = w.get("agents") or []
        hook = max([max(a.get("updatedAt") or 0, a.get("stateStartedAt") or 0) for a in agents] or [0]) / 1000.0
        terms = host["terms"].get(w["path"]) or []
        aterms = [t for t in terms if t.get("agentIdentity")] or terms
        handles = [t["handle"] for t in aterms]
        panes = {"%s:%s" % (t["tabId"], t.get("leafId")) for t in terms if t.get("tabId")}
        # 输出时间只看 agent 所在的终端（认不出哪个是 agent 终端时看全部）
        out = max([(t.get("lastOutputAt") or 0) for t in aterms] or [w.get("lastOutputAt") or 0]) / 1000.0
        scr = 0
        if not hook or not out:
            scr = max([s for s in (screen_since(t["handle"], env, track, (t.get("lastOutputAt") or 0) / 1000.0)
                                   for t in aterms) if s] or [0])
        agent_t, out_t = hook or scr, out or scr
        rec = known.get(key) or {}
        if rec:
            newer = agent_t if rec.get("kind") != SILENT else max(agent_t, out_t)
            if newer <= rec.get("marker", 0) + 60 and not rec.get("handed"):
                continue  # 报过或排除过，之后没有新活动；只交给了 orca-wake 的（handed）每次再 recheck，见 wake_recheck 之后
            del known[key]
        cands.append({"w": w, "key": key, "agents": agents, "hook": hook, "scr": scr, "agent_t": agent_t,
                      "out_t": out_t, "out": out, "handles": handles, "act": (w.get("lastActivityAt") or 0) / 1000.0,
                      "panes": panes, "since": rec.get("handed_since") or rec.get("handed")})
    # 主目录里上次还在、这次 Orca 已没有 agent 记录的终端：agent 退出了。经 notify-run 起的它自己会叫醒，只有 notify-run.log 里
    # 这个终端（pane）那次退出发送明确失败了才报（PER-67 F2）；没包的报一次 agent_gone（终端还在就经复核）。
    # 这台主目录没查到（终端列表失败）时不判断。
    if host["terms_ok"]:
        mains = {w["path"] for w in host["worktrees"] if is_main_watch(w)}
        for key in [k for k in main_seen if k.startswith(label + ":") and k not in main_now]:
            # 报出去之前一直留着这条记录（每次扫描重新报，发送失败了下次还在，F4 的改报才接得上；PER-67 F2），
            # 送达或复核排除后（known 里有记录）才删
            rec = known.get(key) or {}
            if rec.get("notified") or rec.get("dismissed"):
                main_seen.pop(key)
                continue
            ms = main_seen.pop(key)
            if ms.get("wrapped") is None or key.split(":", 1)[1].split("#")[0] not in mains:
                continue  # 上次没查到进程、分不清
            if ms.get("wrapped"):
                nr = wrapped_exit(host, key, ms)
                if nr == "retrying":
                    main_seen[key] = ms  # notify-run 还在重试，下次再看
                elif nr:
                    main_seen[key] = ms
                    eligible.add(key)
                    found.append({"key": key, "kind": GONE, "bot": nr.get("bot") or ms.get("bot") or FALLBACK_BOT,
                                  "task": ms.get("task") or key, "worktree": key, "machine": label, "env": env,
                                  "marker": ms.get("hook") or NOW, "terminals": [], "note":
                                  "主目录里经 notify-run 起的 agent 退出了（status %s），notify-run 退出时发送没成功（http=%s，第 %s 次，%s），"
                                  "派活 bot 没收到。看看它做完没有、结果在哪" % (nr.get("status"), nr.get("http"), nr.get("try"), hm(nr["ts"]))})
                continue
            quiet = (NOW - (ms.get("hook") or ms.get("seen") or NOW)) / 60.0
            sm = stop_mark(host, ms.get("hook"), pane=key.rsplit("#", 1)[-1])
            if sm:
                log("主目录 agent 退出 | %s | 有主动停止标记（%s 停的：%s），不报" % (key, sm.get("by"), sm.get("reason")))
                continue
            alive = any(t["handle"] == ms.get("handle") for ts in host["terms"].values() for t in ts)
            main_seen[key] = ms
            eligible.add(key)
            found.append({"key": key, "kind": GONE, "bot": ms.get("bot") or FALLBACK_BOT, "task": ms.get("task") or key,
                          "worktree": key, "machine": label, "env": env, "marker": ms.get("hook") or NOW,
                          "terminals": [ms["handle"]] if alive else [],
                          "note": "主目录里的 agent 进程退出了（上次检查还在，最近一次 agent 动作在 %.0f 分钟前；它没经 notify-run 起，"
                                  "退出时没人收到）。终端%s。看看它做完没有、结果在哪" % (quiet, "还开着" if alive else "也关了")})
    if DRY:  # 演练 / 核对覆盖面用：这次查了哪些
        for k in sorted(eligible):
            log("查 | %s" % k)
    if not cands:
        return found, eligible, len(eligible)
    probe = get_probe(host)
    rechecks = []
    for c in cands:
        w, key, agents, handles = c["w"], c["key"], c["agents"], c["handles"]
        agent_t, out_t = c["agent_t"], c["out_t"]
        aprocs, notify = [], []
        if probe is not None:
            for p in probe.get("procs", []):
                if c.get("pane"):  # 主目录：按终端认进程
                    if p.get("pane") == c["pane"] and p["kind"] == "agent" and not p.get("agent_anc_cwds"):
                        aprocs.append(p)
                    elif p.get("pane") == c["pane"] and p["kind"] == "notify-run" and not p.get("wraps_agent"):
                        notify.append(p)
                    continue
                # cwd 在工作区里，或者跑在这个工作区的终端里（agent cd 到工作区外面还活着，10-18 13:48 被误报 agent_gone）
                here = ws_of(p.get("cwd") or "", ws_paths) == w["path"] or (p.get("pane") and p["pane"] in c.get("panes", ()))
                if p["kind"] == "agent" and here:
                    aprocs.append(p)
                elif p["kind"] == "notify-run" and not p.get("wraps_agent") and (
                        here or any(ws_of(x, ws_paths) == w["path"] for x in p.get("agent_anc_cwds") or [])):
                    notify.append(p)
        if notify:
            continue  # 有 notify-run 在跑长命令，结束时它会自己叫醒 bot
        if c.get("pane") and any(by_automation(host, args=p.get("args_head")) for p in aprocs):
            main_seen.pop(key, None)
            continue  # 主目录里自动任务起的（paneKey 已不在运行记录里，靠命令行认出来）
        if c.get("pane") and aprocs:
            main_seen[key]["wrapped"] = any(p.get("notify_anc") for p in aprocs)
        linear = w.get("linkedLinearIssue")
        repo_slug = MAP_ID.get(w.get("repoId"), {}).get("slug")
        bot = bot_for(w.get("repoId"), w.get("repo"), repo_slug, linear, w.get("displayName"))
        disp = [p.get("dispatch_bot") for p in aprocs if p.get("dispatch_bot")]
        if disp:  # agent 是 notify-run --bot X 派出来的：直接用 X
            bot = disp[0]
        task = task_name(w)

        def add(kind, note, marker, w=w, key=key, bot=bot, task=task, handles=handles, to=None):
            made_by = automation_of(w, env) if not w.get("isMainWorktree") else None
            if made_by:
                known[key] = {"kind": kind, "marker": marker, "dismissed": NOW,
                              "reason": "自动任务「%s」建的工作区" % made_by}
                return
            found.append({"key": key, "kind": kind, "bot": to or bot, "task": task, "worktree": key, "machine": label,
                          "note": note, "marker": marker, "env": env, "terminals": handles})

        nterm = w.get("liveTerminalCount") or 0
        if probe is None and not agents:
            continue  # 进程查不到，Orca 也没有 agent 记录，没法判断
        if c.get("pane") and not aprocs and (probe is None or not any(
                p.get("pane") for p in probe.get("procs", []) if p["kind"] == "agent")):
            continue  # 主目录按终端认进程，这台读不到进程的 paneKey 时分不清，不报
        if probe is not None and not aprocs:
            last = max(c["act"], c["hook"], c["out"]) or c["scr"]  # 屏幕指纹第一次见到时是「现在」，有别的时间就不用它
            quiet = (NOW - last) / 60.0 if last else None
            sm = stop_mark(host, c["hook"], pane=c["pane"]) if c.get("pane") else \
                stop_mark(host, c["hook"], panes=c.get("panes", ()), ws=w["path"], ws_paths=ws_paths)  # 主目录只按终端认
            if sm and (quiet is None or quiet >= GONE_MIN):
                log("agent_gone | %s | 有主动停止标记（%s 停的：%s），不报" % (key, sm.get("by"), sm.get("reason")))
                known[key] = {"kind": GONE, "marker": agent_t, "dismissed": NOW, "reason": "主动停止：%s" % sm.get("reason")}
            elif quiet is None or quiet >= GONE_MIN:
                add(GONE, "agent 进程已经不在（终端还开着 %d 个，里面没有 agent），工作区还标着 in-progress%s" % (
                    nterm, "，最近一次活动在 %.0f 分钟前" % quiet if quiet is not None else "，没有活动记录"), agent_t)
            continue
        stopped = bool(aprocs) and all((p.get("stat") or "").startswith("T") for p in aprocs)
        idle_for = (NOW - agent_t) / 60.0 if agent_t else None
        idle = stale = False
        waiting = 0  # 停在对话框时 = Orca 的 stateStartedAt（毫秒）
        if not stopped and handles and idle_for is not None and idle_for >= IDLE_MIN:
            probes = [tui_idle(h, env) for h in handles]
            if agents:  # Orca 记录是停了，终端里也确实没在动
                # 停在对话框：主 agent（子 agent 的面板不算）最新状态是 waiting。不走 idle（会占掉 Claude 本回合的
                # idle 去重键），交给 orca-wake --waiting-pid；Esc 后 Orca 仍是 waiting 的情况由它读 transcript 分辨。
                main = [a for a in agents if not a.get("parentPaneKey")] or agents
                newest = max(main, key=lambda a: a.get("stateStartedAt") or 0)
                if newest.get("state") == "waiting":
                    waiting = int(newest.get("stateStartedAt") or 0)
                idle = not waiting and not any(a.get("state") == "working" for a in agents) and \
                    not any(r is False for r in probes)
                # Esc 中断没有 Stop，Orca 的状态可能一直停在 working。状态 30 分钟没变、终端都停在输入框时
                # 只交给 orca-wake 核对（它自己再看 30 分钟内有没有动静）；它不认识的会话照旧不报。
                stale = not waiting and not idle and all(r is True for r in probes)
            else:       # 没有 agent 状态记录：屏幕 30 分钟没变，而且有终端停在输入框
                idle = any(r is True for r in probes)
        elif agents and not stopped and not any(a.get("state") == "working" for a in agents):
            continue  # 停下来等输入，还不到时间
        if idle:
            st = max(agents, key=lambda a: a.get("stateStartedAt") or 0).get("state") if agents else "没有记录，按屏幕判断"
            note = "agent 停在输入框等输入已 %.0f 分钟（Orca 状态：%s），工作区还标着 in-progress，没有 notify-run 在跑" % (
                idle_for, st)
            if aprocs:  # 先交给 orca-wake；它没有记录的再按老办法报（见 wake_recheck 之后）
                top = [p["pid"] for p in aprocs if not p.get("agent_anc_cwds")] or [p["pid"] for p in aprocs]
                rechecks.append({"key": key, "pids": top, "note": note, "marker": agent_t, "add": add, "addf": add,
                                 "since": c.get("since")})
            elif probe is None:  # 拿不到 pid 就问不了 orca-wake；按老办法报可能和它重复叫醒，下次再查
                log("agent_idle | %s | 进程没查到，没法问 orca-wake，这次不报，下次再查" % key)
            else:
                add(IDLE, note, agent_t)
            continue
        if waiting:
            if aprocs:
                top = [p["pid"] for p in aprocs if not p.get("agent_anc_cwds")] or [p["pid"] for p in aprocs]
                rechecks.append({"key": key, "pids": top, "marker": agent_t, "add": None, "addf": add, "waiting": waiting,
                                 "since": c.get("since"),
                                 "note": "agent 停在对话框已 %.0f 分钟（Orca 状态 waiting）" % (
                                     (NOW - waiting / 1000.0) / 60.0)})
            else:
                log("agent_idle | %s | 停在对话框，但进程没查到，没法问 orca-wake，这次不报，下次再查" % key)
            continue
        if stale and aprocs:
            top = [p["pid"] for p in aprocs if not p.get("agent_anc_cwds")] or [p["pid"] for p in aprocs]
            rechecks.append({"key": key, "pids": top, "marker": agent_t, "add": None, "addf": add,
                             "since": c.get("since"), "note": "Orca 状态 working 已 %.0f 分钟没变，终端停在输入框" % idle_for})
        # 进程在、不在等输入：看终端多久没有新输出
        mins = (NOW - out_t) / 60.0 if out_t else None
        if mins is not None and mins >= IDLE_MIN:
            add(SILENT, "agent 进程还在%s、不在等输入，但终端已 %.0f 分钟没有新输出，也没有 notify-run 在跑" % (
                "（进程被挂起，状态 T）" if stopped else "", mins), max(agent_t, out_t))
    if rechecks:
        rr = wake_recheck(host, sorted({p for r in rechecks for p in r["pids"]}),
                          {p: r["waiting"] for r in rechecks if r.get("waiting") for p in r["pids"]})
        for r in rechecks:
            key, marker = r["key"], r["marker"]
            if rr is None:
                log("agent_idle | %s | orca-wake 调用失败，这次不报，下次再查" % key)
                continue
            res = {p: rr["res"].get(p, "no_result") for p in r["pids"]}
            desc = "，".join("pid %d %s" % (p, v) for p, v in sorted(res.items()))
            sent = [p for p, v in res.items() if v == "send"]
            if sent and not DRY and not ("*" in rr["enabled"] or (rr["bot"].get(sent[0]) or "?") in rr["enabled"]):
                # 影子模式：orca-wake 只写了日志、没发（10-16～10-17 这样漏了 58 次）。不算叫醒过，转报 coding-assistant
                bot = rr["bot"].get(sent[0]) or "?"
                log("agent_idle | %s | orca-wake 要补叫醒（%s），但派活 bot %s 不在 enabled-bots 里，只写了影子日志；转报 %s" % (
                    key, desc, bot, FALLBACK_BOT))
                r["addf"](IDLE, "%s；orca-wake 判定这次停顿要补叫醒，但派活 bot %s 不在 enabled-bots 里（影子模式），没发出去。"
                                "请转达 %s，或把它加进 ~/.config/orca-wake/enabled-bots" % (r["note"], bot, bot), marker,
                          to=FALLBACK_BOT)
            elif sent:
                bot = rr["bot"].get(sent[0]) or "?"
                shadow = not ("*" in rr["enabled"] or bot in rr["enabled"])
                log("agent_idle | %s | %sorca-wake 补叫醒（%s；派活 bot：%s，%s）" % (
                    key, (r["note"] + "；needs_input，") if r.get("waiting") else "", desc, bot, "dry-run，不发" if DRY else "不在 enabled-bots 里，影子模式只写 wake.log" if shadow
                    else "已交给 orca-wake 发送；下次扫描再 recheck，already_woken 才算送达（发送失败它会重发同一个去重键）"))
                # 不写 notified：发送是 detached 的，这时还不知道送没送到（PER-67 F1，以前这里记 notified，失败后永远不再补）
                since = r.get("since") or NOW
                known[key] = {"kind": IDLE, "marker": marker, "handed": NOW, "handed_since": since, "to": bot,
                              "via": "orca-wake", "shadow": shadow}
                since = min(since, marker or since)  # 从这次停下算（PER-67 F6），要求之前交出过一次（r["since"]）
                if r.get("since") and NOW - since >= ESCALATE_MIN * 60 and bot != FALLBACK_BOT:
                    # 交出这么久还没 already_woken：派活 bot 的 webhook 多半坏了，改报 coding-assistant（经复核；PER-67 F4）。
                    # 送达后 send_all 记 notified，之后不再 recheck。
                    log("agent_idle | %s | 从 %s 停下起 %s 一直没收到 orca-wake 的补叫醒（%.0f 分钟），转报 %s" % (
                        key, hm(since), bot, (NOW - since) / 60.0, FALLBACK_BOT))
                    r["addf"](IDLE, "%s；从 %s 停下起，orca-wake 给派活 bot %s 的补叫醒 %.0f 分钟一直没送达（它的 webhook 可能坏了），"
                                    "转给 %s：请转达 %s 或看它的服务" % (r["note"], hm(since), bot, (NOW - since) / 60.0,
                                                              FALLBACK_BOT, bot), marker, to=FALLBACK_BOT)
            elif "already_woken" in res.values():
                log("agent_idle | %s | orca-wake 已经叫醒过这次停顿，不再发（%s）" % (key, desc))
                known[key] = {"kind": IDLE, "marker": marker, "dismissed": NOW, "reason": "orca-wake 已叫醒过这次停顿"}
            elif "already_asked" in res.values():
                log("agent_idle | %s | %s；hook 已送达这次对话框的 needs_input，不再发（%s）" % (key, r["note"], desc))
                known[key] = {"kind": IDLE, "marker": marker, "dismissed": NOW,
                              "reason": "hook 已送达这次对话框的 needs_input"}
            elif DRY:
                log("agent_idle | %s | dry-run：orca-wake 不会补叫醒（%s），实际运行时按 recheck 结果决定是否走老办法" % (
                    key, desc or "没有候选"))
            elif all(v in ("no_state_for_pid", "parent_changed") for v in res.values()):
                if r["add"] is None:  # Orca 状态是 working 的那类：旧逻辑本来就不报，这里也不报
                    log("agent_idle | %s | %s；orca-wake 没有这个会话的记录（%s），不报" % (key, r["note"], desc))
                    continue
                r["add"](IDLE, r["note"] + "；orca-wake 没有这个会话的叫醒记录（%s），按老办法报" % desc, marker)
            else:  # recent_activity、agent_gone 或没拿到结果
                log("agent_idle | %s | orca-wake 这次不补叫醒（%s），下次再查" % (key, desc))
    return found, eligible, len(eligible)


# ---- 一 b、Linear due date 对账 ----
DUE_GRACE_MIN = float(os.environ.get("STUCK_DUE_GRACE_MIN", "30"))
BOT_LABEL = re.compile(r"^\s*bot\s*[:：]\s*(\S+)\s*$", re.I)
BOT_LINE = re.compile(r"负责\s*bot\s*[:：]\s*([\w.\-]+)", re.I)


def due_bot(iss, wss):
    """负责 bot：issue 标签「bot:<名字>」→ 描述里「负责 bot：<名字>」→ 关联工作区 → orca-projects.md 的 Linear 编号。"""
    for lb in iss.get("labels") or []:
        m = BOT_LABEL.match(lb.get("name") if isinstance(lb, dict) else str(lb))
        if m:
            return BOT_SLUG.get(m.group(1), m.group(1))
    m = BOT_LINE.search(iss.get("description") or "")
    if m:
        return BOT_SLUG.get(m.group(1), m.group(1))
    for h, w in wss:
        b = bot_for(w.get("repoId"), w.get("repo"), MAP_ID.get(w.get("repoId"), {}).get("slug"), iss["identifier"],
                    w.get("displayName"))
        if b != "未映射":
            return b
    b = MAP_LINEAR.get(iss["identifier"])
    return BOT_SLUG.get(b, b) if b else FALLBACK_BOT


def started_at(ident):
    """issue 最近一次进 In Progress 的时间（Linear 活动记录）；查不到返回 None。"""
    res, _ = orca_json(["linear", "issue", ident, "--activity"], tries=2)
    best = None
    for a in (res or {}).get("activity") or []:
        for ch in a.get("changes") or []:
            if ch.get("field") == "state" and ((ch.get("to") or {}).get("name") or "").lower() == "in progress":
                t = iso_ts(a.get("createdAt"))
                if t and (best is None or t > best):
                    best = t
    return best


def check_due(hosts, track):
    """有 due date 的 Linear issue：
    In Progress 超过 DUE_GRACE_MIN 分钟，还没有工作区或工作区里没有 agent 在跑 → 叫醒负责的 bot（due_no_agent）；
    过了 due（当天 23:59 SGT 之后）还没进 In Review / Done → 叫醒 coding-assistant（due_overdue）。
    每个 issue、每种情况、每个 due date（due_no_agent 还加上进 In Progress 的时间）只报一次。返回直发列表。"""
    issues, ok = [], True
    for st in ("started", "unstarted"):
        res, err = orca_json(["linear", "list-issues", "--state", st, "--workspace", "all"], tries=2)
        if res is None:
            log("Linear 查询失败（%s），这次不对 due date" % (err or "")[:160])
            ok = False
            break
        issues += [i for i in res.get("issues") or [] if i.get("dueDate")]
    seen = track.setdefault("due", {})
    if not ok:
        return []
    out, live = [], set()
    today = datetime.datetime.now(SGT).date()
    for iss in issues:
        ident, sname = iss["identifier"], ((iss.get("state") or {}).get("name") or "").lower()
        if "review" in sname:
            continue
        rx = re.compile(r"(?<![A-Za-z0-9])%s(?![0-9])" % re.escape(ident), re.I)
        wss = [(h, w) for h in hosts for w in h["worktrees"]
               if not w.get("isArchived") and (w.get("linkedLinearIssue") == ident or rx.search(
                   "%s %s" % (w.get("displayName") or "", w.get("branch") or "")))]
        running = [(h, w) for h, w in wss if (w.get("agents") and (w.get("liveTerminalCount") or h["terms"].get(w["path"])))
                   or any(t.get("agentIdentity") for t in h["terms"].get(w["path"]) or [])]
        bot = due_bot(iss, wss)
        task = "%s %s" % (ident, iss.get("title") or "")
        where = "；".join("%s:%s" % (h["label"], w["path"]) for h, w in wss) or "没有工作区"
        due = iss["dueDate"]
        try:
            late = today > datetime.date.fromisoformat(due[:10])
        except ValueError:
            late = False

        def add(kind, to, note, k):
            live.add(k)
            if k in seen or k in {d["id"] for d in out}:
                return
            log("due | %s | %s | %s | %s" % (kind, to, task, note))
            out.append({"id": k, "cfg": "bot:" + to, "after": {"due": [k, {"sent": NOW}]}, "payload": {
                "bot": to, "task": task, "worktree": where, "status": "stuck", "kind": kind, "issue": ident,
                "due": due, "note": note, "machine": "Linear", "source": "stuck-check"}})

        if late:
            add(DUE_LATE, FALLBACK_BOT, "%s due %s 已过，还没进 In Review（现在是 %s，负责 bot：%s，%s）" % (
                ident, due, (iss.get("state") or {}).get("name"), bot,
                "agent 还在跑" if running else "没有 agent 在跑"), "due:%s:%s:%s" % (DUE_LATE, ident, due))
        if sname != "in progress" or running:
            continue
        since = started_at(ident) or iso_ts(iss.get("updatedAt"))
        if since is None or (NOW - since) / 60.0 < DUE_GRACE_MIN:
            continue
        add(DUE_IDLE, bot, "%s 已 In Progress %.0f 分钟（due %s），%s。还在做就起 agent 接着做；等人就改状态" % (
            ident, (NOW - since) / 60.0, due, "没有工作区" if not wss else "工作区里没有 agent 在跑（%s）" % where),
            "due:%s:%s:%s:%d" % (DUE_IDLE, ident, due, since))
    for k in [k for k in seen if k not in live]:
        del seen[k]  # issue 已经交了、改了 due 或不再是这种情况，下次再出现时重新报
    log("due：有 due 的未完成 issue %d 个，新要报 %d 条" % (len(issues), len(out)))
    return out


# ---- 二、报了没人验收（completed / in-review） ----
GIT_FACTS = r'''for p in "$@"; do
  cd "$p" 2>/dev/null || { echo "G $(printf %s "$p" | base64 | tr -d '\n') - -"; continue; }
  d=$(git status --porcelain 2>/dev/null | head -n1 | wc -l | tr -d ' ')
  b=""; for r in origin/HEAD origin/main origin/master upstream/main upstream/master; do
    git rev-parse -q --verify "$r^{commit}" >/dev/null 2>&1 && { b=$r; break; }; done
  if [ -n "$b" ]; then n=$(git rev-list --count HEAD --not "$b" 2>/dev/null); else n=$(git rev-list --count HEAD --not --remotes 2>/dev/null); fi
  echo "G $(printf %s "$p" | base64 | tr -d '\n') ${d:--} ${n:--}"
done
python3 - "$@" <<'WAKEPY'
# 这台机器上，每个工作区最后一次停下有没有送达（2xx）过叫醒（PER-67 F3）。读 orca-wake 的会话状态和 notify-run.log：
#   最后一次停下 = 工作区里最新的 orca-wake 会话（cwd 在工作区内，按 last_event_ts）的当前回合，或它之后 notify-run 的退出发送。
#   W <路径 b64> ok|no|none <说明 b64>：ok 送达过；no 有记录但这次停下没送达；none 没有记录（不是经 notify-run 起的）。
import base64, datetime, glob, json, os, sys
H = os.path.expanduser("~")
sd = os.environ.get("ORCA_WAKE_STATE_DIR") or os.path.join(H, ".local/state/orca-wake")
nl = os.environ.get("NOTIFY_RUN_LOG") or os.path.join(H, ".orca-state/notify-run/notify-run.log")
b64 = lambda t: base64.b64encode(t.encode()).decode()
hm = lambda t: datetime.datetime.fromtimestamp(t).strftime("%m-%d %H:%M")
sess, nr = [], []
for f in glob.glob(os.path.join(sd, "sessions", "*.json")):
    try:
        d = json.load(open(f, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if isinstance(d, dict) and d.get("cwd"):
        sess.append(d)
try:
    for ln in open(nl, encoding="utf-8", errors="replace"):
        c = ln.rstrip("\n").split("\t")
        try:
            ts = datetime.datetime.strptime(c[0], "%Y-%m-%dT%H:%M:%S%z").timestamp()
        except ValueError:
            continue
        nr.append((ts, dict(x.split("=", 1) for x in c[1:] if "=" in x)))
except OSError:
    pass
for p in sys.argv[1:]:
    rp = os.path.realpath(p)
    inside = lambda c: bool(c) and (os.path.realpath(c) + "/").startswith(rp + "/")
    s = max((d for d in sess if inside(d["cwd"])), key=lambda d: d.get("last_event_ts") or 0, default=None)
    n = max((x for x in nr if inside(x[1].get("ws"))), key=lambda x: x[0], default=None)
    if s is None and n is None:
        print("W %s none %s" % (b64(p), b64("没有 orca-wake / notify-run 记录")))
        continue
    ts_s = (s or {}).get("last_event_ts") or 0
    seq = str((s or {}).get("turn", 0))
    woke = s is not None and seq in (s.get("woken") or {})
    nr_ok = n is not None and n[0] >= ts_s and len(n[1].get("http", "")) == 3 and n[1]["http"].startswith("2")
    why = []
    if s is not None:
        why.append("%s 会话最后一次停下（第 %s 回合，%s）%s" % (s.get("agent"), seq, hm(ts_s), "送达过叫醒" if woke else "没有送达的叫醒"))
    if n is not None and n[0] >= ts_s:
        why.append("notify-run 退出时发送 http=%s（%s）" % (n[1].get("http"), hm(n[0])))
    print("W %s %s %s" % (b64(p), "ok" if woke or nr_ok else "no", b64("；".join(why))))
WAKEPY
'''


def git_facts(host, paths):
    """返回 (git, wake)。git：工作区 → (有没有未提交改动, 比远端默认分支多几个提交)；wake：工作区 → (ok|no|none, 说明)，
    最后一次停下有没有送达过叫醒（见 GIT_FACTS 里的 WAKEPY）。查不到的不在结果里。box 上走一个临时终端一次查完。
    没有远端默认分支时，数不在任何远端分支上的提交。"""
    if not paths:
        return {}, {}
    if host["env"] is None:
        rc, text, err = run(["bash", "-c", GIT_FACTS, "git-facts"] + paths, 120)
    else:
        script = "set -- %s\n%s" % (" ".join(shlex.quote(p) for p in paths), GIT_FACTS)
        script = 'echo @@GIT""-BEGIN; { %s} 2>&1 | gzip -c | base64; echo @@GIT""-END\n' % script
        cmd = "echo %s | base64 -d | bash" % base64.b64encode(script.encode()).decode()
        raw, err = box_run(host["env"], cmd, "stuck-check git", r"^@@GIT-END", 40)
        m = re.findall(r"@@GIT-BEGIN(.*?)@@GIT-END", raw or "", re.S)
        try:
            text = gzip.decompress(base64.b64decode("".join(m[-1].split()))).decode("utf-8", "replace")
        except (IndexError, ValueError, OSError):
            text = ""
    out, wake = {}, {}
    for ln in (text or "").splitlines():
        f = ln.split()
        try:
            if len(f) == 4 and f[0] == "G" and f[2].isdigit() and f[3].isdigit():
                out[base64.b64decode(f[1]).decode()] = (f[2] != "0", int(f[3]))
            elif len(f) == 4 and f[0] == "W" and f[2] in ("ok", "no", "none"):
                wake[base64.b64decode(f[1]).decode()] = (f[2], base64.b64decode(f[3]).decode())
        except ValueError:
            pass
    if len(out) < len(paths):
        log("%s：%d 个工作区的 git 状态没查到（%s），这些照旧报" % (host["label"], len(paths) - len(out), (err or "")[:120]))
    return out, wake


def check_reported(host):
    label, env = host["label"], host["env"]
    repos, err = orca_json(["repo", "list"], env, tries=3)
    if repos is None:
        # 10-18 13:05 box 隧道刚断，repo list 失败，box 上 ops 仓库（不在 orca-projects.md 里）被当成「没有 GitHub 远端」误报
        log("%s：repo list 失败（%s），这次不查「报了没人验收」，免得把仓库当成没有远端" % (label, (err or "")[:160]))
        return [], 0
    repos = repos.get("repos") or []
    slug_of = {}
    for r in repos:
        key = (r.get("gitRemoteIdentity") or {}).get("canonicalKey") or ""
        if key.startswith("github.com/"):
            slugs = [key[len("github.com/"):]]
            up = r.get("upstream") or {}
            if up.get("owner") and "%s/%s" % (up["owner"], up["repo"]) not in slugs:
                slugs.append("%s/%s" % (up["owner"], up["repo"]))
            user = GH_USER or r.get("gitUsername")  # fork 上的 PR 也算
            if user and slugs[0].split("/")[0] != user:
                slugs.append("%s/%s" % (user, slugs[0].split("/")[1]))
            slug_of[r["id"]] = slugs
    found, scanned, clean_check = [], 0, []
    for w in host["worktrees"]:
        status = w.get("workspaceStatus")
        if not is_task_ws(w) or status not in ("completed", "in-review"):
            continue
        scanned += 1
        if DRY:
            log("查（二）| %s:%s | %s" % (label, w["path"], status))
        linear = w.get("linkedLinearIssue")
        lstate, lts = linear_state(linear) if linear else (None, None)
        if lstate == "canceled":
            continue
        if any(a.get("state") == "working" for a in w.get("agents") or []):
            continue  # 被叫回去返工
        wz = waiting_zack(w) if status == "in-review" else None
        if wz:  # 10-19 03:34 PER-56 MBA 卡已验收、等 Zack 回答，每次都被算成没人验收
            log("等 Zack | %s:%s | %s 挂着「等 Zack」，已验收在等拍板，不报" % (label, w["path"], wz))
            continue
        branch = (w.get("branch") or "").replace("refs/heads/", "")
        slugs = slug_of.get(w.get("repoId")) or []
        if not slugs and MAP_ID.get(w.get("repoId"), {}).get("slug"):
            slugs = [MAP_ID[w["repoId"]]["slug"]]
        bot = bot_for(w.get("repoId"), w.get("repo"), slugs[0] if slugs else None, linear, w.get("displayName"))
        task = task_name(w)
        where = "%s:%s" % (label, w["path"])

        def add(note, bot=bot, task=task, where=where):  # 绑定当前值：completed 的要等循环后统一判断
            found.append({"bot": bot, "task": task, "worktree": where, "status": REPORTED, "note": note})

        pr, pr_ok = (None, False)
        if slugs and branch:
            pr, pr_ok = find_pr(slugs, branch, (w.get("linkedPR") or {}).get("number"))
        if pr:
            age = hours(iso_ts(pr["createdAt"]), ms=False)
            if pr["state"] == "OPEN" and not reviewed(pr) and age is not None and age > THRESH_H:
                add("agent 已开 PR %.1f 小时，没有 review，也没有人评论：%s" % (age, pr["url"]))
            continue  # PR 有人看过、已合并或已关闭，算验收过
        if slugs and not pr_ok:
            continue  # PR 查询失败，不误报
        if (w.get("linkedPR") or {}).get("state") in ("merged", "closed"):
            continue  # Orca 记着关联 PR 已合并或关闭（远端查不到时的兜底）
        signals, reported_at = ["工作区标为 %s" % status], [(w.get("lastActivityAt") or 0) / 1000.0]
        if lstate == "completed":
            signals.append("Linear %s 已完成" % linear)
            reported_at.append(lts or 0)
        marker = done_marker(w["path"]) if env is None and os.path.isdir(w["path"]) else None
        if marker:
            signals.append("有标记 %s" % marker[0])
            reported_at.append(marker[1])
        age = hours(max(reported_at), ms=False) if max(reported_at) > 0 else None
        if age is None or age > THRESH_H:
            note = "%s，%s没人验收（没有 PR，分支 %s%s）" % (
                "；".join(signals), "已 %.1f 小时" % age if age is not None else "",
                branch or "?", "" if slugs else "，仓库没有 GitHub 远端")
            if status == "completed":
                clean_check.append((w["path"], add, note))  # 先看工作区干不干净，见下
            else:
                add(note)
    # completed、工作区干净、比远端默认分支没有多出提交、也没有 PR：没有东西要验收，放行（不靠备注写「已验收」）。
    # 但最后一次停下没送达过叫醒的照报：有后台 shell 时 Stop / idle_prompt 都不发，派活 bot 不知道它停了（PER-67 F3）。
    # 没有 orca-wake / notify-run 记录（不是经 notify-run 起的，另有 agent_unwrapped 管）或这项没查到的，照旧放行。
    facts, wake = git_facts(host, [p for p, _, _ in clean_check])
    for p, add, note in clean_check:
        f, wk = facts.get(p), wake.get(p)
        if f and not f[0] and f[1] == 0:
            if wk and wk[0] == "no":
                add(note + "（工作区干净，但%s：派活 bot 可能不知道它停了）" % wk[1])
                continue
            log("放行 | %s:%s | completed，工作区干净，没有本地提交，没有 PR；%s" % (
                label, p, wk[1] if wk else "叫醒记录没查到"))
            continue
        add(note + ("（%s）" % "，".join(x for x in ("有未提交改动" if f[0] else "", "%d 个提交不在远端默认分支" % f[1] if f[1] else "") if x) if f else ""))
    return found, scanned


def merge_reported(due):
    """一次检查只发一条：只有一个问题时原样发，多个问题合并，note 里逐条列出。"""
    if len(due) == 1:
        return dict(due[0])
    uniq = lambda k: list(dict.fromkeys(p[k] for p in due))
    return {"bot": "、".join(uniq("bot")), "task": "卡住工作检查：%d 条" % len(due), "worktree": "多个（见 note）",
            "status": REPORTED,
            "note": "共 %d 条 %s：\n" % (len(due), REPORTED) + "\n".join(
                "%d. [%s] %s | %s | %s" % (i, p["bot"], p["task"], p["worktree"], p["note"])
                for i, p in enumerate(due, 1))}


# ---- 三、别的自动任务的 .due/.ok ----
def check_markers(track):
    out = []
    alerted = track.setdefault("markers", {})

    def num(path):
        try:
            return int(open(path).read().split()[0])
        except (OSError, ValueError, IndexError):
            return 0

    for name, title in MARKERS.items():
        due, ok = num(os.path.join(RUNS_DIR, name + ".due")), num(os.path.join(RUNS_DIR, name + ".ok"))
        if not due or ok >= due:
            alerted.pop(name, None)
            continue
        late = (NOW - due) / 60.0
        if late < MARKER_GRACE_MIN or alerted.get(name) == due:
            continue
        fmt = lambda t: datetime.datetime.fromtimestamp(t, SGT).strftime("%m-%d %H:%M")
        out.append({"id": "marker:%s:%d" % (name, due), "cfg": "fallback", "payload": {
            "bot": FALLBACK_BOT, "task": "自动任务没跑完：%s" % title, "worktree": "iMac:%s" % RUNS_DIR,
            "status": "stuck", "kind": "automation_no_ok", "machine": "iMac", "source": "stuck-check",
            "note": "%s 在 %s 开始（%s.due），过了 %.0f 分钟还没有成功标记（%s.ok %s）。看 Orca 里这次运行的会话。" % (
                title, fmt(due), name, late, name, "停在 " + fmt(ok) if ok else "不存在")},
            "after": {"marker": [name, due]}})
    return out


# ---- 发送 ----
def bot_cfg(bot):
    """bot → (实际发给谁, 配置)。没有对应 env 文件的发给 coding-assistant，再没有就用兜底 webhook。"""
    for name in ([FORCE_BOT] if FORCE_BOT else [bot, FALLBACK_BOT]):
        cfg = read_env(os.path.join(WEBHOOK_DIR, "%s.env" % name)) if re.fullmatch(r"[A-Za-z0-9._-]+", name or "") else None
        if cfg:
            return name, cfg
    return FALLBACK_BOT, read_env(ENV_FILE)


def agent_payload(s, to):
    return {"bot": to, "task": s["task"], "worktree": s["worktree"], "status": "stuck", "kind": s["kind"],
            "note": s["note"] + ("（按映射应归 %s，没有它的 webhook，转给 %s）" % (s["bot"], to) if to != s["bot"] and not FORCE_BOT else ""),
            "machine": s["machine"], "source": "stuck-check"}


def hm(t):
    return datetime.datetime.fromtimestamp(t, SGT).strftime("%m-%d %H:%M")


def escalate(fails, iid, to, note, marker=None):
    """发给 to 的这一条失败过，而且从这次停下（marker；没有就从第一次失败）起已满 ESCALATE_MIN 分钟：改发 coding-assistant
    （PER-67 F4、F6）。返回 (to, cfg, note)，不改发时 cfg 为 None。"""
    since = fails.get(iid)
    if since is not None and marker:
        since = min(since, marker)
    if FORCE_BOT or to == FALLBACK_BOT or since is None or NOW - since < ESCALATE_MIN * 60:
        return to, None, note
    log("改报 | %s | 发给 %s 从 %s 起一直失败（%.0f 分钟），改发 %s" % (iid, to, hm(since), (NOW - since) / 60.0, FALLBACK_BOT))
    to2, cfg = bot_cfg(FALLBACK_BOT)
    return to2, cfg, note + "（原本发给 %s，没发出去；从 %s 起 %.0f 分钟了，转给 %s）" % (
        to, hm(since), (NOW - since) / 60.0, to2)


def send_all(pending, known, track, seen):
    """发 pending 里的东西并更新状态。返回失败条数。一条重试后仍失败，这次运行里发给同一个目标的不再发，
    发给别的目标的照发（PER-67 F5：以前一条失败其余全停，一个坏掉的 bot 挡住所有人，包括 Coding助手）。
    发给某个 bot 的一条从第一次失败起满 ESCALATE_MIN 分钟还没发出去，改发 coding-assistant（F4）。"""
    failed, broken = 0, set()  # broken：这次运行里已经失败过的目标
    fails = track.setdefault("post_fail", {})  # 条目 → 第一次发送失败的时间（成功后删掉，24 小时没再失败的也删）
    for k in [k for k, v in fails.items() if NOW - v > 86400]:
        del fails[k]
    left_direct, left_suspects = [], []
    for d in pending.get("direct", []):
        if d["cfg"].startswith("bot:"):  # 发给负责的 bot；没有它的 webhook 时转 coding-assistant
            want = d["cfg"][4:]
            to, cfg = bot_cfg(want)
            d["payload"]["bot"] = to
            if to != want and not FORCE_BOT and "（按映射应归" not in d["payload"]["note"]:
                d["payload"]["note"] += "（按映射应归 %s，没有它的 webhook，转给 %s）" % (want, to)
            to2, cfg2, note2 = escalate(fails, d["id"], to, d["payload"]["note"],
                                        ((d.get("after") or {}).get("known") or [None, {}])[1].get("marker"))
            if cfg2:
                to, cfg, d["cfg"] = to2, cfg2, "fallback"
                d["payload"].update(bot=to, note=note2)
        else:
            to = "stuck-webhook" if d["cfg"] == "stuck" else FALLBACK_BOT
            cfg = read_env(ENV_FILE) if d["cfg"] == "stuck" else bot_cfg(FALLBACK_BOT)[1]
        if cfg is None:
            log("webhook 未配置，只记日志不发：%s" % d["payload"]["task"])
            continue
        if DRY:
            log("dry-run，将 POST：%s" % json.dumps(d["payload"], ensure_ascii=False))
            continue
        if to in broken or not post(cfg, d["payload"], d["payload"]["task"]):
            failed = failed + 1
            broken.add(to)
            fails.setdefault(d["id"], NOW)
            left_direct.append(d)
            continue
        fails.pop(d["id"], None)
        after = d.get("after") or {}
        if "marker" in after:
            track.setdefault("markers", {})[after["marker"][0]] = after["marker"][1]
        if after.get("box_alert"):
            track["box_alerted"] = True
        if after.get("mba_alert"):
            track["mba_alerted"] = True
        for k in after.get("seen") or []:
            seen[k] = {"notified": NOW, "last_seen": NOW}
        if after.get("known"):
            k, rec = after["known"]
            known[k] = dict(rec, notified=NOW, to=d["payload"]["bot"])
        if after.get("due"):
            track.setdefault("due", {})[after["due"][0]] = after["due"][1]
        for k, rec in after.get("unwrapped") or []:
            track.setdefault("unwrapped", {})[k] = rec
        if after.get("undelivered"):
            track.setdefault("undelivered", {})[after["undelivered"]] = NOW
    for s in pending.get("suspects", []):
        why = DISMISS.get(s.get("id", ""))
        if why:
            log("排除 %s | %s | %s：%s" % (s["id"], s["kind"], s["worktree"], why))
            known[s["key"]] = {"kind": s["kind"], "marker": s["marker"], "dismissed": NOW, "reason": why}
            continue
        to, cfg = bot_cfg(s["bot"])
        if cfg is None:
            log("webhook 未配置，只记日志不发：%s" % s["worktree"])
            continue
        payload = agent_payload(s, to)
        iid = "suspect:%s:%s" % (s["kind"], s["key"])
        to2, cfg2, note2 = escalate(fails, iid, to, payload["note"], s.get("marker"))
        if cfg2:
            to, cfg = to2, cfg2
            payload.update(bot=to, note=note2)
        if DRY:
            log("dry-run，将 POST 给 %s：%s" % (to, json.dumps(payload, ensure_ascii=False)))
            continue
        if to in broken or not post(cfg, payload, "%s %s → %s" % (s["kind"], s["worktree"], to)):
            failed = failed + 1
            broken.add(to)
            fails.setdefault(iid, NOW)
            left_suspects.append(s)
            continue
        fails.pop(iid, None)
        known[s["key"]] = {"kind": s["kind"], "marker": s["marker"], "notified": NOW, "to": to}
    pending["direct"], pending["suspects"] = left_direct, left_suspects
    return failed


def show_pending(pending):
    sus = pending.get("suspects") or []
    if pending.get("error"):
        print("上次扫描出错：%s" % pending["error"])
    if pending.get("direct"):
        print("有 %d 条直发消息上次没发出去，--send 时会补发。" % len(pending["direct"]))
    if not sus:
        print("没有等复核的嫌疑。")
        return
    print("等复核的嫌疑 %d 条（扫描时间 %s）：" % (len(sus), datetime.datetime.fromtimestamp(
        pending.get("created", 0), SGT).strftime("%F %T SGT")))
    for s in sus:
        envflag = " --environment %s" % s["env"] if s.get("env") else ""
        print("\n%s | %s | 派活 bot：%s | %s\n  工作区：%s\n  脚本的判断：%s" % (
            s["id"], s["kind"], s["bot"], s["task"], s["worktree"], s["note"]))
        for h in s.get("terminals") or []:
            print("  复核：orca terminal read --terminal %s --screen --limit 40%s" % (h, envflag))
        if not s.get("terminals"):
            print("  复核：orca worktree ps%s --json（这个工作区没有可读的 agent 终端）" % envflag)


def main():
    global GH_USER, SCAN_DONE
    pending = load_json(PENDING_FILE, {})
    if MODE == "--list":
        show_pending(pending)
        return 0
    known = load_json(AGENTS_FILE, {})
    track = load_json(TRACK_FILE, {})
    track.setdefault("screens", {})
    seen = load_json(SEEN_FILE, {})
    seen = {k: v for k, v in seen.items() if isinstance(v, dict) and NOW - v.get("last_seen", 0) < FORGET_H * 3600}

    if MODE == "--send" and not pending.get("error"):
        log("开始发送（pending：%d 条嫌疑，%d 条直发）" % (len(pending.get("suspects") or []), len(pending.get("direct") or [])))
        failed = send_all(pending, known, track, seen)
        save_json(AGENTS_FILE, known), save_json(TRACK_FILE, track), save_json(SEEN_FILE, seen)
        save_json(PENDING_FILE, pending)
        log("发送结束：%d 条失败%s" % (failed, "，留在 pending 里下次再发" if failed else ""))
        return 3 if failed else 0
    DISMISS.clear()  # 走到这里是重新扫描，旧编号对不上

    log("开始%s（orca=%s，等输入/无输出阈值 %.0f 分钟）" % ({"--dry-run": "（dry-run）", "--scan": "（scan）"}.get(MODE, ""),
                                               os.path.basename(ORCA), IDLE_MIN))
    hosts = []
    imac, err = load_host("iMac", None)
    if imac is None:
        log("iMac Orca 查询失败：%s" % err)
        pending = {"created": NOW, "error": "iMac Orca 查询失败：%s" % err, "suspects": [],
                   "direct": pending.get("direct") or []}
        save_json(PENDING_FILE, pending)
        if MODE == "--scan":
            touch_due()
            return 0
        return 2
    hosts.append(imac)
    direct = list(pending.get("direct") or [])
    remote = {"box": box_env_name(), "MBA": mba_env_name()}
    for label, env in remote.items():
        if not env:
            log("%s：没有配好的 Orca environment，跳过" % label)
            continue
        host = load_remote(label, env, direct, track)
        if host:
            hosts.append(host)
    checked = {h["label"] for h in hosts}

    # 一、卡住的 agent
    suspects, eligible = [], set()
    have = {d["id"] for d in direct}
    for h in hosts:
        found, elig, n = check_agents(h, known, track)
        eligible |= elig
        nb = 0
        for s in found:
            if s["kind"] != BROKEN:
                suspects.append(s)
                continue
            nb += 1  # 没有终端可读，不用复核，直接叫醒
            log("断了 | %s | %s | %s | %s" % (s["bot"], s["task"], s["worktree"], s["note"]))
            if "broken:" + s["key"] not in have:
                direct.append({"id": "broken:" + s["key"], "cfg": "bot:" + s["bot"],
                               "payload": agent_payload(s, s["bot"]),
                               "after": {"known": [s["key"], {"kind": BROKEN, "marker": s["marker"]}]}})
        log("%s：in-progress 任务工作区和主目录 agent %d 个，新嫌疑 %d 个，断了的 %d 个" % (h["label"], n, len(found) - nb, nb))
        # 没经 notify-run 起的 agent（每次都查，要跑一次 agent-probe）
        pend = {k for d in direct for k, _ in (d.get("after") or {}).get("unwrapped") or []}
        uw = check_unwrapped(h, track, pend)
        have = {d["id"] for d in direct}
        direct += [d for d in uw if d["id"] not in have]
        log("%s：没包 notify-run 的 agent 新报 %d 条" % (h["label"], len(uw)))
        ud = check_undelivered(h, track)
        have = {d["id"] for d in direct}
        direct += [d for d in ud if d["id"] not in have]
    for k in [k for k in known if k.split(":", 1)[0] in checked and k not in eligible]:
        del known[k]  # 工作区已经不是 in-progress 或不在了
    track["screens"] = {h: r for h, r in track["screens"].items() if NOW - r.get("seen", 0) < 6 * 3600}
    # 一 b、due date 对账（box 或 MBA 连不上时看不全工作区，不对）
    missed = [l for l, e in remote.items() if e and l not in checked]
    if missed:
        log("%s 这次没查到，不对 due date" % "、".join(missed))
    else:
        have = {d["id"] for d in direct}
        direct += [d for d in check_due(hosts, track) if d["id"] not in have]
    for i, s in enumerate(suspects, 1):
        s["id"] = "S%d" % i
        log("嫌疑 %s | %s | %s | %s | %s | %s" % (s["id"], s["bot"], s["kind"], s["task"], s["worktree"], s["note"]))

    # 二、报了没人验收：约每小时一次
    if FULL or NOW - track.get("last_full", 0) >= 55 * 60:
        rc, out, _ = run(["gh", "api", "user", "-q", ".login"], 30)
        GH_USER = out.strip() if rc == 0 and out.strip() else None
        problems = []
        for h in hosts:
            found, n = check_reported(h)
            problems += found
            log("%s：completed / in-review 任务工作区 %d 个，%d 个没人验收" % (h["label"], n, len(found)))
        key = lambda p: "%s|%s" % (p["worktree"], p["status"])
        for p in problems:
            log("问题 | %s | %s | %s | %s | %s" % (p["bot"], p["status"], p["task"], p["worktree"], p["note"]))
            if key(p) in seen:
                seen[key(p)]["last_seen"] = NOW
        due = [p for p in problems if key(p) not in seen]
        if due:
            direct = [d for d in direct if d["id"] != "reported"]
            direct.append({"id": "reported", "cfg": "stuck", "payload": merge_reported(due),
                           "after": {"seen": [key(p) for p in due]}})
        track["last_full"] = NOW

    # 三、别的自动任务的标记
    have = {d["id"] for d in direct}
    for m in check_markers(track):
        log("标记 | %s" % m["payload"]["note"])
        if m["id"] not in have:
            direct.append(m)

    pending = {"created": NOW, "suspects": suspects, "direct": direct}
    SCAN_DONE = True  # 扫完了（发送失败不算没扫完）：心跳的 last_scan 前进
    if MODE == "--scan":
        pending["suspects"] = []
        failed = send_all(pending, known, track, seen)
        pending["suspects"] = suspects
        save_json(AGENTS_FILE, known), save_json(TRACK_FILE, track), save_json(SEEN_FILE, seen)
        save_json(PENDING_FILE, pending)
        if suspects or failed:
            touch_due()
            log("scan 结束：%d 条嫌疑等复核，%d 条直发失败 → 启动 agent" % (len(suspects), failed))
            return 0
        log("scan 结束：没有嫌疑，不启动 agent")
        return 1
    failed = send_all(pending, known, track, seen)
    save_json(AGENTS_FILE, known), save_json(TRACK_FILE, track), save_json(SEEN_FILE, seen)
    save_json(PENDING_FILE, pending)
    log("结束：%d 条嫌疑，%d 条直发，%d 条发送失败" % (len(suspects), len(direct), failed))
    return 3 if failed else 0


def load_remote(label, env, direct, track):
    """查一台远端 Orca（box / MBA）：第一轮 3 次都没连上就等 BOX_RETRY_WAIT 秒再查一轮；连续 2 次查不到，
    往 direct 里加一条「连不上」发给 FALLBACK_BOT（只报一次，连上后重置）。返回 host 或 None。"""
    k = label.lower()  # track 里的键和直发编号：box_fail / box-unreachable，mba_fail / mba-unreachable
    PROBE_WT[env] = MBA_PROBE_WT if k == "mba" else BOX_PROBE_WT
    host, err = load_host(label, env)
    if host is None and BOX_RETRY_WAIT > 0:
        log("%s（--environment %s）第一轮 3 次都没连上（%s），等 %.0f 秒再查一轮" % (label, env, (err or "")[:120], BOX_RETRY_WAIT))
        time.sleep(BOX_RETRY_WAIT)
        host, err = load_host(label, env)
        if host is not None:
            log("%s 第二轮连上了，不算失败" % label)
    if host is None:
        track[k + "_fail"] = track.get(k + "_fail", 0) + 1
        log("%s（--environment %s）重试 3 次仍查询失败，这次跳过（连续第 %d 次）：%s" % (
            label, env, track[k + "_fail"], (err or "")[:160]))
        if track[k + "_fail"] >= 2 and not track.get(k + "_alerted") and k + "-unreachable" not in {d["id"] for d in direct}:
            direct.append({"id": k + "-unreachable", "cfg": "fallback", "payload": {
                "bot": FALLBACK_BOT, "task": "%s 的 Orca 连不上" % label, "worktree": label, "status": "stuck",
                "kind": k + "_unreachable", "machine": label, "source": "stuck-check",
                "note": "卡住工作检查连续 %d 次连不上 %s 的 Orca（--environment %s，每次重试 3 次）：%s。这段时间 %s 上的工作区没人查。" % (
                    track[k + "_fail"], label, env, (err or "")[:160], label)}, "after": {k + "_alert": True}})
        return None
    track[k + "_fail"], track[k + "_alerted"] = 0, False
    direct[:] = [d for d in direct if d["id"] != k + "-unreachable"]
    return host


def box_env_name():
    if os.environ.get("STUCK_BOX_ENV"):
        return os.environ["STUCK_BOX_ENV"]
    rc, out, _ = run([ORCA, "environment", "list"], 30)
    names = [ln.split()[1] for ln in out.splitlines() if len(ln.split()) >= 2] if rc == 0 else []
    return next((n for n in ("box", "grok-bot") if n in names), None)


def mba_env_name():
    if os.environ.get("STUCK_MBA_ENV") is not None:
        return os.environ["STUCK_MBA_ENV"] or None  # 设成空串 = 不查 MBA
    rc, out, _ = run([ORCA, "environment", "list"], 30)
    names = [ln.split()[1] for ln in out.splitlines() if len(ln.split()) >= 2] if rc == 0 else []
    return next((n for n in ("mba", "MBA") if n in names), None)


def orca_ident(env):
    """这台 Orca 这次启动的身份：app 进程号 + runtimeId（box 是 headless serve，没有 app 进程号）。查不到返回 None。"""
    res, _ = orca_json(["status"], env, timeout=20)
    if not res:
        return None
    rt = (res.get("runtime") or {}).get("runtimeId")
    pid = (res.get("app") or {}).get("pid")
    return "pid:%s|rt:%s" % (pid, rt) if (pid or rt) else None


def gate():
    """--scan 的闸门。自动任务每分钟跑一次 precheck：距上次扫描满 INTERVAL_MIN 分钟，或 iMac / box / MBA 的 Orca
    重启过（进程号或 runtimeId 变了，比上次扫描时记的），才真正扫描。返回 (原因 或 None, 这次看到的身份)。"""
    g = load_json(GATE_FILE, {})
    ids = {"iMac": orca_ident(None)}
    why = None
    if NOW - g.get("last", 0) >= INTERVAL_MIN * 60 - 45:
        why = "到点"
    if ids["iMac"] and g.get("iMac") and ids["iMac"] != g["iMac"]:
        why = "iMac 的 Orca 重启过（%s → %s）" % (g["iMac"], ids["iMac"])
    for k, env in (("box", box_env_name()), ("MBA", mba_env_name())):
        if not env:
            continue
        ids[k] = orca_ident(env)
        if ids[k] and g.get(k) and ids[k] != g[k] and not why:
            why = "%s 的 Orca 重启过（%s → %s）" % (k, g[k], ids[k])
        elif ids[k] and g.get(k) and ids[k] != g[k]:
            why += "；%s 的 Orca 也重启过（%s → %s）" % (k, g[k], ids[k])
    for k in ("iMac", "box", "MBA"):
        ids[k] = ids.get(k) or g.get(k)  # 这次没查到的沿用上次的，免得下次误判成重启
    return why, ids


def touch_due():
    """给 codex 备用任务看的标记：主任务到点了。成功收尾由 agent 调 orca-ok.sh 写 .ok。"""
    if DRY:
        return
    os.makedirs(RUNS_DIR, exist_ok=True)
    with open(os.path.join(RUNS_DIR, "stuck-check.due"), "w") as f:
        f.write("%d\n" % NOW)
    try:
        os.remove(os.path.join(RUNS_DIR, "stuck-check.fb"))
    except OSError:
        pass


def heartbeat(rc):
    """每次跑完写心跳：heartbeat.json，并在 stdout 打一行 @@HB {...}。自动任务的运行记录会存 precheck 的 stdout，
    另一台机器的 heartbeat-watch 经 `orca automations runs --environment ...` 读到它，超过 N 分钟没有新的就报警。
    last_scan 是上次跑完的扫描（gate.json 的 done，main() 扫完才写）：扫描每次超时被杀或每次出错时它不再前进，
    heartbeat-watch 按「太久没扫描」报（PER-67 F7、F8；以前取扫描开始时写的 gate.last，被杀、出错也照样前进）。"""
    if MODE in ("--list", "--dry-run"):
        return
    g = load_json(GATE_FILE, {})
    hb = {"ts": int(time.time()), "mode": MODE, "rc": rc, "last_scan": int(g.get("done") or g.get("last") or 0)}
    try:
        save_json(HB_FILE, hb)
    except OSError:
        pass
    print("@@HB " + json.dumps(hb), flush=True)


def take_lock():
    """同一时间只跑一个（10-15 13:23 出过两次扫描同时跑）。拿不到锁返回 None。"""
    f = open(os.path.join(STATE_DIR, "run.lock"), "a+")
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        f.close()
        return None
    f.seek(0), f.truncate(), f.write("%d %d\n" % (os.getpid(), NOW)), f.flush()
    return f


_lock = None
_gate = None
SCAN_DONE = False
if MODE == "--scan" and os.environ.get("STUCK_NO_GATE") != "1":
    _gate = gate()
    if not _gate[0]:
        _g = load_json(GATE_FILE, {})
        if _g and any(_gate[1].get(k) and not _g.get(k) for k in ("iMac", "box", "MBA")):
            save_json(GATE_FILE, dict(_g, **{k: v for k, v in _gate[1].items() if v}))  # 上次扫描时没查到的身份先补记
        heartbeat(1)
        sys.exit(1)  # 没到点、Orca 也没重启：安静退出，不写日志
if MODE not in ("--list", "--dry-run"):
    _lock = take_lock()
    if _lock is None:
        try:
            holder = open(os.path.join(STATE_DIR, "run.lock")).read().split()
            since = "，pid %s，%.0f 秒前开始" % (holder[0], NOW - float(holder[1])) if len(holder) >= 2 else ""
        except (OSError, ValueError):
            since = ""
        log("另一个 stuck-check 还在跑（这次 %s%s），这次直接退出" % (MODE, since))
        heartbeat(1 if MODE == "--scan" else 0)  # last_scan 不变：扫描卡住时 heartbeat-watch 靠它报
        sys.exit(1 if MODE == "--scan" else 0)
if _gate:
    _g = load_json(GATE_FILE, {})
    # done = 上次跑完的扫描；还没有时（刚装、或从旧版升级）先记成上次开始扫描的时间，这次扫描卡住也照样会变旧
    save_json(GATE_FILE, dict(_gate[1], last=NOW, why=_gate[0], done=_g.get("done") or _g.get("last") or NOW))
    if _gate[0] != "到点":
        FULL = True  # Orca 刚启动：连「报了没人验收」一起查一遍
        log("Orca 启动后补查一遍：%s" % _gate[0])
try:
    rc = main()
except Exception as e:  # 脚本自己出错不能当成「没事」：scan 时照样启动 agent，由它报出来
    import traceback
    log("脚本出错：%s" % traceback.format_exc()[-1500:])
    rc, SCAN_DONE = 4, False  # 发送时出错也算没跑完
    if MODE == "--scan":
        save_json(PENDING_FILE, {"created": NOW, "error": "脚本出错：%s: %s" % (type(e).__name__, e), "suspects": [],
                                 "direct": []})
        touch_due()
        rc = 0
if SCAN_DONE and not DRY:
    save_json(GATE_FILE, dict(load_json(GATE_FILE, {}), done=int(time.time())))
heartbeat(rc)
sys.exit(rc)
PYEOF
