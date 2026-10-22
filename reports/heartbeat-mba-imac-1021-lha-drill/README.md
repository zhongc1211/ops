# 第六轮：复审方复现脚本对照

由当前 Codex 会话在 iMac 执行。只用临时目录、假 lockf 和假 curl，不联系主机，不算 E2E。

重跑命令（仓库根目录）：

```bash
bash reports/heartbeat-mba-imac-1021-lha-drill/lha-drill.sh "$PWD" 6e144e16
bash reports/heartbeat-mba-imac-1021-lha-drill/lha-drill.sh "$PWD" 3686006
```

附件脚本的适配沿用前一位 Claude 留下的版本：仓库及commit参数化，输出按commit分目录；BSD date没有%N，临时请求体文件名改为秒+pid+RANDOM。判定条件不变。

- 旧版 6e144e16：3 PASS、2 FAIL（L3.second-episode、L4.stale-first）、3 INFO。
- 初版修复 fab9219、最终测试提交 3686006：均为5 PASS、0 FAIL、3 INFO。
- L2只有INFO，其文字“kept alerted only”来自旧脚本说明；新版实际JSON含alerted和recovered，以log为准。
- L7只记录并发实际次数与临时文件残留，未断言不丢更新；各次结果以对应results.tsv为准。

77f16e8只修演练计时器和失败清单，lock-held-alert生产源码与3686006相同（sha记录见../heartbeat-mba-imac-1021-r6/versions.json），未重复这套逻辑演练。

输出在 out-6e144e1/、out-fab9219/ 和 out-3686006/。随机临时目录会在退出时移除；保留输出用于核对逻辑与原始状态。
