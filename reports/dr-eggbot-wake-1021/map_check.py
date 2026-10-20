"""从 stuck-check.sh 内嵌的 python 里取出映射相关的真实代码（BOT_SLUG、load_mapping、bot_for、due_bot 等），
对样例 orca-projects.md 和样例 Linear issue 跑一遍。用法：python3 -I map_check.py <stuck-check.sh> <样例 orca-projects.md> <webhook 目录>"""
import ast, os, re, sys
src_path, mapping, hookdir = sys.argv[1:4]
L = open(src_path, encoding="utf-8").read().split("\n")
s = next(i for i, l in enumerate(L) if l.endswith("<<'PYEOF'")) + 1
e = len(L) - 1 - L[::-1].index("PYEOF")
tree = ast.parse("\n".join(L[s:e]))
WANT_ASSIGN = {"BOT_SLUG", "NAME_BOT", "UUID", "SLUG", "LINEAR_RUN", "BOT_LABEL", "BOT_LINE", "FALLBACK_BOT"}
WANT_FUNC = {"load_mapping", "bot_for", "due_bot"}
keep = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))
        or (isinstance(n, ast.Assign) and any(getattr(t, "id", "") in WANT_ASSIGN for t in n.targets))
        or (isinstance(n, ast.FunctionDef) and n.name in WANT_FUNC)]
g = {"MAPPING": mapping, "log": lambda m: print("  [log]", m)}
exec(compile(ast.Module(body=keep, type_ignores=[]), src_path, "exec"), g)
g["MAP_ID"], g["MAP_NAME"], g["MAP_LINEAR"] = g["load_mapping"]()
print("MAP_LINEAR:", g["MAP_LINEAR"])
cases = [("PER-901", "dr eggbot（orca-projects 行）"), ("PER-902", "ops 系统（orca-projects 行）"),
         ("PER-903", "Coding助手（orca-projects 行）"), ("PER-904", "心月网站 运维（已有映射，对照）")]
for ident, what in cases:
    b = g["due_bot"]({"identifier": ident, "labels": [], "description": ""}, [])
    print("%s %-28s → %-18r webhook 文件 %s.env %s" % (ident, what, b, b,
          "存在" if re.fullmatch(r"[A-Za-z0-9._-]+", b) and os.path.exists(os.path.join(hookdir, b + ".env")) else "不存在（bot_cfg 会改发 coding-assistant）"))
for desc in ("负责 bot：dr-eggbot", "负责 bot：dr eggbot"):
    print("描述 %-22r → %r" % (desc, g["due_bot"]({"identifier": "PER-999", "labels": [], "description": desc}, [])))
