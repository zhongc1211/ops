#!/usr/bin/env python3
"""Run on site as root. Backs up /etc/everos/everos.env, then appends EVEROS_RERANK__* lines pointing at the loopback forwarder.
The API key value is copied from EVEROS_EMBEDDING__API_KEY (same DashScope intl key); it is never printed. Keeps mode/owner."""
import os, shutil, stat, hashlib, datetime, sys
P = "/etc/everos/everos.env"
lines = open(P).read().splitlines()
if any(l.startswith("EVEROS_RERANK__") for l in lines): sys.exit("EVEROS_RERANK__ lines already present, not touching")
key = [l.split("=", 1)[1].strip() for l in lines if l.startswith("EVEROS_EMBEDDING__API_KEY=")]
if len(key) != 1 or not key[0]: sys.exit("embedding key not found")
st = os.stat(P)
ts = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%S+0000")
bak = f"{P}.bak.rerank-on-{ts}"
shutil.copy2(P, bak); os.chown(bak, st.st_uid, st.st_gid)
add = ["# Rerank via loopback nginx forwarder -> DashScope intl compatible-api/v1/reranks qwen3-rerank (Zack 2026-10-17 20:10 SGT).",
       "# Provider 'vllm' = POST <base>/rerank {model,query,documents}. Rollback: delete these 6 lines + restart, or restore " + bak,
       "EVEROS_RERANK__PROVIDER=vllm", "EVEROS_RERANK__MODEL=qwen3-rerank", "EVEROS_RERANK__BASE_URL=http://127.0.0.1:8031",
       "EVEROS_RERANK__API_KEY=" + key[0]]
tmp = P + ".tmp"
with open(tmp, "w") as f: f.write("\n".join(lines + add) + "\n")
os.chmod(tmp, stat.S_IMODE(st.st_mode)); os.chown(tmp, st.st_uid, st.st_gid); os.replace(tmp, P)
v = key[0]
print("backup", bak)
print("added EVEROS_RERANK__PROVIDER/MODEL/BASE_URL and EVEROS_RERANK__API_KEY len", len(v), "sha256[:8]", hashlib.sha256(v.encode()).hexdigest()[:8])
