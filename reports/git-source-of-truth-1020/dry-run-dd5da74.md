# sync-bot-rules 干跑（--check，只读）：commit dd5da74ea0a75e3f3a2465e69b6e21c11f60907b

跑的人：PER-106 工作区的 Claude Code，2026-10-20 20:42–20:46 SGT。
跑法：`git bundle` 打包 PR 分支，拷到 box、MBA 的 `mktemp -d` 临时目录，clone 出 dd5da74 后运行
`bash scripts/sync-bot-rules --check --repo <临时 clone> --ref dd5da74… --no-fetch`，同一处再跑一遍 `scripts/tests/sync-bot-rules-test.sh`。
跑完删掉临时目录（`ls -d` 确认不存在）。iMac 直接在工作区跑。没有对任何真实目标跑 `--apply`。
用 `--ref dd5da74` 而不是默认的 `origin/main`：main 上还没有 `docs/bot-rules/targets.tsv`（见 iMac 一节最后一项，合并前退出 2 是预期结果）。

## 结果

| 机器 | 目标路径 | 源 sha256（dd5da74） | 目标 sha256 | 状态 |
|---|---|---|---|---|
| box | /home/box/agent-data/workflows/dev-bot-rules/SKILL.md | f12040ef8f94fa99e921480257a07ca245fbc261a0b91758e2ec9a06d271e9ae | f12040ef8f94fa99e921480257a07ca245fbc261a0b91758e2ec9a06d271e9ae | same |
| iMac | — | — | — | 本机在 targets.tsv 里没有目标（退出 0） |
| MBA | — | — | — | 本机在 targets.tsv 里没有目标（退出 0） |

box 是 same：仓库里的 SKILL.md（来自暂存树，按 stage-sha256.txt 核对过）和 box 现在的文件一致，19:52 之后没有再改。
box 目标目录里的 8 个 `SKILL.md.bak-*` 按设计不算 extra。

box 目标目录前后对比：跑之前和跑之后各记一次 `find -exec stat -c '%n %Y %s'` + `sha256sum *`，两次逐字节相同（`cmp` 无差异），9 个文件的修改时间、大小、sha256 都没变。

## box 原始输出

```
## host: grok-bot-vm-418519647  uname: Linux 6.12.94+  bash: 5.2.37(1)-release
## test
ok   1 same: exit 0
ok   2 same: two files reported same, sha256 shown
ok   3 same: *.bak* in target is not reported as extra
ok   4 no file content printed
ok   5 drift/missing/extra: exit 1
ok   6 drift reported
ok   7 missing reported
ok   8 extra reported
ok   9 --check writes nothing (find + sha256 of repo and targets before/after)
ok   10 --check is the default mode
ok   11 --apply with extra left: exit 1, extra kept
ok   12 --apply: drifted file backed up with old content
ok   13 --apply: SKILL.md and appendix/A.md now match git
ok   14 --apply: sha256 printed after write
ok   15 --apply second run: exit 0, 0 writes, tree unchanged
ok   16 target dir missing (--check): exit 2, dir not created
ok   17 target dir missing (--apply): exit 2, dir not created
ok   18 bad ref: exit 2
ok   19 host matches no row: exit 0, says no targets
19/19 passed
test rc=0
## check
# sync-bot-rules --check  ref=dd5da74ea0a75e3f3a2465e69b6e21c11f60907b  commit=dd5da74ea0a75e3f3a2465e69b6e21c11f60907b  host=grok-bot-vm-418519647
机器 | 目标路径 | 源 sha256 | 目标 sha256 | 状态
box | /home/box/agent-data/workflows/dev-bot-rules/SKILL.md | f12040ef8f94fa99e921480257a07ca245fbc261a0b91758e2ec9a06d271e9ae | f12040ef8f94fa99e921480257a07ca245fbc261a0b91758e2ec9a06d271e9ae | same
check rc=0
```

## MBA 原始输出（测试逐条结果略，19 条全 ok）

```
## host: mba  uname: Darwin 25.6.0  bash: 3.2.57(1)-release
## test
19/19 passed
test rc=0
## check
# sync-bot-rules --check  ref=dd5da74ea0a75e3f3a2465e69b6e21c11f60907b  commit=dd5da74ea0a75e3f3a2465e69b6e21c11f60907b  host=mba
机器 | 目标路径 | 源 sha256 | 目标 sha256 | 状态
# 本机（mba）在 docs/bot-rules/targets.tsv 里没有目标
check rc=0
```

## iMac 原始输出

```
## host: iMac  uname: Darwin 25.6.0  bash: 3.2.57(1)-release
## check
# sync-bot-rules --check  ref=dd5da74ea0a75e3f3a2465e69b6e21c11f60907b  commit=dd5da74ea0a75e3f3a2465e69b6e21c11f60907b  host=iMac
机器 | 目标路径 | 源 sha256 | 目标 sha256 | 状态
# 本机（iMac）在 docs/bot-rules/targets.tsv 里没有目标
check rc=0
## check --ref origin/main（合并前）
sync-bot-rules: docs/bot-rules/targets.tsv not found at origin/main (b28b7a56107352d685c3221af0aff28c30fbe376)
check rc=2
```
