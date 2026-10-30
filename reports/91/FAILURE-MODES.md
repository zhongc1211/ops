# scripts/pr-gate：失败方式清单（先写清单，再写代码）

写于 2026-10-30，`scripts/pr-gate` 还只是骨架（退出 2）的时候。每一条对应 `rerun.sh` 里的一个用例。
修前 = 骨架提交上的 `scripts/pr-gate`；修后 = 本分支 head。每条演练断言在骨架上先挂一次，原始输出留在产物里。

## A. gate 要拦住的（构造输入，演练）

| # | 失败方式 | 用例 | 修后期望 |
|---|---|---|---|
| A1 | 描述里的 sha 不是 PR head，旧 head 上的 E2E 被当成新 head 的 | `sha_mismatch` | 只有 E2E_SHA FAIL，打印两边前 12 位 |
| A2 | 描述没有「E2E（PR head）」块 | `no_e2e_block` | E2E_SHA FAIL；产物写在块里，块没了 ARTIFACT 也 FAIL（两项，不放宽解析） |
| A3 | 产物路径写了但不存在 | `artifact_missing` | 只有 ARTIFACT FAIL |
| A4 | 产物在，但 results.tsv 一个用例都没有 | `artifact_zero` | 只有 ARTIFACT FAIL |
| A5 | 缺「为什么安全」 | `no_why_safe` | 只有 FIELDS FAIL，列出缺的那个 |
| A6 | 缺「回滚」 | `no_rollback` | 同上 |
| A7 | 缺「没跑的」 | `no_notrun` | 同上 |
| A8 | 描述里有 Co-Authored-By 行 | `body_coauthor` | 只有 NO_AI_ATTRIBUTION FAIL，打印行号 |
| A9 | 描述里有「执行：」后跟工具名的行 | `body_exec_tool` | 同上 |
| A10 | 提交信息带 Co-Authored-By trailer | `commit_trailer` | 只有 NO_COAUTHOR FAIL，注明提交前 12 位 |
| A11 | 没有 `reports/<N>/rerun.sh` | `rerun_missing` | 只有 RERUN FAIL，写「不存在」 |
| A12 | rerun.sh 不可执行（100644） | `rerun_not_exec` | 只有 RERUN FAIL，写「不可执行」 |
| A13 | `--run`：rerun.sh 退出 1 | `run_exit1` | 只有 RERUN FAIL |
| A14 | `--run`：total=0 | `run_total0` | 只有 RERUN FAIL |
| A15 | `--run`：RERUN 行的 head 不是 PR head | `run_head_mismatch` | 只有 RERUN FAIL |
| A16 | 「Claude/Codex」这种斜杠连着的工具名漏掉（评审后补，第一版边界把 `/` 当成路径） | `body_slash_tools` | 只有 NO_AI_ATTRIBUTION FAIL |

各用例可带 `want_text`：输出里必须出现的原因文字。`run_*` 四个都要求出现「跑了 rerun.sh」，这样没真跑的 gate 过不了 `run_pass`。

## B. gate 不该拦的（构造输入，演练）

| # | 风险 | 用例 | 修后期望 |
|---|---|---|---|
| B1 | 一切齐全却报 FAIL | `all_pass` | 六项 PASS，退出 0 |
| B2 | 文件名 `CLAUDE.md`、`~/.claude/…`、`.claude/skills/` 被当成署名 | `filename_not_attribution` | 六项 PASS |
| B3 | `--run` 正常的 rerun.sh 被判 FAIL | `run_pass` | 六项 PASS |
| B4 | `run-e2e.sh` 写的 results.tsv（没表头、5 列）被算成 0 用例 | `artifact_run_e2e_format` | 六项 PASS |
| B5 | 本机绝对路径的产物没被认出 | `artifact_abs_path` | 六项 PASS |
| B6 | `mba:` 路径：真 ssh 只读，存在的认、不存在的拦 | `artifact_mba_ok`、`artifact_mba_missing` | 前者六项 PASS；后者只有 ARTIFACT FAIL |
| B7 | 用法错（没 PR 号、离线参数不全）被当成通过 | `usage_no_pr`、`usage_partial_offline` | 退出 2，不打 RESULT: PASS |

## C. 真 PR（E2E）

对 `zhongc1211/ops` 的 #90、#71、#75、#88、#89 各跑一次（不带 `--run`）。断言只写：退出码 0 或 1、六项都有 PASS/FAIL 输出、有 RESULT 行。
各项的实际结果记在 results.tsv 的 detail 列。

| # | 风险 | 处理 |
|---|---|---|
| C1 | gh 读不到 PR、网络断了却打成 PASS | 退出 2，不打 RESULT 行；真 PR 用例会因退出码不是 0/1 而 FAIL |
| C2 | 真 PR 描述以后被改，断言就失效 | 真 PR 用例不断言具体 PASS/FAIL |

## D. 演练本身可能骗人的地方

- 构造输入的用例不连 gh：描述、提交、文件树都是 `fixtures/` 里的文件，PR 号用 7，head 是假 sha。这部分叫演练，不叫 E2E。
- `artifact_mba_*` 读的是 MBA 上真实存在的旧产物目录（`~/.orca-state/e2e/migration-1020/f3fb2bc-2109/post`），目录被清掉后 `artifact_mba_ok` 会 FAIL。
- `--run` 的 4 个演练用例跑的是 fixtures 里的假 rerun.sh，不是真 PR 的；对真 PR 的 `--run` 只在本 PR 自己身上跑一次（gate_on_self），不在 rerun.sh 里（会自己调自己）。
