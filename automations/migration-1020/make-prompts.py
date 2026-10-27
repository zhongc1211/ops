#!/usr/bin/env python3
"""Build the MBA / iMac prompts of the tasks moved off box (PER-79) from the live box prompts in box-baseline/.

  python3 -I make-prompts.py          write prompts/<machine>/<task>.prompt.md
  python3 -I make-prompts.py --check  exit 1 if the committed files differ from what this script makes
  python3 -I make-prompts.py --diff   print the diff box original -> new prompt (not committed; for the reviewer)

Every replacement must match the baseline the stated number of times, so a box prompt edited after 2026-10-20 stops the
build instead of being half-converted.
"""
import difflib, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OPS = "~/orca/workspaces/ops"
MACHINES = {   # main checkouts per `orca worktree list --json` isMainWorktree, 2026-10-20
    "mba": {"label": "MBA（macOS）", "repos": {"xinyue-site": "~/orca/projects/xinyue-site", "deepvision-site": "~/orca/projects/deepvision-site",
                                             "deepvision-ads": "~/orca/projects/deepvision-ads", "vllm-omni": "~/orca/projects/vllm-omni"}},
    "imac": {"label": "iMac（macOS，MBA 错过时的备用）", "repos": {"xinyue-site": "~/pi/remote/xinyue-site", "deepvision-site": "~/claude/site",
                                                        "deepvision-ads": "~/orca/workspaces/deepvision-ads", "vllm-omni": "~/pi/remote/h3-c1-lab/repository.git"}},
}
# night reviews: task -> (box id, project key, display name, SGT date: hours back)
REVIEWS = {"xinyue": ("75b324a4", "心月", 6), "deepvision-site": ("43c55a22", "deepvision官网", 13),
           "deepvision-ads": ("9b5c20e7", "deepvision广告", 13), "vllm-omni": ("c392a743", "vllm-omni", 13)}
DATE = f"bash {OPS}/scripts/review-date.sh"
GATE = f"bash {OPS}/scripts/night-review-gate.sh"
LOCK = f"bash {OPS}/scripts/heavy-lock.sh"


def sub(s, old, new, n=1):
    c = s.count(old)
    if c != n:
        sys.exit(f"make-prompts: expected {n} x {old[:70]!r}, found {c} (box prompt changed? re-read it and update the rules)")
    return s.replace(old, new)


def common_block(p, m, name):
    if m == "mba":
        take = ""
    elif p == "deepvision-site":   # dv_addflush.py (deepvision-site repo) has no --skip-existing
        take = ("- 这是接替运行（MBA 错过了这一晚，原因见 `" + GATE + f" reason {p} \"$D\"`）：写 EverOS 前先读回去重，同一晚只写一次。"
                "dv_addflush.py 没有跳过已写会话的开关：先 `python3 -I " + OPS + "/everos-ingest/everos_readback.py --project deepvision-site --session <清单里每个 session_id> ...`，"
                "全都读得到就不跑 dv_addflush.py（摘要写「已由别的机器写入」），一个都读不到才跑，读到一部分就不跑、按失败告警，note 写「接替时部分会话已写入，需人工补」。"
                "lesson 用同一个 session_id（nightly-review-deepvision-site-${D}），先按它读回，读得到就不再写。\n")
    else:
        take = ("- 这是接替运行（MBA 错过了这一晚，原因见 `" + GATE + f" reason {p} \"$D\"`）：同一晚只写一次 EverOS。"
                "会话写入已带 --skip-existing（已有 episode 的会话 result=ALREADY，不再写，摘要计数）；lesson / skill 脚本对已有的 session 或同名 skill 本来就不重写。\n")
    return (
        f"{m.upper() if m == 'mba' else 'iMac'} 版通用规则（PER-79 从 box 迁来，先读这一段；和下文冲突时以这一段为准）：\n"
        f"- 开始前：export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH；`command -v gh && gh auth status` 失败 → 失败项「gh 不可用」；"
        f"`orca linear team list >/dev/null` 失败 → 失败项「Linear 未登录」（都按下文的失败告警处理）。\n"
        f"- 防睡：先跑 `nohup caffeinate -dimsu -w $PPID >/dev/null 2>&1 &`（跟着本会话的 agent 进程，会话结束它就退出）。\n"
        f"- 锁：预检已经拿了 heavy-lock（名字 night-review-{p}）。每做完一步跑一次 `{LOCK} refresh night-review-{p}`，不要自己 release，最后一步会放。\n"
        f"- 会话清单：预检已把当晚的会话清单同步到 ~/everos-ingest/{p}/${{D}}/（transcript_path 已改成本机路径）。先读 ~/everos-ingest/{p}/${{D}}/SYNC-STATUS：不是 ok 开头 → 按「清单缺失」处理（失败告警，note 写 SYNC-STATUS 的内容）。\n"
        f"- box 上的 status.md 等文件用 `ssh box cat <路径>` 只读；不在 box 上改任何东西（存放位置在 box 时，最后一步的拷贝除外）。\n"
        + take +
        f"- 最后一步（摘要写完、摘要里有一行行首是「状态：完成」之后）：`R=$({GATE} reason {p} \"$D\"); "
        f"notify-run --bot ops-system --no-tty --task \"{name}夜审 ${{D}} machine={m} reason=$R\" -- {GATE} finish {p} \"$D\" {m} \"$R\"`。"
        f"它把摘要、台账、日志拷到夜审结果的存放位置（`night-review-gate.sh` 里的 NR_STORE_HOST / NR_STORE_DIR，用 tar），记 done，放锁，并叫醒 ops-system。"
        f"退出码 3 = 摘要里没有「状态：完成」，4 = 没拷到存放位置（notify-run 会把非 0 退出码报给 ops-system）：在本机摘要的失败项补一行，不要重试超过 2 次。\n\n")


def review(p, m):
    bid, name, back = REVIEWS[p]
    s = open(os.path.join(HERE, "box-baseline", bid + ".prompt.md"), encoding="utf-8").read()
    repos = MACHINES[m]["repos"]
    first = "【运行环境：box（Linux），工作目录是 ops 主工作区。】" if p == "xinyue" else "【运行环境：box（Linux），ops 主工作区。】"
    s = sub(s, first, f"【运行环境：{MACHINES[m]['label']}，ops 主工作区 {OPS}；box 原版 {bid}。】\n" + common_block(p, m, name))
    # dates: BSD date has no -d (bash 3.2 on both Macs, no gdate on the iMac)
    if p == "xinyue":
        s = sub(s, "D=$(TZ=Asia/Singapore date +%F)", f"D=$({DATE} ago 6)（23:40 定时；减 6 小时，接替或补跑拖到次日 05:59 前都还是这一天）")
    elif p == "deepvision-site":
        s = sub(s, "D=$(TZ=Asia/Singapore date -d yesterday +%F)", f"D=$({DATE} ago 13)")
    else:
        s = sub(s, 'D=$(TZ=Asia/Singapore date -d "13 hours ago" +%F)', f"D=$({DATE} ago 13)")
    if p != "xinyue":
        s = sub(s, '$(TZ=Asia/Singapore date -d "${D} +1 day" +%F)', f'$({DATE} next "$D")')
        s = sub(s, "box load>8 时只做 HTTP+git 检查并在摘要注明。",
                "本机负载高（`sysctl -n vm.loadavg` 的 1 分钟值 > 8，或 `memory_pressure` 的 free percentage < 15%）时只做 HTTP+git 检查并在摘要注明。")
    s = s.replace("720 分钟补跑窗口", "120 分钟补跑窗口")
    # paths
    s = s.replace("/workspace/ops/everos-ingest/", OPS + "/everos-ingest/")
    s = s.replace("/var/lib/everos-ingest/", "~/everos-ingest/")
    s = s.replace('"worktree":"/workspace/repos/ops"', f'"worktree":"{OPS}"')
    for r, path in repos.items():
        s = s.replace("/workspace/repos/" + r, path)
    for box_path in ("/workspace/xinyue-web/status.md", "/workspace/vllm-omni/status.md", "/workspace/deepvision/status.md",
                     "/workspace/ops/everos-lessons-plan/HANDOFF-coding.md"):
        s = s.replace(box_path, f"box:{box_path}（`ssh box cat`，只读）")
    s = s.replace("orca worktree ps --json", "orca worktree ps --json（本机）和 `ssh box 'PATH=$HOME/.local/bin:$PATH orca worktree ps --json'`（box，只读）")
    # writers read the synced lists; takeover-safe on both machines
    if p == "xinyue":
        s = sub(s, 'python3 -I "$S" --date "$D" --log', f'python3 -I "$S" --date "$D" --sessions-dir ~/everos-ingest/xinyue/"$D" --skip-existing --log')
    elif p == "deepvision-site":
        s = sub(s, "dv_addflush.py --date \"$D\" --log", "dv_addflush.py --date \"$D\" --sessions-root ~/everos-ingest/deepvision-site --log")
    else:
        s = sub(s, f'python3 -I "$S0" --project {p} --date "$D" --log', f'python3 -I "$S0" --project {p} --date "$D" --sessions-dir ~/everos-ingest/{p}/"$D" --skip-existing --log')
    # failure alarms go to ops-system (task brief §1 and §9②), with the machine in the note
    s = sub(s, "source ~/.config/grokbot/webhooks/coding-assistant.env", "source ~/.config/grokbot/webhooks/ops-system.env")
    s = sub(s, '"bot":"coding-assistant"', '"bot":"ops-system"')
    s = s.replace('"note":"<', f'"note":"machine={m} <')
    if p != "xinyue":   # the watcher and the box guard look for this line; 心月's skeleton already has it
        s = s.rstrip("\n") + f"\n7. 摘要最后单独一行写「状态：完成」（行首，有失败项也写；只有真正走到这一步才写），然后做通用规则里的最后一步。\n"
    else:
        s = s.rstrip("\n") + "\n9. 然后做通用规则里的最后一步。\n"
    return s


def linear_sync(m):
    s = open(os.path.join(HERE, "box-baseline", "bc9ee42b.prompt.md"), encoding="utf-8").read()
    s = ("【运行环境：iMac（macOS），ops 主工作区 ~/orca/workspaces/ops；box 原版 bc9ee42b（PER-79 迁来）。】"
         "开始前 export PATH=/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH。box 上的文件一律 `ssh box` 只读，下面写明的 changes.log 追加除外。\n" + s)
    s = sub(s, "`orca-ide --environment iMac linear ...`；iMac 不在线（命令连不上）时改用 box 的 `orca linear ...`",
            "本机 `orca linear ...`；本机连不上 Linear 时不改用 box：停下，在最后一条消息里写明（预检已经用 `orca linear team list` 查过一次）")
    s = sub(s, "orca-ide --environment iMac linear", "orca linear")
    for r, path in MACHINES["imac"]["repos"].items():
        s = s.replace(f"box /workspace/repos/{r}", f"iMac {path}")
    s = sub(s, "先找 box 仓库里的", "先找 iMac 仓库里的，没有再 `ssh box cat` box 仓库里的")
    s = sub(s, "在绝对路径 /workspace/ops/reports/linear-sync/changes.log 追加一行（不是当前仓库下的 reports/），目录不在就建",
            "在 iMac 的 ~/.orca-state/linear-sync/changes.log 追加一行（目录不在就建），同一行再追加到 box：`ssh box 'cat >> /workspace/ops/reports/linear-sync/changes.log'`（ops-system 照旧读 box 那份；追加失败在最后一条消息里写明）")
    return s.rstrip("\n") + "\n- 最后一条消息之前：`bash ~/orca/workspaces/ops/scripts/heavy-lock.sh release linear-sync`。\n"


def vllm_upstream(m):
    s = open(os.path.join(HERE, "box-baseline", "349967f6.prompt.md"), encoding="utf-8").read()
    s = ("【运行环境：iMac（macOS），ops 主工作区 ~/orca/workspaces/ops；box 原版 349967f6（PER-79 迁来）。】"
         "开始前 export PATH=/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH。\n" + s)
    s = sub(s, "/workspace/repos/ops/scripts/orca-ok.sh", "~/orca/workspaces/ops/scripts/orca-ok.sh")
    return s.rstrip("\n") + "\n5) 不管第 4 步做没做，最后都跑 `bash ~/orca/workspaces/ops/scripts/heavy-lock.sh release vllm-upstream`。\n"


def build():
    out = {}
    for m in MACHINES:
        for p in REVIEWS:
            out[f"prompts/{m}/night-review-{p}.prompt.md"] = review(p, m)
    out["prompts/imac/linear-sync.prompt.md"] = linear_sync("imac")
    out["prompts/imac/vllm-upstream.prompt.md"] = vllm_upstream("imac")
    base = {"night-review-xinyue": "75b324a4", "night-review-deepvision-site": "43c55a22", "night-review-deepvision-ads": "9b5c20e7",
            "night-review-vllm-omni": "c392a743", "linear-sync": "bc9ee42b", "vllm-upstream": "349967f6"}
    diff = []
    for path in sorted(out):
        b = base[os.path.basename(path).replace(".prompt.md", "")]
        old = open(os.path.join(HERE, "box-baseline", b + ".prompt.md"), encoding="utf-8").read()
        # one sentence per line so the diff shows each replacement
        split = lambda t: [x + "\n" for x in t.replace("。", "。\n").replace("；", "；\n").split("\n")]
        diff += difflib.unified_diff(split(old), split(out[path]), f"box-baseline/{b}.prompt.md", path)
    return out, "".join(diff)


def main():
    check = "--check" in sys.argv
    out, diff = build()
    if "--diff" in sys.argv:
        sys.stdout.write(diff); return 0
    bad = 0
    for rel, text in out.items():
        path = os.path.join(HERE, rel)
        if check:
            cur = open(path, encoding="utf-8").read() if os.path.exists(path) else None
            if cur != text:
                print(f"make-prompts --check: {rel} differs from the generated version"); bad = 1
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w", encoding="utf-8").write(text)
    print("make-prompts: " + ("check failed" if bad else ("up to date" if check else "written")))
    return bad


if __name__ == "__main__":
    sys.exit(main())
