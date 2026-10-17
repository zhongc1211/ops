import json,os,sys,urllib.request,time
env={}
for l in open(os.path.expanduser("~/.config/everos/xinyue.env")):
    l=l.strip()
    if l and not l.startswith('#') and '=' in l:
        k,v=l.split('=',1); env[k.replace('export ','')]=v.strip().strip('"\'')
q=sys.argv[1]; m=sys.argv[2] if len(sys.argv)>2 else "hybrid"
b={"app_id":env["EVEROS_APP_ID"],"project_id":env["EVEROS_PROJECT_ID"],"user_id":env["EVEROS_USER_ID"],"query":q,"method":m,"top_k":3}
t=time.time()
r=urllib.request.urlopen(urllib.request.Request("http://100.64.0.5/api/v2/memory/search",json.dumps(b).encode(),{"Content-Type":"application/json","Authorization":"Bearer "+env["EVEROS_API_KEY"],"Host":"everos.deepvision.sg"}),timeout=90)
d=json.load(r)["data"]
print(f"- xinyue/xinyue-site user=zack {m} q={q} -> {r.status} {time.time()-t:.3f}s")
for e in d["episodes"]:
    print("  ep", e["id"], e["app_id"]+"/"+e["project_id"], e["timestamp"][:19], "score=%.3f"%e["score"], "facts=%d"%len(e.get("atomic_facts") or []))
    for a in (e.get("atomic_facts") or [])[:4]:
        print("     fact", a.get("id"), str(a.get("timestamp",""))[:19], "score=", a.get("score"), "|", (a.get("atomic_fact") or a.get("content") or a.get("fact") or "")[:90])
