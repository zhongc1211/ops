# ops-system webhook（PER-90）

## check-bot-webhooks 要分辨的情况（先写，后写脚本）

1. 某 bot 在 enabled-bots 里，但没有 `<bot>.env`：叫醒发不出去，报「缺 env」。
2. `<bot>.env` 存在但不可读：notify-run 退到 /home/box 路径、orca-wake 跳过，报「不可读」。
3. 权限不是 600：报「权限」。
4. 缺 `URL=` 或 `KEY=`，或值为空：三个读取方都当没配置，报「缺 URL / 缺 KEY」。
5. 同一个变量写了多行：不同读取方取的值可能不同（source 取最后一行），报「重复」。
6. 有 env 但不在 enabled-bots 里：orca-wake 只写影子日志不发，报「影子」（提示，不算错）。
7. enabled-bots 文件不存在：所有 bot 都是影子，报错。
8. enabled-bots 写了 `*`：全部放行，照常逐个查 env。
9. `--require <bot>` 指定的 bot 不在 enabled-bots 或没有 env：报错。
10. 脚本自己不能泄露：不输出值、不输出 sha、不发网络请求。
