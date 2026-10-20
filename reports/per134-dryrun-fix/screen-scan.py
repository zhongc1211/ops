# screen-scan.py <输入目录> <要查的目录...>：把磁带里终端屏幕内容（orca terminal read / terminal wait、agent-probe 的输出）
# 中 ≥24 字符的行逐条拿去这些目录的文件里找原文，确认报告里没带出屏幕内容。
import json, glob, os, sys

IN, dirs = sys.argv[1], sys.argv[2:]
lines = set()
for t in glob.glob(os.path.join(IN, "*.tape")):
    for c in json.load(open(t, encoding="utf-8"))["calls"]:
        k = json.loads(c["key"])
        if "read" in k[1:3] or "wait" in k[1:3] or "agent-probe" in " ".join(k):
            try:
                txt = json.dumps(json.loads(c["out"]), ensure_ascii=False)
            except ValueError:
                txt = c["out"]
            lines.update(s.strip() for s in txt.replace("\\n", "\n").splitlines() if len(s.strip()) >= 24)
print("# 磁带里终端屏幕内容中 ≥24 字符的行共 %d 条，逐条在下列目录的文件里查原文" % len(lines))
n = hits = 0
for d in dirs:
    for f in sorted(glob.glob(os.path.join(d, "*"))):
        if os.path.basename(f) == "screen-scan.txt":
            continue
        n += 1
        body = open(f, encoding="utf-8", errors="replace").read()
        hit = [s for s in lines if s in body]
        if hit:
            hits += 1
            print("命中 %s：%d 行" % (f, len(hit)))
print("查了 %d 个文件（%s），命中 %d 个" % (n, "、".join(dirs), hits))
