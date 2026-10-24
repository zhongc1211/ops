"""key-fill.sh 的实现。只连本机 Paperclip；不打印 key、ID 或响应内容。

--fill   从 stdin 读 key，建 company secret「ANTHROPIC_API_KEY」，把 agent 的 env.ANTHROPIC_API_KEY 绑上去。
         secret 已存在就停下（换 key 用 Paperclip 界面里的轮换，或先删再填）。
--check  只打印「有」或「没有」：secret 在、且 agent 的 env 绑到了它，才算有。
"""
import json
import os
import sys
import urllib.error
import urllib.request

API = os.environ["API_URL"].rstrip("/") + "/api"
SECRET_KEY = "ANTHROPIC_API_KEY"


def call(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as e:
        # 不回显响应体：错误信息里可能带上请求内容。
        raise SystemExit("%s %s 失败，HTTP %s" % (method, path.split("/")[1], e.code))


def find():
    _, companies = call("GET", "/companies")
    company = next((c for c in companies if c.get("name") == os.environ["COMPANY_NAME"]), None)
    if not company:
        raise SystemExit("找不到 company")
    cid = company["id"]
    _, agents = call("GET", "/companies/%s/agents" % cid)
    agent = next((a for a in agents if a.get("name") == os.environ["AGENT_NAME"]), None)
    if not agent:
        raise SystemExit("找不到 agent")
    _, agent = call("GET", "/agents/%s" % agent["id"])
    _, secrets = call("GET", "/companies/%s/secrets" % cid)
    secret = next((s for s in secrets if SECRET_KEY in (s.get("key"), s.get("name"))), None)
    return cid, agent, secret


def bound(agent, secret):
    env = (agent.get("adapterConfig") or {}).get("env") or {}
    b = env.get(SECRET_KEY)
    return bool(secret) and isinstance(b, dict) and b.get("type") == "secret_ref" and b.get("secretId") == secret["id"]


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    cid, agent, secret = find()
    if mode == "--check":
        print("有" if bound(agent, secret) else "没有")
        return
    if mode != "--fill":
        raise SystemExit("用法: key-fill.py --fill|--check")
    if secret:
        raise SystemExit("secret %s 已存在，没改。换 key 请用界面轮换，或先删掉再填" % SECRET_KEY)
    value = sys.stdin.read().strip()
    if not value:
        raise SystemExit("没读到 key")
    _, created = call("POST", "/companies/%s/secrets" % cid, {
        "name": SECRET_KEY, "key": SECRET_KEY, "value": value,
        "description": "ops-system agent 用的 Console API key（Zack 填）",
    })
    del value
    env = dict((agent.get("adapterConfig") or {}).get("env") or {})
    env[SECRET_KEY] = {"type": "secret_ref", "secretId": created["id"]}
    # PATCH 默认和已有 adapterConfig 浅合并，只改 env 这一项；agent 保持暂停。
    call("PATCH", "/agents/%s" % agent["id"], {"adapterConfig": {"env": env}})
    _, agent = call("GET", "/agents/%s" % agent["id"])
    _, secrets = call("GET", "/companies/%s/secrets" % cid)
    secret = next((s for s in secrets if SECRET_KEY in (s.get("key"), s.get("name"))), None)
    print("填好了，读回：", "有" if bound(agent, secret) else "没有", "| agent 状态:", agent.get("status"))


if __name__ == "__main__":
    main()
