构造的 PR 描述（演练用，PR 号 7）。

## 做了什么
改了一个脚本。

## 为什么安全
只读，不改现网。

## 回滚
`git revert` 这个提交。

## 没跑的
无

## E2E（PR head）
- sha: a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
- 命令: `reports/7/rerun.sh`
- 结果: 2/2 通过
- 产物: `mba:~/.orca-state/e2e/pr-gate-drill-does-not-exist`
