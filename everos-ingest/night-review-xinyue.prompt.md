【运行环境：box（Linux），工作目录是 ops 主工作区。】心月夜审（xinyue-site，每晚一次，EverOS 版，按 /workspace/ops/everos-lessons-plan/HANDOFF-coding.md §4）。只记录，不改业务代码、不部署、不碰生产；不打印、不提交、不写日志任何密钥。

准备：D=$(TZ=Asia/Singapore date +%F)。摘要目录 ~/xinyue-deploy/nightly-review/ 不存在先 mkdir -p。在做任何其他事之前，先写摘要骨架 ~/xinyue-deploy/nightly-review/${D}-xinyue.md（已存在就覆盖），内容如下，各行行首格式不变，00:30 的兜底检查按「状态：」和「当前步骤：」这两行判断：

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

1. 读会话清单：/var/lib/everos-ingest/xinyue/${D}/sessions-box.jsonl 和 sessions-imac.jsonl（每行一个 JSON：session_id, machine, workspace, linear_id, started_at, ended_at, status, transcript_path, status_md_path, summary_path, git_branch, pr_urls），按 session_id 去重。同时看当天（SGT 00:00–现在）xinyue-site 的 commit/PR（cd /workspace/repos/xinyue-site && git fetch origin --prune；gh pr list/view 含评论，只读，不改该仓库分支和文件）、Linear 心月网站 project 当天评论（orca linear 只读）、/workspace/xinyue-web/status.md。若任一侧 jsonl 缺失，而另一侧或 git/PR/Linear 显示当天有心月开发活动 → 失败（第 6 步）。两侧都缺且当天无任何活动 → 正常，摘要写「当日无会话」。
2. 写入 EverOS：不要自己拼 add/flush，调用写入脚本 S=/workspace/ops/everos-ingest/nightly_addflush.py（不存在就用工作目录下的 everos-ingest/nightly_addflush.py）：
   python3 -I "$S" --date "$D" --log ~/xinyue-deploy/nightly-review/${D}-addflush.json --ledger ~/xinyue-deploy/nightly-review/${D}-xinyue-ledger.jsonl > ~/xinyue-deploy/nightly-review/${D}-addflush.out 2>&1
   脚本按第 1 步的两份 jsonl 逐会话读 transcript，POST /api/v2/memory/add（app_id=xinyue, project_id=xinyue-site, agent 侧 sender 取 env 的 EVEROS_ASSISTANT_SENDER_ID=coding-xinyue-site），再 POST flush；transcript 不可读的会话记为 FAIL。写入前后各 POST /api/v2/memory/get 一次 episode 计数（含 id 列表），每次 add/flush/get 立即追加一行到台账。当日无会话也照常运行一次，让台账有写前、写后计数。
   运行时间可能超过单条命令的时限；放后台运行可以，但要把 PID 和 ${D}-addflush.out 路径写进摘要，并且在第 3 步写 skill 和第 7 步收尾之前，必须等到进程退出、台账出现 kind=summary 那一行。进程退出了却没有 summary 行 → 失败（第 6 步）。
   脚本自己选通道：每次请求先连 tailnet，只有连接阶段失败（连不上、被拒绝，请求肯定没发出）才改走公网，台账该行 endpoint=public 并带 fallback 原因。HTTP 超时约 420s。
   结果未知规则（脚本已实现，只走脚本，不要手拼 add/flush/get 去补）：add 或 flush 拿到 524/504/502、超时或连接中途断开，算「结果未知」。脚本先用 get（filters.session_id）和 search 的未 flush 缓冲查这条会话是否已落库：已落库就不再 add；没落库就用原来的时间戳重发一次 add，再 flush 一次。每条会话最多补发一次，再失败就记 failed 并停这条会话。台账每行有 endpoint（tailnet/public）和 outcome（ok / unknown→landed / unknown→resent / failed），补发的那行带 resend=true，查落库的调用是 kind=check。
   结果判定看 ${D}-addflush.json 和台账：任一会话 result=FAIL（第 1 步已判定为正常的「jsonl 缺失」除外）、任一台账行 outcome=failed、count_before 或 count_after 的 http 不是 200 → 失败（第 6 步）。outcome 为 unknown→landed 或 unknown→resent 且该会话 result=OK 的不算失败，但要在摘要里逐条列出（session_id、哪一步、最后结果）。摘要里引用台账：写前/写后 total_count、新增 episode id（台账 summary 行的 new_episode_ids）、OK/FAIL 会话数、走公网的调用数（endpoint=public 的行数，0 也写）。
3. 对照当日 commit/PR/Linear，只找：修完又返工的、不该合的、验证太糙的；做对的记 Done right。优先让 EverOS 抽 case/skill；当前无 embedding，skill_extraction 不可用，所以先 POST /api/v2/memory/search（keyword）查是否已有同类 agent_skill：已有就只更新其 SKILL.md 的 seen_count/seen_dates（加当天日期，同日不重复）；没有就新写一条 SKILL.md（frontmatter 与已导入的 15 条同格式：id/type=agent_skill/schema_version/agent_id/track/name/description/confidence/maturity_score/category/seen_count/seen_dates/source=xinyue-nightly-${D}；done_right 用 category: done_right，不计入升级）。SKILL.md 位于 EverOS 数据根 xinyue/xinyue-site/agents/coding-xinyue-site/skills/；若本机无写入通道，就把新增/更新的 SKILL.md 全文写到 ~/xinyue-deploy/nightly-review/${D}-skills/ 并在摘要里列为「待写入」失败项，不要绕道拿凭据。不再读写仓库 docs/solutions/LESSONS.md 或 lessons/，不再开 docs PR。
4. 维护 docs/decisions.md 的工作停用；把当天 PR/Linear/status 里写明「Zack 批/定」的决定列进摘要即可。
5. 某条规则 seen_dates 刚达到 3 个不同 SGT 日期时才执行：source ~/.config/grokbot/webhooks/xinyue.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"xinyue","task":"心月夜审","worktree":"/workspace/repos/ops","status":"done","note":"规则升级：<skill 名>"}'。其余情况不叫醒心月 bot。
6. 失败告警（第 0/1/2 步的失败条件，或 add/flush/search 报错）：source ~/.config/grokbot/webhooks/coding-assistant.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"coding-assistant","task":"心月夜审 '"${D}"'","worktree":"/workspace/repos/ops","status":"stuck","note":"<失败项一句话，不含密钥>"}'，然后照常写摘要。
7. 最后把 ~/xinyue-deploy/nightly-review/${D}-xinyue.md 补全：会话数（box / iMac）、写入 EverOS 的会话数、写前/写后 episode 计数和新增 episode id（引用台账 ${D}-xinyue-ledger.jsonl）、新增/更新 skill 数及名字、达到 3 日升级的条目、Zack 决定、失败项。全部写完后把「状态：进行中」改成「状态：完成」、「当前步骤」改成「全部完成」、更新「更新时间」。有失败项也改成完成，失败项留在「失败项」里；只有真正走到这一步才改。
8. 不发首跑 webhook。
