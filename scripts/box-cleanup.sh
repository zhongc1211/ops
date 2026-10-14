#!/bin/bash
# box-cleanup.sh: Linux cleanup that only covers THIS machine (the box). No model needed.
#   --pressure-check          exit 0 if 5-min load > LOAD_MAX (default 8) and >3h since last cleanup, else 1
#   --trigger nightly|pressure|manual [--dry-run]
# Never touches: claude/codex/pi/gemini agent sessions, anything under notify-run, anything with a live
# agent/notify-run in its cwd, the Orca runtime, orbitd/pod-daemon/sand-*/supervise-*. Agents are report-only.
# Kills only orphaned (ppid 1) dev-tool leftovers unused >12h: wrangler/workerd/vitest/esbuild/vite/next dev
# servers and headless Chrome bridges. SIGTERM, 8s, SIGKILL only if still alive. Dry-run if ~/.orca-state/cleanup/DRYRUN exists.
S=$HOME/.orca-state/cleanup; mkdir -p "$S"
LOAD_MAX=${LOAD_MAX:-8}
if [ "$1" = "--pressure-check" ]; then
  L5=$(awk '{print $2}' /proc/loadavg)
  python3 - "$L5" "$LOAD_MAX" "$S/last-run" <<'PY'
import sys,os,time
l5,mx,f=float(sys.argv[1]),float(sys.argv[2]),sys.argv[3]
last=float(open(f).read()) if os.path.exists(f) else 0
sys.exit(0 if l5>mx and time.time()-last>3*3600 else 1)
PY
  exit $?
fi
TRIGGER=manual; DRY=0
while [ $# -gt 0 ]; do case "$1" in --trigger) TRIGGER=$2; shift;; --dry-run) DRY=1;; esac; shift; done
[ -e "$S/DRYRUN" ] && DRY=1
exec python3 - "$TRIGGER" "$DRY" "$S" "$LOAD_MAX" <<'PY'
import os,sys,re,time,signal,datetime
trigger,dry,S,load_max=sys.argv[1],sys.argv[2]=="1",sys.argv[3],float(sys.argv[4])
AGENT=re.compile(r'(^|/)(claude|codex|pi|gemini|opencode)(\s|$)|notify-run')
DEV=re.compile(r'wrangler|workerd|vitest|esbuild|node .*--test|next[ -](dev|server)|vite|chrome-devtools-axi|chrome.*--headless')
PROTECT=re.compile(r'orca|orbitd|pod-daemon|sand-|supervise-|tini|watchdog\.sh|sshd|gh |grok')
HZ=os.sysconf('SC_CLK_TCK'); BOOT=float(open('/proc/uptime').read().split()[0]); NOW=time.time()
def procs():
    out={}
    for p in os.listdir('/proc'):
        if not p.isdigit(): continue
        try:
            st=open(f'/proc/{p}/stat').read(); r=st.rindex(')'); f=st[r+2:].split()
            cmd=open(f'/proc/{p}/cmdline').read().replace('\0',' ').strip()
            if not cmd: continue
            age=BOOT-int(f[19])/HZ
            try: cwd=os.readlink(f'/proc/{p}/cwd')
            except OSError: cwd=''
            out[int(p)]=dict(pid=int(p),ppid=int(f[1]),age=age,cpu=(int(f[11])+int(f[12]))/HZ,cmd=cmd,cwd=cwd,uid=os.stat(f'/proc/{p}').st_uid)
        except (OSError,ValueError): pass
    return out
P=procs()
def ancestors(pid):
    a=[]
    while pid in P and P[pid]['ppid'] in P and len(a)<64:
        pid=P[pid]['ppid']; a.append(pid)
    return a
me=os.getuid()
guard_cwds=[p['cwd'] for p in P.values() if p['cwd'] and AGENT.search(p['cmd'])]
def near_agent(cwd):
    return any(cwd==g or cwd.startswith(g.rstrip('/')+'/') or g.startswith(cwd.rstrip('/')+'/') for g in guard_cwds if g not in ('/','/home/box'))
rows=[]
for p in P.values():
    if p['uid']!=me or p['pid']==os.getpid(): continue
    if AGENT.search(p['cmd']):
        # agent sessions: report only
        if p['age']>24*3600:
            rows.append(dict(p,action='report',why='agent 会话，只报告不处理'))
        continue
    if not DEV.search(p['cmd']): continue
    why=None
    if PROTECT.search(p['cmd']): why='受保护的平台/Orca 进程'
    elif p['ppid']!=1: why='不是孤儿（父进程 %d）'%p['ppid']
    elif p['age']<12*3600: why='运行不足 12 小时'
    elif any(AGENT.search(P[a]['cmd']) for a in ancestors(p['pid'])): why='祖先里有 agent/notify-run'
    elif near_agent(p['cwd']): why='工作目录附近有 agent/notify-run 在跑'
    rows.append(dict(p,action='skip' if why else 'kill',why=why or '孤儿开发工具进程，闲置超过 12 小时'))
def load(): return open('/proc/loadavg').read().split()[:3]
before=load(); results=[]
for r in rows:
    if r['action']!='kill': continue
    if dry: r['result']='dry-run，未发信号'; continue
    try:
        os.kill(r['pid'],signal.SIGTERM); time.sleep(8)
        try: os.kill(r['pid'],0); os.kill(r['pid'],signal.SIGKILL); r['result']='SIGTERM 无效，已 SIGKILL'
        except ProcessLookupError: r['result']='已退出（SIGTERM）'
    except ProcessLookupError: r['result']='已不存在'
    except PermissionError: r['result']='无权限'
if not dry: open(os.path.join(S,'last-run'),'w').write('%d\n'%NOW)
after=load()
tz=datetime.timezone(datetime.timedelta(hours=8)); now=datetime.datetime.now(tz)
L=['## %s %s%s'%(now.strftime('%H:%M'),{'nightly':'夜间定时','pressure':'负载触发'}.get(trigger,trigger),'（dry-run）' if dry else ''),'',
   '- 运行前 load %s；运行后 load %s（阈值 %g，box 本机）'%(' / '.join(before),' / '.join(after),load_max)]
k=[r for r in rows if r['action']=='kill']; s=[r for r in rows if r['action']=='skip']; a=[r for r in rows if r['action']=='report']
L.append('- 处理（%s）%d 个，跳过 %d 个，agent 会话（只报告）%d 个。'%('将关闭' if dry else '已关闭',len(k),len(s),len(a)))
def tbl(rs,extra):
    if not rs: return ['没有。','']
    o=['| PID | 已运行 | cwd | 命令 | %s |'%extra,'|---|---|---|---|---|']
    for r in rs: o.append('| %d | %.1fh | %s | %s | %s |'%(r['pid'],r['age']/3600,r['cwd'].replace('|','/'),r['cmd'][:80].replace('|','/'),(r.get('result') or r['why']).replace('|','/')))
    return o+['']
L+=['','### 处理的进程','']+tbl(k,'结果')+['### 跳过的开发工具进程','']+tbl(s,'跳过原因')+['### 运行超过 24 小时的 agent 会话（只报告）','']+tbl(a,'说明')
RD=os.path.join(S,'reports'); os.makedirs(RD,exist_ok=True)
path=os.path.join(RD,'cleanup-%s.md'%now.strftime('%Y-%m-%d'))
new=not os.path.exists(path)
with open(path,'a') as f:
    if new: f.write('# box 内存与 CPU 清理报告（%s）\n\n'%now.strftime('%Y-%m-%d'))
    f.write('\n'.join(L)+'\n')
print('\n'.join(L)); print('报告：%s（退出码 0）'%path)
PY
