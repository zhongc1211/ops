# deepvision-site LESSONS → EverOS 导入证据

- 时间：2026-10-16 13:10–13:12 SGT（site UTC 05:10–05:12）；site 157.230.194.108，EverOS 1.4.2，经 iMac ssh
- Scope（Zack 13:07 批准）：app_id=deepvision, project_id=deepvision-site, agent_id=coding-deepvision-site, user_id=zack
- 方法：`sudo -u everos env EVEROS_ROOT=/var/lib/everos /opt/everos/venv/bin/python3 import_deepvision_lessons.py docs/solutions`（AgentSkillWriter.write_main(..., app_id=, project_id=)）
- 校验：`site_verify.py --recall`，只打 site loopback `127.0.0.1:8000`，没用也没打印 token
- 没升级、没重启 EverOS；site /tmp 和 iMac 中转文件已删

## 备份
- 导入前目标目录 `/var/lib/everos/deepvision/deepvision-site` **不存在**（整个 `deepvision/` app 目录也没有），所以没有可备份的旧数据。
- 导入后快照（便于回滚/对比）：`/root/deepvision-site-after-import-20261016.tgz`，sha256 `f02b4a2b932a4942e966ed3d5c9985a85e4ade7690dd6d190a0fa0525e7415c8`。回滚 = `rm -rf /var/lib/everos/deepvision/deepvision-site`。

## 计数
| | 导入前 | 导入后 |
|---|---|---|
| xinyue episode（user zack） | 3 | 3 |
| xinyue agent_skill API / 磁盘 | 44 / 44 | 44 / 44 |
| vllm-omni agent_skill | 1 | 1 |
| deepvision/deepvision-site agent_skill API / 磁盘 SKILL.md | 0 / 0 | **8 / 8** |

## 召回（keyword，query=条目标题，top_k=10）
| skill | deepvision scope | xinyue scope |
|---|---|---|
| all-or-nothing-i18n-fallback-per-product | 命中 | 无 |
| pricing-compare-and-brand-logos | 命中 | 无 |
| single-flag-seed-gating-transactional-write | 命中 | 无 |
| single-product-site-conversion | 命中 | 无 |
| whatsapp-assistant-widget | 命中 | 无 |
| tailwind-v4-custom-theme-tokens | 命中 | 无 |
| insert-or-ignore-requires-unique-constraint | 命中 | 无 |
| role-guard-tightening-silent-403-ui | 命中 | 无 |

8/8 召回，xinyue 泄漏 0，全部请求 200。正式的 check_recall.py（经 nginx + token）留给 deepvision-site bot 跑。
