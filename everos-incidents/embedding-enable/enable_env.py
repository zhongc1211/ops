#!/usr/bin/env python3
"""Run on site as root. Backup env, un-comment staged key, add MODEL/BASE_URL/DIMENSIONS. Prints names/len/sha8 only.
With --revert <backup>: restore that backup (rollback)."""
import grp, hashlib, os, shutil, sys, time
ENV = "/etc/everos/everos.env"; G = grp.getgrnam("everos").gr_gid
def fix(p): os.chown(p, 0, G); os.chmod(p, 0o640)
if len(sys.argv) == 3 and sys.argv[1] == "--revert":
    shutil.copy2(sys.argv[2], ENV); fix(ENV); print("restored", sys.argv[2]); sys.exit(0)
lines = open(ENV).read().splitlines(True)
assert any(l.startswith("#STAGED# EVEROS_EMBEDDING__API_KEY=") for l in lines), "staged key line not found"
assert not any(l.startswith(("EVEROS_EMBEDDING__", "EVEROS_RERANK__")) for l in lines), "embedding vars already active"
bak = ENV + ".bak.embedding-on-" + time.strftime("%Y%m%dT%H%M%S%z"); shutil.copy2(ENV, bak); fix(bak)
new = []
for l in lines:
    if l.startswith("#STAGED# EVEROS_EMBEDDING__API_KEY="):
        new.append(l[len("#STAGED# "):])
        new += ["EVEROS_EMBEDDING__MODEL=text-embedding-v4\n",
                "EVEROS_EMBEDDING__BASE_URL=https://dashscope-intl.aliyuncs.com/compatible-mode/v1\n",
                "EVEROS_EMBEDDING__DIMENSIONS=1024\n"]
    else:
        new.append(l)
tmp = ENV + ".tmp-embedding-on"; open(tmp, "w").write("".join(new)); fix(tmp); os.replace(tmp, ENV)
s = os.stat(ENV); print("backup:", bak); print("env mode", oct(s.st_mode & 0o777), "uid", s.st_uid, "gid-name", grp.getgrgid(s.st_gid).gr_name)
for l in open(ENV):
    if l.startswith(("EVEROS_EMBEDDING", "EVEROS_RERANK", "#STAGED#")):
        k, v = l.rstrip("\n").split("=", 1)
        print(" ", k, "=", ("<len %d sha8 %s>" % (len(v), hashlib.sha256(v.encode()).hexdigest()[:8])) if k.endswith("API_KEY") else v)
