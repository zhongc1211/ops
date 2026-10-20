# PIXEL — 2026-10-18T15:38:01.560Z

- command: node scripts/ryze-geom/run.mjs --mode pixel --twice --ours http://localhost:4318 --pages home,pricing --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/baseline-3e050d2/pixel
- ours: http://localhost:4318 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: whole page ≤ 0.01% differing pixels (a pixel differs when any channel is off by more than 12). Exempt blocks are blanked on both sides. Per-block rows are diagnostic.

| page | width | mode | result | detail |
|---|---|---|---|---|
| home | 1440 | pixel | FAIL | 62.46% of the page differs |
| home | 390 | pixel | FAIL | 72.88% of the page differs |
| pricing | 1440 | pixel | FAIL | 36.03% of the page differs |
| pricing | 390 | pixel | FAIL | 31.58% of the page differs |

### home @ 1440 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4318/en with Ryze text and pictures

Screens: Ryze 10, ours 11. Pictures still loading: Ryze 0, ours 0.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 1043191 | 80.49% | FAIL |
| 1 | 900 | 900 | 684695 | 52.83% | FAIL |
| 2 | 1800 | 1800 | 939371 | 72.48% | FAIL |
| 3 | 2700 | 2700 | 486321 | 37.52% | FAIL |
| 4 | 3600 | 3600 | 808374 | 62.37% | FAIL |
| 5 | 4500 | 4500 | 458661 | 35.39% | FAIL |
| 6 | 5400 | 5400 | 232231 | 17.92% | FAIL |
| 7 | 6300 | 6300 | 1160175 | 89.52% | FAIL |
| 8 | 7200 | 7200 | 842996 | 65.05% | FAIL |
| 9 | 7790 | 8100 | 951865 | 73.45% | FAIL |
| 10 | — | 8827 | 1296000 | 100% | FAIL (screen missing on Ryze) |

**Whole page: 8903880 of 14256000 px = 62.46% → FAIL** (limit 0.01%).

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 1440×58.5 | 0,0 1440×57 | — |  | 10/9, 0/1, 0/0, 3/0 |
| hero | 0,0 1440×900 | 0,0 1440×900 | 80.74% |  | 37/292, 0/20, 1/0, 0/13 |
| hero.cta | 55,574.1 373×49 | 68,721.2 495.5×48 | — | email-form | 2/1, 0/0, 0/0, 0/1 |
| strip | 0,900 1440×93.8 | 0,900 1440×210 | 99.98% |  | 1/1, 6/5, 0/0, 0/0 |
| twocol | 0,993.8 1440×447.6 | 0,1110 1440×661.5 | 47.96% |  | 9/2, 6/11, 0/0, 0/0 |
| wall | 0,1441.3 1440×1011.5 | 0,1771.5 1440×1689.1 | 74.80% |  | 20/26, 3/16, 0/0, 1/9 |
| logos | 0,2452.8 1440×624.5 | — | missing on ours |  | no block on our page |
| cards5 | 0,3077.3 1440×750.9 | 0,3460.6 1440×798.5 | 46.06% |  | 24/219, 4/2, 0/0, 0/2 |
| scan | 0,3828.2 1440×497 | 0,4259.1 1440×517.2 | 92.91% |  | 6/6, 0/1, 1/0, 0/1 |
| scan.cta | 654.8,4161.2 576×52 | 626.4,4616.3 178.8×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| three | 0,4325.2 1440×647 | 0,4776.3 1440×847.9 | 48.89% |  | 34/37, 12/18, 0/0, 0/4 |
| why | 0,4972.2 1440×647.5 | 0,5624.3 1440×614.2 | 14.88% |  | 17/17, 6/8, 0/0, 0/0 |
| list | 0,5619.7 1440×760 | 0,6238.4 1440×840.3 | 99.12% |  | 38/29, 0/0, 0/0, 0/24 |
| agency | 0,6379.7 1440×530 | 0,7078.8 1440×597.8 | 88.85% |  | 13/284, 1/7, 1/0, 0/44 |
| faq | 0,6909.7 1440×839 | 0,7676.6 1440×890.7 | 10.39% |  | 19/27, 0/0, 0/0, 8/8 |
| footer | 0,7748.7 1440×941 | 0,8567.3 1440×1160.2 | 91.97% |  | 38/39, 1/1, 1/0, 0/1 |
| footer.cta | 768,8270.1 384×52 | 879.3,9147.9 161.3×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| float | 1062.6,798 361.4×78 | — | missing on ours |  | no block on our page |
| whatsapp | — | 1368,828 56×56 | — | whatsapp | no Ryze content |

Repeat check (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 76 px = 0.0006%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0006%, ours 0.0000%.

### home @ 390 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4318/en with Ryze text and pictures

Screens: Ryze 12, ours 18. Pictures still loading: Ryze 0, ours 0.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 268606 | 81.60% | FAIL |
| 1 | 844 | 844 | 237057 | 72.02% | FAIL |
| 2 | 1688 | 1688 | 200157 | 60.81% | FAIL |
| 3 | 2532 | 2532 | 197336 | 59.95% | FAIL |
| 4 | 3376 | 3376 | 229899 | 69.84% | FAIL |
| 5 | 4220 | 4220 | 150574 | 45.74% | FAIL |
| 6 | 5064 | 5064 | 135229 | 41.08% | FAIL |
| 7 | 5908 | 5908 | 105725 | 32.12% | FAIL |
| 8 | 6752 | 6752 | 126839 | 38.53% | FAIL |
| 9 | 7596 | 7596 | 115558 | 35.11% | FAIL |
| 10 | 8440 | 8440 | 254681 | 77.37% | FAIL |
| 11 | 8938 | 9284 | 321314 | 97.62% | FAIL |
| 12 | — | 10128 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 13 | — | 10972 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 14 | — | 11816 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 15 | — | 12660 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 16 | — | 13504 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 17 | — | 14030 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page: 4317935 of 5924880 px = 72.88% → FAIL** (limit 0.01%).

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| hero | 0,0 390×844 | 0,0 390×1089.4 | 85.74% |  | 37/292, 0/20, 1/0, 0/13 |
| hero.cta | 24,326.5 342×46 | 24,397 342×48 | — | email-form | 2/1, 0/0, 0/0, 0/1 |
| strip | 0,844 390×72.1 | 0,1089.4 390×218.2 | 99.96% |  | 1/1, 6/4, 0/0, 0/0 |
| twocol | 0,916.1 390×554.5 | 0,1307.5 390×1015.4 | 67.99% |  | 9/2, 6/11, 0/0, 0/0 |
| wall | 0,1470.6 390×1228.4 | 0,2323 390×2260.8 | 79.47% |  | 12/14, 2/7, 0/0, 1/3 |
| logos | 0,2699 390×717 | — | missing on ours |  | no block on our page |
| cards5 | 0,3416 390×868.8 | 0,4583.8 390×1200.7 | 71.77% |  | 24/174, 4/2, 0/0, 0/1 |
| scan | 0,4284.7 390×414 | 0,5784.5 390×373.2 | 86.59% |  | 6/6, 0/0, 0/0, 0/1 |
| scan.cta | 24,4570.7 342×48 | 24,6045.6 178.8×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| three | 0,4698.7 390×1653.5 | 0,6157.6 390×2048 | 51.77% |  | 34/31, 12/18, 0/0, 0/4 |
| why | 0,6352.2 390×957 | 0,8205.6 390×1773.5 | 55.10% |  | 17/13, 6/2, 0/0, 0/0 |
| list | 0,7309.2 390×955.6 | 0,9979.1 390×1305.3 | 97.96% |  | 38/29, 0/0, 0/0, 0/24 |
| agency | 0,8264.9 390×599.4 | 0,11284.4 390×1185.1 | 95.53% |  | 13/284, 1/7, 1/0, 0/44 |
| faq | — | 0,12469.5 390×930.5 | missing on Ryze |  | no Ryze content |
| footer | 0,8864.3 390×917.8 | 0,13399.9 390×1474.5 | 98.46% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,13583.3 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | — | missing on ours |  | no block on our page |
| whatsapp | — | — | — | whatsapp | no Ryze content |

Repeat check (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 56 px = 0.0014%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0014%, ours 0.0000%.

### pricing @ 1440 — Ryze https://www.get-ryze.ai/pricing vs ours http://localhost:4318/en/pricing with Ryze text and pictures

Screens: Ryze 8, ours 9. Pictures still loading: Ryze 0, ours 0.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 744505 | 57.45% | FAIL |
| 1 | 900 | 900 | 94251 | 7.27% | FAIL |
| 2 | 1800 | 1800 | 183796 | 14.18% | FAIL |
| 3 | 2700 | 2700 | 180750 | 13.95% | FAIL |
| 4 | 3600 | 3600 | 176896 | 13.65% | FAIL |
| 5 | 4500 | 4500 | 153908 | 11.88% | FAIL |
| 6 | 5400 | 5400 | 258745 | 19.96% | FAIL |
| 7 | 6166 | 6300 | 1113997 | 85.96% | FAIL |
| 8 | — | 6667 | 1296000 | 100% | FAIL (screen missing on Ryze) |

**Whole page: 4202848 of 11664000 px = 36.03% → FAIL** (limit 0.01%).

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 1440×58.5 | 0,0 1440×57 | — |  | 10/9, 0/1, 0/0, 3/0 |
| hero | 0,0 1440×740 | 0,0 1440×798.6 | 91.23% |  | 6/5, 6/10, 1/0, 1/1 |
| hero.title | 92,291.6 780×149.3 | 60,215.2 760×149 | 92.12% |  | 1/1, 0/0, 0/0, 0/0 |
| hero.grid | 1008,180 340×340 | 1052,130.8 328×328 | 90.15% |  | 0/0, 6/9, 0/0, 1/1 |
| plans.billing | — | 60,498.6 1320×44 | — | billing-toggle | no Ryze content |
| plans.cards | 92,544 1256×773.1 | 60,562.6 1320×872.7 | — | three-tiers | 41/67, 0/0, 0/0, 0/27 |
| plans.annual | 92,1333.1 1256×77.5 | 60,1451.4 1320×82.8 | 23.56% |  | 4/5, 0/0, 0/0, 0/3 |
| compare | 60,1490.6 1320×1500 | 0,1598.1 1440×1790 | 32.83% |  | 80/90, 31/0, 0/0, 0/22 |
| agencies | 0,2990.6 1440×817.6 | 0,3388.1 1440×711.8 | 27.13% |  | 22/31, 0/0, 0/0, 0/0 |
| parts | 60,3808.2 1320×668 | 0,4099.9 1440×718.7 | 25.73% |  | 19/21, 0/0, 0/0, 0/6 |
| faq | 0,4476.2 1440×1274.6 | 0,4818.6 1440×1268.3 | 9.97% |  | 18/23, 0/0, 0/0, 0/0 |
| summary | 60,5750.8 1320×374 | 0,6086.9 1440×320.3 | 30.30% |  | 6/8, 0/0, 0/0, 0/0 |
| footer | 0,6124.8 1440×941 | 0,6407.2 1440×1160.2 | 91.95% |  | 38/39, 1/1, 1/0, 0/1 |
| footer.cta | 768,6646.2 384×52 | 879.3,6987.8 161.3×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| float | 1062.6,798 361.4×78 | — | missing on ours |  | no block on our page |
| whatsapp | — | 1368,828 56×56 | — | whatsapp | no Ryze content |

Repeat check (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

### pricing @ 390 — Ryze https://www.get-ryze.ai/pricing vs ours http://localhost:4318/en/pricing with Ryze text and pictures

Screens: Ryze 14, ours 15. Pictures still loading: Ryze 0, ours 0.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 180497 | 54.84% | FAIL |
| 1 | 844 | 844 | 17282 | 5.25% | FAIL |
| 2 | 1688 | 1688 | 16588 | 5.04% | FAIL |
| 3 | 2532 | 2532 | 17116 | 5.20% | FAIL |
| 4 | 3376 | 3376 | 81547 | 24.77% | FAIL |
| 5 | 4220 | 4220 | 51291 | 15.58% | FAIL |
| 6 | 5064 | 5064 | 58860 | 17.88% | FAIL |
| 7 | 5908 | 5908 | 81647 | 24.80% | FAIL |
| 8 | 6752 | 6752 | 58343 | 17.72% | FAIL |
| 9 | 7596 | 7596 | 53878 | 16.37% | FAIL |
| 10 | 8440 | 8440 | 69303 | 21.05% | FAIL |
| 11 | 9284 | 9284 | 71648 | 21.77% | FAIL |
| 12 | 10128 | 10128 | 156579 | 47.57% | FAIL |
| 13 | 10723 | 10972 | 315407 | 95.82% | FAIL |
| 14 | — | 11697 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page: 1559146 of 4937400 px = 31.58% → FAIL** (limit 0.01%).

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| hero | 0,0 390×538.6 | 0,0 390×773.9 | 98.55% |  | 7/6, 6/9, 1/0, 0/0 |
| hero.title | 16,192.5 358×136.1 | 24,199.2 342×132 | 90.79% |  | 1/1, 0/0, 0/0, 0/0 |
| hero.grid | — | — | missing on both |  | no Ryze content |
| plans.billing | — | 24,505.9 342×83.5 | — | billing-toggle | no Ryze content |
| plans.cards | 16,442.6 358×3129.6 | 24,609.4 342×2834.8 | — | three-tiers | 41/67, 0/0, 0/0, 0/27 |
| plans.annual | 16,3588.2 358×180 | 24,3460.2 342×216.7 | 37.70% |  | 4/5, 0/0, 0/0, 0/3 |
| compare | 0,3832.2 390×1607.3 | 0,3740.9 390×1980.4 | 32.51% |  | 37/90, 12/0, 0/0, 0/22 |
| agencies | 0,5439.5 390×1277.4 | 0,5721.3 390×1342.1 | 26.77% |  | 22/31, 0/0, 0/0, 0/0 |
| parts | 0,6716.9 390×1416.5 | 0,7063.5 390×1455.4 | 20.11% |  | 19/21, 0/0, 0/0, 0/6 |
| faq | 0,8133.4 390×1848.8 | 0,8518.8 390×1979.1 | 27.82% |  | 18/23, 0/0, 0/0, 0/0 |
| summary | 0,9982.3 390×666.5 | 0,10497.9 390×568.5 | 32.17% |  | 6/8, 0/0, 0/0, 0/0 |
| footer | 0,10648.8 390×917.8 | 0,11066.5 390×1474.5 | 98.55% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,11249.9 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | — | missing on ours |  | no block on our page |
| whatsapp | — | 326,780 48×48 | — | whatsapp | no Ryze content |

Repeat check (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.
