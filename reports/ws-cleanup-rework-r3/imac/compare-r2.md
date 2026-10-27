## 真实工作区：R2 128 行，R3 96 行
| 结论 | R2 | R3 | 差 |
|---|---|---|---|
| RM | 19 | 0 | -19 |
| BACKUP_RM | 13 | 0 | -13 |
| SKIP | 95 | 95 | +0 |
| LIST | 1 | 1 | +0 |

逐行有变化的：
- xinyue-site auto-run-1-20261013T1530：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- xinyue-site auto-run-2-20261013T1725：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- xinyue-site docs-lessons-to-everos：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- xinyue-site ops-everos-imac-mcp：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site per-50-flood-timeout：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site pr83-merge：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site unpushed-cleanup-20261018：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site 心月-AGENTS-对齐：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site 心月-CI-CD-第二阶段：SKIP W17 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- xinyue-site 心月-EverOS-MCP-v2-接线：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site 心月-EverOS-启动器-v2.1：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- xinyue-site 心月-PER-27-模型不可用提示：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site 心月-PER-28-失败按钮：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site 心月-PER-54-文档合并与-feed-monster-排查：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site 心月-生产-Builds-接入：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- xinyue-site xinyue-ci：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- xinyue-site xinyue-site-cicd：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- xinyue-site nightly-xinyue-site：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- xinyue-site xy-combined-src：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- deepvision-ads dvads-fdv-64-oauth：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- deepvision-ads dvads-prod-admin-secret：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- deepvision-ads dv广告-FDV-62-AGENTS-测试规矩：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- deepvision-ads dv广告-FDV-76-隐私页GEO：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- vllm-omni · H3/C1 PER-7-review-导入挪顶部：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- vllm-omni · H3/C1 per-8714-schedule-400：SKIP W17 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- ops everos-research：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- ops everos-vps-deploy：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- ops ops-PER-66-叫醒漏叫修复第二批：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- ops ops-PER-67-e2e-imac：SKIP W12 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- ops ops-PER-84-everos-docs：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- ops ops-PER80-drill-gap9：SKIP W12 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- ops ops-PER82-stuck-budget：SKIP W12 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- ops ops-box-decommission-inventory-1021：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- ops ops-everos-ingest-commit：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- ops ops-stuck-routing-1020：SKIP W18 → SKIP W9（PR 还开着）
- ops ops-tunnel-flaps-1019-imac：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- ops ops-unpushed-nested-1020：SKIP W12 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- ops xinyue-everos-recheck：SKIP W11 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）
- ops xinyue-everos-tailnet：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- ops xinyue-night-review-guard：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- site dv官网-AGENTS-测试规矩：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- site dv官网-FDV-63-AGENTS对齐：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- site dv官网-FDV-65-base-205187c：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- site dv官网-FDV-65-base-683f287：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- site dv官网-FDV-65-iMac整轮e2e：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- site dv官网-FDV-65-testing-Builds修复：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- site dv官网-Open-Design-重设计：RM W14 → （R3 没有，run1 已删或已不在 Orca）
- site dv运维-CI-自动部署：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- site dv运维-FDV-78-EverOS-走-tailnet：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- site fdv-92-rerun-imac：BACKUP_RM W13 → （R3 没有，run1 已删或已不在 Orca）
- site ops-per83-verify-dv-site：SKIP W12 → SKIP W19（NO_LINEAR_ISSUE：Orca 里没挂 Linear issue）

## 演练仓库：R2 25 行，R3 0 行
| 结论 | R2 | R3 | 差 |
|---|---|---|---|
| RM | 0 | 0 | +0 |
| BACKUP_RM | 0 | 0 | +0 |
| SKIP | 25 | 0 | -25 |
| LIST | 0 | 0 | +0 |

逐行有变化的：
- ws-cleanup-drill ws-cleanup-drill：SKIP W1 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d04-unpushed：SKIP W8 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d05-dirty：SKIP W7 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d06-gone-local：SKIP W4 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d08-inreview：SKIP W11 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d09-late-commit：SKIP W8 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d10-late-dirty：SKIP W7 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d11-locked：SKIP W18 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d13-noperm：SKIP W12 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d15-nested：SKIP W12 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d16-linear-missing：SKIP W10 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d17-branch-only：SKIP W12 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d04-unpushed：SKIP W8 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d05-dirty：SKIP W7 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d06-gone-local：SKIP W4 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d08-inreview：SKIP W11 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d09-late-commit：SKIP W8 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d10-late-dirty：SKIP W7 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d11-locked：SKIP W18 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d12-sha：SKIP W12 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d13-noperm：SKIP W12 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d15-nested：SKIP W12 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d16-linear-missing：SKIP W10 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d17-branch-only：SKIP W12 → （R3 没有，run1 已删或已不在 Orca）
- ws-cleanup-drill d01-clean：SKIP W6 → （R3 没有，run1 已删或已不在 Orca）

