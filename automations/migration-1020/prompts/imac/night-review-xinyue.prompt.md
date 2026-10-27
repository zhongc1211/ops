【运行环境：iMac（macOS，MBA 错过时的备用），ops 主工作区 ~/orca/workspaces/ops；box 原版 75b324a4。】
iMac 版通用规则（PER-79 从 box 迁来，先读这一段；和下文冲突时以这一段为准）：
- 开始前：export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH；`command -v gh && gh auth status` 失败 → 失败项「gh 不可用」；`orca linear team list >/dev/null` 失败 → 失败项「Linear 未登录」（都按下文的失败告警处理）。
- 防睡：先跑 `nohup caffeinate -dimsu -w $PPID >/dev/null 2>&1 &`（跟着本会话的 agent 进程，会话结束它就退出）。
- 锁：预检已经拿了 heavy-lock（名字 night-review-xinyue）。每做完一步跑一次 `bash ~/orca/workspaces/ops/scripts/heavy-lock.sh refresh night-review-xinyue`，不要自己 release，最后一步会放。
- 会话清单：预检已把当晚的会话清单同步到 ~/everos-ingest/xinyue/${D}/（transcript_path 已改成本机路径）。先读 ~/everos-ingest/xinyue/${D}/SYNC-STATUS：不是 ok 开头 → 按「清单缺失」处理（失败告警，note 写 SYNC-STATUS 的内容）。
- box 上的 status.md 等文件用 `ssh box cat <路径>` 只读；不在 box 上改任何东西（存放位置在 box 时，最后一步的拷贝除外）。
- 这是接替运行（MBA 错过了这一晚，原因见 `bash ~/orca/workspaces/ops/scripts/night-review-gate.sh reason xinyue "$D"`）：同一晚只写一次 EverOS。会话写入已带 --skip-existing（已有 episode 的会话 result=ALREADY，不再写，摘要计数）；lesson / skill 脚本对已有的 session 或同名 skill 本来就不重写。
- 最后一步（摘要写完、摘要里有一行行首是「状态：完成」之后）：`R=$(bash ~/orca/workspaces/ops/scripts/night-review-gate.sh reason xinyue "$D"); notify-run --bot ops-system --no-tty --task "心月夜审 ${D} machine=imac reason=$R" -- bash ~/orca/workspaces/ops/scripts/night-review-gate.sh finish xinyue "$D" imac "$R"`。它把摘要、台账、日志拷到夜审结果的存放位置（`night-review-gate.sh` 里的 NR_STORE_HOST / NR_STORE_DIR，用 tar），记 done，放锁，并叫醒 ops-system。退出码 3 = 摘要里没有「状态：完成」，4 = 没拷到存放位置（notify-run 会把非 0 退出码报给 ops-system）：在本机摘要的失败项补一行，不要重试超过 2 次。

心月夜审（xinyue-site，每晚一次，EverOS 版，按 box:/workspace/ops/everos-lessons-plan/HANDOFF-coding.md（`ssh box cat`，只读） §4）。只记录，不改业务代码、不部署、不碰生产；不打印、不提交、不写日志任何密钥。

准备：D=$(bash ~/orca/workspaces/ops/scripts/review-date.sh ago 6)（23:40 定时；减 6 小时，接替或补跑拖到次日 05:59 前都还是这一天）。摘要目录 ~/xinyue-deploy/nightly-review/ 不存在先 mkdir -p。在做任何其他事之前，先写摘要骨架 ~/xinyue-deploy/nightly-review/${D}-xinyue.md（已存在就覆盖），内容如下，各行行首格式不变，00:30 的兜底检查按「状态：」和「当前步骤：」这两行判断：

```
# 心月夜审 ${D}

状态：进行中
当前步骤：第 0 步 准备
开始时间：<HH:MM SGT>
更新时间：<HH:MM SGT>
写入台账：~/xinyue-deploy/nightly-review/${D}-xinyue-ledger.jsonl

## 已完成步骤

## 失败项
```

之后每完成一步就更新这个文件：改「当前步骤」为下一步、改「更新时间」，在「已完成步骤」下追加一行该步结果；发现失败项立即追加到「失败项」。中途断掉时，从文件能看出停在哪一步。

EverOS：tailnet 优先、公网回落。tailnet 地址 http://100.64.0.5（请求带 Host: everos.deepvision.sg，路径和 Bearer 与公网相同，nginx 超时 400s，没有 Cloudflare 的 100s 限制；只有 tailnet 机器能连）；公网 EVEROS_BASE_URL=https://everos.deepvision.sg 只在 tailnet 连不上时用。app_id=xinyue，project_id=xinyue-site，agent_id/sender=coding-xinyue-site，user_id=zack，API 前缀 /api/v2/memory/*，search 一律 "method":"keyword"（无 embedding，hybrid 会 422）。密钥：set -a; source ~/.config/everos/xinyue.env; set +a（提供 EVEROS_API_KEY，只用作 curl 的 Authorization: Bearer 头，不 echo）。先查 health：curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 -H 'Host: everos.deepvision.sg' http://100.64.0.5/health，200 就算通过并在摘要写「health：tailnet 200」；连不上或非 200，再用公网 https://everos.deepvision.sg/health，200 就算通过并在摘要写「health：tailnet 不通，公网 200」。该文件不存在、两条路的 health 都不是 200、或带 token 的请求 401 → 视为失败（见第 6 步）。

1. 读会话清单：~/everos-ingest/xinyue/${D}/sessions-box.jsonl 和 sessions-imac.jsonl（每行一个 JSON：session_id, machine, workspace, linear_id, started_at, ended_at, status, transcript_path, status_md_path, summary_path, git_branch, pr_urls），按 session_id 去重。同时看当天（SGT 00:00–现在）xinyue-site 的 commit/PR（cd ~/pi/remote/xinyue-site && git fetch origin --prune；gh pr list/view 含评论，只读，不改该仓库分支和文件）、Linear 心月网站 project 当天评论（orca linear 只读）、box:/workspace/xinyue-web/status.md（`ssh box cat`，只读）。若任一侧 jsonl 缺失，而另一侧或 git/PR/Linear 显示当天有心月开发活动 → 失败（第 6 步）。两侧都缺且当天无任何活动 → 正常，摘要写「当日无会话」。
   MBA（2026-10-18 起）：同目录还有 sessions-mba.jsonl 和 mba/（采集 automation：MBA 5a9491fe「心月 · 13 EverOS 会话采集 MBA」21:50），和另两份一样读、一起按 session_id 去重；写入脚本已经会读它。MBA 那份缺了只在摘要里记一句「MBA 清单缺失」，不算失败。摘要里的会话数写 box / iMac / MBA。
2. 写入 EverOS：不要自己拼 add/flush，调用写入脚本 S=~/orca/workspaces/ops/everos-ingest/nightly_addflush.py（不存在就用工作目录下的 everos-ingest/nightly_addflush.py）：
   python3 -I "$S" --date "$D" --sessions-dir ~/everos-ingest/xinyue/"$D" --skip-existing --log ~/xinyue-deploy/nightly-review/${D}-addflush.json --ledger ~/xinyue-deploy/nightly-review/${D}-xinyue-ledger.jsonl > ~/xinyue-deploy/nightly-review/${D}-addflush.out 2>&1
   脚本按第 1 步的两份 jsonl 逐会话读 transcript，POST /api/v2/memory/add（app_id=xinyue, project_id=xinyue-site, agent 侧 sender 取 env 的 EVEROS_ASSISTANT_SENDER_ID=coding-xinyue-site），再 POST flush；transcript 不可读的会话记为 FAIL。写入前后各 POST /api/v2/memory/get 一次 episode 计数（含 id 列表），每次 add/flush/get 立即追加一行到台账。当日无会话也照常运行一次，让台账有写前、写后计数。
   运行时间可能超过单条命令的时限；放后台运行可以，但要把 PID 和 ${D}-addflush.out 路径写进摘要，并且在第 3 步写 skill 和第 7 步收尾之前，必须等到进程退出、台账出现 kind=summary 那一行。进程退出了却没有 summary 行 → 失败（第 6 步）。
   脚本自己选通道：每次请求先连 tailnet，只有连接阶段失败（连不上、被拒绝，请求肯定没发出）才改走公网，台账该行 endpoint=public 并带 fallback 原因。HTTP 超时约 420s。
   结果未知规则（脚本已实现，只走脚本，不要手拼 add/flush/get 去补）：add 或 flush 拿到 524/504/502、超时或连接中途断开，算「结果未知」。EverOS 的索引有延迟（10-17 实测 flush 200 后约 18s 才按 session 查得到），所以脚本不立刻判定，而是等 5s、15s、30s、60s 各复查一次（共约 2 分钟），每次查这条会话的 episode 数（get，filters.session_id）、未 flush 缓冲（search，filters.session_id）和 episode 总数。任一次查到已落库就停止复查、不补发；四次都没查到才补发：add 用原来的时间戳重发该块，flush 先把各块重新 add 再 flush 一次（消息还在缓冲里就只再 flush）。总数涨了但按 session 查不到，或复查本身读不到，记 failed、不补发。每条会话最多补发一轮，再失败就记 failed 并停这条会话。台账：每次复查一行 kind=recheck（attempt、delay_s、session_hits、buffered、total_count、total_before、endpoint、http），最后一行 kind=recheck_decision（decision=landed/resend/failed，失败时带 reason）；add/flush 行仍有 endpoint（tailnet/public）和 outcome（ok / unknown→landed / unknown→resent / failed），补发的那行带 resend=true。
   写完脚本会按 session_id 读回每个 OK 会话（everos_readback.py，同一作用域，最多等 180s；HTTP 200 不算数）：读不回、作用域不对或读回请求失败的会话改成 FAIL、reason 以 readback_failed 开头，退出码 3，台账有 kind=readback / readback_summary 行。
   结果判定看退出码、${D}-addflush.json 和台账：退出码非 0、任一会话 result=FAIL（第 1 步已判定为正常的「jsonl 缺失」除外）、任一台账行 outcome=failed、count_before 或 count_after 的 http 不是 200 → 失败（第 6 步）。outcome 为 unknown→landed 或 unknown→resent 且该会话 result=OK 的不算失败，但要在摘要里逐条列出（session_id、哪一步、复查了几次、recheck_decision、最后结果）；recheck_decision=failed 的按失败处理，reason 写进失败项。摘要里引用台账：写前/写后 total_count、新增 episode id（台账 summary 行的 new_episode_ids）、OK/FAIL 会话数、走公网的调用数（endpoint=public 的行数，0 也写）。
3. 对照当日 commit/PR/Linear，只找：修完又返工的、不该合的、验证太糙的；做对的记 Done right。优先让 EverOS 抽 case/skill；当前无 embedding，skill_extraction 不可用，所以先 POST /api/v2/memory/search（keyword）查是否已有同类 agent_skill：已有就只更新其 SKILL.md 的 seen_count/seen_dates（加当天日期，同日不重复）；没有就新写一条 SKILL.md（frontmatter 与已导入的 15 条同格式：id/type=agent_skill/schema_version/agent_id/track/name/description/confidence/maturity_score/category/seen_count/seen_dates/source=xinyue-nightly-${D}；done_right 用 category: done_right，不计入升级）。SKILL.md 位于 EverOS 数据根 xinyue/xinyue-site/agents/coding-xinyue-site/skills/；写入后按 name 读回：python3 -I ~/orca/workspaces/ops/everos-ingest/everos_readback.py --project xinyue --skill <name>（每条 skill 一个 --skill，退出码 3 = readback_failed，失败项写 skill 名和 reason）。若本机无写入通道（box 上是常态），就把新增/更新的 SKILL.md 全文写到 ~/xinyue-deploy/nightly-review/${D}-skills/，摘要里写「由心月 · 28 在 00:20 写入 EverOS」；这不算失败项，不发 stuck webhook，也不要绕道拿凭据。不再读写仓库 docs/solutions/LESSONS.md 或 lessons/，不再开 docs PR。 每写一条 EverOS，立刻按目标 app/project/user 读回；读不到算没写，记进报告并叫醒负责的 bot。一条只记一个会改变以后做法的事实。
4. 维护 docs/decisions.md 的工作停用；把当天 PR/Linear/status 里写明「Zack 批/定」的决定列进摘要即可。
5. 某条规则 seen_dates 刚达到 3 个不同 SGT 日期时才执行：source ~/.config/grokbot/webhooks/xinyue.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"xinyue","task":"心月夜审","worktree":"~/orca/workspaces/ops","status":"done","note":"规则升级：<skill 名>"}'。其余情况不叫醒心月 bot。
6. 失败告警（第 0/1/2 步的失败条件，或 add/flush/search 报错）：source ~/.config/grokbot/webhooks/ops-system.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"ops-system","task":"心月夜审 '"${D}"'","worktree":"~/orca/workspaces/ops","status":"stuck","note":"machine=imac <失败项一句话，不含密钥>"}'，然后照常写摘要。
7. 最后把 ~/xinyue-deploy/nightly-review/${D}-xinyue.md 补全：会话数（box / iMac）、写入 EverOS 的会话数、写前/写后 episode 计数和新增 episode id（引用台账 ${D}-xinyue-ledger.jsonl）、新增/更新 skill 数及名字、达到 3 日升级的条目、Zack 决定、失败项。全部写完后把「状态：进行中」改成「状态：完成」、「当前步骤」改成「全部完成」、更新「更新时间」。有失败项也改成完成，失败项留在「失败项」里；只有真正走到这一步才改。
8. 不发首跑 webhook。
9. 然后做通用规则里的最后一步。
