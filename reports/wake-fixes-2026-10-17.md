# 叫醒系统修复（2026-10-17 晚，Zack 23:06「全部 fix 掉」）

## 1. box Orca 一天重启 70–90 次
- 根因：box 虚拟机在空闲时会被平台暂停、之后恢复（watchdog 日志里 guest clock STOPPED = VM paused，这一段我们控制不了）。
  但每次恢复后 watchdog 都**无条件**重启 Orca（`resume -> restart immediately`）。10-11..10-17 共 358 次重启里 294 次是 resume，
  这 294 次重启后 291 次马上就是 local=200/public=200，说明 Orca 本来就好好的，重启是多余的，还会打断 box 上的终端。
  10-15/16/17 分别重启 93/76/87 次，其中 resume 85/57/66 次。
- 改法（orca-remote/watchdog.sh rev 2026-10-17b）：
  - 恢复只记日志，开 120 秒宽限期（WATCHDOG_GRACE），宽限期内的不健康不计数；重启/启动之后同样有 120 秒宽限（serve 起来要 60–75 秒）。
  - 隧道失效（local 200、public 530/502）要连续 2 次才处理，而且只重启 cloudflared（tunnel-loop 5 秒后自己拉起），不动 Orca。
  - 其余不健康照旧：宽限期外连续 2 次才整体重启，两次重启至少隔 90 秒。
- 另一个原因（没改，需要决定）：Orca 绑在 orca-bot 的桌面 DISPLAY=:4 上，这个桌面会被平台回收重建。10-17 22:45–22:55 :4 不在，
  serve 每 5 秒退出一次（"DISPLAY=:4 is not verifiably live"），watchdog 跟着重启了 5 次也没用，:4 22:55 重建后才恢复。

## 2. 营销没接进卡住检查
- 营销没有自己的仓库和 Linear 团队（FDV 编号和广告、运维共用），所以按仓库/Linear 映射永远认不出来，一律落到 coding-assistant。
- stuck-check.sh：BOT_SLUG 加「deepvision 营销」；新增工作区显示名前缀规则（「营销 · 」「dv营销 · 」「deepvision-marketing」「Marketing · 」→ deepvision-marketing）。
- agent-probe：notify-run 进程带出 `--bot`，agent 进程带出最近一层 notify-run 的 bot（dispatch_bot）。第一类（卡住的 agent）优先用它，
  所以只要是 `notify-run --bot deepvision-marketing` 派出的会话，一定发给营销，不靠命名。

## 3. 日志
- notify-run：每次发送（含重试、找不到配置）追加一行到 ~/.orca-state/notify-run/notify-run.log：时间、bot、issue、status、exit、http、第几次、工作区目录。不写 URL/KEY/payload/输出。
- stuck-check：webhook 非 2xx 时日志带响应体前 160 字符（去掉 URL/KEY、key/token 值和 32 位以上长串，压成一行）。

## 4. 防止两次扫描同时跑
- stuck-check：~/.orca-state/stuck-check/run.lock（fcntl.flock，非阻塞）。拿不到锁就记一行退出；--scan 返回 1（自动化不启动 agent）。--list / --dry-run 不加锁。

## 5. box 短暂连不上
- stuck-check：box 查询 3 次都失败后，等 STUCK_BOX_RETRY_WAIT（默认 30）秒再查一轮，两轮都失败才计为一次连不上；box 的 agent-probe 临时终端失败也等 15 秒重试一次。

## 验证
- watchdog：23:19 把 watchdog 进程 STOP 150 秒造一个 173 秒的空档，恢复后日志是 `no restart for resume; grace 120s`，Orca 的 tmux 会话没被重建（仍是 22:54:12 创建的那个）。
- notify-run：两台机器上用本地假 webhook 测了 200 / 400 / 找不到配置三种，日志各一行，没有 key。
- stuck-check：iMac 上 --dry-run --full 跑通；模拟锁被占时 --send / --scan 都直接退出（日志两行）；23:18 的定时扫描用的就是新脚本，正常发出 2 条（200）。
  非 2xx 响应体截取用本地假 webhook 测过；营销显示名映射用单元测试测过（「dv广告 · FDV-40 AI Marketer」不会误判成营销）。
