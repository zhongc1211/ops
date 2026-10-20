# GEOM — 2026-10-18T17:46:31.361Z

- command: node scripts/ryze-geom/run.mjs --mode geom --font-normalize --twice --ours http://localhost:4320 --pages glossary,privacy,data-deletion --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/pr6-0058769/geom
- ours: http://localhost:4320 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: any block's x, y, width, height, heading font size / line height, or a gap off by more than 2% fails. x and width are divided by the viewport width, y and gaps by Ryze's page height, height / font / line height by Ryze's value. Exempt only what exempt.json lists.
- fonts: one font, every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4320/_next/static/media/e4af272ccee01ff0-s.p.woff2)

| page | width | mode | result | detail |
|---|---|---|---|---|
| glossary | 1440 | geom | FAIL | 14 failing rows of 20 |
| glossary | 390 | geom | FAIL | 15 failing rows of 20 |
| privacy | 1440 | geom | FAIL | 5 failing rows of 10 |
| privacy | 390 | geom | FAIL | 5 failing rows of 10 |
| data-deletion | 1440 | geom | FAIL | 6 failing rows of 8 |
| data-deletion | 390 | geom | FAIL | 6 failing rows of 8 |

### glossary @ 1440 — Ryze https://www.get-ryze.ai/glossary vs ours http://localhost:4320/en/glossary

Page height: Ryze 3971, ours 3161 (20.40%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| head — Head: breadcrumbs, title, lead card | 0 / 0 / 1440 / 570.8 · 52 / 54.6 | 0 / 57 / 1440 / 494.6 · 52 / 54.6 | 13.35% (h) | FAIL | over 2%: h |
| head.crumbs — Breadcrumbs and byline | 68 / 150 / 1304 / 21 · — / — | 68 / 150 / 682 / 21 · — / — | 43.19% (w) | FAIL | over 2%: w |
| head.title — H1 | 68 / 239.5 / 682 / 54.6 · 52 / 54.6 | 68 / 240 / 682 / 54.6 · 52 / 54.6 | 0.0126% (y) | PASS |  |
| head.lead — Lead card on the right | 814 / 211 / 558 / 303.8 · 28 / 30.2 | 814 / 211 / 558 / 283.6 · — / — | 100.00% (font) | FAIL | over 2%: h, font |
| head.lead.cta — Lead card email field / our button | 850 / 440.8 / 388.8 / 38 · — / — | 850 / 420.6 / 175.6 / 38 · — / — | 14.81% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| logos — Client logo row | 0 / 570.8 / 1440 / 118.3 · — / — | — | — | FAIL | Ryze has it; we have no such block |
| body — Term column | 290 / 689.1 / 940 / 2340.8 · 34 / 51 | 0 / 551.6 / 1440 / 1551 · — / — | 100.00% (font) | FAIL | over 2%: x, w, y, h, font |
| body.intro — Intro section | 328 / 719.1 / 864 / 252 · — / — | — | — | FAIL | Ryze has it; we have no such block |
| body.terms — Definitions | 328 / 971.1 / 864 / 683 · 34 / 51 | 328 / 581.6 / 864 / 1409 · — / — | 106.30% (h) | FAIL | over 2%: y, h, font |
| body.where — Where this fits | 328 / 1654.1 / 864 / 581.8 · 34 / 51 | — | — | FAIL | Ryze has it; we have no such block |
| body.faq — Questions | 328 / 2235.8 / 864 / 754 · 34 / 51 | — | — | FAIL | Ryze has it; we have no such block |
| promo — Promo card beside the column (wide screens) | 68 / 711.4 / 222 / 519.7 · — / — | 68 / 581.6 / 240 / 281.1 · — / — | 45.91% (h) | FAIL | over 2%: y, h |
| promobar — Promo bar at the bottom of the screen (narrow screens) | — | — | — | n/a | shown on neither side at this width |
| footer — Footer | 0 / 3029.8 / 1440 / 941 · 38 / 34.2 | 0 / 2102.6 / 1440 / 1058.7 · 36 / 40.3 | 23.35% (y) | FAIL | over 2%: y, h, font, lineHeight |
| footer.cta — Footer card email form / our button | 768 / 3551.3 / 384 / 52 · — / — | 872.2 / 2654.1 / 175.6 / 48 · — / — | 22.59% (y) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | 1049.2 / 798 / 374.8 / 78 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button | — | 1164 / 751.5 / 260 / 132.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| head → body | 118.3 | 0 | 2.98% | FAIL | includes logos (on one side only) |
| body → footer | -0.1 | 0 | 0.0025% | PASS | includes promobar (on one side only) |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### glossary @ 390 — Ryze https://www.get-ryze.ai/glossary vs ours http://localhost:4320/en/glossary

Page height: Ryze 6285, ours 4479 (28.74%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 390 / 58.5 · — / — | 0 / 0 / 390 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| head — Head: breadcrumbs, title, lead card | 0 / 0 / 390 / 918.5 · 36 / 37.8 | 0 / 57 / 390 / 734.7 · 36 / 37.8 | 20.01% (h) | FAIL | over 2%: h |
| head.crumbs — Breadcrumbs and byline | 24 / 150 / 342 / 50 · — / — | 24 / 150 / 342 / 21 · — / — | 58.00% (h) | FAIL | over 2%: h |
| head.title — H1 | 24 / 268.5 / 342 / 75.6 · 36 / 37.8 | 24 / 240 / 342 / 37.8 · 36 / 37.8 | 50.00% (h) | FAIL | over 2%: h |
| head.lead — Lead card on the right | 24 / 607.3 / 342 / 255.2 · 24 / 25.9 | 24 / 429.5 / 342 / 305.2 · — / — | 100.00% (font) | FAIL | over 2%: y, h, font |
| head.lead.cta — Lead card email field / our button | 40 / 808.5 / 310 / 38 · — / — | 60 / 660.7 / 175.6 / 38 · — / — | 34.46% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| logos — Client logo row | 0 / 918.5 / 390 / 425.4 · — / — | — | — | FAIL | Ryze has it; we have no such block |
| body — Term column | 40 / 1343.9 / 390 / 4023.8 · 26 / 39 | 0 / 791.7 / 390 / 2235 · — / — | 100.00% (font) | FAIL | over 2%: x, y, h, font |
| body.intro — Intro section | 64 / 1373.9 / 342 / 508 · — / — | — | — | FAIL | Ryze has it; we have no such block |
| body.terms — Definitions | 64 / 1881.9 / 342 / 1167.5 · 26 / 39 | 24 / 821.7 / 342 / 2093 · — / — | 100.00% (font) | FAIL | over 2%: x, y, h, font |
| body.where — Where this fits | 64 / 3049.4 / 342 / 1058.3 · 26 / 39 | — | — | FAIL | Ryze has it; we have no such block |
| body.faq — Questions | 64 / 4107.6 / 342 / 1220 · 26 / 39 | — | — | FAIL | Ryze has it; we have no such block |
| promo — Promo card beside the column (wide screens) | — | — | — | n/a | shown on neither side at this width |
| promobar — Promo bar at the bottom of the screen (narrow screens) | 0 / 866 / 390 / 73.5 · — / — | 12 / 707.6 / 366 / 56.4 · — / — | 40.62% (y) | FAIL | over 2%: x, w, y, h |
| footer — Footer | 0 / 5367.6 / 390 / 917.8 · — / — | 0 / 3026.7 / 390 / 1452.7 · 30 / 33.6 | 100.00% (font) | FAIL | over 2%: y, h, font |
| footer.cta — Footer card email form / our button | — | 107.2 / 3291.2 / 175.6 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button | — | 114 / 703.5 / 260 / 124.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| head → body | 425.4 | 0 | 6.77% | FAIL | includes logos (on one side only) |
| body → footer | -0.1 | 0 | 0.0016% | PASS | includes promo (on one side only) |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### privacy @ 1440 — Ryze https://www.get-ryze.ai/privacy vs ours http://localhost:4320/en/privacy

Page height: Ryze 6301, ours 2419 (61.61%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| col — Text column | 208 / 184 / 1024 / 4984 · 48 / 48 | 240 / 184 / 960 / 984 · 48 / 48 | 80.26% (h) | FAIL | over 2%: x, w, h |
| col.title — H1 | 240 / 184 / 960 / 48 · 48 / 48 | 240 / 184 / 960 / 48 · 48 / 48 | 0.0000% (x) | PASS |  |
| col.date — Last updated | 240 / 240 / 960 / 24 · — / — | 240 / 240 / 960 / 24 · — / — | 0.0000% (x) | PASS |  |
| col.h2 — First part heading | — | 240 / 392 / 960 / 32 · 24 / 32 | — | FAIL | ours shows it; Ryze hides it at this width |
| footer — Footer | 0 / 5360 / 1440 / 941 · 38 / 34.2 | 0 / 1360 / 1440 / 1058.7 · 36 / 40.3 | 63.48% (y) | FAIL | over 2%: y, h, font, lineHeight |
| footer.cta — Footer card email form / our button | 768 / 5881.4 / 384 / 52 · — / — | 872.2 / 1911.5 / 175.6 / 48 · — / — | 63.00% (y) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | 1049.2 / 798 / 374.8 / 78 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button | — | 1164 / 751.5 / 260 / 132.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| col → footer | 192 | 192 | 0.0000% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### privacy @ 390 — Ryze https://www.get-ryze.ai/privacy vs ours http://localhost:4320/en/privacy

Page height: Ryze 11526, ours 3469 (69.90%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 390 / 58.5 · — / — | 0 / 0 / 390 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| col — Text column | 0 / 136 / 390 / 10280 · 30 / 36 | 16 / 136 / 358 / 1688 · 30 / 36 | 83.58% (h) | FAIL | over 2%: x, w, h |
| col.title — H1 | 16 / 136 / 358 / 36 · 30 / 36 | 16 / 136 / 358 / 36 · 30 / 36 | 0.0000% (x) | PASS |  |
| col.date — Last updated | 16 / 180 / 358 / 24 · — / — | 16 / 180 / 358 / 24 · — / — | 0.0000% (x) | PASS |  |
| col.h2 — First part heading | — | 16 / 404 / 358 / 32 · 24 / 32 | — | FAIL | ours shows it; Ryze hides it at this width |
| footer — Footer | 0 / 10608 / 390 / 917.8 · — / — | 0 / 2016 / 390 / 1452.7 · 30 / 33.6 | 100.00% (font) | FAIL | over 2%: y, h, font |
| footer.cta — Footer card email form / our button | — | 107.2 / 2280.6 / 175.6 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button | — | 114 / 703.5 / 260 / 124.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| col → footer | 192 | 192 | 0.0000% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### data-deletion @ 1440 — Ryze https://www.get-ryze.ai/facebook-data vs ours http://localhost:4320/en/data-deletion

Page height: Ryze 1024, ours 2019 (97.17%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (Ryze has none on this page) | — | 0 / 0 / 1440 / 57 · — / — | — | FAIL | we have it; Ryze has no such block |
| col — Text column | 208 / 184 / 1024 / 648 · 48 / 48 | 240 / 184 / 960 / 584.8 · 48 / 48 | 9.75% (h) | FAIL | over 2%: x, w, h |
| col.title — H1 | 240 / 184 / 960 / 96 · 48 / 48 | 240 / 184 / 960 / 48 · 48 / 48 | 50.00% (h) | FAIL | over 2%: h |
| col.lookup — Our deletion status lookup | — | 240 / 388 / 960 / 128.8 · — / — | — | FAIL | we have it; Ryze has no such block |
| col.h2 — First step heading | 240 / 408 / 960 / 32 · 24 / 32 | 240 / 540.8 / 960 / 32 · 24 / 32 | 12.97% (y) | FAIL | over 2%: y |
| footer — Footer (Ryze has none on this page) | — | 0 / 960.8 / 1440 / 1058.7 · 36 / 40.3 | — | FAIL | we have it; Ryze has no such block |
| float — Floating call-to-action (Ryze has none on this page) | — | — | — | n/a | shown on neither side at this width |
| whatsapp — Our WhatsApp button | — | 1164 / 751.5 / 260 / 132.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### data-deletion @ 390 — Ryze https://www.get-ryze.ai/facebook-data vs ours http://localhost:4320/en/data-deletion

Page height: Ryze 1312, ours 2696 (105.49%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation (Ryze has none on this page) | — | 0 / 0 / 390 / 57 · — / — | — | FAIL | we have it; Ryze has no such block |
| col — Text column | 0 / 136 / 390 / 984 · 30 / 36 | 16 / 136 / 358 / 915.8 · 30 / 36 | 8.21% (w) | FAIL | over 2%: x, w, h |
| col.title — H1 | 16 / 136 / 358 / 72 · 30 / 36 | 16 / 136 / 358 / 36 · 30 / 36 | 50.00% (h) | FAIL | over 2%: h |
| col.lookup — Our deletion status lookup | — | 16 / 400 / 358 / 155.8 · — / — | — | FAIL | we have it; Ryze has no such block |
| col.h2 — First step heading | 16 / 324 / 358 / 64 · 24 / 32 | 16 / 579.8 / 358 / 32 · 24 / 32 | 50.00% (h) | FAIL | over 2%: y, h |
| footer — Footer (Ryze has none on this page) | — | 0 / 1243.8 / 390 / 1452.7 · 30 / 33.6 | — | FAIL | we have it; Ryze has no such block |
| float — Floating call-to-action (Ryze has none on this page) | — | — | — | n/a | shown on neither side at this width |
| whatsapp — Our WhatsApp button | — | 114 / 703.5 / 260 / 124.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.
