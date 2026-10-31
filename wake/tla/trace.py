#!/usr/bin/env python3
"""wake/tla/trace.py <TLC 输出文件>
把 TLC 的反例打成「第几步、哪个动作、对应代码、这一步变了什么」，只列变化的变量。
动作 → 代码的对应表和 Wake.tla / Heartbeat.tla 里动作上方的注释一致；代码行号变了两边一起改。
"""
import re
import sys

CODE = {
    "AgentPause": "Claude Stop hook → orca-wake cmd_claude_hook Stop（wake/bin/orca-wake:734-749）→ dispatch_send（:370-423）",
    "AgentExit": "agent 退出 → notify-run wait 返回（wake/bin/notify-run:259-268）→ finish → send_webhook（:199-214）",
    "MarkCompleted": "agent 把任务工作区标 completed（Orca 看板）",
    "NrAttempt": "notify-run 一次 curl POST（wake/bin/notify-run:148-158）",
    "OwAttempt": "orca-wake _deliver 一次 POST（wake/bin/orca-wake:501-556，成功判断 :520，_mark_sent :450-463）",
    "IdlePrompt": "Claude idle_prompt hook（wake/bin/orca-wake:774-789）→ dispatch_send 去重（:378-397）",
    "WebhookDown": "派活 bot 的 webhook 开始不可用（环境）",
    "WebhookUp": "webhook 恢复（环境）",
    "Scan": "卡住检查一次扫描：check_agents + wake_recheck + send_all（scripts/stuck-check.sh:957,1522-1626,1704-1797）",
    "Tick": "过 15 分钟（下一次扫描，stuck-check.sh:153）",
    "Step": "过 1 分钟：ops · 01 precheck（scripts/stuck-check.sh:2289-2329）+ 每 5 分钟 heartbeat-watch（scripts/heartbeat-watch.sh:188-257）",
    "Fail": "卡住检查出故障（自动任务停 / 每次出错 / 每次超时 / 每次到整轮时限）",
    "WatcherDown": "看守机下线（环境）",
}


def main(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"Error: (Invariant \S+ is violated|Temporal properties were violated)\.?", text)
    if not m:
        print("没有反例（%s）" % ("通过" if "No error has been found" in text else "看原文"))
        return 0
    print(m.group(1))
    body = text[m.end():]
    blocks = re.split(r"\n(?=State \d+:|Back to state \d+|\d+: Stuttering)", body)
    prev = {}
    for b in blocks:
        lines = b.strip().split("\n")
        head = lines[0]
        if not re.match(r"State \d+:|Back to state|\d+: Stuttering", head):
            continue
        act = re.search(r"<(\w+)", head)
        name = act.group(1) if act else ""
        cur, key = {}, None
        for ln in lines[1:]:
            mm = re.match(r"/\\ (\w+) = (.*)", ln)
            if mm:
                key = mm.group(1)
                cur[key] = mm.group(2)
            elif key and ln.startswith(" "):
                cur[key] += " " + ln.strip()
        num = re.match(r"(State \d+|Back to state \d+|\d+: Stuttering)", head).group(1)
        print("\n%s  %s" % (num, name or head))
        if name in CODE:
            print("    代码：%s" % CODE[name])
        for k, v in cur.items():
            if prev.get(k) != v:
                print("    %s = %s" % (k, v[:200]))
        if cur:
            prev = cur
        if head.startswith(("Back to state", )) or "Stuttering" in head:
            print("    （从这里开始无限循环：之后一直这样，性质要求的事永远不发生）")
            break
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
