# r6 验收复跑：run14

结果：71 PASS、0 FAIL、0跳过，退出0。未触发额外整轮重跑。

执行者：当前Codex会话。2026-10-22 10:19:08 SGT在iMac执行用户指定的只读show命令，首次返回ok:true；无需5分钟重试。只保留不含任务正文的READINESS.json摘要。

本轮在临时共享克隆中detached检出77f16e848317d0ee4692eddb0680fef65f2bdb62，演练记录的代码未提交改动为0。主工作区保持12d65761056b65ce1ee38983d9ba35050b59a76e，代码与77f16e8一致；只新增本次reports产物。临时克隆及演练自己的临时目录在退出时清理。

实际执行（在临时检出的77f16e8根目录）：

```bash
HB_DRILL_OUT=/Users/jiawenwang/orca/workspaces/ops/ops-heartbeat-mba-imac-1021/reports/heartbeat-mba-imac-1021-run14-77f16e8 bash wake/tests/heartbeat-watch-ssh.sh
```

环境：iMac macOS26.6.2 x86_64；MBA macOS26.6.2 arm64；两台Orca1.4.237，bash3.2.57、Python3.9.6。开始时间10:19:54 SGT，详见env.txt。MBA场景经ssh在临时目录执行。

此前失败的S9.94e4b0bc和S6b.box均PASS。S6b读取到box 10:20的新鲜心跳，紧接着的base precheck也正常，原始输出在raw/S6b/及results.tsv。其余69项全部PASS，包括S12.old及新增5项。

run13的S9.94e4b0bc、S6b.box曾返回remote_runtime_unavailable，其69 PASS/2 FAIL产物在../heartbeat-mba-imac-1021-run13-77f16e8/原样保留。本次是用户明确授权的整轮验收复跑，没有挑选单项，没有改代码、断言、现网或隧道。此前完整回退71/71符合预期的证据沿用，本次未重跑回退。

本次未运行register --apply，未写box，未安装持久脚本，未合并；PR保持draft。演练含静态与替身场景，不能把71项统称E2E，原有真实上线验证边界不变。

README.md为脚本生成的完整场景报告；results.tsv为每项结果；raw/为原始输出。脚本原生992个产物SHA已核对，添加本说明及READINESS.json后重新生成SHA256SUMS，提交及干净导出均按完整清单校验。
