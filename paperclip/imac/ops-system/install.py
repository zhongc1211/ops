"""Offline plan by default; --inspect reads history; --apply needs operator approval.
S12 r5: cleanup first on failed host, then receipt-bound reinstall; retain history.
No trigger, resume, grant changes, secret files, DB access, or LaunchAgent changes.
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
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


def readback_configuration(api, aid, adapter_config, routines):
    """Compare the whole API-visible adapter object, not just retained keys.
    No mismatch is repaired here; do not print success for a partial rollback.
    """
    agent = api('GET', '/agents/' + aid)
    host.require(agent['status'] == 'paused', 'agent_not_paused_on_readback')
    host.require(agent['adapterConfig'] == adapter_config, 'adapter_config_readback_mismatch')
    host.require(len(routines) == 2, 'expected_two_routines')
    for rid, expected in routines.items():
        host.require(set(expected) == {'description', 'concurrencyPolicy', 'catchUpPolicy'}, 'incomplete_routine_snapshot')
        actual = api('GET', '/routines/' + rid)
        host.require({key: actual[key] for key in expected} == expected, 'routine_readback_mismatch')


def readback_instruction(api, route, content, committed):
    actual = api('GET', route + '?path=AGENTS.md')
    host.require(actual['content'] == content and actual['path'] == 'AGENTS.md', 'instruction_readback_mismatch')
    # Rollback restores bytes as a NEW revision, never rewinds to the old revision.
    # Check after config replacement too: restored paths must resolve that revision.
    revision = committed['revision']['id']
    host.require(actual['revision']['id'] == revision, 'instruction_revision_readback_mismatch')


def run_snapshot(api, cid, aid, label, expected=None):
    # v2026.1012.0 services/heartbeat.ts:793–817. Unknown is NOT terminal.
    host.require(api('GET', '/agents/' + aid)['status'] == 'paused', 'agent_not_paused')
    rows = api('GET', '/companies/' + cid + '/heartbeat-runs?agentId=' + aid + '&limit=1000')
    host.require(isinstance(rows, list) and len(rows) < 1000, 'run_history_incomplete')
    terminal = {'succeeded', 'interrupted', 'failed', 'cancelled', 'timed_out'}
    result = []
    for r in rows:
        host.require(isinstance(r, dict) and isinstance(r.get('id'), str)
                     and re.fullmatch(r'[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}', r['id']),
                     'bad_run_history_id')
        host.require(r['agentId'] == aid and r['companyId'] == cid, 'run_history_owner_mismatch')
        result.append({'id': r['id'], 'status': r['status']})
    result.sort(key=lambda r: r['id'])
    print(label + ': ' + json.dumps(result), flush=True)
    host.require(len({r['id'] for r in result}) == len(result), 'duplicate_run_history')
    host.require(all(r['status'] in terminal for r in result), 'active_or_unknown_runs')
    if expected is not None:
        host.require(result == expected, 'runs_changed')
    return result


def load_cleanup():
    spec = importlib.util.spec_from_file_location('ops_cleanup', HERE / 'close-failed-e2e.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--apply', action='store_true')
    p.add_argument('--inspect', action='store_true', help='Read-only paused/run-history plan; no key check or writes')
    p.add_argument('--cleanup-backup', type=Path, help='Completed cleanup backup; required for this failed-host upgrade')
    p.add_argument('--claude', type=Path)
    p.add_argument('--linear-author', help='Expected shared Linear account, supplied by operator; never committed')
    p.add_argument('--rollback', type=Path, help='Backup directory; still requires --apply')
    a = p.parse_args()
    root = Path.home() / '.local/share/paperclip-ops/ops-system-host'
    target = Path(os.environ['AGENT_SETTINGS'])
    print('PLAN: cleanup FIRST for failed E2E; then backup/install; paused; terminal history preserved; no triggers')
    print('PLAN: rollback' if a.rollback else 'PLAN: install', str(root))
    host.require(not (a.apply and a.inspect), 'choose_inspect_or_apply')
    host.require(not (a.rollback and a.cleanup_backup), 'cleanup_receipt_is_for_install')
    if not a.apply and not a.inspect:
        print('PLAN_RUNS: not read in offline mode; --inspect or --apply prints actual IDs/statuses')
        print('DRY RUN: no API calls, no files changed; execution approval is checked by operator')
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
    runs = run_snapshot(api, cid, aid, 'PLAN_RUNS')
    if a.inspect:
        print('READ-ONLY PLAN: history shown; apply also checks cleanup receipt/configuration; no writes or key check')
        return
    cleanup = load_cleanup()
    receipt_digest = None
    if not a.rollback:
        # Never overwrite an unsettled wrapper. The known old-host upgrade must
        # carry the completed cleanup receipt, not a manually deleted fuse.
        host.require(not os.path.lexists(root / 'state/FUSED.json') and not os.path.lexists(root / 'state/INFLIGHT.json'),
                     'cleanup_required_before_install')
        old_failed_host = (root / 'host.py').exists() and digest(root / 'host.py') == cleanup.FAILED_HOST_SHA256
        host.require(not (runs and old_failed_host) or a.cleanup_backup is not None, 'cleanup_receipt_required')
        if a.cleanup_backup:
            a.cleanup_backup = a.cleanup_backup.resolve(strict=True)
            receipt_digest = cleanup.verify_completed(root, a.cleanup_backup, aid, cid)
    bundle_route = '/agents/' + aid + '/instructions-bundle/file'
    old_instruction = api('GET', bundle_route + '?path=AGENTS.md')
    if a.rollback:
        backup = a.rollback.resolve()
        saved = json.loads((backup / 'snapshot.json').read_text())
        host.require(saved['agent'] == aid and saved['company'] == cid, 'wrong_backup')
        restored_instruction = api('PUT', bundle_route, {'path': 'AGENTS.md', 'content': saved['instructions'],
                                'baseRevisionId': (old_instruction.get('revision') or {}).get('id')})
        # v2026.1012.0 routes/agents.ts:5557–5558,5608–5628:
        # default PATCH shallow-merges; true is required to REMOVE newly added keys.
        api('PATCH', '/agents/' + aid, {'adapterConfig': saved['adapterConfig'],
                                      'replaceAdapterConfig': True})
        for name, value in saved['routines'].items():
            api('PATCH', '/routines/' + name, value)
        write(target, (backup / 'settings.json').read_bytes())
        for name in ('host.py', 'linear-safe.py', 'host.json', 'manifest.json'):
            if (backup / name).exists():
                write(root / name, (backup / name).read_bytes(), 0o700 if name.endswith('.py') else 0o600)
        readback_configuration(api, aid, saved['adapterConfig'], saved['routines'])
        readback_instruction(api, bundle_route, saved['instructions'], restored_instruction)
        host.require(digest(target) == digest(backup / 'settings.json')
                     and stat.S_IMODE(target.stat().st_mode) == 0o600, 'rollback_settings_mismatch')
        run_snapshot(api, cid, aid, 'READBACK_RUNS', runs)
        # Keep host files/fuse/claims; never erase evidence or re-enable the model.
        print('ROLLBACK read back: full adapterConfig, two routines, instructions/revision, settings; paused; history/state retained')
        return
    host.require(a.claude is not None and a.claude.is_absolute() and a.claude.is_file(), 'claude_path_required')
    host.require(a.linear_author and len(a.linear_author) <= 100, 'linear_author_required')
    host.require(agent['adapterConfig'].get('dangerouslySkipPermissions') is False, 'unsafe_existing_config')
    provision = load_provision()
    host.require(agent['adapterConfig'].get('extraArgs') == provision.EXTRA_ARGS, 'extra_args_changed')
    # key-fill --check exits zero for BOTH 有 and 没有. Require the affirmative
    # output before any mkdir/backup/file write/API mutation; unknown is a refusal.
    key_check = subprocess.run(['/bin/bash', str(HERE.parent / 'key-fill.sh'), '--check'],
                               capture_output=True, text=True, timeout=60)
    host.require(key_check.returncode == 0 and key_check.stdout.strip() == '有', 'key_not_confirmed_present')
    routines = api('GET', '/companies/' + cid + '/routines')
    selected = [r for r in routines if r['title'] in (os.environ['ROUTINE_OPS_TITLE'], os.environ['ROUTINE_TEST_TITLE'])]
    host.require(len(selected) == 2, 'missing_routines')
    expected = json.dumps(settings(str(Path.home())), indent=2, ensure_ascii=False) + '\n'
    host.require((HERE / 'settings.json').read_text() == expected, 'regenerate_settings_for_target_home')
    # Recheck after potentially slow preflight, before any backup/deployment write.
    run_snapshot(api, cid, aid, 'PREWRITE_RUNS', runs)
    if receipt_digest is not None:
        host.require(cleanup.verify_completed(root, a.cleanup_backup, aid, cid) == receipt_digest, 'cleanup_receipt_changed')
    # Back up before any installed file or API mutation, including repeated apply.
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    host.require(root.resolve() == root, 'host_root_symlink')
    os.chmod(root, 0o700)
    backup = root / 'backups' / dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup.mkdir(parents=True, mode=0o700)
    os.chmod(backup.parent, 0o700)
    write(backup / 'settings.json', target.read_bytes())
    fields = ('description', 'concurrencyPolicy', 'catchUpPolicy')
    host.store(backup / 'snapshot.json', {'agent': aid, 'company': cid, 'runs': runs,
        'cleanupBackup': str(a.cleanup_backup) if a.cleanup_backup else None,
        'cleanupSnapshotSha256': receipt_digest,
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
    committed_instruction = old_instruction
    if old_instruction['content'] != content:
        committed_instruction = api('PUT', bundle_route, {'path': 'AGENTS.md', 'content': content,
                                'baseRevisionId': (old_instruction.get('revision') or {}).get('id')})
    # Re-read config: instruction API may have updated its managed path/revision fields.
    config = api('GET', '/agents/' + aid)['adapterConfig']
    config.update({'command': str(root / 'host.py'), 'timeoutSec': 900, 'graceSec': 5,
                   'dangerouslySkipPermissions': False})
    api('PATCH', '/agents/' + aid, {'adapterConfig': config})
    expected_routines = {}
    for routine in selected:
        template = next(r['description'] for r in provision.ROUTINES if r['title'] == routine['title'])
        expected_routines[routine['id']] = {'description': template,
              'concurrencyPolicy': 'coalesce_if_active', 'catchUpPolicy': 'skip_missed'}
        api('PATCH', '/routines/' + routine['id'], expected_routines[routine['id']])
    for name in ('host.py', 'linear-safe.py'):
        host.require(digest(root / name) == digest(HERE / name), 'host_file_readback_mismatch')
    host.require(json.loads((root / 'host.json').read_text()) == conf, 'host_config_readback_mismatch')
    host.store(root / 'manifest.json', {str(f): digest(f) for f in (target, root / 'host.py', root / 'linear-safe.py', root / 'host.json')})
    # Whole-object equality includes command/timeoutSec/graceSec/extraArgs/skip.
    readback_configuration(api, aid, config, expected_routines)
    readback_instruction(api, bundle_route, content, committed_instruction)
    host.require(target.read_text() == expected and stat.S_IMODE(target.stat().st_mode) == 0o600, 'settings_mismatch')
    run_snapshot(api, cid, aid, 'READBACK_RUNS', runs)
    if receipt_digest is not None:
        host.require(cleanup.verify_completed(root, a.cleanup_backup, aid, cid, after_install=True) == receipt_digest,
                     'cleanup_receipt_changed')
    print('PASS: full adapterConfig/two routines/instructions revision/hashes/settings mode/paused/unchanged terminal history; backup:', backup)
    print('Instructions sha256:', hashlib.sha256(content.encode()).hexdigest())
    print('Settings sha256:', digest(target))


if __name__ == '__main__':
    main()
