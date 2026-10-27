#!/usr/bin/python3 -I
"""Only model-callable executable: fixed local Orca Linear read/comment operations.
No network client, subprocess shell, arbitrary paths, remote/environment flags or API.
The host wrapper is NOT callable through this helper.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent


def main():
    conf = json.loads((ROOT / 'host.json').read_text())
    state = Path(conf['state'])
    if (state / 'FUSED.json').exists():
        raise ValueError('fused')
    context = json.loads((state / 'active.json').read_text())
    args = sys.argv[1:]
    command = [conf['orca'], 'linear']
    if len(args) == 2 and args[0] == 'log':
        # Fixed PLAN 3.1 local sources only; no shell, remote host, env, or arbitrary file.
        relative = args[1]
        roots = ['.orca-state/unpushed-scan/', '.orca-state/cf-usage/reports/', 'deepvision/seo-geo/']
        exact = ['.local/state/orca-wake/wake.log', '.orca-state/notify-run/notify-run.log',
                 '.orca-state/prod-watch/last.json'] + ['.orca-state/stuck-check/' + name for name in
                    ('stuck-check.log', 'pending.json', 'heartbeat.json', 'scan-history.json')]
        import fnmatch
        allowed = relative in exact or any(relative.startswith(p) for p in roots)
        allowed = allowed or fnmatch.fnmatchcase(relative, 'orca-alerts/*.flag')
        allowed = allowed or fnmatch.fnmatchcase(relative, 'orca/workspaces/ops/reports/cleanup-*.md')
        candidate = Path(conf['home']) / relative
        if candidate.suffix not in ('.log', '.json', '.md', '.txt', '.flag'):
            raise ValueError('not a text log')
        if any(word in candidate.name.lower() for word in ('secret', 'token', 'credential', '.env')):
            raise ValueError('sensitive path')
        if not allowed or '..' in Path(relative).parts or candidate.resolve() != candidate or not candidate.is_file():
            raise ValueError('log path refused')
        if any(part.startswith('.') for part in Path(relative).parts[1:]):
            raise ValueError('hidden log refused')
        with candidate.open('rb') as f:
            f.seek(max(0, candidate.stat().st_size - 131072))
            print(f.read(131072).decode('utf-8', errors='replace'))
        return
    if args == ['read']:
        command += ['issue', context['target'], '--comments', '--json']
        body = None
    elif len(args) == 2 and args[0] == 'comment':
        body = args[1]
        if not body.strip() or len(body) > 20000 or '[Zack答' in body:
            raise ValueError('invalid comment')
        if not body.startswith(context['prefix']):
            raise ValueError('missing required comment prefix')
        if body.splitlines()[-1:] != [context['marker']]:
            raise ValueError('missing marker')
        # Durable write-intent BEFORE the network write. An ambiguous response is not retried.
        intent = state / ('write-' + context['run'] + '.json')
        fd = os.open(intent, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump({'run': context['run']}, f)
            f.flush()
            os.fsync(f.fileno())
        command += ['comment', 'add', context['target'], '--body-file', '-', '--json']
    else:
        raise ValueError('use read, comment BODY, or log RELATIVE_PATH; no other arguments')
    result = subprocess.run(command, input=None if body is None else body.encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=25,
                            env={'HOME': conf['home'], 'PATH': '/usr/bin:/bin'})
    if result.returncode:
        raise ValueError('Orca failed; no retry')
    data = json.loads(result.stdout)
    if data.get('ok') is not True:
        raise ValueError('unconfirmed; no retry')
    if body is not None:
        fd, tmp = tempfile.mkstemp(dir=state)
        with os.fdopen(fd, 'w') as f:
            json.dump({'run': context['run'], 'marker': context['marker'], 'body': body}, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, state / 'write-receipt.json')
    print(json.dumps(data, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('linear-safe: refused or unconfirmed; stop, do not retry', file=sys.stderr)
        sys.exit(1)
