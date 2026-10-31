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
- sha: ffffeeeeddddccccbbbbaaaa9999888877776666
- 命令: `reports/7/rerun.sh`
- 结果: 2/2 通过
- 产物: `artifact`
