> **DRAFT — not in any deepvision-ads branch yet.** Proposed `AGENTS.md` for the **main branch** of deepvision-ads (main currently has no AGENTS.md; the 26-line version lives only on feature branches, the 32-line iMac version only in worktree FDV-58-AGENTS测试规矩).
> Based on the iMac 32-line version. Changes vs. that version:
> 1. Deleted "Pure logic goes in `lib/` with a Vitest test in `tests/`."
> 2. "Before opening a PR" no longer gates on `npm test`; it requires real E2E on the PR head with the report fields.
> 3. Testing section replaced with the English block from 00-shared-testing-block.md.
> 4. Added "Pushing, PRs, deploys" (dispatch decides), "Deploy & CI" (cf CLI, Workers Builds, GH Actions tests only), one-line notify-run pointer.
> 5. "No production deploys" softened to "unless the dispatch explicitly says so" (**Zack approved 2026-10-16**).
> 6. Does not name or prefer any specific coding agent.
> Everything below the `---` line is the proposed file.

---

# Deepvision Ads — rules for coding agents

Product: a functional rebuild of an ads-automation SaaS for Deepvision. Feature list and acceptance criteria: `docs/features.md`. Reference screenshots: `ryze-screens/` (see `research.md`). Status: `status.md`. Product decisions Zack has made: `docs/decisions.md` — don't overturn them.

## Hard rules
- Never copy the reference product's copy, images, logos or code. Write our own English UI copy.
- No real ad accounts (Google Ads test accounts and Meta sandbox only), no payments, nothing that costs money without an approved budget.
- No production deploys unless the dispatch explicitly says so. (Zack approved 2026-10-16)
- One feature module = one Linear issue = one Orca worktree = one PR (≤2000 changed lines excluding `package-lock.json`), stacked in the order of the table in `docs/features.md`.
- Do not use `wrangler` for deploys or secrets; use the Cloudflare CLI (`npx cf`). Do not leave servers running.
- The box has Node 20 system-wide; this project needs Node 22: `export PATH=$HOME/.local/node22/bin:$PATH`. Install with `npm install --legacy-peer-deps`.
- At most one heavy task (build, E2E run) at a time on the box.
- Never `git add .` / `git add -A`; stage explicit files.
- Do not name or prefer a specific coding agent in this repo or in dispatch.

## Pushing, PRs, deploys
- If the dispatch says you may push / open a PR / merge / deploy, do it. If it doesn't, don't — stop at a local commit and say so in your report. (Zack approved 2026-10-16)
- Before your first change, read this file and `docs/solutions/LESSONS.md` (if present) in your worktree. If your worktree's AGENTS.md is older than main's (no Testing section), rebase onto the current base or follow the testing rules pasted in the dispatch.
- Wrap any command longer than 15 minutes with `notify-run --bot deepvision-ads --task "<issue> <summary>" -- <command>`. Don't go silent when done or stuck: your last message states the conclusion and the report path.

## Stack
Next.js App Router on Cloudflare Workers through OpenNext. D1 (`DB`) for data, R2 (`FILES_BUCKET`) for files. Tailwind v4 tokens live in `app/globals.css`.

## Conventions
- Workspace pages live in `app/[org]/[ws]/<path>/page.tsx` and call `requireWorkspace(org, ws)` first; org pages call `requireOrg`. A concrete route replaces the placeholder in `app/[org]/[ws]/[...slug]`.
- Sidebar, breadcrumbs and placeholder titles come from `lib/nav.ts`. Add pages there, not in components.
- Shared UI is in `components/ui` (Button, Card, EmptyState, PageHeader, Input, Modal, Tabs) and `components/shell`. Reuse before adding.
- D1 access goes through `getDb()` with prepared statements; every query on tenant data filters by `workspace_id` or `org_id`.
- Migrations: `migrations/00NN_<name>.sql` where NN is the Linear issue number (FDV-37 → `0037_…`), so stacked branches never collide. Never edit a merged migration.
- New env vars: add to `cloudflare-env.d.ts`, `.env.example` and `wrangler.jsonc` (non-secret vars only).

## Deploy & CI
- Deploys go through Cloudflare Workers Builds: `staging` → testing, `main` → production. Secrets via `npx cf`.
- GitHub Actions run tests only; they never deploy. No Cloudflare token in GitHub.
- Before deploying a commit to testing or production, its CI must have finished green (cancelled runs don't count).
- Merge with the reviewed sha pinned: `gh pr merge --match-head-commit <sha>`.

## Before opening a PR
1. `npm run typecheck && npm run lint && npm run build` — must pass; record each exit status separately. (Existing `npm test` runs in CI; it is not acceptance.)
2. Real E2E on the PR's current head commit against the testing deployment, using Google Ads test accounts / Meta sandbox. See Testing below.
3. `git diff --stat <base>` to confirm size and that only this module's files changed; remove scaffolding and stray scripts.
4. PR body: what changed, what was not touched, the E2E report (format below), rollback. Link the Linear issue. No E2E result → stay draft, don't request review.

## Testing (Zack's rules — apply to every change in this repo)

Verbatim:

- NEVER write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.

In practice:

- Do not add unit tests after writing code. Existing unit tests and CI stay as they are (don't delete or weaken them), but they are not acceptance.
- E2E must be honest: real deployment (testing environment) and real user flows. No mocks, no stubs, no faked API responses, no skipped steps, no loosened assertions, no cherry-picked reruns. A run that uses test doubles is a "local check with doubles", never "E2E".
- Report failures as they are. If the test itself was wrong, say why and what you changed, keep the failed run's output, then rerun the whole suite.
- Leave an artifact someone else can reproduce: command, URL, commit, build id / deployed version, and paths to screenshots, recordings or logs.

E2E on every PR:

- Every PR runs real E2E on **that PR's current head commit**. Passing unit tests or green CI do not replace it. If the head changes (new push, rebase), rerun; results from an older commit don't count.
- No E2E result → the PR does not go ready and does not request review.
- Anything that costs money needs an approved budget first.

E2E report in the PR body / PR comment — all fields required:

```
E2E (PR head)
- Command: <full command, env var names, no secrets>
- Environment/hardware: <testing URL; machine (box / iMac); browser; ad test account / sandbox used>
- Commit: <full sha of the PR head>
- Result: <passed N / failed M / skipped K; names of failing cases>
- Artifact: <paths/links to screenshots, logs, traces; deployed Worker version>
Revert check: <with the old code put back, this E2E fails: yes / no / not run>
Rollback: <Worker version / commit to roll back to, and how>
Not run: <each item marked "not run" with the reason>
Unit tests: CI covers unit tests
```

When you call a failure "unrelated to this change":

- In the PR comment give the case name (file:line), the raw error, and the same case's result on base (CI link or rerun record). If you don't have it, write "not compared against base".
- If you reran, say whether it was the full run or failed jobs only, who decided, and the result. Never write just "unrelated", "flaky" or "green on rerun" in `status.md` or reports.
- Second time the same case or batch fails: search Linear first; add a comment counting the occurrence if a ticket exists, otherwise open one. Don't repeat "unrelated, rerun".
