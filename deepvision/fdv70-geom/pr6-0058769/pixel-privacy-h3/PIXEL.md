# PIXEL — 2026-10-18T17:51:00.408Z

- command: node scripts/ryze-geom/run.mjs --mode pixel --font-normalize --twice --ours http://localhost:4320 --pages privacy --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/pr6-0058769/pixel-privacy-h3
- ours: http://localhost:4320 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: whole page ≤ 0.01% differing pixels (a pixel differs when any channel is off by more than 12), for each column. Exempt blocks are blanked on both sides. Per-block rows are diagnostic.
- fonts: "original" = each site with its own fonts; "one font" = every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4320/_next/static/media/e4af272ccee01ff0-s.p.woff2), taken from the same load right after the original shots

| page | width | pixel diff, original fonts | pixel diff, one font |
|---|---|---|---|
| privacy | 1440 | FAIL 86.33% | FAIL 90.21% |
| privacy | 390 | FAIL 95.83% | FAIL 96.18% |

### privacy @ 1440 — Ryze https://www.get-ryze.ai/privacy vs ours http://localhost:4320/en/privacy with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 7, ours 4.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 874764 | 67.50% | FAIL |
| 1 | 900 | 900 | 943706 | 72.82% | FAIL |
| 2 | 1800 | 1800 | 1046668 | 80.76% | FAIL |
| 3 | 2700 | 1816 | 1078737 | 83.24% | FAIL |
| 4 | 3600 | — | 1296000 | 100% | FAIL (screen missing on ours) |
| 5 | 4500 | — | 1296000 | 100% | FAIL (screen missing on ours) |
| 6 | 5289 | — | 1296000 | 100% | FAIL (screen missing on ours) |

**Whole page, original fonts: 7831875 of 9072000 px = 86.33% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 8, ours 3.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 884179 | 68.22% | FAIL |
| 1 | 900 | 900 | 940236 | 72.55% | FAIL |
| 2 | 1800 | 1797 | 1049041 | 80.94% | FAIL |
| 3 | 2700 | — | 1296000 | 100% | FAIL (screen missing on ours) |
| 4 | 3600 | — | 1296000 | 100% | FAIL (screen missing on ours) |
| 5 | 4500 | — | 1296000 | 100% | FAIL (screen missing on ours) |
| 6 | 5400 | — | 1296000 | 100% | FAIL (screen missing on ours) |
| 7 | 5401 | — | 1296000 | 100% | FAIL (screen missing on ours) |

**Whole page, one font: 9353456 of 10368000 px = 90.21% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 1440×58.5 | 0,0 1440×57 | — |  | 10/9, 0/1, 0/0, 3/0 |
| col | 208,184 1024×4984 | 240,184 960×1180 | 94.53% |  | 15/141, 0/0, 0/0, 0/0 |
| col.title | 240,184 960×48 | 240,184 960×48 | 76.41% |  | 1/1, 0/0, 0/0, 0/0 |
| col.date | 240,240 960×24 | 240,240 960×24 | 72.76% |  | 1/1, 0/0, 0/0, 0/0 |
| col.h2 | 240,312 960×32 | 240,364 960×192 | 96.25% |  | no Ryze content |
| footer | 0,5360 1440×941 | 0,1556 1440×1140.7 | 91.65% |  | 38/39, 1/1, 1/0, 0/1 |
| footer.cta | 768,5881.4 384×52 | 879.3,2126.9 161.3×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| float | 1049.2,798 374.8×78 | — | missing on ours |  | no block on our page |
| whatsapp | — | 1164,751.5 260×132.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

### privacy @ 390 — Ryze https://www.get-ryze.ai/privacy vs ours http://localhost:4320/en/privacy with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 13, ours 5.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 296499 | 90.08% | FAIL |
| 1 | 844 | 844 | 295516 | 89.78% | FAIL |
| 2 | 1688 | 1688 | 291462 | 88.55% | FAIL |
| 3 | 2532 | 2532 | 289157 | 87.85% | FAIL |
| 4 | 3376 | 3143 | 294789 | 89.56% | FAIL |
| 5 | 4220 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 6 | 5064 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 7 | 5908 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 8 | 6752 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 9 | 7596 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 10 | 8440 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 11 | 9284 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 12 | 9870 | — | 329160 | 100% | FAIL (screen missing on ours) |

**Whole page, original fonts: 4100703 of 4279080 px = 95.83% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 14, ours 5.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 295907 | 89.90% | FAIL |
| 1 | 844 | 844 | 295385 | 89.74% | FAIL |
| 2 | 1688 | 1688 | 292431 | 88.84% | FAIL |
| 3 | 2532 | 2532 | 289779 | 88.04% | FAIL |
| 4 | 3376 | 3123 | 296425 | 90.05% | FAIL |
| 5 | 4220 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 6 | 5064 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 7 | 5908 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 8 | 6752 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 9 | 7596 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 10 | 8440 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 11 | 9284 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 12 | 10128 | — | 329160 | 100% | FAIL (screen missing on ours) |
| 13 | 10682 | — | 329160 | 100% | FAIL (screen missing on ours) |

**Whole page, one font: 4432367 of 4608240 px = 96.18% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| col | 0,136 390×10280 | 16,136 358×2184 | 99.99% |  | 15/141, 0/0, 0/0, 0/0 |
| col.title | 16,136 358×36 | 16,136 358×36 | 99.57% |  | 1/1, 0/0, 0/0, 0/0 |
| col.date | 16,180 358×24 | 16,180 358×24 | 92.71% |  | 1/1, 0/0, 0/0, 0/0 |
| col.h2 | 16,204 358×32 | 16,264 358×512 | 99.99% |  | no Ryze content |
| footer | 0,10608 390×917.8 | 0,2512 390×1455 | 98.36% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,2695.4 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | — | missing on ours |  | no block on our page |
| whatsapp | — | 114,703.5 260×124.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.
