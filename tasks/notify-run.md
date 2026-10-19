任务：notify-run 脚本（Zack 已批，派活 bot = deepvision-ops）。按 compound-engineering 做。

1. 写 bash 脚本 notify-run，装到 iMac ~/.local/bin/notify-run 和 box /home/box/.local/bin/notify-run（chmod 755）。
   用法：notify-run --bot <bot> --task "<描述>" [--issue X] -- <命令...>
   - 运行命令，输出同时 tee 到临时日志；记开始时间。
   - trap EXIT/INT/TERM：不管成功、失败、被 kill，都 source 对应 env（iMac ~/.config/grokbot/webhooks/<bot>.env；box /home/box/.config/grokbot/webhooks/<bot>.env；按 $HOME 或存在性判断），用 curl POST $URL，头 Authorization: Bearer $KEY、Content-Type: application/json。
   - JSON 字段：bot, task, issue, machine(hostname), exit_code, status(done=0 / failed=非0 / killed=收到信号), log_tail(日志最后约 20 行), duration_s。用 jq 或 python 正确转义。
   - 被 kill 时要先把信号转给子进程再发 webhook，只发一次。
   - 密钥只从 env 文件读，绝不出现在命令行参数（curl 头用 -H @- 或 --config 从 stdin 读）、日志或输出里。
   - 脚本原样返回命令的退出码（被信号杀时返回 128+信号）。
2. 测试（iMac 和 box 各三条，bot=test）：没有 test.env 就 cp deepvision-ops.env test.env（chmod 600）。分别跑 `true`、`false`、`sleep 300` 然后 kill。再在 iMac 用 --bot vllm-omni 跑一条 `true`，task 写「notify-run 连通测试，忽略」。共 7 条。记录每条 exit_code、status、curl 是否 2xx。
   - box 负载高（约 38），box 上只跑这几条轻命令，不跑别的。若 iMac 这里够不到 box，就在结果里说明，不要硬来。
3. 完成后（或卡住时）发一次 webhook 叫醒我：source ~/.config/grokbot/webhooks/deepvision-ops.env && curl -fsS -X POST "$URL" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"bot":"deepvision-ops","task":"notify-run","worktree":"<路径>","status":"done|stuck","note":"<脚本路径 + 7 条结果表：机器/bot/命令/exit_code/status/HTTP 码>"}'
   同时把结果表写进工作区 RESULT.md。不要把密钥写进任何文件或输出。
