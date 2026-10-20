# GEOM — 2026-10-18T16:41:46.209Z

- command: node scripts/ryze-geom/run.mjs --mode geom --font-normalize --twice --ours http://localhost:4319 --pages about --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/about-7a4239c/geom
- ours: http://localhost:4319 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: any block's x, y, width, height, heading font size / line height, or a gap off by more than 2% fails. x and width are divided by the viewport width, y and gaps by Ryze's page height, height / font / line height by Ryze's value. Exempt only what exempt.json lists.
- fonts: one font, every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4319/_next/static/media/e4af272ccee01ff0-s.p.woff2)

| page | width | mode | result | detail |
|---|---|---|---|---|
| about | 1440 | geom | FAIL | 7 failing rows of 21 |
| about | 390 | geom | FAIL | 8 failing rows of 21 |

### about @ 1440 — Ryze https://www.get-ryze.ai/about vs ours http://localhost:4319/en/about

Page height: Ryze 4299, ours 4378 (1.84%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 1440 / 58.5 · — / — | 0 / 0 / 1440 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| label — #1 Label above the title | 296 / 128 / 848 / 15 · — / — | 296 / 128 / 848 / 15 · — / — | 0.0000% (x) | PASS |  |
| title — #1 H1 | 296 / 191 / 848 / 136.8 · 72 / 68.4 | 296 / 191 / 848 / 136.8 · 72 / 68.4 | 0.0000% (x) | PASS |  |
| photo1 — #1 Wide photo | 296 / 375.8 / 848 / 450.5 · — / — | 296 / 375.8 / 848 / 450.5 · — / — | 0.0000% (x) | PASS |  |
| split1 — #2 Text left, square photo right | 296 / 922.3 / 848 / 325.3 · — / — | 296 / 922.3 / 848 / 429 · — / — | 31.88% (h) | FAIL | over 2%: h |
| split2 — #3 Tall photo left, text right | 296 / 1311.6 / 848 / 500 · — / — | 296 / 1415.3 / 848 / 500 · — / — | 2.41% (y) | FAIL | over 2%: y |
| narrow — #4 Narrow column: text, landscape photo, caption | 296 / 1875.6 / 848 / 666 · — / — | 296 / 1979.3 / 848 / 783 · — / — | 17.57% (h) | FAIL | over 2%: y, h |
| end — #5 Closing lines | 296 / 2605.6 / 848 / 142 · — / — | 296 / 2826.3 / 848 / 142 · — / — | 5.13% (y) | FAIL | over 2%: y |
| marquee — #6 Ryze photo marquee / our company details | 0 / 2747.6 / 1440 / 610 · — / — | 272 / 2968.3 / 896 / 351 · 10 / 15 | 100.00% (font) | exempt | about-marquee: 营销 r2 删了跑马灯，Zack 23:06 接受和 Ryze 不同 (/about #6: Ryze's photo marquee; we keep the company details block instead). |
| footer — Footer | 0 / 3357.6 / 1440 / 941 · 38 / 34.2 | 0 / 3319.3 / 1440 / 1058.7 · 36 / 40.3 | 17.89% (lineHeight) | FAIL | over 2%: h, font, lineHeight |
| footer.cta — Footer card email form / our button | 768 / 3879 / 384 / 52 · — / — | 872.2 / 3890.9 / 175.6 / 48 · — / — | 14.47% (w) | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | 1049.2 / 798 / 374.8 / 78 · — / — | 1192 / 828 / 164 / 56 · — / — | 28.21% (h) | FAIL | over 2%: x, w, y, h |
| whatsapp — Our WhatsApp button | — | 1164 / 751.5 / 260 / 132.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| label → title | 48 | 48 | 0.0000% | PASS |  |
| title → photo1 | 48 | 48 | 0.0000% | PASS |  |
| photo1 → split1 | 96 | 96 | 0.0000% | PASS |  |
| split1 → split2 | 64 | 64 | 0.0000% | PASS |  |
| split2 → narrow | 64 | 64 | 0.0000% | PASS |  |
| narrow → end | 64 | 64 | 0.0000% | PASS |  |
| end → marquee | 0 | 0 | 0.0000% | PASS | next to exempt about-marquee (gap still judged) |
| marquee → footer | 0 | 0 | 0.0000% | PASS | next to exempt about-marquee (gap still judged) |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.

### about @ 390 — Ryze https://www.get-ryze.ai/about vs ours http://localhost:4319/en/about

Page height: Ryze 4210, ours 4981 (18.31%).

| block | Ryze x / y / w / h · font / line | ours x / y / w / h · font / line | max diff (which) | result | reason |
|---|---|---|---|---|---|
| nav — Top navigation | 0 / 0 / 390 / 58.5 · — / — | 0 / 0 / 390 / 57 · — / — | 2.56% (h) | FAIL | over 2%: h |
| label — #1 Label above the title | 24 / 128 / 342 / 15 · — / — | 24 / 128 / 342 / 15 · — / — | 0.0000% (x) | PASS |  |
| title — #1 H1 | 24 / 191 / 342 / 102.6 · 36 / 34.2 | 24 / 191 / 342 / 68.4 · 36 / 34.2 | 33.33% (h) | FAIL | over 2%: h |
| photo1 — #1 Wide photo | 24 / 341.6 / 342 / 181.7 · — / — | 24 / 307.4 / 342 / 181.7 · — / — | 0.81% (y) | PASS |  |
| split1 — #2 Text left, square photo right | 24 / 619.3 / 342 / 650 · — / — | 24 / 585.1 / 342 / 780 · — / — | 20.00% (h) | FAIL | over 2%: h |
| split2 — #3 Tall photo left, text right | 24 / 1333.3 / 342 / 670.5 · — / — | 24 / 1429.1 / 342 / 768 · — / — | 14.54% (h) | FAIL | over 2%: y, h |
| narrow — #4 Narrow column: text, landscape photo, caption | 24 / 2067.8 / 342 / 539.4 · — / — | 24 / 2261.1 / 342 / 681.9 · — / — | 26.42% (h) | FAIL | over 2%: y, h |
| end — #5 Closing lines | 24 / 2671.1 / 342 / 161.5 · — / — | 24 / 3006.9 / 342 / 194 · — / — | 20.12% (h) | FAIL | over 2%: y, h |
| marquee — #6 Ryze photo marquee / our company details | 0 / 2832.6 / 390 / 460 · — / — | 0 / 3200.9 / 390 / 351 · 10 / 15 | 100.00% (font) | exempt | about-marquee: 营销 r2 删了跑马灯，Zack 23:06 接受和 Ryze 不同 (/about #6: Ryze's photo marquee; we keep the company details block instead). |
| footer — Footer | 0 / 3292.6 / 390 / 917.8 · — / — | 0 / 3551.9 / 390 / 1428.9 · 30 / 33.6 | 100.00% (font) | FAIL | over 2%: y, h, font |
| footer.cta — Footer card email form / our button | — | 107.2 / 3792.7 / 175.6 / 48 · — / — | — | exempt | email-form: Buttons instead of Ryze's email forms: we have no email sign-up flow. |
| float — Floating call-to-action: Ryze banner / our sticky Book a demo | 12 / 804 / 366 / 52 · — / — | — | — | FAIL | Ryze shows it; ours is not visible |
| whatsapp — Our WhatsApp button | — | 114 / 703.5 / 260 / 124.5 · — / — | — | exempt | whatsapp: Our WhatsApp assistant button stays on every page. |

| gap between | Ryze | ours | diff | result | note |
|---|---|---|---|---|---|
| label → title | 48 | 48 | 0.0000% | PASS |  |
| title → photo1 | 48 | 48 | 0.0000% | PASS |  |
| photo1 → split1 | 96 | 96 | 0.0000% | PASS |  |
| split1 → split2 | 64 | 64 | 0.0000% | PASS |  |
| split2 → narrow | 64 | 64 | 0.0000% | PASS |  |
| narrow → end | 63.9 | 63.9 | 0.0000% | PASS |  |
| end → marquee | 0 | 0 | 0.0000% | PASS | next to exempt about-marquee (gap still judged) |
| marquee → footer | 0 | 0 | 0.0000% | PASS | next to exempt about-marquee (gap still judged) |

Repeat check (each side measured twice in fresh browsers): largest change Ryze 0 px, ours 0 px.
