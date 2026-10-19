# iMac Tailscale 重连（2026-10-18）

结论：iMac 已重新连上 headscale tailnet，三项验收都通过。没有用到 sudo，没有出现 macOS 弹窗，也不需要重新登录。

执行者：Claude Code（在 iMac 本机）。

## 重连前

- `tailscale status`：`Tailscale is stopped.`
- `tailscale version`：1.98.9（独立版 Tailscale.app，network extension 在运行）
- prefs：`ControlURL` = `https://headscale.deepvision.sg:8443`，`LoggedOut` = false，`WantRunning` = false，`Hostname` = imac
- 判断：节点仍是登录状态，只是重启后没有自动 up。

## 操作

1. `open -a Tailscale`：app 启动了，但等了约 30 秒状态仍是 stopped（`WantRunning` 还是 false）。
2. `tailscale up`，不带任何参数：退出码 0，没有弹出登录链接。

没有改 login server，没有重新注册节点，也没有碰 headscale 服务端。操作完再看 prefs，`ControlURL` 没变，`WantRunning` 变为 true。

## 验收

| 项目 | 结果 |
|---|---|
| `tailscale status` | 在线。imac 100.64.0.4、box 100.64.0.6、site 100.64.0.5 都没有 offline 标记 |
| `tailscale ip -4` | 100.64.0.4 |
| `tailscale ping -c 5 100.64.0.6` | 5/5 pong，都走 DERP(site)，233–734ms。命令退出码为 1，原因是 `direct connection not established`（没有建立直连），不是不通 |
| `tailscale ping -c 5 100.64.0.5` | 5/5 pong；前 4 次走 DERP(site)，第 5 次直连 159.65.0.82:41641，18ms。退出码 0 |
| `scp` 测试文件到 `box:/tmp/` | 成功，退出码 0。传的是 `/tmp/imac-tailscale-test-20261018.txt`，本地和 box 上的 sha256 一致（56ed6257…2000） |

其余节点 iphone、mbp、office 显示 offline，最后在线是 25 天前。这次没有处理它们。

## 遗留

- iMac → box 走的是 DERP 中继（经 site），延迟 230–730ms，没有建立直连。可用，但比直连慢。要直连得另外查 NAT 和 UDP 41641，这次没查。
- box 上的测试文件 `/tmp/imac-tailscale-test-20261018.txt` 还在，没删。
- 重启后 Tailscale 没有自动连上。这次没改登录项或开机自启设置，下次重启可能还会这样。
