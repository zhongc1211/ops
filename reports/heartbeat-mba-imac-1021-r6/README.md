# B1 第六轮（PER-144 / draft PR #75）

必改代码和文档已完成，最终正向演练尚未全通过：69 PASS、2 FAIL，均为读取box失败；回退结果见下表。当前 Codex 会话已核对并保留前一位 Claude 的六个未提交文件。未改现网、未 register --apply、未安装脚本、未写 box、未合并。仍保持 draft。

最终测试提交：77f16e848317d0ee4692eddb0680fef65f2bdb62。3686006的正向S12.old计时失败后，先在6555b8e记失败方式和期望，再在77f16e8改用单调时钟计算耗时；240秒限制和断言不变。接手时 HEAD 为90c6b90a33f3232970e7ef517655740248d84de1；第六轮相对6f6266ca的代码与文档共8文件，+476/-131。相对8d99db3（排除reports/.orca-task），共10文件，+1840/-207，另包含前一轮引入的lockf、lock-held-alert和S13–S15；本轮新增内容见下表。

| 必改 | 完成内容 |
|---|---|
| 恢复发送失败后再次卡住漏报 | POST前记录待补发恢复；旧串prev_alerted与新串alerted分开；新串到45分钟可再次报 |
| 旧记录误报 | now-last超过15分钟重新记first；无last时回退first |
| 最终版加锁 | lock-held-alert + lockf -k -t 0，沿用5c2d0575.lock，超时仍300 |
| PR正文 | 删除指定工具版本与S11检查行；按最终实现和新结果更新 |
| D2收件人 | heartbeat-watch与lock-held-alert同PR改ops-system；卡③须换iMac安装副本并比sha，回滚还原旧副本 |
| 上线卡片 | 卡②持锁6分钟必做，75/status/stdout/放锁恢复和异常退出停止；约50分钟报警；卡④记录两条75次数和最长durationMs、最终版带锁及无人盯风险 |

详细核对：[AUDIT.md](AUDIT.md)。历史执行者与运行记录：[RUNS.md](RUNS.md)、[HISTORY-before-r6.md](HISTORY-before-r6.md)。被测文件sha：[versions.json](versions.json)。

验证环境：iMac macOS26.6.2 x86_64、MBA macOS26.6.2 arm64，两台Orca1.4.237；bash3.2.57、Python3.9.6。MBA场景经ssh在临时目录执行。

| 验证 | commit | 结果 | 产物 |
|---|---|---|---|
| 首次整轮演练 | fab9219be2dff003a9d4cecc6578171f74789758 | 71 PASS、0 FAIL；992个sha通过 | [run11](../heartbeat-mba-imac-1021-run11-fab9219/README.md) |
| 报告文字修正后的整轮 | 3686006c0cca6dfdef62d36b4f0eeee6bad02328 | 70 PASS、1 FAIL：S12.old，timedOut=true但墙钟耗时239.9秒；原始证据保留 | [run12](../heartbeat-mba-imac-1021-run12-b72493e/README.md) |
| 最终整轮演练 | 77f16e848317d0ee4692eddb0680fef65f2bdb62 | 69 PASS、2 FAIL：S9.94e4b0bc、S6b.box；S12.old已PASS，耗时使用monotonic；992个sha通过 | [最终results.tsv](../heartbeat-mba-imac-1021-run13-77f16e8/results.tsv) |
| 前次完整回退对照 | base f828d452345f16898d6c9d133984e170d98d9f83，测试取自3686006 | 71/71符合预期：40 FAIL、31 PASS；20项失败原因符合；990个sha通过 | [ROLLBACK.md](../heartbeat-mba-imac-1021-rollback-f828d45-3686006/ROLLBACK.md) |
| 最终完整回退对照 | base f828d452345f16898d6c9d133984e170d98d9f83，测试取自77f16e8 | 71/71符合预期：40 FAIL、31 PASS；20项失败原因符合；990个sha通过 | [最终回退](../heartbeat-mba-imac-1021-rollback-f828d45-77f16e8/ROLLBACK.md) |
| 复审lha脚本 | 6e144e16 / 3686006 | 旧版3 PASS、2 FAIL、3 INFO；新版5 PASS、0 FAIL、3 INFO。旧版失败为L3.second-episode和L4.stale-first | [复现对照](../heartbeat-mba-imac-1021-lha-drill/README.md) |

新增的5项为S1.bot、S15.MBA.rf、S15.iMac.rf、S15.MBA.old、S15.iMac.old。首轮和最终轮全部通过。最终S12.old的单调时钟耗时240.0秒；base对照同样240.0秒。回退时5项均失败且原因符合预期；原S0.bot、S3由应通过改为应失败，旧默认收件人为coding-assistant。

用于复跑的命令（iMac仓库根目录）：

```bash
env HB_DRILL_OUT=reports/heartbeat-mba-imac-1021-run13-77f16e8 bash wake/tests/heartbeat-watch-ssh.sh

env HB_ROLLBACK_OUT=reports/heartbeat-mba-imac-1021-rollback-f828d45-77f16e8 bash wake/tests/heartbeat-watch-ssh-rollback.sh
```

前次回退最初目录名为rollback-f828d45-fab9219，完成后按测试commit改名为3686006；文件内容和sha未改。run12-b72493e实际测试commit为3686006，保留原始目录名和失败证据。最终run13及回退目录直接使用77f16e8。实际测试commit以env.txt和ROLLBACK.md完整SHA为准。

失败详情（测试commit77f16e8）：S9.94e4b0bc（wake/tests/heartbeat-watch-ssh.sh:958）读不到box；S6b.box（同文件:1084）未得到正常心跳。错误原文均含 {"code": "remote_runtime_unavailable", "message": "Could not connect to the remote Orca runtime."}。S6b在同一时段紧接着跑的base precheck也返回同样错误，证据在run13/raw/S6b/before-base.out和results.tsv；现网5c2d0575的09:35运行也记录断联。此前base整轮3686006和最终base整轮77f16e8的这两项均通过；最终base读取到09:40、09:45恢复记录，保留09:35断联记录。具体断联原因未查。没有把失败改为PASS，没有只挑这两项重跑，也没有去修box或隧道。

整轮含真机只读检查、静态检查和替身，71项不能统称E2E。S15用假curl、缩短阈值或手写历史状态；恢复失败用假curl回500。S6/S6b用现有MBA ops·09代替尚未创建的新任务。真实Orca调度、ops-system实际接收处理未验证，卡②验证75是必做。

未做及原因：

- EverOS recall_agent_experience：当前会话发现不到可调用工具，未调用成功。
- 可选71/73持续45分钟报警：未做；73时同目录状态不可写，需要另设状态位置。已写进限制。
- 真实Orca调度验证75/完整部署E2E：未做；任务书禁止建、改、运行自动任务，不将draft转ready、不请review。
- wake-tla：未跑；按任务留B10更新模型与SOURCES，现有环境不足。
- 真等45分钟、首次stale发送失败、ServerAlive半路断线、同时写状态和接收方处理：未完整验证。lha的并发次数只记不判。
- heartbeat-watch自己加锁、临时文件按pid命名：留后续。

剩余风险：最终版恢复POST最多额外20秒，最坏约310秒可能超过固定300秒超时；待补发状态在POST前保存，但该极端时序未实测。5c2d0575无人盯；71/73可能静默。MBA睡眠和两机同时停仍有空档。box停用前仍发coding-assistant，iMac/MBA安装本PR副本后发ops-system。
