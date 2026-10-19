# EverOS 心月会话采集

夜审 `75b324a4` 需要每日 SGT 日 `D` 的：

- `/var/lib/everos-ingest/xinyue/$D/sessions-box.jsonl`
- `/var/lib/everos-ingest/xinyue/$D/sessions-imac.jsonl`

## 脚本

- `collect_xinyue_sessions.py` — 从本机 `orca worktree list` + `~/.claude/projects` 抽心月会话
- `collect-box.sh` / `collect-imac.sh` — Orca automation **precheck**（工作全做完后 `exit 1`，不启模型）
- `ensure-sshd.sh` — box 上保证 Tailscale IP `:22` 有 sshd，供 iMac `scp`

## 自动化（Orca，非 cron）

- box：`ops · EverOS 心月会话采集 box` — 每天 22:00 SGT
- iMac：`ops · EverOS 心月会话采集 iMac` — 每天 21:50 SGT（先推到 box）

手动：

```bash
# box
MACHINE=box D=$(TZ=Asia/Singapore date +%F) /workspace/ops/everos-ingest/collect-box.sh; true

# iMac
EVEROS_INGEST_ROOT=$HOME/.orca-state/bin/everos-ingest \
  $HOME/.orca-state/bin/everos-ingest/collect-imac.sh; true
```

不含密钥；不要把 `~/.config/everos/` 写进仓库。

## 2026-10-16 修改（备份：/home/box/orca-backups/everos-ingest-20261016/）

- iMac：transcript 先过滤密钥（env 文件里的字面值 + 常见 token 格式），再推到 box 的
  `/var/lib/everos-ingest/xinyue/$D/imac/<session_id>.jsonl`（目录 700、文件 600，先传到 `imac.incoming/` 再整体换上）；
  jsonl 的 `transcript_path` 写 box 路径，原路径放在 `transcript_source_path`。jsonl 最后推。
  读不到 env 密钥列表时拒绝推送（exit 3）。ssh 用复用连接，首连最多重试 8 次（约 5 分钟），precheck 超时为 420s。
- 两台机器：排除冒烟会话、夜审会话和采集会话本身（按工作区名、auto-run 路径、开场 prompt 判断），
  被排除的会话写到 `sessions-<machine>.excluded.jsonl`，并注明原因。
- 采集脚本出错时 exit 4（exit 1 留给「做完了，不启动模型」）。
- 手动 `orca automations run` 不会执行 precheck；要验证只能等定时运行。
- 第二轮（同日，备份在 /home/box/orca-backups/everos-ingest-20261016-r2/）：去掉按工作区名排除的规则，改为按会话任务类型判断：
  首条消息（或它指向的 brief .md）的前两行。冒烟、夜审、采集、接入/配置（挂 everos-mcp、接入 EverOS、改采集/夜审 automation）都排除；
  前两行里出现 PER-N、PR、feat/ 分支或 Linear 的，一律当开发会话保留。

## deepvision-site 采集（FDV-68，2026-10-16 19:xx，**disabled**）

- 规则 A+E+H+K（Zack 19:07）：按 git remote 认 deepvision-site；接入/配置规则先于工单保护（FDV-N）；夜审 43c55a22 会话排除
- 脚本：`collect_deepvision_site_sessions.py`（复用 `collect_xinyue_sessions.py` 的函数，心月脚本没改）、`collect-box-deepvision-site.sh`、`collect-imac-deepvision-site.sh`（iMac 副本在 `~/.orca-state/bin/everos-ingest/`）
- 输出：`/var/lib/everos-ingest/deepvision-site/$D/`，D = 前一天
- automation：box `207ff52e-2dfb-4365-9b3d-3951ef3054ca`（00:05），iMac `34fe1ab0-7b3d-4e6a-917a-2c254e0e6dc6`（00:01），都是 disabled
- dry-run：`DRY_RUN=1 D=YYYY-MM-DD <precheck 脚本>`，只打印，不写文件
- 19:21 改动（备份在 /home/box/orca-backups/fdv68-collect-20261016-1921/，iMac 上是 ~/orca-backups/…）：加 OD 规则（固定前缀 `~/Library/Application Support/Open Design/namespaces/release-stable/data/projects/fdv61-`）；首条消息被 `<pasted_content>` 包着时先拆包装再判定；输出每行加 `included_by`。43c55a22 夜审改成读 `/var/lib/everos-ingest/deepvision-site/$D/`
- 19:28：207ff52e / 34fe1ab0 已启用；一次性核查 `098bc4e7-7bcd-4d2f-a391-1ab2b665c8c0`（2026-10-17 00:30，`fdv68-firstrun-check.sh` + `fdv68_firstrun_check.py`，跑完自己 disable）

## 心月夜审写入台账 + 00:30 兜底（2026-10-17）

- `nightly_addflush.py` — 夜审第 2 步写入脚本（box 上原有版本 + 写入台账）。每次 add/flush 追加一行到
  `~/xinyue-deploy/nightly-review/$D-xinyue-ledger.jsonl`（`--ledger` 可改），写前写后各 get 一次 episode 计数（含 id 列表）。
- `night-review-xinyue.prompt.md` — `75b324a4` 的 prompt 全文：先写摘要骨架（状态：进行中），每步更新，第 2 步调用上面的脚本，结尾改为完成。
- `night-review-guard-xinyue.sh` — Orca automation「心月夜审兜底」的 precheck（00:30，只读，总是 exit 1）；参数见
  `night-review-guard-xinyue.automation.md`。

## deepvision-ads / vllm-omni 会话采集 + vllm 夜审写入修复（2026-10-18，Zack 13:18「补，顺便查修 vllm 写入」）

- 规则和输出同官网（A+E+H+K）：`collect_repo_sessions.py --repo deepvision-ads|vllm-omni` 换掉官网采集脚本的
  仓库名、夜审标记（9b5c20e7 / c392a743）、工单号（FDV-N / PER-N），不用 OD 规则；官网脚本没改。
- precheck：`collect-box-repo.sh <repo>`、`collect-imac-repo.sh <repo>`（iMac 副本在 `~/.orca-state/bin/everos-ingest/`），
  采前一天，输出 `/var/lib/everos-ingest/<repo>/$D/`。DRY_RUN=1 只打印。
- automation：
  - box `91fa38d4` dv广告 · 26 EverOS 广告会话采集 box（00:06），iMac `8b06646f` dv广告 · 26 EverOS 广告会话采集 iMac（00:02）
  - box `4ce0c307` vllm · 27 EverOS 会话采集 box（00:20），iMac `89faa2a6` vllm · 27 EverOS 会话采集 iMac（00:16）
- 写入：`nightly_addflush.py --project deepvision-ads|vllm-omni`（会话，默认仍是心月）、`dv_ads_lessons.py --project vllm-omni`
  （lesson，默认仍是广告）。都按 env 文件核对作用域，ID 用 10-16 批的：user_id zack；deepvision/deepvision-ads/coding-deepvision-ads；
  vllm-omni/vllm-omni/coding-vllm-omni。
- 夜审：9b5c20e7、c392a743 加第 0 步读采集清单并用上面的脚本写入；c392a743 第 4 步改用 lesson 脚本、env 改 `vllm-omni.env`
  （以前用 xinyue.env 覆盖成 app_id=vllm、user_id=zack@vllm-omni，coding agent 召回不到）。prompt 全文：
  `night-review-deepvision-ads.prompt.md`、`night-review-vllm-omni.prompt.md`。

## 整条排除 secret-like 会话（2026-10-18，dr eggbot 16:11 定，依据 Zack「密钥不落地」）

- 四个采集入口都加了（`collect_xinyue_sessions.py` 的 `secret_like_reason`，官网脚本调用它，广告和 vllm 通过
  `collect_repo_sessions.py` 随官网脚本生效）。只对原规则会保留的会话检查，原来被排除的会话原因不变。
- 命中就整条写进 `sessions-<machine>.excluded.jsonl`，reason 以 `secret-like:` 开头（只写命中的类别，不写值），不进 EverOS：
  - 标题（工作区名）、开场任务前两行、brief 前两行里出现 KEYS、AI KEY(S)/AIKEY(S)、API KEY(S)/API_KEY、SECRET(S)、
    REVOKE(D/S)、API TOKEN、ACCESS TOKEN、PRIVATE_KEY、PASSWORD、CREDENTIAL、令牌、密钥（不分大小写；英文按词边界，
    词组中间可以是空格、`_`、`-` 或不隔开）；
  - 开场任务、brief 全文或 transcript 任一行里出现 env 文件里的密钥原值，或固定前缀的 token 格式
    （私钥块、sk-、gh?_、github_pat_、cfut_、AKIA、xox?-、JWT、带数字的 Bearer）。
- 关键词不查正文和工具输出：10-17 实测几乎每条开发会话的工具输出里都有 API_KEY/SECRET/TOKEN（box 广告 3 条里 2 条、
  iMac vllm 4 条全中），查了会把正常会话也排掉。通用的 NAME=value 格式也不算（命中的都是占位符）。
- 10-17 dry-run：iMac 广告 12 → 保留 7、排除 5（KEYS、AIKEYS、PROD-ADMIN-SECRET、REVOKE 四条会话 + FDV-77「生产管理员secret」
  工作区的占位行）；box 广告、两边 vllm、官网、心月都和改前一样。
- 只排除，不删已有数据。
- 关键词 v2（2026-10-18，Zack 16:30「还是按他的来吧」，FDV-67）：去掉单独的 TOKEN(S)（vllm 开场任务常写 max tokens），
  只认 api token、access token、令牌；新增 api key、ai key、密钥（FDV-72「开AI key」那条占位行因此被排除）。
  匹配范围不变，没有 transcript 的占位行照样查标题。

## MBA（2026-10-18 起）

- precheck：`collect-mba.sh`、`collect-mba-deepvision-site.sh`、`collect-mba-repo.sh <repo>`，是 iMac 那三份把 `imac` 换成 `mba` 的副本（MBA 副本在 `~/.orca-state/bin/everos-ingest/`）。
  推到 box 的 `/var/lib/everos-ingest/<项目>/$D/sessions-mba.jsonl` 和 `mba/`，用 MBA 自己的 key `~/.ssh/everos-ingest-mba`（box authorized_keys 注释 `everos-ingest-mba-to-box`，限 `from="100.64.0.7"`）。
- 采集器 `--machine` 多认一个 `mba`；`nightly_addflush.py` 多读 `sessions-mba.jsonl`，MBA 那份缺了记 WARN，不算失败（deepvision-site 仓库的 `dv_addflush.py` 同样改法，另一个 PR）。
- automation（MBA 本机 ops 工作区，时间和 iMac 同）：`5a9491fe` 心月 · 13 EverOS 会话采集 MBA（21:50），`25ec90b7` dv运维 · 14 EverOS 官网会话采集 MBA（00:01），
  `679f7c06` dv广告 · 26 EverOS 广告会话采集 MBA（00:02），`fc1dd06a` vllm · 27 EverOS 会话采集 MBA（00:16）。

## 夜审写入后读回（PER-67 第 4 步第 1 项，2026-10-19）

- HTTP 200 不算写进去了（FDV-81：add/flush 都 200 却没有 episode；vllm 10-18 写进了错的作用域）。
  共用模块 `everos_readback.py`：按 session_id 查 episode（`/memory/get` + `filters.session_id`），或按 name 查
  agent_skill（get 没有 name 过滤，翻页精确匹配），逐条核对记录里的 app_id / project_id / user_id（skill 是
  agent_id）/ session_id 和该项目 env 一致。EverOS 抽取是异步的：每 10s 轮询一次，上限 `READBACK_TIMEOUT_S=180`。
  失败一律 `readback_failed`，reason 是 not_found / not_more_than_before / scope_mismatch / request_failed，退出码 3。
- 四个入口：
  - 心月、广告、vllm 会话：`nightly_addflush.py` 写完、count_after 之后读回每个 OK 会话（要比写前的 episode 多）；
    读不回的行改成 `result=FAIL`、`reason=readback_failed: …`，台账多 `kind=readback` / `readback_summary`。
  - 广告、vllm lesson：`dv_ads_lessons.py`（替换原来的 5/15/30/60s post_check）；ALREADY 也读回。
  - 官网：写入脚本在 deepvision-site 仓库 `scripts/everos/dv_addflush.py`，不改它；夜审在它之后跑
    `python3 -I everos_readback.py --project deepvision-site --from-log <D>-deepvision-site-addflush.json --session nightly-review-deepvision-site-<D>`。
  - 只读复查：`everos_readback.py --project P --from-log LOG.json --session SID --skill NAME --report OUT.json`；
    两个写入脚本也有 `--readback-only`（不 add/flush）。
- 演练专用（夜审里不用）：`EVEROS_WRITE_STUB_URL`（add/flush 只发到这个地址，读回仍查真 EverOS）、
  `everos_readback.py --query-project-id`、`EVEROS_PUBLIC_URL`（CLI 的公网回落地址）。
- 演练产物：`/workspace/ops/reports/drills/per67-a-readback/`。
