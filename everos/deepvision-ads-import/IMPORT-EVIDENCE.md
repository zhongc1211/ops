# deepvision-ads LESSONS → EverOS 导入证据

- 时间：2026-10-16 13:15–13:18 SGT（site UTC 05:15–05:18）；site 157.230.194.108，EverOS 1.4.2，经 iMac ssh
- Scope（Zack 13:07）：app_id=deepvision, project_id=deepvision-ads, agent_id=coding-deepvision-ads, user_id=zack
- 范围：**全部 16 条**（父会话 13:15 更正：#15 box-heavy-job-gate、#16 dvads-tooling-gotchas 也导，不用 --skip）。脚本保留了可选的 `--skip`，本次没用
- 方法：`sudo -u everos env EVEROS_ROOT=/var/lib/everos /opt/everos/venv/bin/python3 import_lessons_dvads.py source`（AgentSkillWriter.write_main(..., app_id=APP_ID, project_id=PROJECT_ID)）
- 校验：`site_verify.py --recall`，只打 site loopback，没用也没打印 token；没升级、没重启 EverOS；site /tmp 与 iMac 中转已删

## 备份
- 导入前 `/var/lib/everos/deepvision/deepvision-ads` **不存在**，没有旧数据需要备份（之前一次跑到一半被打断的命令什么都没写，导入前再次确认目录不存在）
- 导入后快照：`/root/deepvision-ads-after-import-20261016.tgz`，sha256 `c334fc8210c1c71af7af3bf2f5b2e852a15d7d6dc258249035552baa43d7ccbc`；回滚 = 删掉该目录

## 计数
| | 导入前 05:15 UTC | 导入后 |
|---|---|---|
| xinyue episode（zack） | 3 | 3 |
| xinyue agent_skill API / 磁盘 | 44 / 44 | 44 / 44 |
| vllm-omni agent_skill | 1 | 1 |
| deepvision-site agent_skill API / 磁盘 | 8 / 8 | 8 / 8 |
| deepvision-ads agent_skill API / 磁盘 | 0 / 0 | **16 / 16** |

## 召回（keyword，query=每条的「规则」原文，top_k=10）
16/16 在 deepvision/deepvision-ads 命中；同样的查询在 deepvision/deepvision-site 和 xinyue/xinyue-site 命中 0；全部请求 200。
条目：box-heavy-job-gate, cf-custom-domain-overwrites-dns, cf-deploy-auto-creates-d1-r2, d1-migrations-do-not-roll-back, dvads-tooling-gotchas, green-checks-before-merging-staging, honest-e2e-on-pr-head, migration-number-equals-linear-issue, never-copy-reference-product-assets, no-prod-deploy-no-real-ad-accounts, no-slash-in-orca-workspace-names, node22-and-legacy-peer-deps, one-issue-one-worktree-one-pr-2000, stop-when-cf-builds-repo-not-visible, tenant-queries-filter-workspace-or-org, use-cf-cli-not-wrangler。

正式的 check_recall.py（经 nginx + token，不带 --skip）留给广告产品 bot 跑。
