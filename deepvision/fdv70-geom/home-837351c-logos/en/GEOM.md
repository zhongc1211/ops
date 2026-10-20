# GEOM — 2026-10-18T19:21:09.423Z

- command: node scripts/ryze-geom/run.mjs --mode geom --font-normalize --twice --ours http://localhost:4324 --locale en --pages home --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/home-837351c-logos/en
- ours: http://localhost:4324 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: any block's x, y, width, height, heading font size / line height, or a gap off by more than 2% fails. x and width are divided by the viewport width, y and gaps by Ryze's page height, height / font / line height by Ryze's value. Exempt only what exempt.json lists.
- fonts: one font, every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4324/_next/static/media/e4af272ccee01ff0-s.p.woff2)

| page | width | mode | result | detail |
|---|---|---|---|---|
| home | 1440 | geom | FAIL | 12 failing rows of 31 |
| home | 390 | geom | FAIL | 16 failing rows of 30 |

### home @ 1440 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4324/en

Page height: Ryze 8735, ours 9447 (8.15%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (DIFF #0) | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — Hero (DIFF #1) | 0 / 0 / 1440 / 900 · 69.1 / 74.6 | 0 / 0 / 1440 / 900 · 69 / 74.5 | 0.17% (lineHeight) | PASS |  |
| hero.cta — Hero email form / our buttons (DIFF #1a) | 55 / 574.1 / 373 / 49 · — / — | 68 / 647.9 / 495.5 / 48 · — / — | 8.51% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| strip — Press strip / platform strip (DIFF #2) | 0 / 900 / 1440 / 93.8 · — / — | 0 / 900 / 1440 / 94 · — / — | 0.21% (h) | PASS |  |
| twocol — All platforms + AI search, two columns (DIFF #3) | 0 / 993.8 / 1440 / 447.6 · 34 / 38.1 | 0 / 994 / 1440 / 771.9 · 34 / 38.1 | 72.45% (h) | FAIL | over 2%: h |
| wall — Wall of Love / monthly output wall (DIFF #4) | 0 / 1441.3 / 1440 / 1028 · 56 / 62.2 | 0 / 1765.9 / 1440 / 1004.2 · 56 / 62.2 | 3.72% (y) | FAIL | over 2%: y, h |
| logos — Customer logo wall (DIFF #5) | 0 / 2469.3 / 1440 / 624.5 · 38 / 47.5 | 0 / 2770.1 / 1440 / 420 · 38 / 47.5 | 32.75% (h) | FAIL | over 2%: y, h |
| cards5 — Five demo cards (DIFF #6) | 0 / 3093.8 / 1440 / 750.9 · 44 / 66 | 0 / 3190.1 / 1440 / 751.4 · 44 / 66 | 1.10% (y) | PASS |  |
| scan — Free scan / how we start (DIFF #7) | 0 / 3844.7 / 1440 / 497 · 42 / 52.5 | 0 / 3941.5 / 1440 / 480.5 · 42 / 52.5 | 3.32% (h) | FAIL | over 2%: h |
| scan.cta — Scan email form / our button (DIFF #7) | 654.8 / 4177.7 / 576 / 52 · — / — | 633.4 / 4262 / 175.6 / 48 · — / — | 27.81% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| three — Three products (DIFF #8) | 0 / 4341.7 / 1440 / 647 · 36 / 45 | 0 / 4422 / 1440 / 815.1 · 36 / 45 | 25.98% (h) | FAIL | over 2%: h |
| why — Why bento (DIFF #9) | 0 / 4988.7 / 1440 / 647.5 · 48 / 72 | 0 / 5237.1 / 1440 / 706.5 · 48 / 72 | 9.11% (h) | FAIL | over 2%: y, h |
| list — Everything list (DIFF #10) | 0 / 5636.2 / 1440 / 760 · 48 / 60 | 0 / 5943.6 / 1440 / 839.4 · 48 / 60 | 10.45% (h) | FAIL | over 2%: y, h |
| agency — Agency / AI sales assistant (DIFF #11) | 0 / 6396.2 / 1440 / 558.5 · 42 / 52.5 | 0 / 6783 / 1440 / 715 · 42 / 52.5 | 28.02% (h) | FAIL | over 2%: y, h |
| faq — FAQ (DIFF #12) | 0 / 6954.7 / 1440 / 839 · 40 / 60 | 0 / 7498 / 1440 / 890.8 · 40 / 60 | 6.22% (y) | FAIL | over 2%: y, h |
| footer — Footer (DIFF #13) | 0 / 7793.7 / 1440 / 941 · 38 / 34.2 | 0 / 8388.7 / 1440 / 1058.7 · 36 / 40.3 | 17.89% (lineHeight) | FAIL | over 2%: y, h, font, lineHeight |
| footer.cta — Footer card email form / our button (DIFF #13) | 768 / 8315.2 / 384 / 52 · — / — | 872.2 / 8940.3 / 175.6 / 48 · — / — | 14.47% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo (DIFF #14) | 1049.2 / 798 / 374.8 / 78 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button (DIFF #14) | — | 1368 / 828 / 56 / 56 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → strip | 0 | 0 | 0.0000% | PASS |  |
| strip → twocol | 0 | 0 | 0.0000% | PASS |  |
| twocol → wall | -0.1 | 0 | 0.0011% | PASS |  |
| wall → logos | 0 | 0 | 0.0000% | PASS |  |
| logos → cards5 | 0 | 0 | 0.0000% | PASS |  |
| cards5 → scan | 0 | 0 | 0.0000% | PASS |  |
| scan → three | 0 | 0 | 0.0000% | PASS |  |
| three → why | 0 | 0 | 0.0000% | PASS |  |
| why → list | 0 | 0 | 0.0000% | PASS |  |
| list → agency | 0 | 0 | 0.0000% | PASS |  |
| agency → faq | 0 | 0 | 0.0000% | PASS |  |
| faq → footer | 0 | -0.1 | 0.0011% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### home @ 390 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4324/en

Page height: Ryze 9847, ours 14025 (42.43%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (DIFF #0) | 0 / 0 / 390 / 58.5 · — / — | 0 / 0 / 390 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — Hero (DIFF #1) | 0 / 0 / 390 / 844 · 33.6 / 37.6 | 0 / 0 / 390 / 1220.4 · 34 / 38.1 | 44.60% (h) | FAIL | over 2%: h |
| hero.cta — Hero email form / our buttons (DIFF #1a) | 24 / 326.5 / 342 / 46 · — / — | 24 / 372 / 342 / 90 · — / — | 95.65% (h) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| strip — Press strip / platform strip (DIFF #2) | 0 / 844 / 390 / 72.1 · — / — | 0 / 1220.4 / 390 / 132.4 · — / — | 83.63% (h) | FAIL | over 2%: y, h |
| twocol — All platforms + AI search, two columns (DIFF #3) | 0 / 916.1 / 390 / 554.5 · 24 / 26.9 | 0 / 1352.8 / 390 / 1158.6 · 24 / 26.9 | 108.94% (h) | FAIL | over 2%: y, h |
| wall — Wall of Love / monthly output wall (DIFF #4) | 0 / 1470.6 / 390 / 1228.4 · 28 / 42 | 0 / 2511.4 / 390 / 1584.5 · 28 / 42 | 28.99% (h) | FAIL | over 2%: y, h |
| logos — Customer logo wall (DIFF #5) | 0 / 2699 / 390 / 717 · 24 / 30 | 0 / 4095.9 / 390 / 568.7 · 24 / 30 | 20.68% (h) | FAIL | over 2%: y, h |
| cards5 — Five demo cards (DIFF #6) | 0 / 3416 / 390 / 868.8 · 28 / 42 | 0 / 4664.6 / 390 / 1212.2 · 28 / 42 | 39.53% (h) | FAIL | over 2%: y, h |
| scan — Free scan / how we start (DIFF #7) | 0 / 4284.7 / 390 / 434 · 28 / 35 | 0 / 5876.8 / 390 / 491 · 28 / 35 | 16.17% (y) | FAIL | over 2%: y, h |
| scan.cta — Scan email form / our button (DIFF #7) | 24 / 4590.7 / 342 / 48 · — / — | 24 / 6239.8 / 175.6 / 48 · — / — | 42.67% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| three — Three products (DIFF #8) | 0 / 4718.7 / 390 / 1653.5 · 22 / 27.5 | 0 / 6367.8 / 390 / 1877.6 · 22 / 27.5 | 16.75% (y) | FAIL | over 2%: y, h |
| why — Why bento (DIFF #9) | 0 / 6372.2 / 390 / 957 · 28 / 42 | 0 / 8245.3 / 390 / 1076 · 28 / 42 | 19.02% (y) | FAIL | over 2%: y, h |
| list — Everything list (DIFF #10) | 0 / 7329.2 / 390 / 955.6 · 28 / 35 | 0 / 9321.3 / 390 / 1155.5 · 28 / 35 | 20.92% (h) | FAIL | over 2%: y, h |
| agency — Agency / AI sales assistant (DIFF #11) | 0 / 8284.9 / 390 / 644.4 · 28 / 35 | 0 / 10476.8 / 390 / 1161.6 · 28 / 35 | 80.26% (h) | FAIL | over 2%: y, h |
| faq — FAQ (DIFF #12) | — | 0 / 11638.5 / 390 / 934 · 28 / 42 | — | FAIL | ours shows it; Ryze hides it at this width |
| footer — Footer (DIFF #13) | 0 / 8929.3 / 390 / 917.8 · — / — | 0 / 12572.5 / 390 / 1452.7 · 30 / 33.6 | 100.00% (font) | FAIL | over 2%: y, h, font |
| footer.cta — Footer card email form / our button (DIFF #13) | — | 107.2 / 12837 / 175.6 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo (DIFF #14) | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button (DIFF #14) | — | — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → strip | 0 | 0 | 0.0000% | PASS |  |
| strip → twocol | 0 | 0 | 0.0000% | PASS |  |
| twocol → wall | 0 | 0 | 0.0000% | PASS |  |
| wall → logos | 0 | 0 | 0.0000% | PASS |  |
| logos → cards5 | 0 | 0 | 0.0000% | PASS |  |
| cards5 → scan | -0.1 | 0 | 0.0010% | PASS |  |
| scan → three | 0 | 0 | 0.0000% | PASS |  |
| three → why | 0 | -0.1 | 0.0010% | PASS |  |
| why → list | 0 | 0 | 0.0000% | PASS |  |
| list → agency | 0.1 | 0 | 0.0010% | PASS |  |
| agency → footer | 0 | 934.1 | 9.49% | FAIL | includes faq (on one side only) |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.
