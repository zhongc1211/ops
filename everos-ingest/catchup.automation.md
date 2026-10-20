# 可选 Orca automation「EverOS 采集补推」（PER-67，2026-10-20，**没建**，要建需 Zack 批）

每天的采集 automation 已经在每次运行时补推最近 3 天（见 README「推送失败后补推」）。这个 automation 只是把
「box 恢复 → 补推」的间隔从最长约 1 天缩到约 2 小时。不采集，只推本机已有的清单。

## 参数（MBA；iMac 同样一份，把 mba 换成 imac）

| 字段 | 值 |
|---|---|
| 名字 | ops · EverOS 采集补推 MBA |
| 主机 / 工作区 | MBA 本机 ops 工作区（和 `5a9491fe` 相同：`workspaceMode=existing`，`/Users/jiawenwang/orca/workspaces/ops`） |
| agent | claude（不会启动；precheck 总是非 0） |
| 时区 | Asia/Singapore |
| 计划 | 每 2 小时，`rrule` = `30 1-23/2 * * *`（01:30 … 23:30；和 21:50、00:01、00:02、00:16 的采集错开，避免两个进程同时推同一天） |
| missedRunPolicy | 跳过（下一次 2 小时后再来） |
| precheck 超时 | 600s |
| prompt | `本任务的全部工作由预检脚本完成，预检脚本永远以非 0 退出，所以模型不应被启动。若你被启动了：什么都不要做，只回复一句「不应启动」。` |
| reuseSession | false |

## precheck

```bash
bash -c 'B=$HOME/.orca-state/bin/everos-ingest
ssh -o ConnectTimeout=20 -o BatchMode=yes box true || { echo "box unreachable; next run retries" >&2; exit 2; }
rc=1
for a in "collect-mba.sh" "collect-mba-deepvision-site.sh" "collect-mba-repo.sh deepvision-ads" "collect-mba-repo.sh vllm-omni"; do
  CATCHUP_ONLY=1 PUSH_BUDGET=120 CATCHUP_BUDGET=120 bash $B/$a; r=$?
  [ "$r" = 1 ] || rc=$r
done
exit $rc'
```

- 先探一次 box：不通就直接退出 2，不让四个脚本各自重试约 5 分钟（四个加起来会超过 600s）。
- 每个脚本给 120 秒：大转写（官网/广告/vllm）推不完时分块留在 box 的 `mba.resume/`，下一次接着推。
- 全部成功（或没东西要补）退出 1，不启动模型；有失败就退出那个非 1 的码，在 precheckResult 里看得到。
