# everos.deepvision.sg DNS / 证书计划（未建记录、未装服务）

目标：自托管 EverOS（Python :8000）→ HTTPS 反代，域名 `everos.deepvision.sg`。

## 指向（待装服务前可建）
- Zone：`deepvision.sg`（CF zone `71480c1800cc536876c969799c5c59aa`）
- 记录：`A everos → 157.230.194.108`，**橙云代理（proxied）**
  - 原因：DO 防火墙 `deepvision-site-origin` 的 80/443 只放 Cloudflare IP；直连灰云会被拦。
- 不碰 apex/www（已绑 Worker `deepvision-site-production`）。

## 证书
- 边缘：CF Universal SSL（橙云即可）。
- 源站：zone 若仍 Full (strict)，需源站有效证——复用现有 `deepvision-origin-tls` Origin CA，或 LE 给 everos 反代。
- SSL 模式：保持 Full (strict)，不降 Flexible。

## 反代（等 eggbot 规格后再装）
- nginx/caddy：`everos.deepvision.sg` → `127.0.0.1:8000`
- 旧容器现状（开机后）：`site-app-1` :80→3000、`deepvision-origin-tls`、`headscale` :8443——装 EverOS 前评估 1GB 内存，建议停用无关旧站流量（官网已在 Worker）。

## 不做
- 未改 心月夜审 automation `75b324a4`
- 未装 EverOS / 未配 MCP，等 eggbot base URL/MCP 规格
