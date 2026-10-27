"""Plan by default. --apply requires separate installation approval (S12 r2).
No trigger, resume, grant changes, secret files, DB access, or LaunchAgent changes.
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import host
from generate import settings


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_provision():
    spec = importlib.util.spec_from_file_location('provision', HERE.parent / 'provision.py')
    module = importlib.util.module_from_spec(spec)
    # provision's legacy argv parser should not consume this installer's options.
    old = sys.argv
    sys.argv = [old[0]]
    try:
        spec.loader.exec_module(module)
    finally:
        sys.argv = old
    return module


def write(path, data, mode=0o600):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.is_symlink():
        raise RuntimeError('refuse_symlink')
    temp = path.with_name(path.name + '.new')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    with os.fdopen(fd, 'wb') as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(temp, mode)
    os.replace(temp, path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--apply', action='store_true')
    p.add_argument('--claude', type=Path)
    p.add_argument('--linear-author', help='Expected shared Linear account, supplied by operator; never committed')
    p.add_argument('--rollback', type=Path, help='Backup directory; still requires --apply')
    a = p.parse_args()
    root = Path.home() / '.local/share/paperclip-ops/ops-system-host'
    target = Path(os.environ['AGENT_SETTINGS'])
    print('PLAN: backup then install host + restricted helper + settings + AGENTS; paused only; zero runs; no triggers')
    print('PLAN: rollback' if a.rollback else 'PLAN: install', str(root))
    if not a.apply:
        print('DRY RUN: no API calls, no files changed; separate Zack installation approval required')
        return
    host.CONF = {'api': os.environ['API_URL']}
    api = host.api
    companies = api('GET', '/companies')
    company = next(c for c in companies if c['name'] == os.environ['COMPANY_NAME'])
    cid = company['id']
    agents = api('GET', '/companies/' + cid + '/agents')
    agent = next(x for x in agents if x['name'] == os.environ['AGENT_NAME'])
    aid = agent['id']
    agent = api('GET', '/agents/' + aid)
    host.require(agent['status'] == 'paused', 'agent_not_paused')
    runs = api('GET', '/companies/' + cid + '/heartbeat-runs?agentId=' + aid + '&limit=1000')
    # Rollback may follow the approved single E2E, but never while a run is active.
    host.require(not any(r['status'] in ('queued', 'running', 'scheduled_retry') for r in runs), 'active_runs')
    if not a.rollback:
        host.require(runs == [], 'nonzero_runs_install_refused')
    bundle_route = '/agents/' + aid + '/instructions-bundle/file'
    old_instruction = api('GET', bundle_route + '?path=AGENTS.md')
    if a.rollback:
        backup = a.rollback.resolve()
        saved = json.loads((backup / 'snapshot.json').read_text())
        host.require(saved['agent'] == aid and saved['company'] == cid, 'wrong_backup')
        api('PUT', bundle_route, {'path': 'AGENTS.md', 'content': saved['instructions'],
                                'baseRevisionId': (old_instruction.get('revision') or {}).get('id')})
        api('PATCH', '/agents/' + aid, {'adapterConfig': saved['adapterConfig']})
        for name, value in saved['routines'].items():
            api('PATCH', '/routines/' + name, value)
        write(target, (backup / 'settings.json').read_bytes())
        for name in ('host.py', 'linear-safe.py', 'host.json', 'manifest.json'):
            if (backup / name).exists():
                write(root / name, (backup / name).read_bytes(), 0o700 if name.endswith('.py') else 0o600)
        host.require(api('GET', bundle_route + '?path=AGENTS.md')['content'] == saved['instructions'], 'rollback_instruction_mismatch')
        host.require(digest(target) == digest(backup / 'settings.json'), 'rollback_settings_mismatch')
        # Keep host files/fuse/claims; never erase evidence or re-enable the model.
        host.require(api('GET', '/agents/' + aid)['status'] == 'paused', 'rollback_not_paused')
        print('ROLLBACK read back; paused; host state retained')
        return
    host.require(a.claude is not None and a.claude.is_absolute() and a.claude.is_file(), 'claude_path_required')
    host.require(a.linear_author and len(a.linear_author) <= 100, 'linear_author_required')
    host.require(agent['adapterConfig'].get('dangerouslySkipPermissions') is False, 'unsafe_existing_config')
    provision = load_provision()
    host.require(agent['adapterConfig'].get('extraArgs') == provision.EXTRA_ARGS, 'extra_args_changed')
    # --check reports presence only; never --fill or open the underlying key file.
    subprocess.run(['/bin/bash', str(HERE.parent / 'key-fill.sh'), '--check'], check=True, timeout=60)
    routines = api('GET', '/companies/' + cid + '/routines')
    selected = [r for r in routines if r['title'] in (os.environ['ROUTINE_OPS_TITLE'], os.environ['ROUTINE_TEST_TITLE'])]
    host.require(len(selected) == 2, 'missing_routines')
    expected = json.dumps(settings(str(Path.home())), indent=2, ensure_ascii=False) + '\n'
    host.require((HERE / 'settings.json').read_text() == expected, 'regenerate_settings_for_target_home')
    # Back up before any installed file or API mutation, including repeated apply.
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    host.require(root.resolve() == root, 'host_root_symlink')
    os.chmod(root, 0o700)
    backup = root / 'backups' / dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup.mkdir(parents=True, mode=0o700)
    os.chmod(backup.parent, 0o700)
    write(backup / 'settings.json', target.read_bytes())
    fields = ('description', 'concurrencyPolicy', 'catchUpPolicy')
    host.store(backup / 'snapshot.json', {'agent': aid, 'company': cid,
        'adapterConfig': agent['adapterConfig'], 'instructions': old_instruction['content'],
        'routines': {r['id']: {k: r[k] for k in fields} for r in selected}})
    for name in ('host.py', 'linear-safe.py', 'host.json', 'manifest.json'):
        if (root / name).exists():
            shutil.copy2(root / name, backup / name)
            os.chmod(backup / name, 0o600)
    state = root / 'state'
    state.mkdir(mode=0o700, exist_ok=True)
    host.require(state.resolve() == state and target.resolve() == target, 'target_symlink')
    os.chmod(state, 0o700)
    if not (state / 'reservations.json').exists():
        host.store(state / 'reservations.json', {})
    conf = {'api': os.environ['API_URL'], 'home': str(Path.home()), 'agent': aid, 'company': cid,
            'routines': [r['id'] for r in selected], 'state': str(state), 'settings': str(target),
            'drillRoutine': next(r['id'] for r in selected if r['title'] == os.environ['ROUTINE_TEST_TITLE']),
            'claude': str(a.claude), 'timeout': os.environ['TIMEOUT'],
            'orca': '/Applications/Orca.app/Contents/Resources/bin/orca',
            'linearAuthor': a.linear_author,
            'instructionsSha256': digest(HERE / 'AGENTS.md')}
    for name in ('host.py', 'linear-safe.py'):
        write(root / name, (HERE / name).read_bytes(), 0o700)
    host.store(root / 'host.json', conf)
    write(target, expected.encode())
    content = (HERE / 'AGENTS.md').read_text()
    if old_instruction['content'] != content:
        api('PUT', bundle_route, {'path': 'AGENTS.md', 'content': content,
                                'baseRevisionId': (old_instruction.get('revision') or {}).get('id')})
    # Re-read config: instruction API may have updated its managed path/revision fields.
    config = api('GET', '/agents/' + aid)['adapterConfig']
    config.update({'command': str(root / 'host.py'), 'timeoutSec': 900, 'graceSec': 5,
                   'dangerouslySkipPermissions': False})
    api('PATCH', '/agents/' + aid, {'adapterConfig': config})
    for routine in selected:
        template = next(r['description'] for r in provision.ROUTINES if r['title'] == routine['title'])
        api('PATCH', '/routines/' + routine['id'], {'description': template,
              'concurrencyPolicy': 'coalesce_if_active', 'catchUpPolicy': 'skip_missed'})
    host.store(root / 'manifest.json', {str(f): digest(f) for f in (target, root / 'host.py', root / 'linear-safe.py', root / 'host.json')})
    readback = api('GET', '/agents/' + aid)
    host.require(readback['status'] == 'paused', 'agent_changed_status')
    host.require(readback['adapterConfig']['extraArgs'] == provision.EXTRA_ARGS, 'extra_args_changed')
    host.require(readback['adapterConfig']['dangerouslySkipPermissions'] is False, 'unsafe_readback')
    host.require(api('GET', bundle_route + '?path=AGENTS.md')['content'] == content, 'instruction_mismatch')
    host.require(target.read_text() == expected and stat.S_IMODE(target.stat().st_mode) == 0o600, 'settings_mismatch')
    host.require(api('GET', '/companies/' + cid + '/heartbeat-runs?agentId=' + aid + '&limit=1000') == [], 'runs_changed')
    print('PASS: hashes/settings mode/paused/zero runs/extraArgs; backup:', backup)
    print('Instructions sha256:', hashlib.sha256(content.encode()).hexdigest())
    print('Settings sha256:', digest(target))


if __name__ == '__main__':
    main()
