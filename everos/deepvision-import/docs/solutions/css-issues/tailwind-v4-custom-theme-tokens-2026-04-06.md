---
title: "Tailwind CSS v4 @theme custom color tokens not resolving in browser"
date: 2026-04-06
tags: [tailwind, css, next.js, debugging]
severity: P0
---

# Problem

Custom color tokens defined via Tailwind CSS v4's `@theme` directive were not resolving in the browser, causing all content using custom utility classes (text-text, bg-surface, bg-primary, border-border, etc.) to be invisible — white text on white background.

## Root Cause

Tailwind CSS v4's `@theme` block generates CSS custom properties inside `@layer theme { :root { ... } }`. While the CSS variables were correctly defined and the utility classes referenced them properly, the `@layer` cascade in combination with Next.js 14's dev mode CSS processing caused the variables to not resolve in the browser.

The exact mechanism: CSS `@layer` ordering (`properties, theme, base, components, utilities`) combined with how Next.js dev mode hot-reloads CSS may cause theme variables defined inside `@layer theme` to lose to unlayered or differently-layered styles.

## Solution

**Replace all custom `@theme` color tokens with standard Tailwind CSS color classes.**

Mapping used:
- `text-text` → `text-slate-900`
- `text-text-muted` → `text-slate-500`
- `bg-surface` → `bg-white`
- `bg-surface-alt` → `bg-slate-50`
- `bg-primary` → `bg-slate-900`
- `bg-accent` → `bg-blue-500`
- `border-border` → `border-slate-200`
- All hover/focus variants mapped accordingly

This eliminated all CSS variable resolution issues since standard Tailwind colors don't rely on custom CSS variables.

## Key Learnings

1. **Avoid custom `@theme` tokens for critical UI colors in Tailwind v4 + Next.js 14** — standard Tailwind color utilities (slate-*, blue-*, etc.) are more reliable across build modes.

2. **Stale `.next` cache can cause module resolution errors** — after CSS changes, always clear `.next` and restart the dev server: `rm -rf .next && npm run dev`.

3. **Chrome extension screenshot tools may not capture scrolled content in Next.js dev mode** — DOM inspection (computed styles, element positions) is more reliable than visual screenshots for verifying SSR content rendering.

4. **When debugging "invisible content", check CSS `@layer` ordering first** — browser DevTools may show correct computed values while the actual rendering differs due to layer precedence.
