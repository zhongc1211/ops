# GEOM — 2026-10-18T18:03:44.719Z

- command: node scripts/ryze-geom/run.mjs --mode geom --font-normalize --twice --ours http://localhost:4322 --pages product --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/product-878d921/geom
- ours: http://localhost:4322 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: any block's x, y, width, height, heading font size / line height, or a gap off by more than 2% fails. x and width are divided by the viewport width, y and gaps by Ryze's page height, height / font / line height by Ryze's value. Exempt only what exempt.json lists.
- fonts: one font, every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4322/_next/static/media/e4af272ccee01ff0-s.p.woff2)

| page | width | mode | result | detail |
|---|---|---|---|---|
| product | 1440 | geom | FAIL | 11 failing rows of 25 |
| product | 390 | geom | FAIL | 13 failing rows of 25 |

### product @ 1440 — Ryze https://www.get-ryze.ai/muse vs ours http://localhost:4322/en/products/ai-sales-assistant

Page height: Ryze 9537, ours 9023 (5.39%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — #1 Hero | 0 / 0 / 1440 / 900 · 66 / 68.6 | 0 / 0 / 1440 / 1085.9 · 66 / 68.6 | 20.66% (h) | FAIL | over 2%: h |
| connect — #2-#4 One white section (Ryze #how-to-connect) | 0 / 900 / 1440 / 2081.5 · 48 / 72 | 0 / 1085.9 / 1440 / 2092.1 · 48 / 72 | 1.95% (y) | PASS |  |
| connect.title — #2 Section heading | 100.5 / 1012 / 1239 / 72 · 48 / 72 | 100.5 / 1197.9 / 1239 / 72 · 48 / 72 | 1.95% (y) | PASS |  |
| connect.icons — #2 Icon row / where it replies (Ryze hides it below 768px) | 100.5 / 1116 / 1239 / 84 · — / — | 100.5 / 1301.9 / 1239 / 84 · — / — | 1.95% (y) | PASS |  |
| connect.steps — #3 Two step cards | 100.5 / 1256 / 1239 / 614.3 · 26 / 29.9 | 100.5 / 1479.4 / 1239 / 559 · 26 / 29.9 | 9.00% (h) | FAIL | over 2%: y, h |
| connect.try — #4 Video tutorial / you be the customer | 100.5 / 1926.3 / 1239 / 943.2 · 36 / 39.6 | 100.5 / 2128.4 / 1239 / 903.6 · 36 / 39.6 | 4.20% (h) | FAIL | over 2%: y, h |
| flow — #5 Connection diagram / first message to booking | 0 / 2981.5 / 1440 / 960 · 48 / 72 | 0 / 3178 / 1440 / 960 · 48 / 72 | 2.06% (y) | FAIL | over 2%: y |
| ask — #6 What to ask / what customers ask | 0 / 3941.5 / 1440 / 599.4 · 48 / 72 | 0 / 4138 / 1440 / 597 · 48 / 72 | 2.06% (y) | FAIL | over 2%: y |
| does — #7 What it does per platform | 0 / 4540.8 / 1440 / 1366.7 · 48 / 72 | 0 / 4735 / 1440 / 875.9 · 48 / 72 | 35.91% (h) | FAIL | over 2%: y, h |
| who — #8 Who it's for | 0 / 5907.6 / 1440 / 695.9 · 48 / 72 | 0 / 5610.9 / 1440 / 590.6 · 48 / 72 | 15.13% (h) | FAIL | over 2%: y, h |
| vs — #9 Comparison table | 0 / 6603.5 / 1440 / 851 · 48 / 72 | 0 / 6201.5 / 1440 / 851 · 48 / 72 | 4.22% (y) | FAIL | over 2%: y |
| faq — #10 FAQ | 0 / 7454.5 / 1440 / 1141.8 · 48 / 72 | 0 / 7052.5 / 1440 / 911.7 · 48 / 72 | 20.15% (h) | FAIL | over 2%: y, h |
| footer — Footer | 0 / 8596.2 / 1440 / 941 · 38 / 34.2 | 0 / 7964.2 / 1440 / 1058.7 · 36 / 40.3 | 17.89% (lineHeight) | FAIL | over 2%: y, h, font, lineHeight |
| footer.cta — Footer card email form / our button | 708.6 / 9113.7 / 384 / 60 · — / — | 872.2 / 8556.1 / 175.6 / 48 · — / — | 20.00% (h) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | — | — | — | n/a | shown on neither side at this width |
| whatsapp — Our WhatsApp button | — | 1164 / 751.5 / 260 / 132.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → connect | 0 | 0 | 0.0000% | PASS |  |
| connect → flow | 0 | 0 | 0.0000% | PASS |  |
| flow → ask | 0 | 0 | 0.0000% | PASS |  |
| ask → does | -0.1 | 0 | 0.0010% | PASS |  |
| does → who | 0.1 | 0 | 0.0010% | PASS |  |
| who → vs | 0 | 0 | 0.0000% | PASS |  |
| vs → faq | 0 | 0 | 0.0000% | PASS |  |
| faq → footer | -0.1 | 0 | 0.0010% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### product @ 390 — Ryze https://www.get-ryze.ai/muse vs ours http://localhost:4322/en/products/ai-sales-assistant

Page height: Ryze 11085, ours 11512 (3.85%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 390 / 58.5 · — / — | 0 / 0 / 390 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| hero — #1 Hero | 0 / 0 / 390 / 844 · 40 / 41.6 | 0 / 0 / 390 / 1301.7 · 40 / 41.6 | 54.23% (h) | FAIL | over 2%: h |
| connect — #2-#4 One white section (Ryze #how-to-connect) | 0 / 844 / 390 / 1456.1 · 28 / 42 | 0 / 1301.7 / 390 / 2222.9 · 28 / 42 | 52.66% (h) | FAIL | over 2%: y, h |
| connect.title — #2 Section heading | 24 / 924 / 342 / 84 · 28 / 42 | 24 / 1381.7 / 342 / 84 · 28 / 42 | 4.13% (y) | FAIL | over 2%: y |
| connect.icons — #2 Icon row / where it replies (Ryze hides it below 768px) | — | — | — | n/a | shown on neither side at this width |
| connect.steps — #3 Two step cards | 24 / 1048 / 342 / 763.1 · 22 / 25.3 | 24 / 1620.7 / 342 / 1077.3 · 22 / 25.3 | 41.17% (h) | FAIL | over 2%: y, h |
| connect.try — #4 Video tutorial / you be the customer | 24 / 1851.1 / 342 / 369 · 26 / 28.6 | 24 / 2772 / 342 / 638.6 · 26 / 28.6 | 73.06% (h) | FAIL | over 2%: y, h |
| flow — #5 Connection diagram / first message to booking | 0 / 2300.1 / 390 / 602 · 28 / 42 | 0 / 3524.6 / 390 / 602 · 28 / 42 | 11.05% (y) | FAIL | over 2%: y |
| ask — #6 What to ask / what customers ask | 0 / 2902.1 / 390 / 734.8 · 28 / 42 | 0 / 4126.6 / 390 / 1166.8 · 28 / 42 | 58.79% (h) | FAIL | over 2%: y, h |
| does — #7 What it does per platform | 0 / 3636.9 / 390 / 3158.5 · 28 / 42 | 0 / 5293.4 / 390 / 1768.1 · 28 / 42 | 44.02% (h) | FAIL | over 2%: y, h |
| who — #8 Who it's for | 0 / 6795.5 / 390 / 1190.8 · 28 / 42 | 0 / 7061.5 / 390 / 1040.5 · 28 / 42 | 12.62% (h) | FAIL | over 2%: y, h |
| vs — #9 Comparison table | 0 / 7986.3 / 390 / 919 · 28 / 42 | 0 / 8102 / 390 / 919 · 28 / 42 | 1.04% (y) | PASS |  |
| faq — #10 FAQ | 0 / 8905.3 / 390 / 1262.3 · 28 / 42 | 0 / 9021 / 390 / 1005 · 28 / 42 | 20.38% (h) | FAIL | over 2%: h |
| footer — Footer | 0 / 10167.6 / 390 / 917.8 · — / — | 0 / 10026 / 390 / 1486.3 · 30 / 33.6 | 100.00% (font) | FAIL | over 2%: h, font |
| footer.cta — Footer card email form / our button | — | 107.2 / 10324.2 / 175.6 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button | — | 114 / 703.5 / 260 / 124.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| hero → connect | 0 | 0 | 0.0000% | PASS |  |
| connect → flow | 0 | 0 | 0.0000% | PASS |  |
| flow → ask | 0 | 0 | 0.0000% | PASS |  |
| ask → does | 0 | 0 | 0.0000% | PASS |  |
| does → who | 0.1 | 0 | 0.0009% | PASS |  |
| who → vs | 0 | 0 | 0.0000% | PASS |  |
| vs → faq | 0 | 0 | 0.0000% | PASS |  |
| faq → footer | 0 | 0 | 0.0000% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.
