# PIXEL — 2026-10-18T17:41:02.966Z

- command: node scripts/ryze-geom/run.mjs --mode pixel --font-normalize --twice --ours http://localhost:4320 --pages glossary,privacy,data-deletion --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/pr6-0058769/pixel
- ours: http://localhost:4320 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: whole page ≤ 0.01% differing pixels (a pixel differs when any channel is off by more than 12), for each column. Exempt blocks are blanked on both sides. Per-block rows are diagnostic.
- fonts: "original" = each site with its own fonts; "one font" = every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4320/_next/static/media/e4af272ccee01ff0-s.p.woff2), taken from the same load right after the original shots

| page | width | pixel diff, original fonts | pixel diff, one font |
|---|---|---|---|
| glossary | 1440 | FAIL 57.10% | FAIL 57.31% |
| glossary | 390 | FAIL 51.03% | FAIL 52.06% |
| privacy | 1440 | FAIL 86.33% | FAIL 90.21% |
| privacy | 390 | FAIL 95.83% | FAIL 96.18% |
| data-deletion | 1440 | FAIL 84.81% | FAIL 85.56% |
| data-deletion | 390 | FAIL 82.40% | FAIL 82.52% |

### glossary @ 1440 — Ryze https://www.get-ryze.ai/glossary vs ours http://localhost:4320/en/glossary with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 5, ours 4.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 414417 | 31.98% | FAIL |
| 1 | 900 | 900 | 195994 | 15.12% | FAIL |
| 2 | 1800 | 1800 | 703938 | 54.32% | FAIL |
| 3 | 2700 | 2586 | 1089586 | 84.07% | FAIL |
| 4 | 2932 | — | 1296000 | 100% | FAIL (screen missing on ours) |

**Whole page, original fonts: 3699935 of 6480000 px = 57.10% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 5, ours 4.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 421136 | 32.50% | FAIL |
| 1 | 900 | 900 | 199635 | 15.40% | FAIL |
| 2 | 1800 | 1800 | 708653 | 54.68% | FAIL |
| 3 | 2700 | 2567 | 1088407 | 83.98% | FAIL |
| 4 | 3071 | — | 1296000 | 100% | FAIL (screen missing on ours) |

**Whole page, one font: 3713831 of 6480000 px = 57.31% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 1440×58.5 | 0,0 1440×57 | — |  | 10/9, 0/1, 0/0, 3/0 |
| head | 0,0 1440×570.8 | 0,57 1440×503.2 | 53.82% |  | 8/14, 0/0, 0/0, 0/2 |
| head.crumbs | 68,150 1304×21 | 68,150 682×21 | 59.18% |  | 2/7, 0/0, 0/0, 0/0 |
| head.title | 68,239.5 682×54.6 | 68,240 682×54.6 | 17.29% |  | 1/1, 0/0, 0/0, 0/0 |
| head.lead | 814,211 558×303.8 | 814,211 558×292.2 | 89.22% |  | 4/4, 0/0, 0/0, 0/2 |
| head.lead.cta | 850,440.8 388.8×38 | 850,429.2 184.6×38 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| logos | 0,570.8 1440×118.3 | — | missing on ours |  | no block on our page |
| body | 290,689.1 940×2340.8 | 0,560.2 1440×1766 | 53.47% |  | 26/24, 0/0, 0/0, 0/0 |
| body.intro | 328,719.1 864×252 | — | missing on ours |  | no block on our page |
| body.terms | 328,971.1 864×683 | 328,590.2 864×1624 | 66.05% |  | 21/9, 0/0, 0/0, 0/0 |
| body.where | 328,1654.1 864×581.8 | — | missing on ours |  | no block on our page |
| body.faq | 328,2235.8 864×754 | — | missing on ours |  | no block on our page |
| promo | 68,711.4 222×519.7 | 68,590.2 240×281.1 | — |  | 5/12, 0/5, 0/0, 0/1 |
| promobar | — | — | missing on both |  | no Ryze content |
| footer | 0,3029.8 1440×941 | 0,2326.2 1440×1140.7 | 91.77% |  | 38/39, 1/1, 1/0, 0/1 |
| footer.cta | 768,3551.3 384×52 | 879.3,2897 161.3×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| float | 1049.2,798 374.8×78 | — | missing on ours |  | no block on our page |
| whatsapp | — | 1164,751.5 260×132.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

### glossary @ 390 — Ryze https://www.get-ryze.ai/glossary vs ours http://localhost:4320/en/glossary with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 8, ours 7.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 165749 | 50.36% | FAIL |
| 1 | 844 | 844 | 78229 | 23.77% | FAIL |
| 2 | 1688 | 1688 | 85782 | 26.06% | FAIL |
| 3 | 2532 | 2532 | 95411 | 28.99% | FAIL |
| 4 | 3376 | 3376 | 143638 | 43.64% | FAIL |
| 5 | 4220 | 4220 | 149233 | 45.34% | FAIL |
| 6 | 5064 | 5019 | 296550 | 90.09% | FAIL |
| 7 | 5168 | — | 329160 | 100% | FAIL (screen missing on ours) |

**Whole page, original fonts: 1343752 of 2633280 px = 51.03% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 8, ours 7.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 175694 | 53.38% | FAIL |
| 1 | 844 | 844 | 90646 | 27.54% | FAIL |
| 2 | 1688 | 1688 | 88454 | 26.87% | FAIL |
| 3 | 2532 | 2532 | 96090 | 29.19% | FAIL |
| 4 | 3376 | 3376 | 142047 | 43.15% | FAIL |
| 5 | 4220 | 4220 | 152810 | 46.42% | FAIL |
| 6 | 5064 | 5000 | 295971 | 89.92% | FAIL |
| 7 | 5441 | — | 329160 | 100% | FAIL (screen missing on ours) |

**Whole page, one font: 1370872 of 2633280 px = 52.06% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| head | 0,0 390×918.5 | 0,57 390×716.7 | 70.03% |  | 8/14, 0/0, 0/0, 0/2 |
| head.crumbs | 24,150 342×50 | 24,150 342×21 | 74.90% |  | 2/7, 0/0, 0/0, 0/0 |
| head.title | 24,268.5 342×75.6 | 24,240 342×75.6 | 9.45% |  | 1/1, 0/0, 0/0, 0/0 |
| head.lead | 24,607.3 342×255.2 | 24,411.5 342×305.2 | 83.42% |  | 4/4, 0/0, 0/0, 0/2 |
| head.lead.cta | 40,808.5 310×38 | 60,642.7 184.6×38 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| logos | 0,918.5 390×425.4 | — | missing on ours |  | no block on our page |
| body | 40,1343.9 390×4023.8 | 0,773.7 390×3615 | 43.57% |  | 21/24, 0/0, 0/0, 0/0 |
| body.intro | 64,1373.9 342×508 | — | missing on ours |  | no block on our page |
| body.terms | 64,1881.9 342×1167.5 | 24,803.7 342×3473 | 76.40% |  | 21/9, 0/0, 0/0, 0/0 |
| body.where | 64,3049.4 342×1058.3 | — | missing on ours |  | no block on our page |
| body.faq | 64,4107.6 342×1220 | — | missing on ours |  | no block on our page |
| promo | — | — | missing on both |  | no Ryze content |
| promobar | 0,866 390×73.5 | 12,689.3 366×74.7 | — |  | 2/3, 0/0, 0/0, 1/1 |
| footer | 0,5367.6 390×917.8 | 0,4388.7 390×1455 | 98.50% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,4572.1 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | — | missing on ours |  | no block on our page |
| whatsapp | — | 114,703.5 260×124.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

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
| col.h2 | — | 240,364 960×192 | missing on Ryze |  | no Ryze content |
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
| col.h2 | — | 16,264 358×512 | missing on Ryze |  | no Ryze content |
| footer | 0,10608 390×917.8 | 0,2512 390×1455 | 98.36% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,2695.4 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | — | missing on ours |  | no block on our page |
| whatsapp | — | 114,703.5 260×124.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

### data-deletion @ 1440 — Ryze https://www.get-ryze.ai/facebook-data vs ours http://localhost:4320/en/data-deletion with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 2, ours 3.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 962705 | 74.28% | FAIL |
| 1 | 68 | 900 | 1038839 | 80.16% | FAIL |
| 2 | — | 1116 | 1296000 | 100% | FAIL (screen missing on Ryze) |

**Whole page, original fonts: 3297544 of 3888000 px = 84.81% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 2, ours 3.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 992462 | 76.58% | FAIL |
| 1 | 124 | 900 | 1038075 | 80.10% | FAIL |
| 2 | — | 1116 | 1296000 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 3326537 of 3888000 px = 85.56% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | — | 0,0 1440×57 | missing on Ryze |  | no Ryze content |
| col | 208,184 1024×648 | 240,184 960×496.8 | 82.03% |  | 7/13, 0/0, 0/0, 0/0 |
| col.title | 240,184 960×96 | 240,184 960×96 | 74.86% |  | 1/1, 0/0, 0/0, 0/0 |
| col.lookup | — | 240,408 960×128.8 | missing on Ryze |  | no Ryze content |
| col.h2 | 240,408 960×32 | 240,560.8 960×32 | 70.98% |  | 1/1, 0/0, 0/0, 0/0 |
| footer | — | 0,957 1440×1058.7 | missing on Ryze |  | no Ryze content |
| float | — | — | missing on both |  | no Ryze content |
| whatsapp | — | 1164,751.5 260×132.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

### data-deletion @ 390 — Ryze https://www.get-ryze.ai/facebook-data vs ours http://localhost:4320/en/data-deletion with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 2, ours 3.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 229011 | 69.57% | FAIL |
| 1 | 476 | 844 | 255491 | 77.62% | FAIL |
| 2 | — | 1510 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, original fonts: 813662 of 987480 px = 82.40% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 2, ours 3.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 228947 | 69.55% | FAIL |
| 1 | 468 | 844 | 256724 | 77.99% | FAIL |
| 2 | — | 1510 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 814831 of 987480 px = 82.52% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | — | 0,0 390×57 | missing on Ryze |  | no Ryze content |
| col | 0,136 390×984 | 16,136 358×571.8 | 86.80% |  | 7/13, 0/0, 0/0, 0/0 |
| col.title | 16,136 358×72 | 16,136 358×72 | 75.96% |  | 1/1, 0/0, 0/0, 0/0 |
| col.lookup | — | 16,324 358×155.8 | missing on Ryze |  | no Ryze content |
| col.h2 | 16,324 358×64 | 16,503.8 358×64 | 70.03% |  | 1/1, 0/0, 0/0, 0/0 |
| footer | — | 0,901 390×1452.7 | missing on Ryze |  | no Ryze content |
| float | — | — | missing on both |  | no Ryze content |
| whatsapp | — | 114,703.5 260×124.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.
