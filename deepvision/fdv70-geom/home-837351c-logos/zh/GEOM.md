# GEOM — 2026-10-18T19:24:32.030Z

- command: node scripts/ryze-geom/run.mjs --mode geom --font-normalize --twice --ours http://localhost:4324 --locale zh --pages home --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/home-837351c-logos/zh
- ours: http://localhost:4324 (locale zh); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: any block's x, y, width, height, heading font size / line height, or a gap off by more than 2% fails. x and width are divided by the viewport width, y and gaps by Ryze's page height, height / font / line height by Ryze's value. Exempt only what exempt.json lists.
- fonts: one font, every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4324/_next/static/media/e4af272ccee01ff0-s.p.woff2)

| page | width | mode | result | detail |
|---|---|---|---|---|
| home | 1440 | geom | FAIL | 13 failing rows of 31 |
| home | 390 | geom | FAIL | 16 failing rows of 30 |

### home @ 1440 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4324/zh

Page height: Ryze 8735, ours 9072 (3.86%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (DIFF #0) | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — Hero (DIFF #1) | 0 / 0 / 1440 / 900 · 69.1 / 74.6 | 0 / 0 / 1440 / 900 · 62 / 74.4 | 10.30% (font) | FAIL | over 2%: font |
| hero.cta — Hero email form / our buttons (DIFF #1a) | 55 / 574.1 / 373 / 49 · — / — | 68 / 593.3 / 495.5 / 48 · — / — | 8.51% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| strip — Press strip / platform strip (DIFF #2) | 0 / 900 / 1440 / 93.8 · — / — | 0 / 900 / 1440 / 94 · — / — | 0.21% (h) | PASS |  |
| twocol — All platforms + AI search, two columns (DIFF #3) | 0 / 993.8 / 1440 / 447.6 · 34 / 38.1 | 0 / 994 / 1440 / 671.4 · 34 / 38.1 | 50.00% (h) | FAIL | over 2%: h |
| wall — Wall of Love / monthly output wall (DIFF #4) | 0 / 1441.3 / 1440 / 1028 · 56 / 62.2 | 0 / 1665.4 / 1440 / 956.2 · 56 / 62.2 | 6.98% (h) | FAIL | over 2%: y, h |
| logos — Customer logo wall (DIFF #5) | 0 / 2469.3 / 1440 / 624.5 · 38 / 47.5 | 0 / 2621.6 / 1440 / 420 · 38 / 47.5 | 32.75% (h) | FAIL | over 2%: h |
| cards5 — Five demo cards (DIFF #6) | 0 / 3093.8 / 1440 / 750.9 · 44 / 66 | 0 / 3041.6 / 1440 / 751.4 · 44 / 66 | 0.60% (y) | PASS |  |
| scan — Free scan / how we start (DIFF #7) | 0 / 3844.7 / 1440 / 497 · 42 / 52.5 | 0 / 3792.9 / 1440 / 440.5 · 42 / 52.5 | 11.37% (h) | FAIL | over 2%: h |
| scan.cta — Scan email form / our button (DIFF #7) | 654.8 / 4177.7 / 576 / 52 · — / — | 633.4 / 4073.4 / 140 / 48 · — / — | 30.28% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| three — Three products (DIFF #8) | 0 / 4341.7 / 1440 / 647 · 36 / 45 | 0 / 4233.4 / 1440 / 746.5 · 36 / 46.8 | 15.38% (h) | FAIL | over 2%: h, lineHeight |
| why — Why bento (DIFF #9) | 0 / 4988.7 / 1440 / 647.5 · 48 / 72 | 0 / 4980 / 1440 / 612 · 48 / 72 | 5.48% (h) | FAIL | over 2%: h |
| list — Everything list (DIFF #10) | 0 / 5636.2 / 1440 / 760 · 48 / 60 | 0 / 5592 / 1440 / 833.7 · 48 / 62.4 | 9.70% (h) | FAIL | over 2%: h, lineHeight |
| agency — Agency / AI sales assistant (DIFF #11) | 0 / 6396.2 / 1440 / 558.5 · 42 / 52.5 | 0 / 6425.6 / 1440 / 715 · 42 / 54.6 | 28.02% (h) | FAIL | over 2%: h, lineHeight |
| faq — FAQ (DIFF #12) | 0 / 6954.7 / 1440 / 839 · 40 / 60 | 0 / 7140.6 / 1440 / 890.8 · 40 / 60 | 6.17% (h) | FAIL | over 2%: y, h |
| footer — Footer (DIFF #13) | 0 / 7793.7 / 1440 / 941 · 38 / 34.2 | 0 / 8031.4 / 1440 / 1040.7 · 36 / 45 | 31.58% (lineHeight) | FAIL | over 2%: y, h, font, lineHeight |
| footer.cta — Footer card email form / our button (DIFF #13) | 768 / 8315.2 / 384 / 52 · — / — | 890 / 8576.3 / 140 / 48 · — / — | 16.94% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo (DIFF #14) | 1049.2 / 798 / 374.8 / 78 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button (DIFF #14) | — | 1368 / 828 / 56 / 56 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → strip | 0 | 0 | 0.0000% | PASS |  |
| strip → twocol | 0 | 0 | 0.0000% | PASS |  |
| twocol → wall | -0.1 | 0 | 0.0011% | PASS |  |
| wall → logos | 0 | 0 | 0.0000% | PASS |  |
| logos → cards5 | 0 | 0 | 0.0000% | PASS |  |
| cards5 → scan | 0 | -0.1 | 0.0011% | PASS |  |
| scan → three | 0 | 0 | 0.0000% | PASS |  |
| three → why | 0 | 0.1 | 0.0011% | PASS |  |
| why → list | 0 | 0 | 0.0000% | PASS |  |
| list → agency | 0 | -0.1 | 0.0011% | PASS |  |
| agency → faq | 0 | 0 | 0.0000% | PASS |  |
| faq → footer | 0 | 0 | 0.0000% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### home @ 390 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4324/zh

Page height: Ryze 9847, ours 12965 (31.66%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (DIFF #0) | 0 / 0 / 390 / 58.5 · — / — | 0 / 0 / 390 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — Hero (DIFF #1) | 0 / 0 / 390 / 844 · 33.6 / 37.6 | 0 / 0 / 390 / 1126.9 · 34 / 44.2 | 33.52% (h) | FAIL | over 2%: h, lineHeight |
| hero.cta — Hero email form / our buttons (DIFF #1a) | 24 / 326.5 / 342 / 46 · — / — | 24 / 320.6 / 342 / 48 · — / — | 4.35% (h) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| strip — Press strip / platform strip (DIFF #2) | 0 / 844 / 390 / 72.1 · — / — | 0 / 1126.9 / 390 / 132.4 · — / — | 83.63% (h) | FAIL | over 2%: y, h |
| twocol — All platforms + AI search, two columns (DIFF #3) | 0 / 916.1 / 390 / 554.5 · 24 / 26.9 | 0 / 1259.3 / 390 / 1058.6 · 24 / 26.9 | 90.91% (h) | FAIL | over 2%: y, h |
| wall — Wall of Love / monthly output wall (DIFF #4) | 0 / 1470.6 / 390 / 1228.4 · 28 / 42 | 0 / 2318 / 390 / 1471 · 28 / 42 | 19.75% (h) | FAIL | over 2%: y, h |
| logos — Customer logo wall (DIFF #5) | 0 / 2699 / 390 / 717 · 24 / 30 | 0 / 3789 / 390 / 463.2 · 24 / 30 | 35.40% (h) | FAIL | over 2%: y, h |
| cards5 — Five demo cards (DIFF #6) | 0 / 3416 / 390 / 868.8 · 28 / 42 | 0 / 4252.1 / 390 / 1170.2 · 28 / 42 | 34.69% (h) | FAIL | over 2%: y, h |
| scan — Free scan / how we start (DIFF #7) | 0 / 4284.7 / 390 / 434 · 28 / 35 | 0 / 5422.3 / 390 / 419 · 28 / 35 | 11.55% (y) | FAIL | over 2%: y, h |
| scan.cta — Scan email form / our button (DIFF #7) | 24 / 4590.7 / 342 / 48 · — / — | 24 / 5713.3 / 140 / 48 · — / — | 51.79% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| three — Three products (DIFF #8) | 0 / 4718.7 / 390 / 1653.5 · 22 / 27.5 | 0 / 5841.3 / 390 / 1770.5 · 22 / 28.6 | 11.40% (y) | FAIL | over 2%: y, h, lineHeight |
| why — Why bento (DIFF #9) | 0 / 6372.2 / 390 / 957 · 28 / 42 | 0 / 7611.8 / 390 / 944 · 28 / 42 | 12.59% (y) | FAIL | over 2%: y |
| list — Everything list (DIFF #10) | 0 / 7329.2 / 390 / 955.6 · 28 / 35 | 0 / 8555.8 / 390 / 1069.7 · 28 / 36.4 | 12.46% (y) | FAIL | over 2%: y, h, lineHeight |
| agency — Agency / AI sales assistant (DIFF #11) | 0 / 8284.9 / 390 / 644.4 · 28 / 35 | 0 / 9625.5 / 390 / 1105.5 · 28 / 36.4 | 71.55% (h) | FAIL | over 2%: y, h, lineHeight |
| faq — FAQ (DIFF #12) | — | 0 / 10731 / 390 / 815.5 · 28 / 42 | — | FAIL | ours shows it; Ryze hides it at this width |
| footer — Footer (DIFF #13) | 0 / 8929.3 / 390 / 917.8 · — / — | 0 / 11546.5 / 390 / 1418.8 · 30 / 37.5 | 100.00% (font) | FAIL | over 2%: y, h, font |
| footer.cta — Footer card email form / our button (DIFF #13) | — | 125 / 11795.1 / 140 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo (DIFF #14) | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button (DIFF #14) | — | — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → strip | 0 | 0 | 0.0000% | PASS |  |
| strip → twocol | 0 | 0 | 0.0000% | PASS |  |
| twocol → wall | 0 | 0.1 | 0.0010% | PASS |  |
| wall → logos | 0 | 0 | 0.0000% | PASS |  |
| logos → cards5 | 0 | -0.1 | 0.0010% | PASS |  |
| cards5 → scan | -0.1 | 0 | 0.0010% | PASS |  |
| scan → three | 0 | 0 | 0.0000% | PASS |  |
| three → why | 0 | 0 | 0.0000% | PASS |  |
| why → list | 0 | 0 | 0.0000% | PASS |  |
| list → agency | 0.1 | 0 | 0.0010% | PASS |  |
| agency → footer | 0 | 815.5 | 8.28% | FAIL | includes faq (on one side only) |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.
