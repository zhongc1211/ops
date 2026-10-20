# PIXEL — 2026-10-18T17:55:47.620Z

- command: node scripts/ryze-geom/run.mjs --mode pixel --font-normalize --ours http://localhost:4321 --pages about --widths 390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/accept-61734b7/before
- ours: http://localhost:4321 (locale en); Ryze: https://www.get-ryze.ai
- widths: 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: whole page ≤ 0.01% differing pixels (a pixel differs when any channel is off by more than 12), for each column. Exempt blocks are blanked on both sides. Per-block rows are diagnostic.
- fonts: "original" = each site with its own fonts; "one font" = every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4321/_next/static/media/e4af272ccee01ff0-s.p.woff2), taken from the same load right after the original shots

| page | width | pixel diff, original fonts | pixel diff, one font |
|---|---|---|---|
| about | 390 | FAIL 36.38% | FAIL 35.19% |

### about @ 390 — Ryze https://www.get-ryze.ai/about vs ours http://localhost:4321/en/about with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 5, ours 6.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 4325 | 1.31% | FAIL |
| 1 | 844 | 844 | 16812 | 5.11% | FAIL |
| 2 | 1688 | 1688 | 37880 | 11.51% | FAIL |
| 3 | 2532 | 2532 | 40914 | 12.43% | FAIL |
| 4 | 3269 | 3376 | 289365 | 87.91% | FAIL |
| 5 | — | 3717 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, original fonts: 718456 of 1974960 px = 36.38% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 5, ours 6.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 4353 | 1.32% | FAIL |
| 1 | 844 | 844 | 16009 | 4.86% | FAIL |
| 2 | 1688 | 1688 | 38910 | 11.82% | FAIL |
| 3 | 2532 | 2532 | 17629 | 5.36% | FAIL |
| 4 | 3366 | 3376 | 288905 | 87.77% | FAIL |
| 5 | — | 3795 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 694966 of 1974960 px = 35.19% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| label | 24,128 342×15 | 24,128 342×15 | 6.14% |  | 1/1, 0/0, 0/0, 0/0 |
| title | 24,191 342×102.6 | 24,191 342×102.6 | 0.0000% |  | 1/1, 0/0, 0/0, 0/0 |
| photo1 | 24,341.6 342×181.7 | 24,341.6 342×181.7 | 0.53% |  | 1/0, 1/1, 0/0, 0/0 |
| split1 | 24,619.3 342×650 | 24,619.3 342×650 | 0.71% |  | 3/2, 1/1, 0/0, 0/0 |
| split2 | 24,1333.3 342×670.5 | 24,1333.3 342×670.5 | 3.00% |  | 3/2, 1/1, 0/0, 0/0 |
| narrow | 24,2067.8 342×539.4 | 24,2067.8 342×539.4 | 2.45% |  | 3/3, 1/1, 0/0, 0/0 |
| end | 24,2671.1 342×161.5 | 24,2671.1 342×161.5 | 0.0000% |  | 2/2, 0/0, 0/0, 0/0 |
| marquee | 0,2832.6 390×460 | 0,2832.6 390×351 | — | about-marquee | 6/0, 0/10, 0/0, 0/0 |
| footer | 0,3292.6 390×917.8 | 0,3183.6 390×1455 | 98.50% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,3367 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | 158.2,802.4 147.6×43.2 | — |  | no block on our page |
| whatsapp | — | 114,703.5 260×124.5 | — | whatsapp | no Ryze content |
