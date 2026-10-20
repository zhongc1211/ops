# GEOM — 2026-10-18T17:52:31.341Z

- command: node scripts/ryze-geom/run.mjs --mode geom --font-normalize --twice --ours http://localhost:4320 --pages privacy --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/pr6-0058769/geom-privacy-h3
- ours: http://localhost:4320 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: any block's x, y, width, height, heading font size / line height, or a gap off by more than 2% fails. x and width are divided by the viewport width, y and gaps by Ryze's page height, height / font / line height by Ryze's value. Exempt only what exempt.json lists.
- fonts: one font, every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4320/_next/static/media/e4af272ccee01ff0-s.p.woff2)

| page | width | mode | result | detail |
|---|---|---|---|---|
| privacy | 1440 | geom | FAIL | 4 failing rows of 10 |
| privacy | 390 | geom | FAIL | 4 failing rows of 10 |

### privacy @ 1440 — Ryze https://www.get-ryze.ai/privacy vs ours http://localhost:4320/en/privacy

Page height: Ryze 6301, ours 2419 (61.61%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| col — Text column | 208 / 184 / 1024 / 4984 · 48 / 48 | 240 / 184 / 960 / 984 · 48 / 48 | 80.26% (h) | FAIL | over 2%: x, w, h |
| col.title — H1 | 240 / 184 / 960 / 48 · 48 / 48 | 240 / 184 / 960 / 48 · 48 / 48 | 0.0000% (x) | PASS |  |
| col.date — Last updated | 240 / 240 / 960 / 24 · — / — | 240 / 240 / 960 / 24 · — / — | 0.0000% (x) | PASS |  |
| col.h2 — First part heading | 240 / 312 / 960 / 32 · 24 / 32 | 240 / 392 / 960 / 32 · 24 / 32 | 1.27% (y) | PASS |  |
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
| col.h2 — First part heading | 16 / 204 / 358 / 32 · 24 / 32 | 16 / 404 / 358 / 32 · 24 / 32 | 1.74% (y) | PASS |  |
| footer — Footer | 0 / 10608 / 390 / 917.8 · — / — | 0 / 2016 / 390 / 1452.7 · 30 / 33.6 | 100.00% (font) | FAIL | over 2%: y, h, font |
| footer.cta — Footer card email form / our button | — | 107.2 / 2280.6 / 175.6 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button | — | 114 / 703.5 / 260 / 124.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| col → footer | 192 | 192 | 0.0000% | PASS |  |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.
