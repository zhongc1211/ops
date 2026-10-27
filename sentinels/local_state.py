#!/usr/bin/env python3
"""Local-only atomic storage and bounded daily logs (caller holds its lock)."""
import datetime as dt
import os
from pathlib import Path
import tempfile


def atomic_write(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def maintain_logs(directory, prefix):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    today = dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).date()
    for path in directory.glob(prefix + '-*'):
        suffix = path.name[len(prefix) + 1:]
        if len(suffix) != 12 and len(suffix) != 14:
            continue
        if suffix[8:] not in ('.log', '.log.1'):
            continue
        try:
            day = dt.datetime.strptime(suffix[:8], '%Y%m%d').date()
        except ValueError:
            continue
        if (today - day).days >= 14:
            path.unlink()
    path = directory / (prefix + '-' + today.strftime('%Y%m%d') + '.log')
    if path.exists() and path.stat().st_size >= 2 * 1024 * 1024:
        os.replace(path, str(path) + '.1')
    return path
