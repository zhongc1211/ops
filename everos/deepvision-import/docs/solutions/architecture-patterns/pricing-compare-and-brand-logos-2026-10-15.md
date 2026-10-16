# Package comparison on /pricing and platform logos — solution notes (2026-10-15)

## What was built
FDV-60: `/pricing` shows the three packages as cards, then a comparison table
(`components/sections/PricingTable.tsx`). On a phone the table becomes one `<dl>` per
package behind a package switch. The platforms come from `lib/package-platforms.ts`: the
publishing platforms under "Up to N", and two rows of their own, the assistant's and the ad platforms.
Round 2 (same day) added Messenger, Facebook and Instagram logos to WhatsApp's; every other platform is a
name. Facebook and Instagram sit on a line of their own (`OWN_LINE`).

## Lessons
- **Rearrange instead of adding a second block.** `tests/app/zh-final-wording.test.ts`
  requires each sentence once per page, so a comparison block next to the existing table
  would repeat every tagline. Moving the existing strings into the new layout kept all
  frozen copy and passed the test; new labels live in their own `pricingCompare.*`
  namespace so the `pricing.*` hash test stays unchanged.
- **Check brand rules before placing a logo, platform by platform.** As of 2026-10: Meta's
  product logos (WhatsApp, Messenger, Facebook, Instagram) may be used in marketing without
  asking; only the Meta company logo needs approval. Google does not allow its logo in a
  business's marketing; TikTok, LinkedIn, Reddit and Snapchat need permission; Pinterest's
  badge is for your own account; YouTube asks for 100px. Those are written as names. Keep
  the downloaded file unchanged (Instagram's 5000px PNG was only scaled down) and pin its
  sha256 in a test (`tests/app/pricing-compare.test.ts`); record the source in
  `docs/brand-files.md`.
- **A platform name can trip an older guard.** `tests/app/social-links.test.ts` kept every
  mention of YouTube out after its channel link was removed, and `tests/app/final-copy.test.ts`
  lists the Latin words a Chinese page may show. Both were narrowed, not removed.
- **Pick the logo colour for the background.** The table is dark; the black inline logo
  disappears on it and the white one was not allowed by marketing, so the green one is used.
- **The language switch replaces the history entry.** `LanguageSwitcher` calls
  `router.replace`, so an e2e `page.goBack()` after switching lands on `about:blank`.
  Come back by clicking the switch again.
- **Workers Builds preview fails on non-ASCII branch names** ("Invalid preview name").
  That check is only the per-branch preview; the `staging` build after the merge deploys
  the testing Worker normally.
- **Under load, the full vitest run times out** in `tests/lib/lastmod.test.ts` and
  `tests/migration/*`; rerun those files alone and report both results.

## E2E
`E2E_BASE_URL=https://deepvision-site-testing.xiangrong.workers.dev E2E_SHOTS=<dir outside the repo> npx playwright test tests/e2e/pricing-compare.spec.ts`
— 1440 and 390, en and zh; run `npx playwright install chromium` first on a new machine.
