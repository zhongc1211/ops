### iMac：一致 91 条；不一致 33 条（新规则带来的 28，审计后状态变了 5，要查的 0）

**新规则带来的预期变化（28）**

| 路径 | 说明 | dry-run | 按审计推出的 |
|---|---|---|---|
| `~/orca/workspaces/deepvision-ads/dvads-fdv-66-email` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：.open-next、next-env.d.ts | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/deepvision-ads/dvads-privacy-facts` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：docs/e2e/legal/fdv-76-320d6a4e87ef0827b5d8f8b5b4e3aeb87ba49ad1/report.md、docs/e2e/legal/fdv-76-r2-revert/report.md、next-env.d.ts | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/deepvision-ads/dv广告-FDV-39-Meta沙盒入Business` | 做完的证据只有 Linear 已关（FDV-39 completed），审计没查 Linear | RM W14（条件全部满足） | SKIP（状态是 sleep，PR 也没合并/关闭） |
| `~/orca/workspaces/deepvision-ads/dv广告-FDV-76-隐私页GEO` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：next-env.d.ts | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/ops/everos-vps-deploy` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：xinyue-lessons-import.tgz | RM W14（条件全部满足） | BACKUP_RM（4c 4b-2） |
| `~/orca/workspaces/repository/PER-56-h3-merge-three` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/repository/PER-56-n7-rootcause` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/repository/PER-8-hunyuan-imac-omni` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/repository/per56-n10-rootcause-opus` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | RM（4b-1） |
| `~/orca/workspaces/site/dv官网-FDV-60-套餐对比` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：next-env.d.ts | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/dv官网-FDV-65-base-205187c` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：next-env.d.ts、public/placeholder/sample | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/dv官网-FDV-65-base-683f287` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：next-env.d.ts、public/placeholder/sample | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/dv官网-FDV-70-iMac-产品页` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/dv官网-FDV-70-iMac-关于我们` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/dv官网-FDV-70-iMac-博客` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/dv官网-FDV-70-整版合-staging-上线准备` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/dv运维-CI-自动部署` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：.open-next、next-env.d.ts、public/placeholder/sample | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/fdv-60-e2e-followup` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：next-env.d.ts | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/site/fdv-70-deslop-r2` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/xinyue-site/per-50-flood-timeout` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：studio-public/base.css | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/xinyue-site/per-51-quality-recover` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：studio-public/base.css | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/xinyue-site/per-61-bubble-ai` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/xinyue-site/per-75-oss-games` | 做完的证据只有 Linear 已关（PER-75 completed），审计没查 Linear | RM W14（条件全部满足） | SKIP（状态是 in-review，PR 也没合并/关闭） |
| `~/orca/workspaces/xinyue-site/心月-AGENTS-对齐` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：.cloudflare | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/xinyue-site/心月-CI-CD-第二阶段` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：.cloudflare、studio-public/base.css | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/xinyue-site/心月-PER-27-模型不可用提示` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：studio-public/base.css | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/xinyue-site/心月-PER-28-失败按钮` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：studio-public/base.css | RM W14（条件全部满足） | BACKUP_RM（4b-2） |
| `~/pi/remote/xinyue-site-cicd` | 备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：runtime-public/_headers、runtime-public/assets.json、runtime-public/assets、runtime-public/emscripten-module.wasm、runtime-public/host.bundle.mjs、runtime-public/vendor | RM W14（条件全部满足） | BACKUP_RM（4b-2） |

**审计（01:07）之后状态变了（5）**

| 路径 | 说明 | dry-run | 按审计推出的 |
|---|---|---|---|
| `~/orca/workspaces/ops/ops-P11-devbotrules-two-machines` | 审计（01:07）之后新建的工作区 | SKIP | - |
| `~/orca/workspaces/ops/ops-PER-134-dryrun-fix` | 审计（01:07）之后新建的工作区 | SKIP | - |
| `~/orca/workspaces/ops/ops-PER-94-rework-imac` | 审计（01:07）之后新建的工作区 | SKIP | - |
| `~/orca/workspaces/ops/ops-box-decommission-inventory-1021` | 审计（01:07）之后新建的工作区 | SKIP | - |
| `~/orca/workspaces/ops/ops-cleanup-rules-draft-1021` | 审计（01:07）之后新建的工作区 | SKIP | - |

**真不一致，要查原因（0）**

无

### MBA：一致 27 条；不一致 7 条（新规则带来的 5，审计后状态变了 2，要查的 0）

**新规则带来的预期变化（5）**

| 路径 | 说明 | dry-run | 按审计推出的 |
|---|---|---|---|
| `~/orca/workspaces/deepvision-site/dv官网-FDV-70-PR6-其余页面` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/deepvision-site/dv官网-FDV-70-Ryze复刻重做-MBA` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/deepvision-site/dv官网-FDV-70-Ryze对照图` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/deepvision-site/dv官网-FDV-70-示例行业整改` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | BACKUP_RM（4b-2） |
| `~/orca/workspaces/vllm-omni/vllm-PER-56-4090-A100-MBA` | Linear 现在会查（审计没查） | SKIP W10（Linear 还没关） | RM（4b-1） |

**审计（01:07）之后状态变了（2）**

| 路径 | 说明 | dry-run | 按审计推出的 |
|---|---|---|---|
| `~/orca/workspaces/ops/ops-PER-94-pstack-monitor-mba` | 审计（01:07）之后新建的工作区 | SKIP | - |
| `~/orca/workspaces/ops/ops-per126-v3-review-1021` | 审计（01:07）之后新建的工作区 | SKIP | - |

**真不一致，要查原因（0）**

无

- MBA：审计里的 git-only worktree `/private/tmp/claude-501/-Users-jiawenwang-orca-workspaces-ops-ops-everos-catchup-1020/864e9821-4cd9-4aee-8246-3092d9e7afdb/scratchpad/wt-58d9b8b` 现在已经不在了（归到「状态变了」，不在上面的条数里）
- MBA：审计里的 git-only worktree `/private/tmp/claude-501/-Users-jiawenwang-orca-workspaces-deepvision-site-fdv-70-calendar-claim/d7233ad0-7526-407e-9827-168a9eeb34f1/scratchpad/base-b61fc06` 现在已经不在了（归到「状态变了」，不在上面的条数里）
- MBA：审计里的 git-only worktree `/private/tmp/claude-501/-Users-jiawenwang-orca-workspaces-deepvision-site-fdv-70-g6-g7-g9/72bd3d79-82b5-4e0a-8dc2-2bcb29d1e75b/scratchpad/base` 现在已经不在了（归到「状态变了」，不在上面的条数里）
