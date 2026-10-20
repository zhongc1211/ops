# normalize.py <stdout 文件> <状态目录>：去掉每次运行都会变的东西（日志时间戳、pid、耗时），
# 留下判定（嫌疑、问题、直发、将 POST 的内容）和跑完后的状态文件，base 和 head 逐行比。
import json, os, re, sys

out, st = sys.argv[1], sys.argv[2]
VOLATILE = {"pid", "updated", "start", "end", "duration_s", "ts", "s", "last_duration_s", "created", "secs"}


def scrub(x):
    if isinstance(x, dict):
        return {k: ("<变>" if k in VOLATILE else scrub(v)) for k, v in sorted(x.items())}
    if isinstance(x, list):
        return [scrub(v) for v in x]
    return x


def line(s):
    s = re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", s)
    s = re.sub(r"pid \d+", "pid <变>", s)
    s = re.sub(r"\d+(\.\d+)? 秒", "<n> 秒", s)
    s = re.sub(r'("(?:ts|last_scan|last_duration_s)": )[\d.]+', r"\1<变>", s)
    return s


print("== stdout ==")
for s in open(out, encoding="utf-8", errors="replace"):
    print(line(s.rstrip("\n")))
print("== 状态文件 ==")
for name in sorted(os.listdir(st)):
    p = os.path.join(st, name)
    if not os.path.isfile(p) or name == "run.lock":
        continue
    print("-- %s" % name)
    if name.endswith(".json"):
        try:
            print(json.dumps(scrub(json.load(open(p, encoding="utf-8"))), ensure_ascii=False, indent=1))
        except ValueError:
            print("<不是 JSON>")
    else:
        for s in open(p, encoding="utf-8", errors="replace"):
            print(line(s.rstrip("\n")))
