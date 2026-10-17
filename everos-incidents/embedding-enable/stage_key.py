#!/usr/bin/env python3
"""Run on site as root: key on stdin (never argv, never printed).
1) tiny DashScope-intl embedding call from site; 2) back up /etc/everos/everos.env; 3) append the key as a
STAGED (commented, inert) EVEROS_EMBEDDING__API_KEY line; 4) keep 640 root:everos; 5) print name/len/sha8 only."""
import hashlib, json, os, shutil, sys, time, urllib.request, grp
key = sys.stdin.read().strip()
assert key.startswith("sk-") and "\n" not in key, "bad key on stdin"
ENV = "/etc/everos/everos.env"; NAME = "EVEROS_EMBEDDING__API_KEY"; TAG = "#STAGED# "
t = time.time()
req = urllib.request.Request("https://dashscope-intl.aliyuncs.com/compatible-mode/v1/embeddings",
    data=json.dumps({"model": "text-embedding-v4", "input": "测试", "dimensions": 1024}).encode(),
    headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=30) as r:
    d = json.load(r); print("site embedding: HTTP", r.status, "model", d.get("model"), "dim", len(d["data"][0]["embedding"]), "%.2fs" % (time.time() - t))
text = open(ENV).read()
if NAME in text:
    sys.exit("refusing: %s already present in %s" % (NAME, ENV))
st = os.stat(ENV)
bak = ENV + ".bak.embedding-" + time.strftime("%Y%m%dT%H%M%S%z")
shutil.copy2(ENV, bak); os.chown(bak, st.st_uid, st.st_gid); os.chmod(bak, 0o640)
add = ("\n# DashScope INTL (Model Studio) key for EverOS embedding, Zack 2026-10-17 (via chat). STAGED = commented out on purpose:\n"
       "# with Restart=always, an active key would pair with everos.toml's DeepInfra model/base_url on any restart.\n"
       "# Enable only together with the MODEL/BASE_URL/DIMENSIONS lines in /workspace/ops/everos-incidents/embedding-enable/PROPOSAL.md.\n"
       + TAG + NAME + "=" + key + "\n")
if not text.endswith("\n"): text += "\n"
tmp = ENV + ".tmp-embedding"
with open(tmp, "w") as f: f.write(text + add)
os.chown(tmp, 0, grp.getgrnam("everos").gr_gid); os.chmod(tmp, 0o640); os.replace(tmp, ENV)
s = os.stat(ENV)
print("backup:", bak)
print("env:", ENV, oct(s.st_mode & 0o777), "uid", s.st_uid, "group", grp.getgrgid(s.st_gid).gr_name)
for line in open(ENV):
    if NAME in line:
        v = line.split("=", 1)[1].strip()
        print("line:", (TAG + NAME) if line.startswith(TAG) else NAME, "len", len(v), "sha256[:8]", hashlib.sha256(v.encode()).hexdigest()[:8],
              "matches stdin key:", v == key)
active = [l.split("=", 1)[0] for l in open(ENV) if l.strip() and not l.lstrip().startswith("#")]
print("active EVEROS_EMBEDDING*/RERANK* vars:", [a for a in active if a.startswith(("EVEROS_EMBEDDING", "EVEROS_RERANK"))] or "none")
