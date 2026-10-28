# 第6轮：无 issue 的正常叫醒与 OPS-3 收尾（代码交付，未部署）

`notify-run --bot <演练bot> --no-tty -- true` 不带 `--issue` 是正常路径，不能靠调用方补卡号绕开。本轮从已合并 #83 的 main 起新分支；未改发送方、routine 变量配置或模型工具权限，也未触发／部署。

## 安装版本源码结论

依据私有 `precheck/installed-services-routines.js`、`installed-routine-variables.js`，均为 iMac 实装 2026.1012.0 的源码，不拿另一版推测：

- services:339–346：webhook 顶层字段 → nested `payload.variables` → 显式 input.variables，后者覆盖前者。
- services:349–375：automatic 值优先，否则 provided 值只要不是 undefined 就优先于 defaultValue。显式 `""`、纯空白、null 都会遮住默认值。归一化后空值不进入 resolved；required=true 则拒绝，optional 则跳过。
- services:268–287；shared:103–113：本项目字段全为 text；0 和 false 分别转成 `"0"`、`"false"`，不是缺失。
- services:1379–1391：内建值、automatic、resolved 合并后渲染 title/description；原始 payload 中的空串不会再次补入模板渲染值。
- shared:115–125：没有对应 values 的变量返回原占位符；一次 replace，不递归求值插入的文本。支持模板中的空格／下划线转义，但本仓库固定 issue 槽位就是精确 `{{issue}}`。
- provision.py 的19个字段目前已经是 optional text，defaultValue=`-`。这个默认值对“缺键”有效，对“显式空串”无效；把默认值换成空串反而也会被跳过，**不能让 Paperclip 渲染成空**。

| 输入 | 本配置的渲染结果 | host 的 issue 行为 |
| --- | --- | --- |
| 缺少键 | 默认 `-` | PER-67 |
| 显式空串／纯空白／null | 原 `{{field}}` | 仅 issue 槽位的精确 `{{issue}}` → PER-67 |
| 合法 PER 卡号 | 原卡号 | 只接受 `PER-[1-9][0-9]*` |
| 0／false | `0`／`false` | issue 仍非法，不当空值 |
| `{{task}}`、其它未知占位符／非法目标 | 原输入，一次渲染不递归 | 拒绝，不任意回落 PER-67 |

因此选 **host 精确识别 issue 槽位的未渲染占位符**，不改默认值、不改发送协议、不改调用命令。缺失 issue 行仍不等于“没有提供值”：模板结构不完整继续拒绝。

## 同类字段检查

以下19个字段同样适用上面的显式空值行为：

`bot, status, task, issue, machine, kind, exit_code, duration_s, source, agent, session_id, seq, dedup_key, worktree, orca_worktree_id, orca_terminal, wake_version, note, log_tail`。

- 本次实际 issue 中 `issue` 与 `log_tail` 都留下占位符；note 被 notify-run 省略，所以用默认 `-`。task/status/source/machine 有值，正常渲染；其余缺键字段多为 `-`。
- 普通 notify-run 会生成非空 done/failed/killed（预警为 stuck），不正常发送空 status；但其它 webhook 若显式发空 status，它也会留下 `{{status}}`，不能被当成 done。
- `true` 没有输出，所以空 log_tail 是正常情况。显式空 note 同样会留下 `{{note}}`。
- 本轮不对整份正文做替换、不递归展开 payload 的花括号、不猜测状态或日志事实。host 给模型的收尾补充说明明确：未渲染字段占位符表示缺失，不是实际事实。note/log_tail 中的原始数据不会被程序全局改写。

## 目标防伪造

`host.linear_target()` 是无 IO 的纯解析函数：

1. 只认固定 `## 叫醒内容` 结构，要求结构标记唯一。
2. note 前的17个标量槽位必须数量、顺序、前缀完全吻合；拒绝 CR、多行标量或提前伪造的截断头部。
3. 全描述必须只有一个以 `- issue:` 开头的行。该计数只用于**拒绝歧义**，不从 note/log_tail 选目标。攻击者不能在 task 里插入假 issue 和提前 note 边界，把真正的 issue 行藏在后面。
4. 只取固定 issue 槽位；去首尾空白后仅 `""`、`-`、精确 `{{issue}}` 汇总 PER-67。其它输入仍须匹配合法卡号。

明确的保守边界：note/log_tail 若原样引用另一整行 `- issue:`，也会被视为歧义并拒绝，而不是挑选其中一张卡；普通提及 PER 卡号不会改变路由。显式发送文字 `{{issue}}` 与未渲染占位符无法从描述区分，但两者都只去固定 PER-67，不能借此选择其它目标。

这不依赖演练 bot 别名进入 ops-system 的发送方特殊分支。围栏只是数据呈现，不是权限隔离。别名仍不能被拿来证明正式 bot 的围栏处理／Idempotency-Key 分支已验；本轮也没有声称完成这些线上项目。

## OPS-3 专用收尾，必须先于重装

新脚本 `close-precheck.py`；不是旧的 OPS-1 `close-failed-e2e.py`。默认只打印计划，不读线上、incident 或部署状态。

```sh
python3 -I paperclip/imac/ops-system/close-precheck.py
# 以下仅为后续获准并核过的新版本操作顺序，本轮没有执行：
python3 -I paperclip/imac/ops-system/close-precheck.py \
  --incident '<已核 incident-ops3.json>' --apply
bash paperclip/imac/ops-system/install.sh --apply \
  --claude '<已核 Claude 路径>' --linear-author '<原共享账号>' \
  --precheck-cleanup-backup '<上一步 BACKUP 目录>'
```

私有 incident 来自预检查的原始绑定、FUSED、历史列表、正式 routine 摘要及旧成功信息；仓库只存其摘要，不存真实 ID。脚本还钉住这次失败的 host 摘要，证明 `non_ops_target` 在模型 Popen 前；不把旧 last-invocation/last-result 当成此次模型已经启动，也不把它们的费用清零。

前提：原 host 未被覆盖，agent paused、测试 trigger disabled/setupPending=false；三条 heartbeat 必须仍为原 cancelled/succeeded/cancelled 集合，无新增／排队／活动；当前 issue 绑定、原 run 的零费用和tokens／无重试／进程退出、无 parent／goal 等全部核实；正式 routine 摘要仍等于预检查基线。旧 E2E 有已记录费用，不能要求 agent 累计费用为0；当前读回值必须前后不变且不高于保留的200美分预留。

- 取得现有 host.lock 独占锁。
- 要求 state 是已知的12个文件：本次 FUSED/claim/400预留/MCP数量记录，以及旧 E2E 的 active、回执、write intent、issue claim、invocation/result/success、host.lock。拒绝 INFLIGHT、未知文件、符号链接、错绑定；旧成功文件必须绑定原成功 run，不能绑定本次失败。
- 在 `backups/ops3-<UTC>/`（0700）把全部12个文件原字节备份（0600）、核摘要并 fsync，再进行任何处置。
- 只 PATCH OPS-3 为 **cancelled** 并 GET 核实，不伪造 done，不写 Linear 说明或重开任务。接口仍是固定版 issues PATCH 的标准终态路径；父任务／runner goal 门禁沿用。
- reservations.json 必须精确由本月 **400→200**，只释放本次未启动模型的200美分。保留旧 E2E 的200预留；这是保守预留释放，不是账单退款。
- 只删本次 issue claim，最后才删本次 FUSED；不删 host.lock、历史 claim、active、write receipt/intent、last-*、mcp-filter 或任何触发独占文件。
- 收尾后逐字比较全部保留文件（除预留账本的唯一变更），核三条 heartbeat 不变、历史两条 routine run 状态／绑定不变，测试 trigger 整对象和正式配置不变。当前 routine run 允许服务正常终态处置的状态变化，不伪造历史成功。
- 完成凭据绑定13个源码／payload文件及原备份摘要。安装器只接受本次 `--precheck-cleanup-backup`，不拿 OPS-1 凭据混用；装前／装后复核凭据、目标关闭、历史与保留状态。装后允许 routine 更新描述／策略引起的 updatedAt 变化，仍按既有完整配置读回核其字段、按整对象核测试 trigger。

任一写入阶段失败，尝试留下 `precheck_cleanup_incomplete` 熔断及进度，非零退出。磁盘故障下不声称熔断一定写成；不是跨 API/文件系统事务，不自动退回账本、不重开 OPS-3、不盲重试。源包在清理到安装间不得改变；异常要人工只读核证据再决定。

本轮只交代码和默认计划，**没有清状态、安装或触发**。保留 `IMAC-NOTIFY-CLAIM`、原 E2E 触发锁、完整历史及正式配置。后续安装、精确收尾与续跑／切换由主会话核批准范围，修复不代表六项预检查已经通过。
