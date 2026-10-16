# WhatsApp assistant widget — solution notes (2026-06-18)

## What was built
A site-wide floating WhatsApp assistant (`components/ui/WhatsAppAssistant.tsx`) for
deepvision.sg: launcher → branded chat panel → intent chips that deep-link to
`wa.me/15559498816` with prefilled, locale-specific messages. No backend/API token
(the live agent runs in rf; this is just the conversion front door).

## Reusable patterns
- **Deep-link, don't integrate.** `lib/site.ts` `waLink(text)` URL-encodes a prefilled
  message into `https://wa.me/<number>?text=...`. Opening WhatsApp this way needs zero
  Meta credentials and works on mobile (opens the app) and desktop (web).
- **Intent chips pre-qualify.** Each quick reply carries a different prefilled message
  (demo / pricing / setup / human) so the lead arrives in WhatsApp already segmented.
- **Proactive nudge, once per session.** `sessionStorage['wa-nudge-seen']` gates a ~6s
  delayed bubble; opening or dismissing sets the flag. Avoids nagging on every route change.
- **Two floating CTAs must not collide.** Pre-existing `StickyDemoCTA` was moved to
  `bottom-6 left-6`; the WhatsApp launcher owns `bottom-6 right-6`. Verified non-overlap in Chrome.
- **Analytics without a hard dep.** `track()` calls `window.plausible?.(event,{props:{intent}})`
  guarded — fires only if Plausible is present, no error otherwise.

## Gotchas (learned this build)
- **i18n parity is test-enforced.** `tests/i18n/message-parity.test.ts` fails on any
  en/zh key-set asymmetry AND on empty zh leaves. Add the whole `whatsapp` namespace to
  BOTH `messages/en.json` and `messages/zh.json` in the same change.
- **Chrome test must run from inside the repo.** puppeteer-core is installed
  `--no-save` into the project's `node_modules`; a script in `/tmp` throws
  `ERR_MODULE_NOT_FOUND`. Use a `*.local.mjs` file in the repo root (already gitignored).
- **Assert on prefilled *text*, not chip *label*.** zh label "预约演示" but the message
  reads "我想预约 … 演示" — a naive `includes(label)` check false-negatives. Decode the
  `?text=` param and assert on the real Chinese sentence.
- **Don't select CTAs by visible text alone.** "Book a Demo" also appears in the header
  nav; a `querySelector('a')` text match grabbed the nav link, not the sticky CTA. Select
  the sticky element by its `.fixed.bottom-6.left-6` container.
- **No JS dialogs** — all actions are real `<a target=_blank>` links; nothing triggers
  alert/confirm (keeps the page Chrome-automatable and crawlable).

## Verification (Chrome, headless)
14/14 checks: launcher present (en+zh), panel opens, ≥5 wa links all on 15559498816,
URL-encoded prefilled text correct per locale, zh messages Chinese, no console errors,
launcher bottom-right (24px gap), demo CTA bottom-left with no overlap. Screenshots:
/tmp/wa_en.png, /tmp/wa_zh.png. Gates: 51 tests, lint, tsc, production build all pass.

## Not done (handoff)
Not committed/deployed — left in the working tree pending the user's go-ahead. Deploy
path is the usual manual amd64 Docker pipeline (see memory: site-prod-deploy.md); direct
push to main is classifier-blocked, so a branch + PR is required.
