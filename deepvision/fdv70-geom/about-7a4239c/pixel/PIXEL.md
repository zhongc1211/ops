# PIXEL — 2026-10-18T16:39:39.368Z

- command: node scripts/ryze-geom/run.mjs --mode pixel --font-normalize --twice --ours http://localhost:4319 --pages about --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/about-7a4239c/pixel
- ours: http://localhost:4319 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: whole page ≤ 0.01% differing pixels (a pixel differs when any channel is off by more than 12), for each column. Exempt blocks are blanked on both sides. Per-block rows are diagnostic.
- fonts: "original" = each site with its own fonts; "one font" = every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4319/_next/static/media/e4af272ccee01ff0-s.p.woff2), taken from the same load right after the original shots

| page | width | pixel diff, original fonts | pixel diff, one font |
|---|---|---|---|
| about | 1440 | FAIL 25.22% | FAIL 25.29% |
| about | 390 | FAIL 37.67% | FAIL 36.48% |

### about @ 1440 — Ryze https://www.get-ryze.ai/about vs ours http://localhost:4319/en/about with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 5, ours 5.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 182771 | 14.10% | FAIL |
| 1 | 900 | 900 | 38735 | 2.99% | FAIL |
| 2 | 1800 | 1800 | 33241 | 2.56% | FAIL |
| 3 | 2700 | 2700 | 299284 | 23.09% | FAIL |
| 4 | 3399 | 3359 | 1080282 | 83.36% | FAIL |

**Whole page, original fonts: 1634313 of 6480000 px = 25.22% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 5, ours 5.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 184210 | 14.21% | FAIL |
| 1 | 900 | 900 | 40116 | 3.10% | FAIL |
| 2 | 1800 | 1800 | 34808 | 2.69% | FAIL |
| 3 | 2700 | 2700 | 299038 | 23.07% | FAIL |
| 4 | 3399 | 3339 | 1080845 | 83.40% | FAIL |

**Whole page, one font: 1639017 of 6480000 px = 25.29% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 1440×58.5 | 0,0 1440×57 | — |  | 10/9, 0/1, 0/0, 3/0 |
| label | 296,128 848×15 | 296,128 848×15 | 2.48% |  | 1/1, 0/0, 0/0, 0/0 |
| title | 296,191 848×136.8 | 296,191 848×136.8 | 0.0000% |  | 1/1, 0/0, 0/0, 0/0 |
| photo1 | 296,375.8 848×450.5 | 296,375.8 848×450.5 | 42.81% |  | 1/0, 1/1, 0/0, 0/0 |
| split1 | 296,922.3 848×325.3 | 296,922.3 848×325.3 | 0.0000% |  | 3/2, 1/1, 0/0, 0/0 |
| split2 | 296,1311.6 848×500 | 296,1311.6 848×500 | 0.0000% |  | 3/2, 1/1, 0/0, 0/0 |
| narrow | 296,1875.6 848×666 | 296,1875.6 848×666 | 0.32% |  | 3/3, 1/1, 0/0, 0/0 |
| end | 296,2605.6 848×142 | 296,2605.6 848×142 | 0.0000% |  | 2/2, 0/0, 0/0, 0/0 |
| marquee | 0,2747.6 1440×610 | 272,2747.6 896×351 | — | about-marquee | 6/0, 0/10, 0/0, 0/0 |
| footer | 0,3357.6 1440×941 | 0,3098.6 1440×1140.7 | 91.72% |  | 38/39, 1/1, 1/0, 0/1 |
| footer.cta | 768,3879 384×52 | 879.3,3669.5 161.3×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| float | 1049.2,798 374.8×78 | 1075.9,828 280.1×56 | — |  | 1/2, 0/1, 0/0, 0/0 |
| whatsapp | — | 1164,751.5 260×132.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

### about @ 390 — Ryze https://www.get-ryze.ai/about vs ours http://localhost:4319/en/about with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 5, ours 6.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 29901 | 9.08% | FAIL |
| 1 | 844 | 844 | 16812 | 5.11% | FAIL |
| 2 | 1688 | 1688 | 37880 | 11.51% | FAIL |
| 3 | 2532 | 2532 | 40914 | 12.43% | FAIL |
| 4 | 3269 | 3376 | 289365 | 87.91% | FAIL |
| 5 | — | 3717 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, original fonts: 744032 of 1974960 px = 37.67% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 5, ours 6.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 29929 | 9.09% | FAIL |
| 1 | 844 | 844 | 16009 | 4.86% | FAIL |
| 2 | 1688 | 1688 | 38910 | 11.82% | FAIL |
| 3 | 2532 | 2532 | 17629 | 5.36% | FAIL |
| 4 | 3366 | 3376 | 288905 | 87.77% | FAIL |
| 5 | — | 3795 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 720542 of 1974960 px = 36.48% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| label | 24,128 342×15 | 24,128 342×15 | 6.14% |  | 1/1, 0/0, 0/0, 0/0 |
| title | 24,191 342×102.6 | 24,191 342×102.6 | 0.0000% |  | 1/1, 0/0, 0/0, 0/0 |
| photo1 | 24,341.6 342×181.7 | 24,341.6 342×181.7 | 42.42% |  | 1/0, 1/1, 0/0, 0/0 |
| split1 | 24,619.3 342×650 | 24,619.3 342×650 | 0.71% |  | 3/2, 1/1, 0/0, 0/0 |
| split2 | 24,1333.3 342×670.5 | 24,1333.3 342×670.5 | 3.00% |  | 3/2, 1/1, 0/0, 0/0 |
| narrow | 24,2067.8 342×539.4 | 24,2067.8 342×539.4 | 2.45% |  | 3/3, 1/1, 0/0, 0/0 |
| end | 24,2671.1 342×161.5 | 24,2671.1 342×161.5 | 0.0000% |  | 2/2, 0/0, 0/0, 0/0 |
| marquee | 0,2832.6 390×460 | 0,2832.6 390×351 | — | about-marquee | 6/0, 0/10, 0/0, 0/0 |
| footer | 0,3292.6 390×917.8 | 0,3183.6 390×1455 | 98.50% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,3367 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | 158.2,802.4 147.6×43.2 | — |  | no block on our page |
| whatsapp | — | 114,703.5 260×124.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0002%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0002%, ours 0.0000%.
