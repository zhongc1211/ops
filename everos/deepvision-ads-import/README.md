# deepvision-ads LESSONS → EverOS（等 eggbot 在 site 导入）

- 准备：2026-10-16 SGT，FDV-67 会话（box）。**box 没有写入 EverOS**
- ID（Zack 13:07）：app_id=`deepvision`，project_id=`deepvision-ads`，agent_id=`coding-deepvision-ads`，user_id=`zack`
- `source/`：16 条原文，一条一个文件；frontmatter 格式与 `../import/import_lessons.py` 读的相同。哈希见 `source.sha256`
- `LESSONS-dv-ads.md`：同样 16 条，合成一个文件，带出处；`split_lessons.py` 用它生成 `source/`

## eggbot：在 site 上导入

```bash
# 把 ads-import/ 拷到 site，例如 /tmp/ads-import/
sudo -u everos env EVEROS_ROOT=/var/lib/everos /opt/everos/venv/bin/python3 /tmp/ads-import/import_lessons_dvads.py --dry-run /tmp/ads-import/source   # 应输出 TOTAL 16
sudo -u everos env EVEROS_ROOT=/var/lib/everos /opt/everos/venv/bin/python3 /tmp/ads-import/import_lessons_dvads.py /tmp/ads-import/source
# 预期落盘位置：/var/lib/everos/deepvision/deepvision-ads/agents/coding-deepvision-ads/skills/skill_<slug>/SKILL.md，共 16 个
```

方法和心月的导入一样（`AgentSkillWriter.write_main`）。slug 都不超过 38 字符，不会被 sanitize 截断。`category` 取值是 `rule`（来自 AGENTS 的硬规则）或 `lessons`（踩过的坑），两类都计入 Seen×3。

#15 `box-heavy-job-gate` 和 #16 `dvads-tooling-gotchas` 来自 box 上的 Claude auto-memory，不在仓库里。Zack 已定（2026-10-16）16 条全部导入，已导入完成；check_recall 不需要 `--skip`。

## box：导入后核对

```bash
cd /workspace/ops/everos-lessons-plan/ads-import
set -a; . ~/.config/everos/dv-ads.env; set +a
python3 -I check_recall.py > recall-after-import.md; echo exit=$?   # 要求 exit 0、缺口 0
```

检查内容：每条都在 `/memory/get` 里；用该条的「规则」原文做 keyword search（top_k=10），要能召回；EverOS 里的正文和源文件一致；用 project_id=deepvision-site 和 app_id=xinyue 做同样的查询，命中数为 0。导入前的基线是 `recall-before-import.md`：0/16，exit 1。
