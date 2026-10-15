# LESSONS → EverOS import evidence

- 日期：2026-10-16 ~03:18 SGT
- 执行：dr eggbot（Orca / site via iMac SSH）
- 源：`xinyue-site/docs/solutions/LESSONS.md` + `lessons/*.md`（9 规则）+ Done right 表（6 条）
- 目标：`app_id=xinyue` / `project_id=xinyue-site` / `agent_id=coding-xinyue-site`
- 根：`/var/lib/everos`
- 方式：手写 `SKILL.md`（`AgentSkillWriter.write_main`），**未**改 LLM/Cloudflare/headscale/夜审

## 结果

| 项 | 值 |
|---|---|
| 导入 skill 数 | **15**（9 规则 + 6 done_right） |
| 磁盘 SKILL.md | 15 |
| API `memory/get` agent_skill | 15 |
| keyword search「切流量 绑定」 | 1 hit → `check-bindings-before-shifting-production-traffic` |
| 隔离 `app_id=deepvision` 同 query | 0 hits |
| health | 200，version 1.4.2，cascade healthy，llm true，embed false |

## 路径前缀

```
/var/lib/everos/xinyue/xinyue-site/agents/coding-xinyue-site/skills/skill_<name>/SKILL.md
```

### 9 规则

- skill_check-bindings-before-shifting-production-traffic
- skill_cut-production-prs-from-the-production-base
- skill_fix-a-test-that-runs-at-its-time-limit
- skill_get-a-real-phone-result-before-shipping-a-phone-ta  ← sanitize 截断原 slug
- skill_name-and-rerun-failures-called-unrelated
- skill_post-the-evidence-a-pr-body-points-to
- skill_record-who-decided-before-shipping-an-open-questio  ← sanitize 截断原 slug
- skill_run-browser-tests-on-the-pr-head-before-merging
- skill_treat-check-only-as-a-real-deploy

### 6 Done right（`category: done_right`，不进 Seen×3）

- skill_done-right-verification-five-sections
- skill_done-right-list-unverified-in-ship-comment
- skill_done-right-rollback-commands-in-ship-comment
- skill_done-right-confirm-fail-before-fix
- skill_done-right-explain-changed-test-premise
- skill_done-right-dont-claim-untriggered-as-verified

## Frontmatter（每条）

必填：`id/type=agent_skill/schema_version/agent_id/track/name/description/confidence/maturity_score`  
扩展：`category`（规则种类或 `done_right`）、`seen_count`、`seen_dates`、`source=xinyue-lessons-import-2026-10-16`

## 验证命令（site，经 `ssh site`）

```bash
TOKEN=$(cat /etc/everos/proxy-token)
find /var/lib/everos/xinyue -name SKILL.md | wc -l   # → 15

curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  http://127.0.0.1:8000/api/v2/memory/get \
  -d '{"app_id":"xinyue","project_id":"xinyue-site","memory_type":"agent_skill","agent_id":"coding-xinyue-site","page_size":50}'

curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  http://127.0.0.1:8000/api/v2/memory/search \
  -d '{"app_id":"xinyue","project_id":"xinyue-site","query":"切流量 绑定","method":"keyword","agent_id":"coding-xinyue-site"}'
```

公网等价：`https://everos.deepvision.sg` + 同一 Bearer（`/etc/everos/proxy-token` → `EVEROS_API_KEY`）。

## 导入脚本

- box：`/workspace/ops/everos-lessons-plan/import/import_lessons.py`
- 运行：`sudo -u everos env EVEROS_ROOT=/var/lib/everos /opt/everos/venv/bin/python3 import_lessons.py <lessons_dir>`

## Leftovers / 注意

1. EverOS `sanitize_skill_name` 截断了两个超长 slug（上表已标）；正文标题仍是完整中文原题。
2. 无 embedding → hybrid/vector/skill_extraction 仍 disabled；召回用 `method=keyword`。
3. 未改 `75b324a4`、Cloudflare tunnel、headscale、magpie / EverOS LLM env。
4. best-practices 目录（`built-in-game-modules-2026-10-10.md`）**未**导入（不在 LESSONS 规则/Done right 表内）。
