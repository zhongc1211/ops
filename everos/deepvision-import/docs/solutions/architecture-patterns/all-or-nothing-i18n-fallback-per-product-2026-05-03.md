---
title: "All-or-nothing i18n fallback per product, not per locale"
date: 2026-05-03
track: knowledge
problem_type: architecture_pattern
category: architecture-patterns
module: lib/db/pricing
tags: [i18n, fallback, db-backed-content, locale, design-pattern]
severity: P2
---

# Context

A feature that was content-managed via i18n message files is being migrated to DB-backed storage with an admin UI. To avoid regressing the public site during the rollout window (or after a deliberate operational reset), the reader keeps i18n as a fallback when the DB has no rows for the requested content.

The natural first impulse: per-(product, locale) fallback. If `getPricingTiers('hr-pro', 'zh')` finds no rows for `(product='hr-pro', locale='zh')`, fall back to i18n for *that specific tuple*. The EN and ZH paths each fall back independently.

This is the wrong default.

# Guidance

**Fall back per *product*, not per *(product, locale)*.** If the DB has zero rows for *any* locale of a product, fall back to i18n for **all** locales of that product. Do not let one locale read DB and the other read i18n.

```ts
export function getPricingTiers(product: Product, locale: Locale): Tier[] {
  const rows = db.prepare(
    `SELECT ... FROM pricing_tiers WHERE product = ? ORDER BY display_order ASC, id ASC`
  ).all(product);

  const enRows = rows.filter((r) => r.locale === 'en');
  const zhRows = rows.filter((r) => r.locale === 'zh');

  // All-or-nothing: if either locale is empty, fall back to i18n for both.
  if (enRows.length === 0 || zhRows.length === 0) {
    console.warn('[pricing-fallback-engaged]', {
      product,
      reason: 'locale rows missing',
      en_rows: enRows.length,
      zh_rows: zhRows.length,
    });
    return getI18nFallback(product, locale);
  }

  return mapRowsToTiers(locale === 'en' ? enRows : zhRows);
}
```

The query intentionally reads by `product` only, not `(product, locale)`, so the fallback gate can inspect both locales' presence in one round trip.

# Why This Matters

The per-(product, locale) variant produces a class of failure that is invisible from any single page render: an EN visitor and a ZH visitor see different *sources* of content, with no signal that they're inconsistent.

The operational scenario that surfaces it: admin deletes all `zh` rows for one product to "wipe and re-translate" (a routine flow when content needs to be revised). With per-locale fallback:

- `/zh/products/hr-pro` silently swaps to i18n message JSON (whatever was in there before the migration).
- `/en/products/hr-pro` continues reading the DB-backed content with the admin's recent edits.
- A user toggling locales sees one product as "Pro Plan / S$5" (DB) and another as "专业版 / S$5" (i18n's older copy).
- An ops engineer checking `/zh` sees "the page renders fine" and concludes the DB is healthy. It isn't.

The all-or-nothing variant trades a bit of permissiveness ("only EN is empty, so EN falls back; ZH still works") for **invariance**: when fallback engages, both locales fall back together, and the public site stays internally consistent. The admin's wipe-and-retranslate flow takes both locales offline (back to i18n) while they fix EN; once both are in the DB, both render from the DB. There is no half-state.

The reset path is documented and intentional:

```sql
-- "I want to reseed pricing from the i18n source"
DELETE FROM site_settings WHERE key='pricing_seeded_v1';
-- Then: npm run seed (or restart the app to trigger auto-seed).
```

# When to Apply

Apply this pattern when **all** of the following hold:

1. The feature has multiple parallel content sets keyed by a *secondary* dimension (locale, currency, product variant, A/B-test cohort, …) where users would expect consistency *across* the dimension.
2. The fallback content source is durable and identical for both locales (e.g., the i18n message files are checked into the repo and produce the same shape regardless of locale).
3. The *primary* dimension (product, in this case) is the natural unit of operational reset — admins think in terms of "wipe pricing for hr-pro" or "reseed all of revenue-tunnel", not "wipe just the EN side."

Skip this pattern (and prefer per-locale fallback) when:

- The two locales are genuinely independent products (different currencies, different feature sets, different audiences) and inconsistency is the expected default.
- The fallback source itself is locale-scoped (e.g., a per-locale CDN), so falling back "for both locales" requires two separate calls to two separate sources anyway.

# Examples

**Product page consumer (no awareness of the fallback gate):**

```ts
// app/[locale]/products/hr-pro/page.tsx
export default async function HrProPage({ params }: { params: Promise<{ locale: 'en' | 'zh' }> }) {
  const { locale } = await params;
  const tiers = getPricingTiers('hr-pro', locale);
  // tiers is always populated — either from DB (when both locales seeded)
  // or from i18n (when either locale lacks rows). The page can't tell.
  return <PricingSection tiers={tiers} />;
}
```

**Operational signal:** the structured `console.warn('[pricing-fallback-engaged]', ...)` log fires *exactly when* the fallback path engages. Grep production logs for the literal string to detect drift between admin intent and rendered content. Healthy production has zero of these warnings.

# Related

- The `pricing_seeded_v1` flag pattern documents the seed-gating mechanism that interacts with this fallback (see `architecture-patterns/single-flag-seed-gating-transactional-write-2026-05-03.md`).
- This rule is invariant on the *fallback policy*, not the *seeding policy*. Seeding can be incremental; the fallback gate must still be all-or-nothing.
