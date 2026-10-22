# S14.MBA.crash 崩溃报告数的说明

这个文件是演练跑完以后手写的，不在 `SHA256SUMS` 里。

这次演练 66 项都过了。S14.MBA.crash 的「实际」里记的「DiagnosticReports 里 lockf 开头的文件：发信号前 0 个，之后 0 个」，
数的只是 MBA 的 `~/Library/Logs/DiagnosticReports/`。这个数只记不判，不影响这一项的结果，但它和 `README.md` 里
「crash 让 macOS 给 lockf 写一份崩溃报告（`~/Library/Logs/DiagnosticReports/lockf-<日期>-<时间>.ips`）」对 MBA 都不对。

- 演练跑完以后（2026-10-22 02:38 SGT），在 MBA 上只读 `ls` 了两个目录：
  - `~/Library/Logs/DiagnosticReports/`：没有 lockf 开头的文件。
  - `/Library/Logs/DiagnosticReports/`：有 `lockf-2026-10-22-023527.ips`（属主 root，6227 字节，02:35:27 写的）。
    这次 S14.MBA.crash 发 SIGSEGV 是在 02:35:26 前后（`raw/mba/S14/crash.*`），MBA 上之前没跑过 crash。
- iMac 这次的那份在 `~/Library/Logs/DiagnosticReports/lockf-2026-10-22-023136.ips`，演练记的「发信号前 2 个，之后 3 个」是对的；
  iMac 的 `/Library/Logs/DiagnosticReports/` 里没有 lockf 开头的文件。
- 两台为什么写在不同的地方，没查（`automations/heartbeat-1021/FAILURE-MODES.md` F37）。

之后演练改成两个目录都数、分开记，在新 commit 上重跑了演练和回退测试，见 PR 描述「全部运行」。
这次没跑回退测试：跑之前查到了这件事，先改了演练。
