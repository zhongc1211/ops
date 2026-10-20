# PIXEL — 2026-10-18T18:07:12.724Z

- command: node scripts/ryze-geom/run.mjs --mode pixel --font-normalize --twice --ours http://localhost:4322 --pages product --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/product-878d921/pixel
- ours: http://localhost:4322 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)
- limit: whole page ≤ 0.01% differing pixels (a pixel differs when any channel is off by more than 12), for each column. Exempt blocks are blanked on both sides. Per-block rows are diagnostic.
- fonts: "original" = each site with its own fonts; "one font" = every font except Press Start 2P replaced on both pages by our inter file (http://localhost:4322/_next/static/media/e4af272ccee01ff0-s.p.woff2), taken from the same load right after the original shots

| page | width | pixel diff, original fonts | pixel diff, one font |
|---|---|---|---|
| product | 1440 | FAIL 50.02% | FAIL 49.56% |
| product | 390 | FAIL 52.58% | FAIL 50.68% |

### product @ 1440 — Ryze https://www.get-ryze.ai/muse vs ours http://localhost:4322/en/products/ai-sales-assistant with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 11, ours 11.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 1174699 | 90.64% | FAIL |
| 1 | 900 | 900 | 437779 | 33.78% | FAIL |
| 2 | 1800 | 1800 | 914120 | 70.53% | FAIL |
| 3 | 2700 | 2700 | 1083327 | 83.59% | FAIL |
| 4 | 3600 | 3600 | 990396 | 76.42% | FAIL |
| 5 | 4500 | 4500 | 151531 | 11.69% | FAIL |
| 6 | 5400 | 5400 | 185463 | 14.31% | FAIL |
| 7 | 6300 | 6300 | 183106 | 14.13% | FAIL |
| 8 | 7200 | 7200 | 108378 | 8.36% | FAIL |
| 9 | 8100 | 8100 | 738011 | 56.95% | FAIL |
| 10 | 8499 | 8745 | 1163666 | 89.79% | FAIL |

**Whole page, original fonts: 7130476 of 14256000 px = 50.02% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 11, ours 11.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 1174870 | 90.65% | FAIL |
| 1 | 900 | 900 | 434635 | 33.54% | FAIL |
| 2 | 1800 | 1800 | 902798 | 69.66% | FAIL |
| 3 | 2700 | 2700 | 1058484 | 81.67% | FAIL |
| 4 | 3600 | 3600 | 998420 | 77.04% | FAIL |
| 5 | 4500 | 4500 | 148926 | 11.49% | FAIL |
| 6 | 5400 | 5400 | 157977 | 12.19% | FAIL |
| 7 | 6300 | 6300 | 191950 | 14.81% | FAIL |
| 8 | 7200 | 7200 | 112191 | 8.66% | FAIL |
| 9 | 8100 | 8100 | 717407 | 55.36% | FAIL |
| 10 | 8637 | 8726 | 1167647 | 90.10% | FAIL |

**Whole page, one font: 7065305 of 14256000 px = 49.56% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 1440×58.5 | 0,0 1440×57 | — |  | 10/9, 0/1, 0/0, 3/0 |
| hero | 0,0 1440×900 | 0,0 1440×1085.9 | 94.43% |  | 16/5, 3/12, 0/0, 1/1 |
| connect | 0,900 1440×2081.5 | 0,1085.9 1440×2225.7 | 46.76% |  | 28/36, 2/14, 0/0, 2/4 |
| connect.title | 100.5,1012 1239×72 | 100.5,1197.9 1239×72 | 2.97% |  | 1/1, 0/0, 0/0, 0/0 |
| connect.icons | 100.5,1116 1239×84 | 100.5,1301.9 1239×84 | 22.62% |  | 0/0, 2/14, 0/0, 0/0 |
| connect.steps | 100.5,1256 1239×614.3 | 100.5,1479.4 1239×653 | 28.95% |  | 16/31, 0/0, 0/0, 2/3 |
| connect.try | 100.5,1926.3 1239×943.2 | 100.5,2222.4 1239×943.2 | 72.29% |  | 5/4, 0/0, 0/0, 0/1 |
| flow | 0,2981.5 1440×960 | 0,3311.6 1440×960 | 97.99% |  | 14/17, 0/17, 1/0, 1/1 |
| ask | 0,3941.5 1440×599.4 | 0,4271.6 1440×669.9 | 16.91% |  | 15/13, 0/9, 0/0, 4/0 |
| does | 0,4540.8 1440×1366.7 | 0,4941.5 1440×1022.3 | 32.02% |  | 14/38, 0/17, 0/0, 6/24 |
| who | 0,5907.6 1440×695.9 | 0,5963.8 1440×732.9 | 18.11% |  | 11/10, 0/0, 0/0, 0/0 |
| vs | 0,6603.5 1440×851 | 0,6696.7 1440×851 | 1.75% |  | 22/22, 0/0, 0/0, 1/1 |
| faq | 0,7454.5 1440×1141.8 | 0,7547.7 1440×937.3 | 19.46% |  | 15/20, 0/0, 0/0, 7/9 |
| footer | 0,8596.2 1440×941 | 0,8485 1440×1140.7 | 95.40% |  | 38/39, 1/1, 1/0, 0/1 |
| footer.cta | 708.6,9113.7 384×60 | 879.3,9055.8 161.3×48 | — | email-form | 1/1, 0/0, 0/0, 0/1 |
| float | — | 1200.2,850.8 147.6×50.4 | missing on Ryze |  | no Ryze content |
| whatsapp | — | 1164,751.5 260×132.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 1 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 430 px = 0.0030%; ours vs ours 8 px = 0.0001%. Without masks: Ryze 0.0030%, ours 0.0001%.

### product @ 390 — Ryze https://www.get-ryze.ai/muse vs ours http://localhost:4322/en/products/ai-sales-assistant with Ryze text and pictures

Pictures still loading: Ryze 0, ours 0.

**Original fonts** (Ryze Satoshi, ours Inter / Space Grotesk)

Screens: Ryze 13, ours 15.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 285377 | 86.70% | FAIL |
| 1 | 844 | 844 | 205511 | 62.43% | FAIL |
| 2 | 1688 | 1688 | 212025 | 64.41% | FAIL |
| 3 | 2532 | 2532 | 228767 | 69.50% | FAIL |
| 4 | 3376 | 3376 | 204081 | 62.00% | FAIL |
| 5 | 4220 | 4220 | 52049 | 15.81% | FAIL |
| 6 | 5064 | 5064 | 48756 | 14.81% | FAIL |
| 7 | 5908 | 5908 | 51202 | 15.56% | FAIL |
| 8 | 6752 | 6752 | 101649 | 30.88% | FAIL |
| 9 | 7596 | 7596 | 101329 | 30.78% | FAIL |
| 10 | 8440 | 8440 | 51911 | 15.77% | FAIL |
| 11 | 9284 | 9284 | 104014 | 31.60% | FAIL |
| 12 | 9936 | 10128 | 291082 | 88.43% | FAIL |
| 13 | — | 10972 | 329160 | 100% | FAIL (screen missing on Ryze) |
| 14 | — | 11357 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, original fonts: 2596073 of 4937400 px = 52.58% → FAIL** (limit 0.01%).

**One font on both sides** (every font except Press Start 2P replaced by our inter file on both pages)

Screens: Ryze 14, ours 15.

| screen | Ryze y | ours y | diff px | diff % | result |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 285303 | 86.68% | FAIL |
| 1 | 844 | 844 | 206151 | 62.63% | FAIL |
| 2 | 1688 | 1688 | 207894 | 63.16% | FAIL |
| 3 | 2532 | 2532 | 228349 | 69.37% | FAIL |
| 4 | 3376 | 3376 | 208283 | 63.28% | FAIL |
| 5 | 4220 | 4220 | 52930 | 16.08% | FAIL |
| 6 | 5064 | 5064 | 53312 | 16.20% | FAIL |
| 7 | 5908 | 5908 | 53774 | 16.34% | FAIL |
| 8 | 6752 | 6752 | 101970 | 30.98% | FAIL |
| 9 | 7596 | 7596 | 108487 | 32.96% | FAIL |
| 10 | 8440 | 8440 | 49202 | 14.95% | FAIL |
| 11 | 9284 | 9284 | 52963 | 16.09% | FAIL |
| 12 | 10128 | 10128 | 276494 | 84.00% | FAIL |
| 13 | 10241 | 10972 | 287881 | 87.46% | FAIL |
| 14 | — | 11316 | 329160 | 100% | FAIL (screen missing on Ryze) |

**Whole page, one font: 2502153 of 4937400 px = 50.68% → FAIL** (limit 0.01%).

Per-block crops (one font):

| block | Ryze box | ours box | diff % (block crop) | exempt | content paired (ours/Ryze: texts, imgs, bgs, svgs) |
|---|---|---|---|---|---|
| nav | 0,0 390×58.5 | 0,0 390×57 | — |  | 1/1, 0/1, 0/0, 2/1 |
| hero | 0,0 390×844 | 0,0 390×1301.7 | 97.75% |  | 16/5, 3/8, 0/0, 1/1 |
| connect | 0,844 390×1456.1 | 0,1301.7 390×2310.3 | 63.23% |  | 28/23, 0/0, 0/0, 1/2 |
| connect.title | 24,924 342×84 | 24,1381.7 342×84 | 10.28% |  | 1/1, 0/0, 0/0, 0/0 |
| connect.icons | — | — | missing on both |  | no Ryze content |
| connect.steps | 24,1048 342×763.1 | 24,1620.7 342×1107.6 | 71.18% |  | 16/18, 0/0, 0/0, 1/1 |
| connect.try | 24,1851.1 342×369 | 24,2802.3 342×695.8 | 74.25% |  | 5/4, 0/0, 0/0, 0/1 |
| flow | 0,2300.1 390×602 | 0,3612.1 390×602 | 96.68% |  | 14/17, 0/17, 1/0, 1/1 |
| ask | 0,2902.1 390×734.8 | 0,4214.1 390×1307.5 | 54.15% |  | 15/8, 0/0, 0/0, 4/1 |
| does | 0,3636.9 390×3158.5 | 0,5521.6 390×1931.6 | 47.78% |  | 14/38, 0/17, 0/0, 6/24 |
| who | 0,6795.5 390×1190.8 | 0,7453.2 390×1278.3 | 30.17% |  | 11/10, 0/0, 0/0, 0/0 |
| vs | 0,7986.3 390×919 | 0,8731.6 390×919 | 3.80% |  | 22/22, 0/0, 0/0, 1/1 |
| faq | 0,8905.3 390×1262.3 | 0,9650.6 390×1054.5 | 21.37% |  | 15/20, 0/0, 0/0, 7/9 |
| footer | 0,10167.6 390×917.8 | 0,10705.1 390×1455 | 98.48% |  | 38/36, 1/0, 0/0, 0/0 |
| footer.cta | — | 123.4,10888.5 143.2×48 | — | email-form | no Ryze content |
| float | 12,804 366×52 | 158.2,802.4 147.6×43.2 | — |  | no block on our page |
| whatsapp | — | 114,703.5 260×124.5 | — | whatsapp | no Ryze content |

Repeat check, original fonts (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 0 px = 0.0000%; ours vs ours 0 px = 0.0000%. Without masks: Ryze 0.0000%, ours 0.0000%.

Repeat check, one font (both pages loaded again in fresh browsers, exempt blocks masked as above): Ryze vs Ryze 160 px = 0.0035%; ours vs ours 20 px = 0.0004%. Without masks: Ryze 0.0035%, ours 0.0004%.
