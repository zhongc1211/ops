# FONT FLOOR — 2026-10-18T15:44:56.001Z

- command: node scripts/ryze-geom/run.mjs --mode floor --ours http://localhost:4318 --pages home,pricing --widths 1440,390 --out /Users/jiawenwang/orca/workspaces/ops/deepvision/fdv70-geom/baseline-3e050d2/floor
- ours: http://localhost:4318 (locale en); Ryze: https://www.get-ryze.ai
- widths: 1440, 390 (viewport heights 1440→900, 390→844, device scale 1, reduced motion, animations and transitions off, Math.random seeded, page clock fixed)

| page | width | mode | result | detail |
|---|---|---|---|---|
| home | 1440 | floor | — | font only 11.81%; reload noise 0.0083% |
| home | 390 | floor | — | font only 12.86%; reload noise 0.0012% |
| pricing | 1440 | floor | — | font only 10.92%; reload noise 0.0000% |
| pricing | 390 | floor | — | font only 18.04%; reload noise 0.0000% |

### home @ 1440 — Ryze vs Ryze with Satoshi replaced by our inter

- font only: 1530476 of 12960000 px = 11.81% (screens 10 vs 10; page height with our font 8735)
- same page reloaded, nothing changed: 1079 of 12960000 px = 0.0083%

### home @ 390 — Ryze vs Ryze with Satoshi replaced by our inter

- font only: 507865 of 3949920 px = 12.86% (screens 12 vs 12; page height with our font 9847)
- same page reloaded, nothing changed: 46 of 3949920 px = 0.0012%

### pricing @ 1440 — Ryze vs Ryze with Satoshi replaced by our inter

- font only: 1132343 of 10368000 px = 10.92% (screens 8 vs 8; page height with our font 7184)
- same page reloaded, nothing changed: 0 of 10368000 px = 0.0000%

### pricing @ 390 — Ryze vs Ryze with Satoshi replaced by our inter

- font only: 831209 of 4608240 px = 18.04% (screens 14 vs 14; page height with our font 11785)
- same page reloaded, nothing changed: 0 of 4608240 px = 0.0000%
