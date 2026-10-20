# GEOM — 2026-10-18T16:37:13.413Z

- command: node scripts/ryze-geom/run.mjs --mode geom --font-normalize --twice --ours http://localhost:4318 --pages home,pricing --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/baseline-3e050d2-font/geom
- ours: http://localhost:4318 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: any block's x, y, width, height, heading font size / line height, or a gap off by more than 2% fails. x and width are divided by the viewport width, y and gaps by Ryze's page height, height / font / line height by Ryze's value. Exempt only what exempt.json lists.
- fonts: one font, every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4318/_next/static/media/e4af272ccee01ff0-s.p.woff2)

| page | width | mode | result | detail |
|---|---|---|---|---|
| home | 1440 | geom | FAIL | 14 failing rows of 30 |
| home | 390 | geom | FAIL | 17 failing rows of 29 |
| pricing | 1440 | geom | FAIL | 13 failing rows of 22 |
| pricing | 390 | geom | FAIL | 12 failing rows of 22 |

### home @ 1440 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4318/en

Page height: Ryze 8735, ours 9649 (10.46%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (DIFF #0) | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — Hero (DIFF #1) | 0 / 0 / 1440 / 900 · 69.1 / 74.6 | 0 / 0 / 1440 / 900 · 69 / 74.5 | 0.17% (lineHeight) | PASS |  |
| hero.cta — Hero email form / our buttons (DIFF #1a) | 55 / 574.1 / 373 / 49 · — / — | 68 / 680.9 / 495.5 / 48 · — / — | 8.51% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| strip — Press strip / platform strip (DIFF #2) | 0 / 900 / 1440 / 93.8 · — / — | 0 / 900 / 1440 / 94 · — / — | 0.21% (h) | PASS |  |
| twocol — All platforms + AI search, two columns (DIFF #3) | 0 / 993.8 / 1440 / 447.6 · 34 / 38.1 | 0 / 994 / 1440 / 661.5 · 36 / 45 | 47.79% (h) | FAIL | over 2%: h, font, lineHeight |
| wall — Wall of Love / monthly output wall (DIFF #4) | 0 / 1441.3 / 1440 / 1028 · 56 / 62.2 | 0 / 1655.5 / 1440 / 1627.6 · 48 / 57.6 | 58.33% (h) | FAIL | over 2%: y, h, font, lineHeight |
| logos — Customer logo wall (DIFF #5) | 0 / 2469.3 / 1440 / 624.5 · 38 / 47.5 | — | — | FAIL | Ryze has it; we have no such block |
| cards5 — Five demo cards (DIFF #6) | 0 / 3093.8 / 1440 / 750.9 · 44 / 66 | 0 / 3283.1 / 1440 / 798.5 · 48 / 57.6 | 12.73% (lineHeight) | FAIL | over 2%: y, h, font, lineHeight |
| scan — Free scan / how we start (DIFF #7) | 0 / 3844.7 / 1440 / 497 · 42 / 52.5 | 0 / 4081.6 / 1440 / 499.6 · 48 / 57.6 | 14.29% (font) | FAIL | over 2%: y, font, lineHeight |
| scan.cta — Scan email form / our button (DIFF #7) | 654.8 / 4177.7 / 576 / 52 · — / — | 626.4 / 4421.2 / 175.6 / 48 · — / — | 27.81% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| three — Three products (DIFF #8) | 0 / 4341.7 / 1440 / 647 · 36 / 45 | 0 / 4581.2 / 1440 / 955 · 36 / 45 | 47.60% (h) | FAIL | over 2%: y, h |
| why — Why bento (DIFF #9) | 0 / 4988.7 / 1440 / 647.5 · 48 / 72 | 0 / 5536.2 / 1440 / 712.8 · 48 / 57.6 | 20.00% (lineHeight) | FAIL | over 2%: y, h, lineHeight |
| list — Everything list (DIFF #10) | 0 / 5636.2 / 1440 / 760 · 48 / 60 | 0 / 6249 / 1440 / 801.4 · 48 / 57.6 | 7.02% (y) | FAIL | over 2%: y, h, lineHeight |
| agency — Agency / AI sales assistant (DIFF #11) | 0 / 6396.2 / 1440 / 558.5 · 42 / 52.5 | 0 / 7050.5 / 1440 / 649 · 48 / 55.2 | 16.20% (h) | FAIL | over 2%: y, h, font, lineHeight |
| faq — FAQ (DIFF #12) | 0 / 6954.7 / 1440 / 839 · 40 / 60 | 0 / 7699.5 / 1440 / 890.7 · 48 / 57.6 | 20.00% (font) | FAIL | over 2%: y, h, font, lineHeight |
| footer — Footer (DIFF #13) | 0 / 7793.7 / 1440 / 941 · 38 / 34.2 | 0 / 8590.2 / 1440 / 1058.7 · 36 / 40.3 | 17.89% (lineHeight) | FAIL | over 2%: y, h, font, lineHeight |
| footer.cta — Footer card email form / our button (DIFF #13) | 768 / 8315.2 / 384 / 52 · — / — | 872.2 / 9141.8 / 175.6 / 48 · — / — | 14.47% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo (DIFF #14) | 1049.2 / 798 / 374.8 / 78 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button (DIFF #14) | — | 1368 / 828 / 56 / 56 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → strip | 0 | 0 | 0.0000% | PASS |  |
| strip → twocol | 0 | 0 | 0.0000% | PASS |  |
| twocol → wall | -0.1 | 0 | 0.0011% | PASS |  |
| wall → cards5 | 624.5 | 0 | 7.15% | FAIL | includes logos (on one side only) |
| cards5 → scan | 0 | 0 | 0.0000% | PASS |  |
| scan → three | 0 | 0 | 0.0000% | PASS |  |
| three → why | 0 | 0 | 0.0000% | PASS |  |
| why → list | 0 | 0 | 0.0000% | PASS |  |
| list → agency | 0 | 0.1 | 0.0011% | PASS |  |
| agency → faq | 0 | 0 | 0.0000% | PASS |  |
| faq → footer | 0 | 0 | 0.0000% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### home @ 390 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4318/en

Page height: Ryze 9847, ours 14566 (47.92%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (DIFF #0) | 0 / 0 / 390 / 58.5 · — / — | 0 / 0 / 390 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — Hero (DIFF #1) | 0 / 0 / 390 / 844 · 33.6 / 37.6 | 0 / 0 / 390 / 1106.4 · 34 / 38.1 | 31.09% (h) | FAIL | over 2%: h |
| hero.cta — Hero email form / our buttons (DIFF #1a) | 24 / 326.5 / 342 / 46 · — / — | 24 / 372 / 342 / 90 · — / — | 95.65% (h) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| strip — Press strip / platform strip (DIFF #2) | 0 / 844 / 390 / 72.1 · — / — | 0 / 1106.4 / 390 / 132.4 · — / — | 83.63% (h) | FAIL | over 2%: y, h |
| twocol — All platforms + AI search, two columns (DIFF #3) | 0 / 916.1 / 390 / 554.5 · 24 / 26.9 | 0 / 1238.8 / 390 / 1031.7 · 26 / 32.5 | 86.06% (h) | FAIL | over 2%: y, h, font, lineHeight |
| wall — Wall of Love / monthly output wall (DIFF #4) | 0 / 1470.6 / 390 / 1228.4 · 28 / 42 | 0 / 2270.5 / 390 / 2352 · 28 / 33.6 | 91.47% (h) | FAIL | over 2%: y, h, lineHeight |
| logos — Customer logo wall (DIFF #5) | 0 / 2699 / 390 / 717 · 24 / 30 | — | — | FAIL | Ryze has it; we have no such block |
| cards5 — Five demo cards (DIFF #6) | 0 / 3416 / 390 / 868.8 · 28 / 42 | 0 / 4622.4 / 390 / 1200.7 · 28 / 33.6 | 38.20% (h) | FAIL | over 2%: y, h, lineHeight |
| scan — Free scan / how we start (DIFF #7) | 0 / 4284.7 / 390 / 434 · 28 / 35 | 0 / 5823.1 / 390 / 427.6 · 28 / 33.6 | 15.62% (y) | FAIL | over 2%: y, lineHeight |
| scan.cta — Scan email form / our button (DIFF #7) | 24 / 4590.7 / 342 / 48 · — / — | 24 / 6138.7 / 175.6 / 48 · — / — | 42.67% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| three — Three products (DIFF #8) | 0 / 4718.7 / 390 / 1653.5 · 22 / 27.5 | 0 / 6250.7 / 390 / 1978.6 · 22 / 27.5 | 19.66% (h) | FAIL | over 2%: y, h |
| why — Why bento (DIFF #9) | 0 / 6372.2 / 390 / 957 · 28 / 42 | 0 / 8229.3 / 390 / 1318.6 · 28 / 33.6 | 37.78% (h) | FAIL | over 2%: y, h, lineHeight |
| list — Everything list (DIFF #10) | 0 / 7329.2 / 390 / 955.6 · 28 / 35 | 0 / 9547.9 / 390 / 1373 · 28 / 33.6 | 43.68% (h) | FAIL | over 2%: y, h, lineHeight |
| agency — Agency / AI sales assistant (DIFF #11) | 0 / 8284.9 / 390 / 644.4 · 28 / 35 | 0 / 10920.8 / 390 / 1261.6 · 32 / 36.8 | 95.78% (h) | FAIL | over 2%: y, h, font, lineHeight |
| faq — FAQ (DIFF #12) | — | 0 / 12182.5 / 390 / 930.5 · 28 / 33.6 | — | FAIL | ours shows it; Ryze hides it at this width |
| footer — Footer (DIFF #13) | 0 / 8929.3 / 390 / 917.8 · — / — | 0 / 13112.9 / 390 / 1452.7 · 30 / 33.6 | 100.00% (font) | FAIL | over 2%: y, h, font |
| footer.cta — Footer card email form / our button (DIFF #13) | — | 107.2 / 13377.5 / 175.6 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo (DIFF #14) | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button (DIFF #14) | — | — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → strip | 0 | 0 | 0.0000% | PASS |  |
| strip → twocol | 0 | 0 | 0.0000% | PASS |  |
| twocol → wall | 0 | 0 | 0.0000% | PASS |  |
| wall → cards5 | 717 | -0.1 | 7.28% | FAIL | includes logos (on one side only) |
| cards5 → scan | -0.1 | 0 | 0.0010% | PASS |  |
| scan → three | 0 | 0 | 0.0000% | PASS |  |
| three → why | 0 | 0 | 0.0000% | PASS |  |
| why → list | 0 | 0 | 0.0000% | PASS |  |
| list → agency | 0.1 | -0.1 | 0.0020% | PASS |  |
| agency → footer | 0 | 930.5 | 9.45% | FAIL | includes faq (on one side only) |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### pricing @ 1440 — Ryze https://www.get-ryze.ai/pricing vs ours http://localhost:4318/en/pricing

Page height: Ryze 7184, ours 7248 (0.89%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (DIFF #0) | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — Hero (DIFF #1) | 0 / 0 / 1440 / 740 · 69.1 / 74.6 | 0 / 0 / 1440 / 873.2 · 69 / 74.5 | 18.00% (h) | FAIL | over 2%: h |
| hero.title — Hero H1 (DIFF #1) | 92 / 291.6 / 780 / 149.3 · 69.1 / 74.6 | 60 / 215.2 / 760 / 223.5 · 69 / 74.5 | 49.70% (h) | FAIL | over 2%: x, h |
| hero.grid — Hero 3x3 icon grid (DIFF #1) | 1008 / 180 / 340 / 340 · — / — | 1052 / 168.1 / 328 / 328 · — / — | 3.53% (h) | FAIL | over 2%: x, h |
| plans.billing — Monthly/annual switch (DIFF #1a) | — | 60 / 573.2 / 1320 / 44 · — / — | — | exempt | billing-toggle: Monthly/annual switch is needed by Stripe checkout; Ryze has none. |
| plans.cards — Plan cards (DIFF #2) | 92 / 544 / 1256 / 802.6 · 22 / 27.5 | 60 / 637.2 / 1320 / 696.6 · 22 / 27.5 | 13.21% (h) | exempt | three-tiers: We sell three packages; Ryze shows five cards. |
| plans.annual — Annual note strip (DIFF #3) | 92 / 1362.6 / 1256 / 77.5 · — / — | 60 / 1349.7 / 1320 / 60.4 · — / — | 22.06% (h) | FAIL | over 2%: x, w, h |
| compare — All-plans table (DIFF #4) | 60 / 1520.1 / 1320 / 1540 · 44 / 47.5 | 0 / 1474.1 / 1440 / 1826 · 48 / 57.6 | 21.21% (lineHeight) | FAIL | over 2%: x, w, h, font, lineHeight |
| agencies — Versus agencies / where the money goes (DIFF #5) | 0 / 3060.2 / 1440 / 843.5 · 44 / 47.5 | 0 / 3300.1 / 1440 / 688.1 · 48 / 57.6 | 21.21% (lineHeight) | FAIL | over 2%: y, h, font, lineHeight |
| parts — What each plan does (DIFF #6) | 60 / 3903.7 / 1320 / 690.8 · 44 / 47.5 | 0 / 3988.2 / 1440 / 659.1 · 48 / 57.6 | 21.21% (lineHeight) | FAIL | over 2%: x, w, h, font, lineHeight |
| faq — Pricing FAQ (DIFF #7) | 0 / 4594.5 / 1440 / 1274.6 · 44 / 47.5 | 0 / 4647.3 / 1440 / 1242.8 · 48 / 57.6 | 21.21% (lineHeight) | FAIL | over 2%: h, font, lineHeight |
| summary — For AI assistants box (DIFF #8) | 60 / 5869 / 1320 / 374 · 13 / 19.5 | 0 / 5890.1 / 1440 / 299.5 · 12 / 19.5 | 19.92% (h) | FAIL | over 2%: x, w, h, font |
| footer — Footer (DIFF #9) | 0 / 6243 / 1440 / 941 · 38 / 34.2 | 0 / 6189.6 / 1440 / 1058.7 · 36 / 40.3 | 17.89% (lineHeight) | FAIL | over 2%: h, font, lineHeight |
| footer.cta — Footer card email form / our button (DIFF #9) | 768 / 6764.5 / 384 / 52 · — / — | 872.2 / 6761.3 / 175.6 / 48 · — / — | 14.47% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo (DIFF #10) | 1049.2 / 798 / 374.8 / 78 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button (DIFF #10) | — | 1368 / 828 / 56 / 56 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → compare | 780.1 | 600.9 | 2.49% | FAIL |  |
| compare → agencies | 0.1 | 0 | 0.0014% | PASS |  |
| agencies → parts | 0 | 0 | 0.0000% | PASS |  |
| parts → faq | 0 | 0 | 0.0000% | PASS |  |
| faq → summary | -0.1 | 0 | 0.0014% | PASS |  |
| summary → footer | 0 | 0 | 0.0000% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### pricing @ 390 — Ryze https://www.get-ryze.ai/pricing vs ours http://localhost:4318/en/pricing

Page height: Ryze 11785, ours 11250 (4.54%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (DIFF #0) | 0 / 0 / 390 / 58.5 · — / — | 0 / 0 / 390 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — Hero (DIFF #1) | 0 / 0 / 390 / 538.6 · 42 / 45.4 | 0 / 0 / 390 / 894.7 · 40 / 44 | 66.12% (h) | FAIL | over 2%: h, font, lineHeight |
| hero.title — Hero H1 (DIFF #1) | 16 / 192.5 / 358 / 136.1 · 42 / 45.4 | 24 / 199.2 / 342 / 176 · 40 / 44 | 29.32% (h) | FAIL | over 2%: x, w, h, font, lineHeight |
| hero.grid — Hero 3x3 icon grid (DIFF #1) | — | — | — | n/a | shown on neither side at this width |
| plans.billing — Monthly/annual switch (DIFF #1a) | — | 24 / 626.7 / 342 / 83.5 · — / — | — | exempt | billing-toggle: Monthly/annual switch is needed by Stripe checkout; Ryze has none. |
| plans.cards — Plan cards (DIFF #2) | 16 / 442.6 / 358 / 3149.2 · 22 / 27.5 | 24 / 730.2 / 342 / 2044.7 · 22 / 27.5 | 35.07% (h) | exempt | three-tiers: We sell three packages; Ryze shows five cards. |
| plans.annual — Annual note strip (DIFF #3) | 16 / 3607.8 / 358 / 202.8 · — / — | 24 / 2790.9 / 342 / 149.6 · — / — | 26.23% (h) | FAIL | over 2%: x, w, y, h |
| compare — All-plans table (DIFF #4) | 0 / 3874.5 / 390 / 1651 · 30 / 32.4 | 0 / 3004.5 / 390 / 1928.4 · 28 / 33.6 | 16.80% (h) | FAIL | over 2%: y, h, font, lineHeight |
| agencies — Versus agencies / where the money goes (DIFF #5) | 0 / 5525.5 / 390 / 1299.9 · 30 / 32.4 | 0 / 4932.9 / 390 / 1248.8 · 28 / 33.6 | 6.67% (font) | FAIL | over 2%: y, h, font, lineHeight |
| parts — What each plan does (DIFF #6) | 0 / 6825.5 / 390 / 1416.5 · 30 / 32.4 | 0 / 6181.6 / 390 / 1222.8 · 28 / 33.6 | 13.67% (h) | FAIL | over 2%: y, h, font, lineHeight |
| faq — Pricing FAQ (DIFF #7) | 0 / 8242 / 390 / 1958.6 · 30 / 32.4 | 0 / 7404.5 / 390 / 1802.7 · 28 / 33.6 | 7.96% (h) | FAIL | over 2%: y, h, font, lineHeight |
| summary — For AI assistants box (DIFF #8) | 0 / 10200.6 / 390 / 666.5 · 13 / 19.5 | 0 / 9207.1 / 390 / 590.6 · 12 / 19.5 | 11.39% (h) | FAIL | over 2%: y, h, font |
| footer — Footer (DIFF #9) | 0 / 10867.1 / 390 / 917.8 · — / — | 0 / 9797.8 / 390 / 1452.7 · 30 / 33.6 | 100.00% (font) | FAIL | over 2%: y, h, font |
| footer.cta — Footer card email form / our button (DIFF #9) | — | 107.2 / 10062.3 / 175.6 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo (DIFF #10) | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button (DIFF #10) | — | 326 / 780 / 48 / 48 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → compare | 3335.9 | 2109.8 | 10.40% | FAIL |  |
| compare → agencies | 0 | 0 | 0.0000% | PASS |  |
| agencies → parts | 0.1 | -0.1 | 0.0017% | PASS |  |
| parts → faq | 0 | 0.1 | 0.0008% | PASS |  |
| faq → summary | 0 | -0.1 | 0.0008% | PASS |  |
| summary → footer | 0 | 0.1 | 0.0008% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.
