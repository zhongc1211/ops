---
title: "Single-product site conversion: removing a product without breaking AEO"
date: 2026-06-12
category: architecture-patterns
---

# Single-product site conversion (HR Pro removal)

## What was done
Removed HR Pro from every public surface and its supporting infra, while
genericizing Revenue Funnel positioning (insurance = proof case, not identity).

## Key decisions and why
1. **308 redirects, never 404**: `/products/hr-pro` (en/zh/bare) → flagship
   product page; retired CPF blog post → /blog. Preserves link equity.
2. **DB schema kept, code paths removed**: `pricing_tiers` table and legacy
   rows stay (no destructive prod migration); seeding, admin page, API type,
   and libs were deleted. Tests went 171 → 51 — the 120 removed tests covered
   the removed pricing feature, which is correct, not a regression.
3. **Generic demo handoff trigger = quotation**: a pricing question is the
   universal "human takes over" moment every industry recognises; the
   compliance/audit facts (PDPA, append-only log) stay because they are
   product properties, not insurance properties.
4. **i18n discipline**: dead keys removed from BOTH locales in the same
   commit (parity test enforces).
5. **Residual sweep technique**: `grep -rn "hr-pro|hrPro|HR Pro"` across
   app/components/lib/messages/content after the build; admin select options
   and JSX comments are where stragglers hide.

## Gotchas hit
- `git rm -r` on the shared content API dir nearly deleted faq/features/
  testimonials handling — the [type] route serves four content types.
- Next.js stale `.next/types` break tsc after page deletion: `rm -rf .next`.
- eslint `react-hooks/set-state-in-effect`: loop-resetting animation state
  must go through a 0ms timer, not a synchronous set in the effect.
