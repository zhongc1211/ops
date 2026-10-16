---
title: "Single-flag seed gating with transactional flag write"
date: 2026-05-03
track: knowledge
problem_type: architecture_pattern
category: architecture-patterns
module: lib/db
tags: [seeding, idempotency, sqlite, transactions, first-run]
severity: P2
---

# Context

A new feature adds DB-backed content that needs to be auto-seeded on first install (so a fresh deploy isn't empty), but must **not** re-seed on every server boot, and especially must not "undo" deliberate admin deletions.

Common naive approaches fail in opposite directions:

- **Always seed on boot.** Admin deletes a row to remove a tier; next container restart re-creates it. Annoying and untraceable.
- **Seed only when the table is empty.** Admin deletes all rows to "wipe and reseed from i18n"; the next restart silently restores them, which is the *only* moment "seed when empty" was supposed to handle. Same bug from the opposite side.
- **Manual `npm run seed` only, no auto-seed.** Fresh deploys are broken until someone remembers to run the script. First-time-user experience is bad.

# Guidance

**Gate auto-seed on a single `<feature>_seeded_v1` flag in a settings table, written inside the same transaction as the seed itself, only when the seed completes cleanly.**

```ts
// lib/db/seed-pricing.ts
export function seedPricingTiers(db: Database.Database) {
  let inserted = 0, skipped = 0, partial = false;

  const insertFlag = db.prepare(
    "INSERT OR IGNORE INTO site_settings (key, value) VALUES ('pricing_seeded_v1', '1')",
  );

  const tx = db.transaction(() => {
    for (const { product, tierKeys } of PRODUCTS) {
      for (const locale of LOCALES) {
        const productPricing = getProductPricing(messages, locale, product);
        if (!productPricing) {
          console.warn(`[seed] missing block for product=${product} locale=${locale}`);
          partial = true;
          continue;
        }
        // ... SELECT-then-INSERT each tier ...
      }
    }
    if (!partial) insertFlag.run();
  });

  tx();
  return { inserted, skipped };
}

// lib/db/index.ts:initTables
const pricingFlag = db
  .prepare("SELECT key FROM site_settings WHERE key='pricing_seeded_v1' LIMIT 1")
  .get();
if (!pricingFlag) seedPricingTiers(db);
```

Three load-bearing details:

1. **Single flag, not a row count.** `SELECT COUNT(*) FROM pricing_tiers` flips between "seed" and "skip" on admin deletion. The flag flips only on intentional reset.

2. **`INSERT OR IGNORE` on the flag write.** The settings table has `UNIQUE(key)`. Two workers booting in parallel against a fresh volume both pass the gate, both call the seed, and the second `INSERT INTO site_settings ('pricing_seeded_v1', '1')` would otherwise raise `SQLITE_CONSTRAINT` and crash `initTables`. `OR IGNORE` is correct here because the constraint exists. (In contrast: `OR IGNORE` on the row inserts themselves doesn't deduplicate without a constraint — see `database-issues/insert-or-ignore-requires-unique-constraint-2026-05-03.md`.)

3. **Flag write inside the transaction.** A process crash mid-seed leaves *both* the partial rows and the flag absent (transactions roll back atomically). The next boot retries cleanly. If the flag write were after the transaction, a crash between commit and flag insert would leave rows present and flag absent — surviving boots would re-run the SELECT-then-INSERT idempotency gate harmlessly, but only because the SELECT-then-INSERT is itself sound.

4. **Don't write the flag on partial seeds.** Track a `partial` boolean inside the transaction; skip the flag write if any product/locale was missing from the source data. The next boot will retry, eventually filling in the missing slice when the source is fixed. Partial-seed-with-flag is a one-way door: the missing rows never get filled in, and operators have to know to manually delete the flag.

# Why This Matters

The core problem is conflating two independent operations: "is the data present?" and "did we *intend* to seed it?". Row count answers the first; the flag answers the second. They diverge under deliberate admin action — exactly the case where the system needs to remember intent.

The mistake nearly everyone makes (including the first draft of this implementation) is using row count alone:

```ts
// WRONG
if (db.prepare('SELECT COUNT(*) FROM pricing_tiers').get().count === 0) {
  seedPricingTiers(db);
}
```

This passes every test scenario except the one that matters in production: an admin who needed to wipe and reseed to fix bad data, and now can never wipe without the next boot undoing them. The flag separates the two questions.

The reset path is explicit and documented:

```sql
-- "I want to reseed from defaults"
DELETE FROM site_settings WHERE key='pricing_seeded_v1';
-- Then: npm run seed
```

This makes reset a deliberate two-statement operation rather than an accidental side effect of the auto-seed mechanism.

# When to Apply

Apply this pattern when **all** of the following hold:

1. There is initial content the application needs from boot (so admins can immediately see and edit something) but that admins also need to be able to delete without it coming back.
2. The seed source is durable (committed to the repo, or a checked-in JSON, or i18n messages) so re-running the seed produces the same content from the same input.
3. The settings/config table already exists and is the natural home for the flag — don't introduce a new table just for one flag.

Skip this pattern when:

- The seed *should* be re-applied on every boot (e.g., reference data that should never diverge from the canonical source). For that case, use `INSERT OR REPLACE` keyed on a stable primary key, or wipe-and-rewrite inside the transaction.
- The "seed" is a one-time data migration that should never re-run regardless of state. Use a versioned migrations table (Drizzle Kit, etc.) instead of an ad-hoc flag.
- Multiple processes write the seed concurrently *and* you need cross-process leadership election. SQLite + a flag isn't a distributed coordination primitive; switch to advisory locks or an explicit migration runner.

# Examples

**Naming:** use a versioned key (`pricing_seeded_v1`, not `pricing_seeded`). When the seed source changes shape and needs to be re-applied (e.g., adding a new product the i18n source now defines), bump to `_v2` so a single deploy step (`DELETE FROM site_settings WHERE key='pricing_seeded_v1'; INSERT INTO site_settings (key, value) VALUES ('pricing_seeded_v2', '1')`) re-triggers seeding for everyone, but doesn't undo admins who already migrated their content manually. The version is a guardrail against future-you, not a feature.

**Test contract:** a regression test that proves partial-seed does *not* set the flag:

```ts
it('partial seed (missing tier key) does NOT write pricing_seeded_v1 flag', () => {
  const db = makeTestDb();
  const messagesWithMissingKey = { ...defaultMessages };
  delete messagesWithMissingKey.en.someProduct.pricing.tiers.enterprise;

  seedPricingTiers(db, messagesWithMissingKey);

  const flag = db
    .prepare("SELECT key FROM site_settings WHERE key='pricing_seeded_v1' LIMIT 1")
    .get();
  expect(flag).toBeUndefined();
});
```

This is the test that catches the most likely future regression — someone "simplifying" the partial-tracking variable away.

# Related

- See `architecture-patterns/all-or-nothing-i18n-fallback-per-product-2026-05-03.md` for the reader-side fallback semantics that interact with this pattern. Together they form a closed loop: partial seed → flag absent → reader's fallback engages → next boot retries → flag eventually set → reader uses DB.
- See `database-issues/insert-or-ignore-requires-unique-constraint-2026-05-03.md` for why `OR IGNORE` is correct on the *flag* insert but wrong on the row inserts in the same helper.
