# EverOS VPS 安装任务（ops 系统 / Orca）

## 目标
在旧 site VPS `157.230.194.108` 自托管 EverOS，域名 `https://everos.deepvision.sg`，供 iMac+box coding 会话经 MCP 使用。

## 前置（运维）
- [ ] droplet 已开机
- [ ] SSH 可达（用户/密钥别名以运维回执为准）
- [ ] DNS：`A everos → 157.230.194.108` 橙云（见 DNS-PLAN.md）
- [ ] Origin TLS / Full (strict) 可用


## 清理（Zack 2026-10-16：装前先清）
官网已在 Cloudflare Worker，旧站流量可停。装 EverOS 前：
1. `ssh site` 后列：`docker ps -a`、`systemctl --type=service --state=running`、`free -h`、`df -h`
2. 停并移除无关旧站应用容器（如 `site-app-1` 及仅服务旧官网的栈）；**保留** `deepvision-origin-tls`（证书）、必要时保留 headscale 若仍在用——不确定则先停再记进 EVIDENCE，不要静默删数据卷
3. 清理无用镜像/悬空卷：`docker system prune -f`（**不要** `-a` / 别删 named volumes 除非确认）
4. 再记一版 `free -h`；目标：available ≥400Mi 再装 EverOS

## 装服步骤（本工作区执行）
1. SSH 探活：内存/磁盘/已有容器（site-app、origin-tls、headscale）。官网已在 Worker，可停无关旧站流量以腾 1GB 内存。
2. 装 Python/uv；`uv pip install everos`；`everos init --root /var/lib/everos`（或 `/home/everos/.everos`，固定路径写进本文件）。
3. `everos server start` 绑 `127.0.0.1:8000`；systemd 保活。
4. Caddy/nginx：`everos.deepvision.sg` → `127.0.0.1:8000`；证书与 Full (strict) 对齐。
5. Health：`curl -fsS https://everos.deepvision.sg/api/v2/memory/search` 或上游文档中的 health 路径；本地 `http://127.0.0.1:8000` 先通再公网。
6. 写入证据到 `everos-deploy/EVIDENCE.md`（命令、版本、内存前后、URL）。
7. 回报 ops 系统：base URL、root 路径、SSH 方式、是否需 embedding。

## 不做（本阶段）
- 不改夜审 automation `75b324a4`（交给 Coding助手）
- 不挂 Claude MCP（HANDOFF 后由 Coding助手派）
- 不销毁 droplet / 不改 apex DNS

## 参考
- PLAN.md / HANDOFF-coding.md / DNS-PLAN.md / RESEARCH-REPORT.md
- https://github.com/EverMind-AI/EverOS
- https://github.com/EverMind-AI/EverOS-MCP
