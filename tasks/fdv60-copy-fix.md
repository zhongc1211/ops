# FDV-60 营销审稿结论（15:28）：改完即可上 testing
1. 英文行名 "AI sales assistant runs on" 改为 "AI sales assistant platform"；其余英文/中文措辞不动。
2. 中文行名用「AI 销售助手所在平台」，不用「渠道」。
3. WhatsApp logo 旁不再写文字，img alt="WhatsApp"。浅色底不能用白色横版，换官方包里的深色或绿色横版，原样不改。
然后：push 到 staging（经 PR，SSH 推），等 Workers Build 部署 testing，在真实 testing URL 用真实浏览器跑诚实 e2e（按 Zack 15:23 规则：不 mock、不跳步、不放宽断言、不挑重跑，最后产出可验证可复现的 artifact：截图 + 命令 + commit + 结果）。中英文桌面/手机截图都要。生产不动。
完成发 done webhook，note 写 testing URL、commit、e2e 结果、截图路径；失败照实报 stuck。
