# heartbeat-watch 演练用的固定时钟：PYTHONPATH 指到这个目录、并且设了 HB_FAKE_NOW（秒）时，time.time() 和
# datetime.datetime.now() 都停在这个时刻，time.sleep() 不等。新旧两版 heartbeat-watch 才能逐字节比输出。
import os

_now = os.environ.get("HB_FAKE_NOW")
if _now:
    import datetime as _dt
    import time as _time

    _t = float(_now)
    _time.time = lambda: _t
    _time.sleep = lambda s: None

    class _FrozenDateTime(_dt.datetime):
        @classmethod
        def now(cls, tz=None):
            return cls.fromtimestamp(_t, tz)

    _dt.datetime = _FrozenDateTime
