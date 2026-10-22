# 第六轮接手核对

接手 HEAD：90c6b90a33f3232970e7ef517655740248d84de1。保留并逐项核对了前一位 Claude 留下的六个未提交文件；后续修改由当前 Codex 会话执行。

| 任务书要求 | 核对与处理 |
|---|---|
| 1 恢复发送失败后第二次卡住必须再报 | lock-held-alert 将新串的 alerted 与旧串的 prev_alerted 分开；got_lock 在 POST 前保存待补发记录；S15 两台 .rf 覆盖失败、补发失败、新串再报警及补发成功 |
| 2 旧记录不能立刻报 | now-last 超过 15 分钟重记 first；last 缺失回退 first；S15 两台 .old 覆盖三天旧记录、16/14 分钟边界、旧串已报过的情况 |
| 3 最终版加锁 | defs final 与 parallel 同用 5c2d0575.lock，lock-held-alert + /usr/bin/lockf -k -t 0，超时仍为 300；S8.final、S6b.final 同步 |
| 4 PR 正文删去指定两行 | 正文按最终实现重写，不再保留指定工具版本和 S11 表格行；机器输出产物保留原有检查 |
| 5 ops-system | 两个脚本同 PR 改默认收件人，heartbeat-watch 只改 BOT 与注释；noop 提示词同步。S0 只归一 BOT 行，S1 归一收件人后逐字节比，S1.bot 单独查真实默认。S15 不设 FORCE_BOT。README 卡③必须安装 heartbeat-watch 副本，并增加备份还原 |
| 6 上线卡片 | 卡②锁验证必做、75/status/输出/放锁恢复、71/73/127 停止；约50分钟报警及 ops-system；卡④两条任务75次数、最长durationMs、最终版带锁与无人盯风险 |
| 回退测试 | 前任未改回退脚本；已从33 FAIL/33 PASS扩为40 FAIL/31 PASS，新7项也检查失败原因，合计20项核对原因 |
| EverOS recall | 当前会话工具发现未返回 recall/recall_agent_experience 工具，未完成调用；没有伪称已召回 |

可选71/73告警不做：73时同目录状态也不可写，需要另设状态位置；127也无法由未安装的包装自报，保留在已知限制。

恢复 POST 额外耗时的限制保留：MBA 最坏约320秒/330秒，并行版596秒/600秒；最终版约310秒/300秒，可能超时，待补发状态在POST前保存。没有改变300秒。

复审 lha 脚本使用假 lockf/假 curl，仅为逻辑演练，不称 E2E。保持附件判定方式，L2 文本中的“kept alerted only”是旧版说明；新状态实际同时含 alerted/recovered，以 log 和 JSON 为准。L7 只记录并发丢更新，不要求8次都被记下。

3686006最终正向S12.old失败（240秒timeout已触发、墙钟duration239.9秒），同用例base对照PASS、240.1秒。先提交6555b8e的C24/A69，再于77f16e8修正起动器耗时测量为monotonic；保留墙钟起止时间、240秒超时与原断言。重新整轮正向和回退，保留失败证据。具体校时原因未知。生产脚本在3686006与77f16e8之间没有改动，lha对照仍适用。
