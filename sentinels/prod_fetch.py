#!/usr/bin/env python3
"""prod_fetch.py — 只读查每个生产 Worker 当前在线的部署（ops · 23 生产版本哨兵，iMac 上跑）。

用法: prod_fetch.py            # 打印 JSON（一个对象：workers 列表 + errors）
令牌: $CF_READONLY_TOKEN_FILE（默认 ~/.config/cloudflare/readonly-usage.token，即 orca-cf-usage-readonly，
      全部是 Read 权限）。只经请求头发给 api.cloudflare.com，不打印、不写日志。
只发 GET。退出码: 0 = 全部查到；3 = 有 Worker 没查到（输出里 errors 写明）；2 = 令牌文件读不到。
"""
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

ACCOUNT = os.environ.get("CF_ACCOUNT_ID", "7549b9c77aa27ea8c1a8b394d9b71490")
WORKERS = [
    # (Worker, 域名, 项目) — 名字取自各仓库 wrangler 配置的生产环境
    ("deepvision-site-production", "deepvision.sg", "deepvision-site"),
    ("deepvision-ads", "ads.deepvision.sg", "deepvision-ads"),
    ("xinyue-site", "xy.deepvision.sg", "xinyue"),
    ("xinyue-studio-control", "xinyue-studio.deepvision.sg", "xinyue"),
    ("xinyue-game-runtime", "xinyue-play.deepvision.sg", "xinyue"),
]
# python.org 的 macOS Python 不带根证书，用系统的 /etc/ssl/cert.pem
CTX = ssl.create_default_context(cafile="/etc/ssl/cert.pem") if os.path.exists("/etc/ssl/cert.pem") else None
API = "https://api.cloudflare.com/client/v4/accounts/%s/workers/scripts/%s"


def get(token, url):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
            return json.load(r), None
    except urllib.error.HTTPError as e:
        try:
            body = json.load(e)
            msg = "; ".join("%s %s" % (x.get("code"), x.get("message")) for x in body.get("errors", []))
        except Exception:
            msg = ""
        return None, "HTTP %s %s" % (e.code, msg)
    except Exception as e:
        return None, type(e).__name__ + ": " + str(e)[:120]


def main():
    path = os.path.expanduser(os.environ.get("CF_READONLY_TOKEN_FILE", "~/.config/cloudflare/readonly-usage.token"))
    try:
        token = open(path).read().strip()
    except OSError as e:
        print(json.dumps({"workers": [], "errors": ["令牌文件读不到: %s (%s)" % (path, type(e).__name__)]}, ensure_ascii=False))
        return 2
    out, errors = [], []
    for name, domain, project in WORKERS:
        base = API % (ACCOUNT, name)
        d, err = get(token, base + "/deployments")
        if err or not d.get("success"):
            errors.append("%s: deployments %s" % (name, err or "success=false"))
            continue
        deps = d["result"].get("deployments") or []
        if not deps:
            errors.append("%s: 没有部署记录" % name)
            continue
        dep = max(deps, key=lambda x: x.get("created_on", ""))
        versions = []
        for v in dep.get("versions", []):
            vd, verr = get(token, base + "/versions/" + v["version_id"])
            info = {"id": v["version_id"], "percentage": v.get("percentage")}
            if vd and vd.get("success"):
                r = vd["result"]
                meta = r.get("metadata") or {}
                ann = r.get("annotations") or {}
                info.update({
                    "number": r.get("number"),
                    "created_on": meta.get("created_on"),
                    "source": meta.get("source"),
                    "author_email": meta.get("author_email"),
                    "tag": ann.get("workers/tag"),
                    "message": (ann.get("workers/message") or "")[:200],
                    "triggered_by": ann.get("workers/triggered_by"),
                })
            else:
                info["error"] = verr or "success=false"
            versions.append(info)
        dann = dep.get("annotations") or {}
        out.append({
            "worker": name, "domain": domain, "project": project,
            "deployment_id": dep.get("id"), "created_on": dep.get("created_on"),
            "source": dep.get("source"), "author_email": dep.get("author_email"),
            "triggered_by": dann.get("workers/triggered_by"), "message": (dann.get("workers/message") or "")[:200],
            "versions": versions,
        })
    print(json.dumps({"workers": out, "errors": errors}, ensure_ascii=False))
    return 3 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
