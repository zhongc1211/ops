# PER-134 对照用：经 PYTHONPATH 载入 stuck-check 的 python 进程。只在设了 PER134_MODE 时生效。
#   record：命令照真跑，把 (命令, stdin, 返回码, stdout, stderr) 按顺序记进 PER134_TAPE，并记下开始时间。
#   replay：不跑任何外部命令，按命令和第几次出现从磁带取结果；time.time() 固定在录制时的开始时间，
#           datetime.now 跟着它走，time.sleep 不睡（脚本里的等待只是重试和 POST 间隔），
#           所以 base 和 head 的「多久没动」「今天几号」和写进状态的时间戳逐位相同。
# 两种模式都拦两类调用，不放行、只记一笔：curl（webhook 发送；replay 时回 200，见 PER134_CURL）、
# 带 --environment grok-bot 的 orca 调用（box 已退出开发，不碰）。
import os
if os.environ.get("PER134_MODE") in ("record", "replay"):
    import datetime, json, subprocess, time

    MODE, TAPE = os.environ.pop("PER134_MODE"), os.environ["PER134_TAPE"]  # pop：子进程（如 agent-probe）不再套一层
    LOGF = os.environ.get("PER134_CALLS") or TAPE + ".calls"
    _real_popen, _real_time = subprocess.Popen, time.time
    if MODE == "record":
        tape = {"start": _real_time(), "calls": []}
    else:
        tape = json.load(open(TAPE, encoding="utf-8"))
        time.time = lambda: tape["start"]
        time.sleep = lambda s: None

        class _DT(datetime.datetime):
            @classmethod
            def now(cls, tz=None):
                return cls.fromtimestamp(time.time(), tz)
        datetime.datetime = _DT
    _used = {}

    def _key(cmd):
        return json.dumps(cmd if isinstance(cmd, (list, tuple)) else [cmd], ensure_ascii=False)

    def _note(kind, cmd, rc):
        with open(LOGF, "a", encoding="utf-8") as f:
            f.write(json.dumps({"kind": kind, "cmd": (cmd if isinstance(cmd, list) else [cmd])[:3], "rc": rc},
                               ensure_ascii=False) + "\n")

    class _Fake:
        def __init__(self, rc, out, err, text, resp=None, body=None):
            self.pid, self.returncode, self.args = 0, rc, None
            self._o = out if text else out.encode()
            self._e = err if text else err.encode()
            self._resp, self._body = resp, body
        def communicate(self, input=None, timeout=None):
            if self._resp:  # curl -o <resp>：写个假的响应体
                open(self._resp, "w").write('{"ok":true}')
            return self._o, self._e
        def wait(self, timeout=None): return self.returncode
        def poll(self): return self.returncode
        def kill(self): pass
        def terminate(self): pass
        def __enter__(self): return self
        def __exit__(self, *a): return False

    class Popen:
        def __new__(cls, cmd, *a, **kw):
            text = bool(kw.get("text") or kw.get("universal_newlines") or kw.get("encoding"))
            argv = list(cmd) if isinstance(cmd, (list, tuple)) else [cmd]
            if argv and os.path.basename(str(argv[0])) == "curl":
                _note("blocked-curl", argv, 200)
                resp = argv[argv.index("-o") + 1] if "-o" in argv else None
                return _Fake(0, os.environ.get("PER134_CURL", "200"), "", text, resp=resp)
            if "--environment" in argv and argv[argv.index("--environment") + 1] == "grok-bot":
                _note("blocked-box", argv, 1)
                return _Fake(1, '{"ok":false,"error":"PER-134 harness: box blocked"}', "", text)
            k = _key(argv)
            if MODE == "replay":
                i = _used.get(k, 0)
                _used[k] = i + 1
                hits = [c for c in tape["calls"] if c["key"] == k]
                if i >= len(hits):
                    _note("miss", argv, 127)
                    raise OSError("PER-134 harness: 磁带里没有这条命令（第 %d 次）" % (i + 1))
                c = hits[i]
                _note("replay", argv, c["rc"])
                return _Fake(c["rc"], c["out"], c["err"], text)
            return _Rec(argv, k, text, a, kw)

    class _Rec:
        def __init__(self, argv, k, istext, a, kw):
            self._p, self._k, self._text = _real_popen(argv, *a, **kw), k, istext
            self.pid, self.args = self._p.pid, self._p.args
        def communicate(self, input=None, timeout=None):
            out, err = self._p.communicate(input=input, timeout=timeout)  # 超时照样抛给 run()，不记
            dec = (lambda s: s or "") if self._text else (lambda s: (s or b"").decode("utf-8", "replace"))
            tape["calls"].append({"key": self._k, "rc": self._p.returncode, "out": dec(out), "err": dec(err)})
            _note("record", json.loads(self._k), self._p.returncode)
            json.dump(tape, open(TAPE, "w", encoding="utf-8"), ensure_ascii=False)
            return out, err
        @property
        def returncode(self): return self._p.returncode
        def wait(self, timeout=None): return self._p.wait(timeout)
        def poll(self): return self._p.poll()
        def kill(self): self._p.kill()
        def terminate(self): self._p.terminate()
        def __enter__(self): return self
        def __exit__(self, *a):
            self._p.__exit__(*a)
            return False

    subprocess.Popen = Popen
