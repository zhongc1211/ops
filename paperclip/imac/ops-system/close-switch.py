#!/usr/bin/python3 -I
"""OPS-10 only. Offline plan by default; cleanup BEFORE installation, never resume."""
import argparse
import datetime as dt
from decimal import Decimal
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import host
spec = importlib.util.spec_from_file_location('cleanup_common', HERE / 'close-failed-e2e.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
read, sha = common.read_regular, common.sha
FAILED_HOST_SHA256 = '5f2b0507888c96488d33a168e72cbbdb5bb7c8003d4db2c10102996b8d6c68e8'
RUN = '99f48df5-8fca-4f4a-bd53-3933967fa280'
ISSUE = 'de46c8d5-6ad9-4381-9e24-d0a2c96f7ba8'
CLAIM = 'issue-' + sha(ISSUE.encode()) + '.json'
COST = 'cost-' + RUN + '.json'
REMOVE = {'FUSED.json', 'INFLIGHT.json', CLAIM}


def source_hashes():
    return {**common.install_source_hashes(), 'close-switch.py': sha(read(HERE / 'close-switch.py'))}


def needs_receipt(installed_sha, runs):
    return installed_sha == FAILED_HOST_SHA256 and any(r['id'] == RUN for r in runs)


def bind(root):
    common.private_directory(root)
    common.private_directory(root / 'state')
    conf = json.loads(read(root / 'host.json'))
    host.require(conf['api'] == 'http://127.0.0.1:3110' and conf['state'] == str(root / 'state'), 'switch_wrong_root')
    host.CONF = conf
    return conf


def guard(status):
    c, api = host.CONF, host.api
    a = api('GET', '/agents/' + c['agent'])
    host.require(a['status'] == 'paused' and a['companyId'] == c['company']
                 and a['adapterType'] == 'claude_local' and a['adapterConfig']['engine'] == 'cli'
                 and a['adapterConfig']['command'] == str(Path(c['state']).parent / 'host.py'), 'switch_agent_not_safe')
    rows = api('GET', '/companies/' + c['company'] + '/heartbeat-runs?agentId=' + c['agent'] + '&limit=1000')
    host.require(isinstance(rows, list) and 0 < len(rows) < 1000
                 and all(r['status'] in ('succeeded', 'failed', 'cancelled', 'timed_out')
                         and not r.get('scheduledRetryAt') for r in rows), 'switch_active_history')
    r = api('GET', '/heartbeat-runs/' + RUN)
    ctx = r.get('contextSnapshot') or {}
    host.require(r['id'] == RUN and r['agentId'] == c['agent'] and r['companyId'] == c['company']
                 and (ctx.get('issueId') or ctx.get('taskId')) == ISSUE
                 and r['status'] == 'cancelled' and r['errorCode'] == 'agent_paused'
                 and r['startedAt'] == '2026-10-28T23:33:46.213Z'
                 and r['finishedAt'] == '2026-10-28T23:34:06.857Z'
                 and not r.get('retryOfRunId') and not r.get('scheduledRetryAt'), 'switch_run_changed')
    related = [x['id'] for x in rows if ((x.get('contextSnapshot') or {}).get('issueId') or
                                      (x.get('contextSnapshot') or {}).get('taskId')) == ISSUE]
    host.require(related == [RUN], 'switch_second_run')
    common.no_process(r['processPid'])
    common.no_process(r['processGroupId'], group=True)
    i = api('GET', '/issues/' + ISSUE)
    host.require(i['identifier'] == 'OPS-10' and i['status'] == status and i['companyId'] == c['company']
                 and i['assigneeAgentId'] == c['agent'] and i['executionRunId'] is None
                 and i['originKind'] == 'routine_execution' and i['originId'] in c['routines']
                 and i['originId'] != c['drillRoutine'] and i['parentId'] is None
                 and not i.get('conversationAgentId'), 'switch_issue_changed')
    goal = api('GET', '/issues/' + ISSUE + '/runner-goal?agentId=' + c['agent'])
    host.require(goal['issueId'] == ISSUE and goal['agentId'] == c['agent']
                 and goal['goal'] is None and goal['pendingAction'] is None, 'switch_goal_present')
    triggers = []
    host.require(len(c['routines']) == 2, 'switch_routines_changed')
    for rid in c['routines']:
        routine = api('GET', '/routines/' + rid)
        host.require(routine['companyId'] == c['company'] and len(routine['triggers']) == 1
                     and all(t['enabled'] is False for t in routine['triggers']), 'switch_trigger_enabled')
        triggers.append({'id': rid, 'triggers': routine['triggers']})
    return {'history': sorted(({'id': x['id'], 'status': x['status']} for x in rows), key=lambda x: x['id']),
            'triggers': sorted(triggers, key=lambda x: x['id']), 'spent': a['spentMonthlyCents']}


def snapshot(state):
    # No bearer/env/config: state consists of private audit files only.
    return {p.name: read(p) for p in state.iterdir()}


def check_incident(data):
    j = lambda n: json.loads(data[n])
    host.require(j('FUSED.json') == {'reason': 'no_helper_receipt', 'at': '2026-10-28T23:34:06.838083+00:00'}
                 and j('INFLIGHT.json') == {'run': RUN, 'at': '2026-10-28T23:33:46.815029+00:00'}
                 and j(CLAIM) == {'run': RUN, 'started': '2026-10-28T23:33:46.815029+00:00'}, 'switch_incident_changed')
    host.require(j('last-model-result.json') == {'run': RUN, 'costUsd': 0.0548338, 'exitCode': 0, 'isError': False}
                 and j('reservations.json') == {'2026-10': 1400}, 'switch_result_changed')
    cost = j(COST)
    host.require(cost['run'] == RUN and cost['status'] == 'cli_reported'
                 and Decimal(cost['costUsdExact']) == Decimal('0.0548338')
                 and Decimal(str(cost['costUsd'])) == Decimal('0.0548338')
                 and cost['outcome'] == 'failed' and cost['reason'] == 'no_helper_receipt', 'switch_cost_changed')
    host.require('write-' + RUN + '.json' not in data and 'comment-' + RUN + '.json' not in data,
                 'switch_unexpected_write')


def verify_completed(root, backup, aid, cid, after_install=False):
    common.private_directory(backup)
    host.require(backup.parent == root / 'backups', 'switch_backup_path')
    saved = json.loads(read(backup / 'snapshot.json'))
    progress = json.loads(read(backup / 'progress.json'))
    c = bind(root)
    host.require(c['agent'] == aid == saved['agent'] and c['company'] == cid == saved['company']
                 and saved['source'] == source_hashes() and saved['oldHost'] == FAILED_HOST_SHA256
                 and progress == {'phase': 'complete', 'snapshotSha256': sha(read(backup / 'snapshot.json'))},
                 'switch_receipt_changed')
    originals = {n: read(backup / n) for n in saved['files']}
    host.require(all(sha(b) == saved['files'][n] for n, b in originals.items()), 'switch_backup_changed')
    check_incident(originals)
    host.require(snapshot(root / 'state') == {n: b for n, b in originals.items() if n not in REMOVE},
                 'switch_history_changed')
    host.require(guard('cancelled') == saved['before'], 'switch_api_changed')
    return sha(read(backup / 'snapshot.json'))


def apply(root):
    c = bind(root)
    host.require(sha(read(root / 'host.py')) == FAILED_HOST_SHA256, 'switch_cleanup_old_host_first')
    state = root / 'state'
    read(state / 'host.lock')
    fd = os.open(state / 'host.lock', os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = guard('blocked')
        originals = snapshot(state)
        check_incident(originals)
        common.private_directory(root / 'backups')
        backup = root / 'backups' / ('ops10-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
        backup.mkdir(mode=0o700)
        for n, b in originals.items():
            common.backup_bytes(backup / n, b)
        host.store(backup / 'snapshot.json', {'agent': c['agent'], 'company': c['company'], 'before': before,
                   'oldHost': FAILED_HOST_SHA256, 'source': source_hashes(),
                   'files': {n: sha(b) for n, b in originals.items()}})
        common.fsync_directory(backup)
        common.fsync_directory(backup.parent)
        print('BACKUP:', backup, flush=True)
        host.require(guard('blocked') == before and snapshot(state) == originals, 'switch_prewrite_changed')
        try:
            # r7 already imported actual cost. Verify/retain the exact per-run row;
            # never add a second charge or overwrite it with Paperclip zero.
            host.store(backup / 'progress.json', {'phase': 'local_actual_cost_verified', 'costUsdExact': '0.0548338'})
            updated = host.api('PATCH', '/issues/' + ISSUE, {'status': 'cancelled'})
            host.require(updated['id'] == ISSUE and updated['status'] == 'cancelled'
                         and guard('cancelled') == before, 'switch_close_unconfirmed')
            host.require(snapshot(state) == originals, 'switch_state_changed')
            for n in (CLAIM, 'INFLIGHT.json', 'FUSED.json'):
                host.require(read(state / n) == originals[n], 'switch_remove_changed')
                (state / n).unlink()
                common.fsync_directory(state)
            host.store(backup / 'progress.json', {'phase': 'complete', 'snapshotSha256': sha(read(backup / 'snapshot.json'))})
            verify_completed(root, backup, c['agent'], c['company'])
        except BaseException:
            host.store(state / 'FUSED.json', {'reason': 'switch_cleanup_incomplete', 'at': dt.datetime.now(dt.timezone.utc).isoformat()})
            raise
        print('PASS: OPS-10 cancelled; local actual $0.0548338 retained; Paperclip spend unchanged by cleanup; reservation 1400 unchanged')
        print('NEXT: same source install --switch-cleanup-backup', backup, '; no resume/fire')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--apply', action='store_true')
    p.add_argument('--root', type=Path, default=Path.home() / '.local/share/paperclip-ops/ops-system-host')
    a = p.parse_args()
    print('PLAN: paused + BOTH triggers disabled; pinned OPS-10/run/old host; lock and private backup')
    print('PLAN: verify already imported $0.0548338; cancel OPS-10; remove only its claim/INFLIGHT/FUSED')
    print('PLAN: preserve all costs/history/receipts/reservations; receipt-bound install; no resume/fire')
    if a.apply:
        apply(a.root.resolve(strict=True))
    else:
        print('DRY RUN: no API, installed files, process checks or writes')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('REFUSED/INCOMPLETE: ' + host.reason_code(error) + '; inspect backup, never blindly retry', file=sys.stderr)
        sys.exit(70)
