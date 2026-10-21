# R6 桩测试（假 orca / 假 gh，测试替身，不算 E2E）

命令：`WS_TEST_BASH=<bash> <bash> scripts/tests/ws-cleanup-test.sh`，iMac，2026-10-21 11:3x SGT。旧代码对照加 `WS_CLEANUP=<06f9cc8 的 ws-cleanup.sh>`。

| 被测脚本 | bash | 结果 | 输出 |
|---|---|---|---|
| 9ce6a53（blob b9c46ae） | 3.2.57 | 213/213 通过 | `bash3.2.txt` |
| 9ce6a53（blob b9c46ae） | 5.3 | 213/213 通过 | `bash5.3.txt` |
| 06f9cc8（R5 的代码，blob fc796d6） | 3.2.57 | 198/213，15 个失败 | `old-06f9cc8-bash3.2.txt` |

旧代码上失败的 15 个：
- S1–S6、S8：备份后不复查；
- S10：100 条不当作截断；
- S12：锁目录里有别的文件照样删；
- T1（2 个检查）、T2：合进 staging 的 PR 算合并；
- P7、P9、P10：结论一样（SKIP W17），只是 W17 的原因文字换了。

T4（合进 main 的 PR 照样放行）在旧代码上也过，这是对的。
