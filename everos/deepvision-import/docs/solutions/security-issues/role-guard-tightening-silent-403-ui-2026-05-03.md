---
title: "Tightening an admin route's role guard silently breaks UIs that don't surface fetch errors"
date: 2026-05-03
track: bug
problem_type: security_issue
category: security-issues
module: app/api/admin
tags: [authz, role-guard, error-surfacing, content-manager, next.js]
severity: P0
---

# Problem

An admin API route's authorization was tightened from `session?.user` (any logged-in user) to `session.user.role === 'admin'`. The route now correctly returns 403 to editor-role sessions. But the UI consuming the route (a generic `ContentManager` component) showed every save and delete as successful, with no indication that the request had been rejected. Editors saw a smooth UI flow that wrote nothing.

## Symptoms

- Editor logs in, opens `/admin/content/pricing`, edits a tier, clicks Save.
- The form closes and the page refreshes, exactly as it would for an admin.
- The DB has not been written. No toast, no banner, no console error in the component.
- DevTools network tab shows `403 Forbidden` — the only signal, and only to someone who opened DevTools.

## Root Cause

The component's save handler:

```ts
async function handleSave() {
  setSaving(true);
  await fetch(url, { method, body: JSON.stringify(formData) });
  setSaving(false);
  setEditing(null);
  router.refresh();
}
```

`fetch` resolves with a `Response` object on every HTTP status code, including 4xx and 5xx. The `await fetch(...)` succeeds for any HTTP response; it only rejects on network failures. The handler never reads `res.ok` or `res.status`, so a 403 response is indistinguishable from a 200 response from the component's perspective.

Tightening the role guard on the route was correct (closing a privilege-escalation gap). The breakage was in a *different* file — the consumer that assumed the route always succeeded for any logged-in user.

## What Didn't Work

- **Reading only the route diff.** The route's tests covered the 403 path correctly. The bug only surfaces when you trace what the actual UI does with the response.
- **Trusting that `await fetch(...)` "fails" on bad status.** It doesn't. This is a long-standing surprise in the Fetch API's design — it was deliberate (so `fetch` doesn't reject on every 404), but it consistently catches code reviewers off guard.

## Solution

**Pair every server-side authorization tightening with an audit of the UI's fetch error surfacing.** When the route can now return 401/403/400 in cases it previously returned 200, the component must surface those statuses.

The fix in this case:

```ts
const [error, setError] = useState<string | null>(null);

async function readErrorMessage(res: Response, fallback: string): Promise<string> {
  try {
    const body = await res.json();
    if (body && typeof body.error === 'string') return body.error;
  } catch {
    // body wasn't JSON; fall through.
  }
  if (res.status === 401) return 'Not signed in.';
  if (res.status === 403) return 'Forbidden — admin role required.';
  return fallback;
}

async function handleSave() {
  setSaving(true);
  setError(null);
  const res = await fetch(url, { method, body: JSON.stringify(formData) });
  setSaving(false);
  if (!res.ok) {
    setError(await readErrorMessage(res, `Save failed (HTTP ${res.status}).`));
    return;
  }
  setEditing(null);
  router.refresh();
}
```

Plus a banner in the JSX:

```tsx
{error && (
  <div role="alert" className="mb-4 rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
    {error}
  </div>
)}
```

Apply the same `readErrorMessage` helper to the delete handler and any other mutation in the same component.

## Why This Works

The component now distinguishes "request succeeded" (`res.ok`) from "fetch resolved" (the lower bar Fetch actually clears). Any route that returns 401/403/400/422/500 produces a human-readable message in the UI. The 403-without-feedback failure mode is closed.

## Prevention

- **Audit consumers when tightening server-side auth.** When you change a route's authorization (admin-only, role check, ownership check), grep the codebase for components that call that route and verify each one inspects `res.ok` or `res.status`. The route's test suite alone is not sufficient — the breakage usually lives in the consumer.

- **Add an integration test that asserts the UI surfaces 403.** A unit test that mocks `fetch` to return `{ ok: false, status: 403 }` and asserts the component renders an error banner. Cheap to write; catches regression of the silent-failure path.

- **Prefer an `apiFetch` wrapper over raw `fetch` in admin tools.** A small wrapper that throws on `!res.ok` (or returns `{ data | error }`) forces every consumer to handle the failure case explicitly, instead of silently inheriting Fetch's "any response is success" default.

- **Code-review heuristic:** any `await fetch(...)` immediately followed by `router.refresh()` (or an equivalent "treat as success" call) without a `res.ok` check is suspect. Flag it.

## Related

- Pre-existing pattern in this repo: `app/api/admin/settings/route.ts` and `app/api/admin/submissions/route.ts` use the same `role === 'admin'` guard. Their UI consumers should also be audited.
