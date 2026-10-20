# sync-bot-rules --check（只读）结果，2026-10-21 00:02 SGT

每台都在本分支的全新克隆里跑（box：/workspace/repos/ops-1021；MBA、iMac：`ssh <机器>` 后在 /tmp/ops-bot-rules-targets-1021 克隆），命令：

```
scripts/sync-bot-rules --check --ref origin/zhongc1211/ops-bot-rules-targets-1021
```

跑在 commit d4f0bb0c7be86599079ddf30a2386cf35d65c3b1 上，没跑 --apply。

- check-box.txt：box，same，exit 0
- check-mba.txt：MBA，SKILL.md drift（MBA 是 #67 合并前的旧版），SOURCE.txt / SHA256SUMS.txt extra，exit 1
- check-imac.txt：iMac，没有目标，exit 0

说明：--check 在 d4f0bb0 上跑；d4f0bb0 之后只新增了本目录的报告文件（README.md、check-*.txt），targets.tsv、SYNC.md 和脚本都没改，结果对当前 head 同样成立。
