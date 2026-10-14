#!/bin/bash
# Monday SEO/GEO precheck: cheap fetch of robots/sitemap/llms.txt into ~/deepvision/seo-geo/<date>/; always lets agent run (weekly).
O=$HOME/deepvision/seo-geo/$(TZ=Asia/Singapore date +%F); mkdir -p $O
for u in robots.txt sitemap.xml llms.txt; do curl -fsS -m 30 -o $O/$u https://deepvision.sg/$u || echo "fetch fail $u" >> $O/precheck.log; done
curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' https://deepvision.sg/ >> $O/precheck.log; exit 0
