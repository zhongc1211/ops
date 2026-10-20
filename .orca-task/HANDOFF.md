# 交接：PER-94 / #55 plugin.json 路径，挪去 MBA（2026-10-20 23:4x SGT）

依据：ops 系统 23:40（Coding助手 定）：iMac 内存吃紧，挪去 MBA。
派活：`/Users/jiawenwang/orca/workspaces/ops/briefs/per94-pr55-pluginjson-RESUME-BRIEF.md`（iMac），eta 00:30 SGT。
分支 `zhongc1211/ops-PER-94-pstack-monitor`。文档改动的 head 是 15f14b1f172bbfe82a307386c21639634623c0e5，已在远端（23:32:10 重启后保底推送，ops 系统确认）。本交接提交排在它后面，只加这个文件，DESIGN.md 没变。

## 做到哪
- 开头核对：本地和远端都是 15f14b1，工作区干净。brief 写的远端是 82ed390，对不上，我先停下写了 RESULT。ops 系统确认是保底推送后接着做。
- 15f14b1 已满足「要改的」：DESIGN.md 第 42 行 MANIFEST 改成 `harness/pstack/claude-code/plugin.json`，第 70 行理由也改了；全文没有剩下指 pstack 版本来源的 `.claude-plugin/plugin.json`。不需要补提交。
- EverOS `recall_agent_experience`：这个会话里没有 ops 的 EverOS 工具，没调。
- 第 1 步脚本：已把 DESIGN.md 第 31–63 行的 bash 块原样抽到临时文件，在 iMac 跑了 4 次（23:38–23:4x，load1 约 8）：
  - run1 默认 `PIN_BRANCH=main`：`ERR pinned=? main=88d47514b82e7c44f00f2b2a72ff6dd12158038c（取不到钉版或 ls-remote 失败）` rc=2。原因：main 上还没有 `bootstrap/claude-plugins/pin-claude-plugins.sh`（#48 没合并）。这是脚本定义的出错分支。
  - run2 `PIN_BRANCH=per83-claude-plugins-bootstrap`（#48 分支，PSTACK_SHA=88d4751，第 28 行用的是 `harness/pstack/claude-code/plugin.json`）：`SAME pinned=88d4751… main=88d4751…` rc=0。钉版 = main，没走到取版本号。
  - run3 演练 `PIN_SHA=d457567332aa6989e753ea289f30ea2bfbc80bc0`（0.15.28），`REPORTS=` 空本地目录，新路径：`ERR 取不到 plugin.json 版本 pinned=d457567…(0.15.28) main=88d4751…(?)` rc=2。**没解释清楚**：紧接着手动 curl 新路径在 88d4751 返回 HTTP 200，内容里有 `"version": "0.15.29"`。估计是那一次 curl 偶发失败（超时或限流），没有重跑确认。
  - run4 回退（MANIFEST 改回 `.claude-plugin/plugin.json`，同参数）：`NEW pinned=d457567…(0.15.28) main=88d4751…(0.15.29) ahead ahead_by=4 pstack_files=8 report=…/pstack-0.15.29-compat-REPORT.md（没有或还没写总判定）` rc=1。
- HTTP 核对：d457567、88d4751、182f2ce 三个 commit 上，`harness/pstack/claude-code/plugin.json` 和 `.claude-plugin/plugin.json` 都是 200，两个文件的版本号一样（0.15.28 / 0.15.29）。所以回退不挂：两个文件当前都在。

## 下一步（MBA）
1. 先看 `uptime`，load1 > 20 就等（最多 20 分钟）。
2. 把第 1 步脚本重新抽出来（`awk 'NR>=31 && /^```bash/{f=1;next} f&&/^```/{exit} f' docs/pstack-monitor/DESIGN.md > step1.sh`），用 run3 的参数在新路径上再跑一次（同一步最多试 2 次，run3 算第 1 次）。期望 `NEW … (0.15.28) … (0.15.29)` rc=1。如果还是 ERR，就查 `ver 88d4751`：可能是 curl、raw.githubusercontent 或 python3 的问题。
3. 回退证明「旧路径缺失时报 ERR、新路径能取到」：用一个不存在的路径（或本地假目录、假 commit）验证 curl -f 失败时走 `ERR 取不到 plugin.json 版本` 并 exit 2。比如 MANIFEST 改成 `harness/pstack/claude-code/.claude-plugin/nope.json` 跑一次。
4. gitleaks（git 模式，`origin/main..15f14b1`）；`git merge-tree --write-tree` 分别对 origin/main 和 origin/zhongc1211/ops-PER-89-deny 核冲突。
5. 交付：PR #55 评论写五项硬标准和「为什么安全」，head 写 15f14b1（DESIGN.md 内容的 head；分支 head 是本交接提交，评论里说明）；在 box `/workspace/ops/reports/parallel-1020/PER-94-RESULT.md` 末尾那节补上第 1 步输出，并按 ops 系统要求补一句「远端已是 15f14b1，ops 系统确认为重启后的保底推送」（这句还没补）；`orca linear` 给 PER-94 评论；工作区改 in-review。

## 没跑完的测试
- 新路径的第 1 步取到两边版本号：没跑通（run3 ERR，原因没查清）。
- 旧路径缺失时报 ERR 的证明：没跑。
- gitleaks：没跑。
- merge-tree（origin/main、ops-PER-89-deny）：没跑。

## 没做
PR 评论、Linear 评论、工作区改 in-review：都没做。RESULT 只写了开头核对那节（23:34），还没补后续。
