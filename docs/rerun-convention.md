# `reports/<PR>/rerun.sh` 怎么写、怎么跑

一条命令重跑某个 PR 的 E2E 或演练，结果用固定格式交出来。模板是 `scripts/rerun-template.sh`。

## 目录和文件名

- 脚本：`reports/<PR 号>/rerun.sh`，可执行（git 里是 `100755`）。
- 产物：`${RERUN_OUT:-$HOME/.orca-state/e2e/pr<PR 号>-<HEAD 前 12 位>}/results.tsv`。
  `RERUN_OUT` 给相对路径时按启动目录算。
- 从哪个目录启动都行：脚本用自己的路径找到仓库根，再 `cd` 过去。

## 为什么产物放仓库外

产物写进仓库就会多出文件，要提交就会生成新的 head。PR 描述里 E2E 块写的 sha 就不再等于 PR 的 head，复跑结果对不上。所以脚本只读仓库，产物写到 `~/.orca-state/e2e/` 下。临时文件放脚本里的 `$WORK`（`mktemp -d`，收尾时删掉）；沙箱 `HOME` 写成单条命令前的赋值 `HOME="$WORK/home" <命令>`，只对这一条命令生效，调用方的 `HOME` 不变。

## `results.tsv`

第一行是表头 `case<TAB>status<TAB>detail`，之后一行一个用例。`status` 是 `PASS` 或 `FAIL`。名字和说明里的 TAB、换行由 `case_pass` / `case_fail` 换成空格。每次运行都会重写这个文件，不会留上一次的行。

## 退出码

| 退出码 | 含义 |
|---|---|
| 0 | 全部 PASS，且用例数 > 0 |
| 1 | 有 FAIL |
| 3 | 用例数 = 0 |
| 2 | `PR_NUMBER` 还是占位、找不到仓库根或仓库还没有提交（不写产物） |

## 最后一行

```
RERUN pr=<PR 号> head=<git rev-parse HEAD 的 40 位> pass=<PASS 数> total=<用例数>
```

它之后不再有任何输出。

## 从模板起步

```bash
mkdir -p reports/<N>
cp scripts/rerun-template.sh reports/<N>/rerun.sh
```

然后：

1. 把顶部 `PR_NUMBER=__PR_NUMBER__` 改成 PR 号。
2. 删掉 `# ==== 在这里写你的 E2E 步骤 ↓ ====` 和 `↑` 之间的示例，写自己的用例：跑真实命令，看结果，调 `case_pass <名字> [说明]` 或 `case_fail <名字> [说明]`。
3. 命令失败时记 `case_fail`，脚本继续往下跑；收尾段统一算数、打印最后一行、退出。步骤段落里如果 `exit`，就没有最后一行。
4. 用 `/bin/bash` 跑（macOS 自带 bash 3.2）。变量后面紧跟中文或全角标点时要写成 `${x}`，否则 bash 3.2 会把这些字节读进变量名。

## 最小例子

步骤段落：

```bash
L="$WORK/heavy.lock"
if HEAVY_LOCK_DIR="$L" scripts/heavy-lock.sh acquire demo > /dev/null && [ -d "$L" ]; then
  case_pass lock_acquire "拿到锁，锁目录已建"
else
  case_fail lock_acquire "acquire 失败或没建锁目录"
fi
```

运行和输出：

```
$ cd /tmp && ~/orca/workspaces/ops/<工作区>/reports/<N>/rerun.sh
PASS lock_acquire — 拿到锁，锁目录已建
产物: /Users/<you>/.orca-state/e2e/pr<N>-<head 前 12 位>/results.tsv
RERUN pr=<N> head=<40 位 sha> pass=1 total=1
$ echo $?
0
```
