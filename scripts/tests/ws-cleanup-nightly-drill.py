#!/usr/bin/env python3
"""Isolated process/notification drills using fake cleanup and a local webhook.
Not a real cleanup E2E. Never invokes cleanup execution mode or a real webhook.
Artifacts: --out DIR, including per-case rc, delivery receipts and request payloads.
"""
import argparse
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import threading
import time
import uuid

P = argparse.ArgumentParser()
P.add_argument('--out', type=Path, required=True)
P.add_argument('--launcher', type=Path, default=Path(__file__).resolve().parents[1] / 'ws-cleanup-nightly.sh')
P.add_argument('--case', default='all')
A = P.parse_args()
A.out = A.out.resolve()
A.out.mkdir(parents=True, exist_ok=False)
requests = []
reject = False
key = uuid.uuid4().hex


class Receiver(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.headers['Authorization'] == 'Bearer ' + key
        requests.append(dict(payload=body, accepted=not reject))
        self.send_response(503 if reject else 200)
        self.end_headers()


server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
config = A.out / 'fake-webhooks'
config.mkdir()
endpoint = 'http://' + '127.0.0.1:' + str(server.server_port)
(config / 'ops-system.env').write_text('URL=' + endpoint + '\nKEY=' + key + '\n')
fixture = r'''import json, os, pathlib, subprocess, sys, time
root=pathlib.Path(__file__).resolve().parent.parent
c=json.loads((root/'scenario.json').read_text())
args=sys.argv[1:]
assert '--execute' not in args
out=pathlib.Path(args[args.index('--out')+1]);out.mkdir(parents=True,exist_ok=True)
(out/'worktrees.tsv').write_text('id\taction\n')
if c.get('escape'):
    p=subprocess.Popen(['/bin/sleep','20'],start_new_session=True,close_fds=False)
    (root/'escaped.pid').write_text(str(p.pid))
if c.get('descendant'):
    for i in range(c.get('descendant_count',1)):
        p=subprocess.Popen(['/bin/sleep','20'],close_fds=True)
        (root/('descendant-'+str(i)+'.pid')).write_text(str(p.pid))
        (root/'descendant.pid').write_text(str(p.pid))
if c.get('marker'):
    e=out.parent/'exec';e.mkdir(exist_ok=True)
    note='command failed' if c['marker']=='rm' else 'ERROR BACKUP_FAIL'
    (e/'journal.tsv').write_text('now\trm-end\tfixture\t1\t'+note+'\n')
time.sleep(c.get('sleep',0))
sys.exit(c.get('rc',0))
'''
owned = []
results = {}


def wait_for(fn, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = fn()
        if value:
            return value
        time.sleep(.03)
    raise AssertionError('deadline expired')


def make(name, **scenario):
    root = A.out / name
    (root / 'bundle/scripts').mkdir(parents=True)
    bundle = root / 'bundle'
    shutil.copy2(A.launcher, bundle / 'scripts/ws-cleanup-nightly.sh')
    (bundle / 'scripts/fixture.py').write_text(fixture)
    (bundle / 'scripts/ws-cleanup.sh').write_text('#!/bin/sh\nexec python3 "$(dirname "$0")/fixture.py" "$@"\n')
    (bundle / 'scenario.json').write_text(json.dumps(scenario))
    names = ['scripts/ws-cleanup.sh', 'scripts/ws-cleanup-nightly.sh']
    (bundle / 'SHA256SUMS').write_text(''.join(hashlib.sha256((bundle/n).read_bytes()).hexdigest()+'  '+n+'\n' for n in names))
    return root


def trigger(root, **extra):
    env = dict(os.environ, WS_NIGHTLY_WEBHOOK_DIR=str(config), WS_NIGHTLY_STALE_SECONDS='0',
               WS_NIGHTLY_STOP_SECONDS='0.15', WS_NIGHTLY_ALERT_TIMEOUT='0.5')
    env.update(extra)
    cmd = ['/bin/sh', str(root/'bundle/scripts/ws-cleanup-nightly.sh'), 'trigger', '--dry-run-only',
           '--workspace', str(root), '--archive', str(root/'archive')]
    started = time.monotonic()
    p = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=15)
    assert p.returncode == 1
    run_dir = Path(p.stdout.strip().split()[-1])
    owned.append(run_dir)
    (root/'trigger.json').write_text(json.dumps(dict(rc=p.returncode,elapsed_ms=round((time.monotonic()-started)*1000),stdout=p.stdout,stderr=p.stderr)))
    return run_dir


def rc(run_dir):
    return json.loads(wait_for(lambda: (run_dir/'rc.txt').read_text() if (run_dir/'rc.txt').exists() else None))


def delivered(run_dir):
    return any(json.loads(p.read_text()).get('sent_at') for p in run_dir.glob('alert-*.json'))


def case_failure():
    root = make('stage-failure', rc=7)
    d = trigger(root)
    assert rc(d)['dry_run_rc'] == 7
    wait_for(lambda: delivered(d))
    before = len([r for r in requests if r['accepted']])
    rc(trigger(root))
    time.sleep(.2)
    assert len([r for r in requests if r['accepted']]) == before+1  # Only the new failure.
    return dict(rc=7, alert=True, retry_deduplicated=True)


def case_crash():
    root = make('worker-kill', sleep=20)
    d = trigger(root)
    def stage_progress():
        data=json.loads((d/'progress.json').read_text()) if (d/'progress.json').exists() else {}
        return data if data.get('stage_pgid') else None
    progress = wait_for(stage_progress)
    os.kill(progress['pid'], signal.SIGKILL)
    assert not (d/'rc.txt').exists()
    next_run = trigger(root)
    wait_for(lambda: delivered(d))
    # The owned original stage group is still alive: no overlapping cleanup is allowed.
    assert rc(next_run)['status'] == 'stuck'
    os.killpg(progress['stage_pgid'], signal.SIGTERM)
    return dict(missing_rc=True, recovered_alert=True, overlap_blocked=True)


def case_escaped():
    root = make('setsid-descendant', escape=True)
    d = trigger(root)
    assert rc(d)['status'] == 'completed'
    pid = int((root/'bundle/escaped.pid').read_text())
    os.kill(pid, 0)
    with (root/'archive/.nightly.lock').open('a+') as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    second = trigger(root)
    assert rc(second)['status'] == 'completed'
    pid2 = int((root/'bundle/escaped.pid').read_text())
    os.kill(pid, signal.SIGTERM)
    os.kill(pid2, signal.SIGTERM)
    return dict(rc=0, escaped_descendant_cannot_hold_lock=True, next_status='completed')


def case_stale():
    root = make('stale-owner')
    archive = root/'archive'; archive.mkdir()
    owner_dir=archive/'20000101-owner';owner_dir.mkdir()
    # A real separate process owns this lock; no fake flock result is supplied.
    code = 'import fcntl,json,os,sys,time;f=open(sys.argv[1],"a+");fcntl.flock(f,fcntl.LOCK_EX);json.dump(dict(pid=os.getpid(),started_at="2000-01-01T00:00:00+00:00",status="running",run_dir=sys.argv[2]),f);f.flush();print("ready",flush=True);time.sleep(20)'
    p = subprocess.Popen(['python3','-I','-c',code,str(archive/'.nightly.lock'),str(owner_dir)],stdout=subprocess.PIPE,text=True)
    try:
        assert p.stdout.readline().strip()=='ready'
        d=trigger(root)
        assert rc(d)['status']=='already_running' and rc(d)['rc']!=0
        wait_for(lambda: delivered(owner_dir))
        before=len(requests)
        assert rc(trigger(root))['rc']==75
        time.sleep(.2)
        assert len(requests)==before
    finally:
        p.terminate();p.wait()
    return dict(stale_alert=True, rc=75, owner_alert_deduplicated=True)


def case_send_failure():
    global reject
    root = make('send-failure', rc=9)
    reject = True
    d = trigger(root)
    rc(d)
    wait_for(lambda: any(json.loads(p.read_text()).get('last_error') for p in d.glob('alert-*.json')))
    assert not delivered(d)
    reject = False
    rc(trigger(root))
    wait_for(lambda: delivered(d))
    state = json.loads(next(d.glob('alert-*.json')).read_text())
    assert state['attempts'] >= 2
    return dict(first_delivery_failed=True, retried=True, attempts=state['attempts'])


def case_group_cleanup():
    root = make('same-group-descendant', descendant=True)
    d = trigger(root)
    assert rc(d)['status']=='completed'
    pid=int((root/'bundle/descendant.pid').read_text())
    try:os.kill(pid,0); living=True
    except ProcessLookupError:living=False
    assert not living
    return dict(normal_exit_group_cleaned=True, rc=0)


def case_marker():
    root=make('result-markers', marker=True)
    d=trigger(root)
    r=rc(d)
    assert r['status']=='failed' and r['result_errors']
    wait_for(lambda:delivered(d))
    return dict(stage_rc=r['dry_run_rc'], artifact_failure_alert=True)


def case_journal():
    root=make('headerless-journal', marker='rm')
    d=trigger(root)
    r=rc(d)
    assert r['status']=='failed' and r['result_errors']
    wait_for(lambda:delivered(d))
    return dict(stage_rc=r['dry_run_rc'], headerless_rm_failure_alert=True)


def case_deadline():
    root=make('bounded-group-wait', descendant=True, descendant_count=32)
    d=trigger(root,WS_NIGHTLY_STOP_SECONDS='0.000001')
    r=rc(d)
    assert r['status']=='stuck' and r['rc']==70
    wait_for(lambda:delivered(d))
    return dict(status=r['status'],rc=r['rc'],bounded_wait_alert=True)


cases={'deadline':case_deadline,'journal':case_journal,'failure':case_failure,'crash':case_crash,'escaped':case_escaped,'stale':case_stale,
       'send_failure':case_send_failure,'group':case_group_cleanup,'marker':case_marker}
try:
    for name, fn in cases.items():
        if A.case not in ('all',name):continue
        results[name]=fn()
        print(name,'PASS',flush=True)
finally:
    server.shutdown();server.server_close();thread.join()
    # Only our own recorded fixture workers/processes may be stopped here.
    for d in owned:
        if (d/'progress.json').exists():
            data=json.loads((d/'progress.json').read_text())
            if not (d/'rc.txt').exists():
                for pid, grouped in ((data.get('stage_pgid'),True),(data.get('pid'),False)):
                    if pid:
                        try:(os.killpg if grouped else os.kill)(pid,signal.SIGTERM)
                        except ProcessLookupError:pass
    for path in A.out.rglob('*.pid'):
        try:os.kill(int(path.read_text()),signal.SIGTERM)
        except ProcessLookupError:pass
    (A.out/'received.json').write_text(json.dumps(requests,ensure_ascii=False,indent=2))
    (A.out/'results.json').write_text(json.dumps(results,indent=2))
    for path in A.out.rglob('*'):
        if path.is_file() and path.suffix not in ('.env',) and path.name!='ws-cleanup-nightly.sh':
            content=path.read_text(errors='replace')
            assert key not in content and endpoint not in content, 'credential leaked to artifact'
