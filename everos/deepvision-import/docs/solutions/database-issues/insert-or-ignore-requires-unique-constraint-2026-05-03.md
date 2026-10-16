---
title: "`INSERT OR IGNORE` is a no-op without a matching UNIQUE constraint"
date: 2026-05-03
track: bug
problem_type: database_issue
category: database-issues
module: lib/db
tags: [sqlite, better-sqlite3, idempotency, seed, schema]
severity: P1
---

# Problem

A seed (or any insert path that needs to be idempotent) was written as:

```ts
db.prepare(
  `INSERT OR IGNORE INTO pricing_tiers (
    locale, tier_name, price, ..., product, ...
  ) VALUES (?, ?, ?, ?, ?, ?)`
).run(...);
```

with the assumption that re-running would skip duplicates keyed on `(product, locale, tier_name)`. The plan said "idempotent via `INSERT OR IGNORE` keyed on (product, locale, tier_name)". It wasn't.

## Symptoms

- First seed run: 10 rows inserted.
- Second seed run: **20 rows** in `pricing_tiers` instead of 10.
- No error is raised — `OR IGNORE` succeeds vacuously when there is no constraint to violate.

## Root Cause

`INSERT OR IGNORE` only suppresses inserts that would violate an existing **constraint** (`UNIQUE`, `NOT NULL`, `CHECK`, `FOREIGN KEY`). The `pricing_tiers` schema only constrained the auto-increment `id` to be unique:

```sql
CREATE TABLE pricing_tiers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  locale TEXT NOT NULL DEFAULT 'en',
  tier_name TEXT NOT NULL,
  ...
);
```

There is no `UNIQUE(product, locale, tier_name)`. Without that constraint, every re-run inserts fresh rows with new auto-increment ids. `OR IGNORE` is doing nothing.

## What Didn't Work

- **Reading the SQL.** The query *looks* correct. The bug only surfaces when re-running.
- **Trusting the plan.** Two doc-review passes flagged the mismatch (confidence 100, cross-persona — feasibility + adversarial); the orchestrator caught it before implementation. Without that scrutiny, the bug would have shipped and produced duplicate tiers on every container restart.

## Solution

Two valid fixes, depending on whether schema changes are in scope.

**Option A — keep the existing schema; use SELECT-then-INSERT explicitly:**

```ts
const selectExisting = db.prepare(
  'SELECT id FROM pricing_tiers WHERE product = ? AND locale = ? AND tier_name = ? LIMIT 1',
);
const insertRow = db.prepare(
  `INSERT INTO pricing_tiers (locale, tier_name, ...) VALUES (?, ?, ...)`,
);

const existing = selectExisting.get(product, locale, tierName);
if (!existing) insertRow.run(locale, tierName, ...);
```

Wrap the loop in `db.transaction(...)`. The SELECT is the only protection — drop the `OR IGNORE` clause from any related write so its absence is unmistakable.

**Option B — add a UNIQUE constraint and keep the `INSERT OR IGNORE` shape:**

```sql
CREATE TABLE pricing_tiers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  locale TEXT NOT NULL DEFAULT 'en',
  tier_name TEXT NOT NULL,
  ...
  UNIQUE(product, locale, tier_name)
);
```

Now `INSERT OR IGNORE` actually means what it looks like.

Existing tables in the same repo follow this pattern: `posts (UNIQUE(slug, locale))`, `seo_metadata (UNIQUE(page_key, locale))`, `site_settings (key UNIQUE NOT NULL)`. `INSERT OR IGNORE` against any of these will deduplicate correctly.

## Why This Works

`INSERT OR IGNORE` is shorthand for `INSERT, but if it would violate a constraint, silently drop the row instead of throwing`. The constraint is the load-bearing part. Without one, the `OR IGNORE` clause is purely decorative — every row passes the (nonexistent) check and gets inserted.

The two fixes differ in *where* the uniqueness rule lives: in application code (Option A) or in the database (Option B). Option B is more robust against future code paths that re-implement the insert, but requires a schema migration.

## Prevention

- **Test idempotency by row count, not return values.** A unit test that asserts `seedHelper(db).inserted === 10` on the first run and `seedHelper(db).skipped === 10` on the second run can pass even when the underlying SQL inserts duplicates. Add: `expect(db.prepare('SELECT COUNT(*) FROM pricing_tiers').get().count).toBe(10)` after two consecutive seeds.

- **Code-review checklist for `OR IGNORE` / `OR REPLACE`:** when reviewing a write that uses these clauses, confirm the relevant `UNIQUE` constraint exists in the schema. The clause is invisible without one.

- **Prefer explicit SELECT-then-INSERT** when the deduplication key is also load-bearing in application code (e.g., the helper returns `inserted/skipped` counters). Explicit reads make the dedup gate visible at the call site.

- **Plan-review protocol:** if a plan claims idempotency via `OR IGNORE`, treat it as a load-bearing claim that needs to be verified against the schema before implementation. (This was the catch in this case.)
