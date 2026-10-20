# PIXEL — 2026-10-18T16:33:21.708Z

- command: node scripts/ryze-geom/run.mjs --mode pixel --font-normalize --twice --ours http://localhost:4318 --pages home,pricing --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/baseline-3e050d2-font/pixel
- ours: http://localhost:4318 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: whole page ≤ 0.01% differing pixels (a pixel differs when any channel is off by more than 12), for each column. Exempt blocks are blanked on both sides. Per-block rows are diagnostic.
- fonts: "original" = each site with its own fonts; "one font" = every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4318/_next/static/media/e4af272ccee01ff0-s.p.woff2), taken from the same load right after the original shots

| page | width | pixel diff, original fonts | pixel diff, one font |
|---|---|---|---|
| home | 1440 | FAIL 62.46% | FAIL 60.53% |
| home | 390 | FAIL 72.94% | FAIL 69.92% |
| pricing | 1440 | FAIL 36.03% | FAIL 34.57% |
| pricing | 390 | FAIL 31.58% | FAIL 27.77% |

### home @ 1440 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4318/en with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 10, ours 11.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 1043191 | 80.49% | FAIL |
| 1 | 900 | 900 | 684695 | 52.83% | FAIL |
| 2 | 1800 | 1800 | 939371 | 72.48% | FAIL |
| 3 | 2700 | 2700 | 486315 | 37.52% | FAIL |
| 4 | 3600 | 3600 | 808374 | 62.37% | FAIL |
| 5 | 4500 | 4500 | 458661 | 35.39% | FAIL |
| 6 | 5400 | 5400 | 232231 | 17.92% | FAIL |
| 7 | 6300 | 6300 | 1160175 | 89.52% | FAIL |
| 8 | 7200 | 7200 | 842996 | 65.05% | FAIL |
| 9 | 7790 | 8100 | 951865 | 73.45% | FAIL |
| 10 | — | 8827 | 1296000 | 100% | FAIL (screen missing on Ryze) |

**Whole page, original fonts: 8903874 of 14256000 px = 62.46% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 10, ours 11.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 1011718 | 78.06% | FAIL |
| 1 | 900 | 900 | 657633 | 50.74% | FAIL |
| 2 | 1800 | 1800 | 917782 | 70.82% | FAIL |
| 3 | 2700 | 2700 | 454708 | 35.09% | FAIL |
| 4 | 3600 | 3600 | 784547 | 60.54% | FAIL |
| 5 | 4500 | 4500 | 457832 | 35.33% | FAIL |
| 6 | 5400 | 5400 | 218358 | 16.85% | FAIL |
| 7 | 6300 | 6300 | 1128817 | 87.10% | FAIL |
| 8 | 7200 | 7200 | 780373 | 60.21% | FAIL |
| 9 | 7835 | 8100 | 921035 | 71.07% | FAIL |
| 10 | — | 8808 | 1296000 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 8628803 of 14256000 px = 60.53% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 1440×58.5 | 0,0 1440×57 | — |  | 10/9, 0/1, 0/0, 3/0 |
| hero | 0,0 1440×900 | 0,0 1440×900 | 80.73% |  | 37/292, 0/20, 1/0, 0/13 |
| hero.cta | 55,574.1 373×49 | 68,721.2 495.5×48 | — | email-form | 2/1, 0/0, 0/0, 0/1 |
| strip | 0,900 1440×93.8 | 0,900 1440×210 | 99.98% |  | 1/1, 6/5, 0/0, 0/0 |
| twocol | 0,993.8 1440×447.6 | 0,1110 1440×661.5 | 48.07% |  | 9/2, 6/11, 0/0, 0/0 |
| wall | 0,1441.3 1440×1028 | 0,1771.5 1440×1689.1 | 74.65% |  | 20/26, 3/16, 0/0, 1/9 |
| logos | 0,2469.3 1440×624.5 | — | missing on ours |  | no block on our page |
| cards5 | 0,3093.8 1440×750.9 | 0,3460.6 1440×798.5 | 46.34% |  | 24/219, 4/2, 0/0, 0/2 |
| scan | 0,3844.7 1440×497 | 0,4259.1 1440×517.2 | 91.12% |  | 6/6, 0/1, 1/0, 0/1 |
| scan.cta | 654.8,4177.7 576×52 | 626.4,4616.3 178.8×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| three | 0,4341.7 1440×647 | 0,4776.3 1440×847.9 | 49.26% |  | 34/37, 12/18, 0/0, 0/4 |
| why | 0,4988.7 1440×647.5 | 0,5624.3 1440×614.2 | 14.14% |  | 17/17, 6/8, 0/0, 0/0 |
| list | 0,5636.2 1440×760 | 0,6238.4 1440×840.3 | 99.11% |  | 38/29, 0/0, 0/0, 0/24 |
| agency | 0,6396.2 1440×558.5 | 0,7078.8 1440×597.8 | 86.72% |  | 13/284, 1/7, 1/0, 0/44 |
| faq | 0,6954.7 1440×839 | 0,7676.6 1440×890.7 | 10.43% |  | 19/27, 0/0, 0/0, 8/8 |
| footer | 0,7793.7 1440×941 | 0,8567.3 1440×1140.7 | 89.55% |  | 38/39, 1/1, 1/0, 0/1 |
| footer.cta | 768,8315.2 384×52 | 879.3,9138.2 161.3×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| float | 1049.2,798 374.8×78 | 1200.2,850.8 147.6×50.4 | — |  | no block on our page |
| whatsapp | — | 1164,751.5 260×132.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

### home @ 390 — Ryze https://www.get-ryze.ai/ vs ours http://localhost:4318/en with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 12, ours 18.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 268606 | 81.60% | FAIL |
| 1 | 844 | 844 | 237057 | 72.02% | FAIL |
| 2 | 1688 | 1688 | 200157 | 60.81% | FAIL |
| 3 | 2532 | 2532 | 197336 | 59.95% | FAIL |
| 4 | 3376 | 3376 | 233314 | 70.88% | FAIL |
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

**Whole page, original fonts: 4321350 of 5924880 px = 72.94% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 12, ours 18.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 248666 | 75.55% | FAIL |
| 1 | 844 | 844 | 218575 | 66.40% | FAIL |
| 2 | 1688 | 1688 | 183811 | 55.84% | FAIL |
| 3 | 2532 | 2532 | 182735 | 55.52% | FAIL |
| 4 | 3376 | 3376 | 218999 | 66.53% | FAIL |
| 5 | 4220 | 4220 | 131015 | 39.80% | FAIL |
| 6 | 5064 | 5064 | 123890 | 37.64% | FAIL |
| 7 | 5908 | 5908 | 105960 | 32.19% | FAIL |
| 8 | 6752 | 6752 | 117242 | 35.62% | FAIL |
| 9 | 7596 | 7596 | 96833 | 29.42% | FAIL |
| 10 | 8440 | 8440 | 236774 | 71.93% | FAIL |
| 11 | 9003 | 9284 | 303114 | 92.09% | FAIL |
| 12 | — | 10128 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 13 | — | 10972 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 14 | — | 11816 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 15 | — | 12660 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 16 | — | 13504 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 17 | — | 14011 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 4142574 of 5924880 px = 69.92% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| hero | 0,0 390×844 | 0,0 390×1089.4 | 85.52% |  | 37/292, 0/20, 1/0, 0/13 |
| hero.cta | 24,326.5 342×46 | 24,397 342×48 | — | email-form | 2/1, 0/0, 0/0, 0/1 |
| strip | 0,844 390×72.1 | 0,1089.4 390×218.2 | 99.96% |  | 1/1, 6/4, 0/0, 0/0 |
| twocol | 0,916.1 390×554.5 | 0,1307.5 390×1015.4 | 68.23% |  | 9/2, 6/11, 0/0, 0/0 |
| wall | 0,1470.6 390×1228.4 | 0,2323 390×2260.8 | 79.68% |  | 12/14, 2/7, 0/0, 1/3 |
| logos | 0,2699 390×717 | — | missing on ours |  | no block on our page |
| cards5 | 0,3416 390×868.8 | 0,4583.8 390×1200.7 | 71.99% |  | 24/174, 4/2, 0/0, 0/1 |
| scan | 0,4284.7 390×434 | 0,5784.5 390×373.2 | 85.09% |  | 6/6, 0/0, 0/0, 0/1 |
| scan.cta | 24,4590.7 342×48 | 24,6045.6 178.8×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| three | 0,4718.7 390×1653.5 | 0,6157.6 390×2048 | 52.01% |  | 34/31, 12/18, 0/0, 0/4 |
| why | 0,6372.2 390×957 | 0,8205.6 390×1773.5 | 55.44% |  | 17/13, 6/2, 0/0, 0/0 |
| list | 0,7329.2 390×955.6 | 0,9979.1 390×1305.3 | 98.00% |  | 38/29, 0/0, 0/0, 0/24 |
| agency | 0,8284.9 390×644.4 | 0,11284.4 390×1185.1 | 94.85% |  | 13/284, 1/7, 1/0, 0/44 |
| faq | — | 0,12469.5 390×930.5 | missing on Ryze |  | no Ryze content |
| footer | 0,8929.3 390×917.8 | 0,13399.9 390×1455 | 98.47% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,13583.3 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | 158.2,802.4 147.6×43.2 | — |  | no block on our page |
| whatsapp | — | 114,763.5 260×64.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 34 px = 0.0009%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0009%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 37 px = 0.0009%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0009%, ours 0.0000%.

### pricing @ 1440 — Ryze https://www.get-ryze.ai/pricing vs ours http://localhost:4318/en/pricing with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 8, ours 9.

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

**Whole page, original fonts: 4202848 of 11664000 px = 36.03% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 8, ours 9.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 739495 | 57.06% | FAIL |
| 1 | 900 | 900 | 83949 | 6.48% | FAIL |
| 2 | 1800 | 1800 | 176947 | 13.65% | FAIL |
| 3 | 2700 | 2700 | 164058 | 12.66% | FAIL |
| 4 | 3600 | 3600 | 168317 | 12.99% | FAIL |
| 5 | 4500 | 4500 | 140953 | 10.88% | FAIL |
| 6 | 5400 | 5400 | 182178 | 14.06% | FAIL |
| 7 | 6284 | 6300 | 1080867 | 83.40% | FAIL |
| 8 | — | 6648 | 1296000 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 4032764 of 11664000 px = 34.57% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 1440×58.5 | 0,0 1440×57 | — |  | 10/9, 0/1, 0/0, 3/0 |
| hero | 0,0 1440×740 | 0,0 1440×798.6 | 91.20% |  | 6/5, 6/10, 1/0, 1/1 |
| hero.title | 92,291.6 780×149.3 | 60,215.2 760×149 | 79.47% |  | 1/1, 0/0, 0/0, 0/0 |
| hero.grid | 1008,180 340×340 | 1052,130.8 328×328 | 90.15% |  | 0/0, 6/9, 0/0, 1/1 |
| plans.billing | — | 60,498.6 1320×44 | — | billing-toggle | no Ryze content |
| plans.cards | 92,544 1256×802.6 | 60,562.6 1320×872.7 | — | three-tiers | 41/67, 0/0, 0/0, 0/27 |
| plans.annual | 92,1362.6 1256×77.5 | 60,1451.4 1320×82.8 | 25.75% |  | 4/5, 0/0, 0/0, 0/3 |
| compare | 60,1520.1 1320×1540 | 0,1598.1 1440×1790 | 30.60% |  | 80/90, 31/0, 0/0, 0/22 |
| agencies | 0,3060.2 1440×843.5 | 0,3388.1 1440×711.8 | 29.55% |  | 22/31, 0/0, 0/0, 0/0 |
| parts | 60,3903.7 1320×690.8 | 0,4099.9 1440×718.7 | 23.50% |  | 19/21, 0/0, 0/0, 0/6 |
| faq | 0,4594.5 1440×1274.6 | 0,4818.6 1440×1268.3 | 10.94% |  | 18/23, 0/0, 0/0, 0/0 |
| summary | 60,5869 1320×374 | 0,6086.9 1440×320.3 | 29.99% |  | 6/8, 0/0, 0/0, 0/0 |
| footer | 0,6243 1440×941 | 0,6407.2 1440×1140.7 | 91.70% |  | 38/39, 1/1, 1/0, 0/1 |
| footer.cta | 768,6764.5 384×52 | 879.3,6978 161.3×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| float | 1049.2,798 374.8×78 | 1200.2,850.8 147.6×50.4 | — |  | no block on our page |
| whatsapp | — | 1164,751.5 260×132.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

### pricing @ 390 — Ryze https://www.get-ryze.ai/pricing vs ours http://localhost:4318/en/pricing with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 14, ours 15.

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

**Whole page, original fonts: 1559146 of 4937400 px = 31.58% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 14, ours 15.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 178940 | 54.36% | FAIL |
| 1 | 844 | 844 | 17282 | 5.25% | FAIL |
| 2 | 1688 | 1688 | 16614 | 5.05% | FAIL |
| 3 | 2532 | 2532 | 17116 | 5.20% | FAIL |
| 4 | 3376 | 3376 | 64409 | 19.57% | FAIL |
| 5 | 4220 | 4220 | 43960 | 13.36% | FAIL |
| 6 | 5064 | 5064 | 48194 | 14.64% | FAIL |
| 7 | 5908 | 5908 | 74150 | 22.53% | FAIL |
| 8 | 6752 | 6752 | 53768 | 16.33% | FAIL |
| 9 | 7596 | 7596 | 47220 | 14.35% | FAIL |
| 10 | 8440 | 8440 | 61357 | 18.64% | FAIL |
| 11 | 9284 | 9284 | 66669 | 20.25% | FAIL |
| 12 | 10128 | 10128 | 67338 | 20.46% | FAIL |
| 13 | 10941 | 10972 | 284845 | 86.54% | FAIL |
| 14 | — | 11678 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 1371022 of 4937400 px = 27.77% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| hero | 0,0 390×538.6 | 0,0 390×773.9 | 98.03% |  | 7/6, 6/9, 1/0, 0/0 |
| hero.title | 16,192.5 358×136.1 | 24,199.2 342×132 | 92.08% |  | 1/1, 0/0, 0/0, 0/0 |
| hero.grid | — | — | missing on both |  | no Ryze content |
| plans.billing | — | 24,505.9 342×83.5 | — | billing-toggle | no Ryze content |
| plans.cards | 16,442.6 358×3149.2 | 24,609.4 342×2834.8 | — | three-tiers | 41/67, 0/0, 0/0, 0/27 |
| plans.annual | 16,3607.8 358×202.8 | 24,3460.2 342×216.7 | 30.28% |  | 4/5, 0/0, 0/0, 0/3 |
| compare | 0,3874.5 390×1651 | 0,3740.9 390×1980.4 | 31.83% |  | 37/90, 12/0, 0/0, 0/22 |
| agencies | 0,5525.5 390×1299.9 | 0,5721.3 390×1342.1 | 26.51% |  | 22/31, 0/0, 0/0, 0/0 |
| parts | 0,6825.5 390×1416.5 | 0,7063.5 390×1455.4 | 21.93% |  | 19/21, 0/0, 0/0, 0/6 |
| faq | 0,8242 390×1958.6 | 0,8518.8 390×1979.1 | 22.34% |  | 18/23, 0/0, 0/0, 0/0 |
| summary | 0,10200.6 390×666.5 | 0,10497.9 390×568.5 | 33.60% |  | 6/8, 0/0, 0/0, 0/0 |
| footer | 0,10867.1 390×917.8 | 0,11066.5 390×1455 | 98.45% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,11249.9 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | 158.2,802.4 147.6×43.2 | — |  | no block on our page |
| whatsapp | — | 114,703.5 260×124.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.
