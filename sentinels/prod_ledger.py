#!/usr/bin/env python3
"""iMac local production ledger. run fetches; apply reads fetch JSON; latest is read-only.
Missing ledgers require --init-baseline. Notifications never imply a completed report.
State must be local, not shared between machines. Human edits must take ledger.lock.
"""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from local_state import atomic_write, maintain_logs
from prod_fetch import WORKERS

SGT = dt.timezone(dt.timedelta(hours=8))
COLS = ['时间 SGT', 'Worker', '版本', 'version id', 'deployment id', 'commit', '报告人', 'Linear', '状态', '备注']
HEADER = '''# 生产台账

本机正本：~/.orca-state/prod-watch/prod-ledger.md；日志同目录 prod-watch-YYYYMMDD.log。
基线版本为「已知」，不叫醒；box 历史「已报」和 Linear 列未恢复。
后续变更为「未报」；叫醒尝试不等于送达，更不等于报告完成。
人工核实报告后持 prod-ledger.md.lock 排他锁，原子改为「已报」并填写 Linear。
生产哨兵只在 iMac 运行，此目录不得同步到另一台机器。

'''


def now():
    return dt.datetime.now(SGT)


def table_line(cells):
    return '| ' + ' | '.join(str(c).replace('|', '/').replace('\n', ' ') for c in cells) + ' |'


def read_rows(path):
    text = path.read_text(encoding='utf-8')
    rows = []
    for line in text.splitlines():
        if not line.startswith('|'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if cells == COLS or all(c == '---' for c in cells):
            continue
        if len(cells) != len(COLS):
            raise ValueError('台账表格损坏')
        row = dict(zip(COLS, cells))
        if not row['deployment id'] or row['状态'] not in ('已知', '未报', '已报'):
            raise ValueError('台账字段损坏')
        rows.append(row)
    if not rows or set(r['Worker'] for r in rows) != {w[0] for w in WORKERS}:
        raise ValueError('台账缺少 Worker 或含未知 Worker')
    return rows


def save_rows(path, rows):
    atomic_write(path, HEADER + table_line(COLS) + '\n' + table_line(['---'] * len(COLS)) + '\n' +
                 ''.join(table_line([r[c] for c in COLS]) + '\n' for r in rows))


def log(args, message):
    path = maintain_logs(args.state_dir, 'prod-watch')
    line = now().strftime('%Y-%m-%d %H:%M:%S') + ' ' + message
    with path.open('a', encoding='utf-8') as f:
        f.write(line + '\n')
    print(line, flush=True)


def wake(args, title, body):
    if args.no_wake:
        log(args, 'NO_WAKE：只打印，不发送：' + title)
        return
    nr = shutil.which('notify-run') or os.path.expanduser('~/.local/bin/notify-run')
    try:
        p = subprocess.run([nr, '--bot', 'coding-assistant', '--no-tty', '--task', title,
                            '--', 'sh', '-c', 'printf "%s\\n" "$1"', 'sh', body],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=180)
        # notify-run may exit zero even if delivery failed. Never mark a row reported.
        codes = re.findall(r'http=(\d{3})', p.stderr or '')
        log(args, '叫醒尝试 rc=%s http=%s；送达/已报均未确认' % (p.returncode, ','.join(codes) or '未知'))
    except (OSError, subprocess.TimeoutExpired) as e:
        log(args, '叫醒失败：' + type(e).__name__ + '；仍未报')


def parse_created_on(value):
    """Accept RFC3339 fractional seconds on macOS Python 3.9 too.

    Python 3.9 fromisoformat only accepts certain fractional widths; Cloudflare
    can return other widths. Normalize to microseconds before parsing, without
    accepting missing timestamps, invalid calendar values, or missing offsets.
    The ledger displays minutes, so sub-microsecond truncation loses no display data.
    """
    if not isinstance(value, str):
        raise ValueError('deployment 时间字段不是字符串')
    match = re.fullmatch(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})', value)
    if not match:
        raise ValueError('deployment 时间字段不是 RFC3339')
    base, fraction, zone = match.groups()
    normalized = base + ('.' + (fraction + '000000')[:6] if fraction else '')
    return dt.datetime.fromisoformat(normalized + ('+00:00' if zone == 'Z' else zone))


def validate(data, rc):
    if rc != 0 or not isinstance(data, dict) or data.get('errors'):
        raise ValueError('Cloudflare 查询失败')
    workers = data.get('workers')
    if not isinstance(workers, list) or len(workers) != len(WORKERS):
        raise ValueError('Worker 数目不完整')
    if {w['worker'] for w in workers} != {w[0] for w in WORKERS}:
        raise ValueError('Worker 名单不完整或重复')
    for w in workers:
        if not isinstance(w['deployment_id'], str) or not w['deployment_id'] or not w['versions']:
            raise ValueError('缺 deployment 或版本')
        parse_created_on(w['created_on'])
        for v in w['versions']:
            if not v.get('id') or v.get('error') or v.get('number') is None:
                raise ValueError('版本查询不完整')
    return workers


def row_for(w, baseline):
    versions = w['versions']
    number = '+'.join('v%s%s' % (v['number'], '' if v.get('percentage') in (100, 100.0, None)
                               else '(%s%%)' % v['percentage']) for v in versions)
    commit = '未知'
    for text in [w.get('message')] + [v.get('message') for v in versions]:
        m = re.search(r'\b[0-9a-f]{7,40}\b', text or '')
        if m:
            commit = m.group(0)
            break
    cells = [parse_created_on(w['created_on']).astimezone(SGT).strftime('%Y-%m-%d %H:%M'),
             w['worker'], number, '+'.join(v['id'] for v in versions), w['deployment_id'], commit,
             'ops · 23 哨兵', '—', '已知' if baseline else '未报',
             '本机基线；不追溯报告历史' if baseline else '通知不代表已报']
    return dict(zip(COLS, cells))


def process(args):
    exists = args.ledger.exists()
    if args.init_baseline and exists:
        log(args, '拒绝重建：台账已经存在')
        return 2
    if not args.init_baseline and not exists:
        log(args, '缺本机台账：请先显式 --init-baseline；本轮不比对、不叫醒')
        return 2
    rows = read_rows(args.ledger) if exists else []
    state_path = args.state_dir / 'delivery.json'
    # Broken delivery state is an error, not permission to send again immediately.
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    try:
        if args.cmd == 'run':
            p = subprocess.run([sys.executable, str(Path(__file__).with_name('prod_fetch.py'))],
                               capture_output=True, text=True, timeout=240)
            data, rc = json.loads(p.stdout), p.returncode
        else:
            data, rc = json.load(sys.stdin), args.fetch_rc
        workers = validate(data, rc)
        new_rows = [row_for(w, args.init_baseline) for w in workers]
    except (ValueError, KeyError, TypeError, AttributeError, OSError, subprocess.TimeoutExpired) as e:
        log(args, '查询失败/不完整：%s；不比对，原台账不动' % type(e).__name__)
        if not args.init_baseline:
            state['failures'] = state.get('failures', 0) + 1
            due = now().timestamp() - state.get('failure_attempt', 0) >= 21600
            if state['failures'] >= 4 and due:
                state['failure_attempt'] = now().timestamp()
                atomic_write(state_path, json.dumps(state))
                wake(args, '生产版本哨兵连续查询失败', '查不到不等于版本没变，请查看本机 prod-watch 日志。')
            atomic_write(state_path, json.dumps(state))
        return 3
    if args.init_baseline:
        save_rows(args.ledger, new_rows)
        log(args, '基线完成：%d 个已知，0 个未报；不叫醒' % len(new_rows))
        return 0
    last = {r['Worker']: r for r in rows}
    changes = [r for r in new_rows if r['deployment id'] != last[r['Worker']]['deployment id']]
    if changes:
        rows.extend(changes)
        save_rows(args.ledger, rows)
    state['failures'] = 0
    state.pop('failure_attempt', None)
    pending = [r for r in rows if r['状态'] == '未报']
    if pending and (changes or now().timestamp() - state.get('pending_attempt', 0) >= 21600):
        # Write before sending: a crash leaves pending intact and delays retry at most six hours.
        state['pending_attempt'] = now().timestamp()
        atomic_write(state_path, json.dumps(state))
        body = '\n'.join('%s %s %s SGT' % (r['Worker'], r['版本'], r['时间 SGT']) for r in pending[-20:])
        wake(args, '生产变更未报：共 %d 条' % len(pending), body + '\n完整本机台账：' + str(args.ledger))
    atomic_write(state_path, json.dumps(state))
    log(args, '完成：%d 个未变，%d 个变化，%d 个未报，0 个查询错误' % (len(workers) - len(changes), len(changes), len(pending)))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('cmd', choices=['run', 'apply', 'latest'])
    ap.add_argument('--state-dir', type=Path, default=Path(os.environ.get('PROD_WATCH_STATE_DIR', '~/.orca-state/prod-watch')).expanduser())
    ap.add_argument('--ledger', type=Path, default=os.environ.get('PROD_LEDGER'))
    ap.add_argument('--fetch-rc', type=int, default=0)
    ap.add_argument('--init-baseline', action='store_true')
    ap.add_argument('--no-wake', action='store_true', help='仅允许临时目录；只打印叫醒，不发送')
    args = ap.parse_args()
    args.state_dir = args.state_dir.expanduser().resolve()
    args.ledger = (args.ledger or args.state_dir / 'prod-ledger.md').expanduser().resolve()
    if args.ledger.parent != args.state_dir:
        ap.error('台账必须位于 --state-dir 内；隔离运行请显式指定状态目录')
    if args.no_wake:
        roots = (Path('/tmp').resolve(), Path(tempfile.gettempdir()).resolve())
        if not all(any(root in p.parents for root in roots) for p in (args.state_dir, args.ledger)):
            ap.error('--no-wake 只允许状态和台账都在临时目录')
    if args.cmd == 'latest':
        try:
            for r in {r['Worker']: r for r in read_rows(args.ledger)}.values():
                print('%s %s %s' % (r['Worker'], r['版本'], r['状态']))
            return 0
        except (OSError, ValueError) as e:
            print('台账不可读：' + type(e).__name__, file=sys.stderr)
            return 2
    os.umask(0o077)
    args.state_dir.mkdir(parents=True, exist_ok=True)
    args.ledger.parent.mkdir(parents=True, exist_ok=True)
    with open(str(args.ledger) + '.lock', 'a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('已有生产哨兵持锁，本轮不运行', file=sys.stderr)
            return 4
        try:
            result = process(args)
            if result == 0:
                atomic_write(args.state_dir / 'local-errors.json', '{}')
            return result
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
            log(args, '本机状态错误：%s；停止比对' % type(e).__name__)
            if not args.init_baseline:
                error_path = args.state_dir / 'local-errors.json'
                try:
                    errors = json.loads(error_path.read_text())
                except (OSError, ValueError):
                    errors = {}
                errors['count'] = errors.get('count', 0) + 1
                due = now().timestamp() - errors.get('attempt', 0) >= 21600
                send = errors['count'] >= 4 and due
                if send:
                    errors['attempt'] = now().timestamp()
                atomic_write(error_path, json.dumps(errors))
                if send:
                    wake(args, '生产版本哨兵本机状态连续出错', '未比对生产版本，请人工核查本机台账和状态；不要重建基线掩盖未报。')
            return 2


if __name__ == '__main__':
    sys.exit(main())
