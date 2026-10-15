# 心月网站：夜审总表

每晚的夜审复盘当天的 commit、PR 和 Linear 评论，只找三类问题：修完又返工的、不该合的、验证太糙的；做对的也记。每条规则一个文件，在 `docs/solutions/lessons/`。同一条规则再次出现时只加次数和日期，不新建条目。

「Seen」里的日期是夜审记到这条规则的日子（SGT）。一条规则在 3 个不同日子出现时升级，通知派活 bot。

## 规则

| 规则                                                                                                              | 类别       | Seen             | 文件                                                                                                                        |
| ----------------------------------------------------------------------------------------------------------------- | ---------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------- |
| 准备上生产的改动，每个 PR 以 `feat/xinyue-site` 为 base、一款游戏一个 PR，不叠在别的未合并 PR 或 testing 分支上。 | 修完又返工 | 1×（2026-10-13） | [cut-production-prs-from-the-production-base](lessons/cut-production-prs-from-the-production-base.md)                       |
| 一条用例的正常耗时接近它的时限时，当天就调时限或缩短用例，并提交进仓库。                                          | 修完又返工 | 1×（2026-10-13） | [fix-a-test-that-runs-at-its-time-limit](lessons/fix-a-test-that-runs-at-its-time-limit.md)                                 |
| 合并前等 CI 的四个 check 在 PR 的 head 上出结果；改了哪个模块，就确认对应的 Playwright spec 跑过。                | 不该合的   | 1×（2026-10-13） | [run-browser-tests-on-the-pr-head-before-merging](lessons/run-browser-tests-on-the-pr-head-before-merging.md)               |
| 标了「待定」「待 Zack 定」「还没批准」的事，合并或上线前把谁在什么时候怎么定的写进同一个 PR 或 issue。            | 不该合的   | 1×（2026-10-13） | [record-who-decided-before-shipping-an-open-question](lessons/record-who-decided-before-shipping-an-open-question.md)       |
| 生产新版本先只上传、不接流量，核对 secret 和绑定与线上版本一致，再切流量。                                        | 验证太糙   | 1×（2026-10-13） | [check-bindings-before-shifting-production-traffic](lessons/check-bindings-before-shifting-production-traffic.md)           |
| 跑 `cf-deploy.sh --check-only` 之前记下当前版本号，跑完核对版本没有变；没核对过就当它会上线。                     | 验证太糙   | 1×（2026-10-13） | [treat-check-only-as-a-real-deploy](lessons/treat-check-only-as-a-real-deploy.md)                                           |
| 把失败归为「与本次改动无关」时，写出用例名和在 base 上重跑的结果；同一批失败第二次出现就开单查。                  | 验证太糙   | 1×（2026-10-13） | [name-and-rerun-failures-called-unrelated](lessons/name-and-rerun-failures-called-unrelated.md)                             |
| 任务写了真机目标时，上生产前要么有真机结果，要么写明谁接受了没有真机结果就上。                                    | 验证太糙   | 1×（2026-10-13） | [get-a-real-phone-result-before-shipping-a-phone-target](lessons/get-a-real-phone-result-before-shipping-a-phone-target.md) |
| PR 正文引用的验证结果，发 PR 时就要在；CI 出红后写明是哪条用例、与改动有没有关系。                                | 验证太糙   | 1×（2026-10-13） | [post-the-evidence-a-pr-body-points-to](lessons/post-the-evidence-a-pr-body-points-to.md)                                   |

## Done right

不属于某一条规则、但值得照做的做法。

| 日期       | 做法                                                                                              | 出处                                             |
| ---------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| 2026-10-13 | 验证记录固定五节：回退测试（改动前后各一次 CI）、真实使用证据、跑在哪个提交、回滚方式、没跑的。   | #74 的验证评论                                   |
| 2026-10-13 | 上线评论单列「没有验证的」：没有用真实口令登录、没有实际调用模型、没有在真实手机上试玩。          | #61–#67、#73 的上线评论，Linear PER-37 到 PER-43 |
| 2026-10-13 | 上线评论里给出可以直接执行的回滚命令和回滚版本号。                                                | 同上；PER-28 的上线评论                          |
| 2026-10-13 | 修复前先确认新用例会失败：新增用例和原有的 403 用例在修复前都失败，修复后通过。                   | #66、#72                                         |
| 2026-10-13 | 改了一条用例的前提时，在 PR 正文里单独说明原来测什么、现在测什么、为什么。                        | #72「一个用例改了前提」                          |
| 2026-10-13 | 没有在 testing 上制造真实故障时，写明「这句话的显示没有实际触发过」，不把部署成功写成功能验证过。 | #66                                              |

## 夜审记录

| 日期       | 新增规则 | 加次数的规则 | 读不到的来源                                                       |
| ---------- | -------- | ------------ | ------------------------------------------------------------------ |
| 2026-10-13 | 9        | 0            | box 的 `/workspace/xinyue-web/status.md`（这台机器上没有这个路径） |
