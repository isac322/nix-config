# Site QA gates (SITE-25, SITE-31, SITE-48, SITE-53~61)

Everything here runs before the owner sees a preview and again before merge. Follow impeccable's bounded-pass rule: build fully, inspect once in a batched round, fix everything in one batch, confirm with at most one more round. Screenshots and dumps go to a scratch directory outside the repo or a gitignored path.

## 1. Visual QA matrix (SITE-53)

| Axis | Values |
|---|---|
| Widths | 1440, 1024, 768, 390, 360 px (360 is mandatory; add 1920 for hero/pointer effects) |
| Themes | light and dark on every page (both are shipped) |
| Captures | first viewport and full page; mobile at DPR 2–3 |
| Pages | every route in the sitemap, not a sample: landing, each docs tab's first and longest page, reference tables, 404 |

Tooling: headless Chromium via Playwright (`bun` script) or the camofox browser (iframe at 360 px for narrow checks, `evaluate`/`getComputedStyle` for measurements).

Look for, per page:
- Clipped or wrapped identifiers (`overflow-wrap` splitting flags or resource names), smart quotes breaking `--flags`, font ligatures changing code (`--` → en dash in monospace).
- Tables that clip columns at 360 px without a scroll cue; wide code blocks without horizontal scroll.
- Sticky elements covering content or the footer; the sidebar `scrollIntoView` scrolling the whole window.
- Focus ring invisible in either theme; unlabeled icon buttons (hamburger, theme toggle).
- Generic AI-template cues: accent left borders on cards or sidebars, cramped table padding, card grids everywhere, gradient text, eyebrow kickers, `→` link spam.
- Broken anchors from headings; search not deep-linking to headings.
- Diagram or hero art cropped at narrow widths.

Record each defect as a row: `page | width | theme | defect | owner file | severity (P0 blocker, P1 major, P2 minor)`. Route rows to the file owner, then close every row as `fixed`, `still broken`, or `accepted` (with reason) after re-verification (SITE-55).

## 2. Automated overlap and overflow scan (SITE-54)

Run on every page × {1440, 1024, 768, 360} in both themes. Gate: 0 collisions, 0 horizontal overflow.

```js
// In page context. Reports sibling text boxes that intersect and elements wider than the viewport.
const vw = document.documentElement.clientWidth;
const overflow = [...document.querySelectorAll('body *')]
  .filter(el => el.getBoundingClientRect().right > vw + 1 && getComputedStyle(el).position !== 'fixed')
  .map(el => el.tagName + '.' + el.className);
const hits = [];
for (const parent of document.querySelectorAll('body *')) {
  const kids = [...parent.children].filter(k => k.innerText?.trim() && k.getClientRects().length);
  for (let i = 0; i < kids.length; i++) for (let j = i + 1; j < kids.length; j++) {
    const a = kids[i].getBoundingClientRect(), b = kids[j].getBoundingClientRect();
    const ix = Math.min(a.right, b.right) - Math.max(a.left, b.left);
    const iy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
    if (ix > 2 && iy > 2) hits.push([kids[i].outerHTML.slice(0, 80), kids[j].outerHTML.slice(0, 80)]);
  }
}
({ overflowX: document.documentElement.scrollWidth > vw, overflow, hits });
```

Also scroll in 40 px steps on pages with sticky or scroll-driven elements and re-run. Known traps: `white-space: nowrap` spans inside grid items, absolutely positioned counters, sticky pills over footers, hero text at extreme pointer positions. For pointer- or scroll-reactive heroes, sweep the pointer past both ends of the element at every width and confirm neighbours are not covered and the logo stays visible.

## 3. Design review (SITE-56)

1. `impeccable detect --json site/src` and `impeccable detect --json site/dist` (exit 0 clean, 2 findings, 1 scan failure). Add `--viewport 390x844` for the mobile pass. Classify each finding as real or false positive (e.g. overlays injected by the test browser) and fix the real ones.
2. `impeccable critique` and `impeccable audit` run by two isolated assessors: A = design review (heuristic scores), B = detector + live browser. Neither sees the other's output. Audit covers a11y, performance, responsive, theming across all routes.
3. Finish reviewer (fresh eyes, no build history) issues a disposition against the approved surface brief and the craft floor. Re-score after fixes until "ship".
4. After ship, regenerate DESIGN.md and the design sidecar from the shipped tokens and check drift (SITE-14).

## 4. Links and HTML validity (SITE-57)

- `lychee` on `dist/**/*.html` and `README.md`: PR runs `--offline` (internal only, no flakiness); a weekly scheduled run checks external links with caching and opens an issue on failure.
- `vnu --errors-only --skip-non-html dist/` (or `htmltest` for alt text and missing assets).
- Internal link check over `dist` after every route move; redirects verified per `seo-checklist.md` §4.

## 5. Accessibility gate (SITE-58)

- axe-core or `pa11y-ci` on every route, WCAG 2.2 AA, both themes, in CI; failures block merge.
- Keyboard pass: tab order, visible focus in both themes, skip link, no traps, focus returns after dismissing banners, dialogs, or nudges.
- Every animation honours `prefers-reduced-motion` (WCAG 2.3.3); media galleries show posters only under reduced motion.
- Touch targets ≥44 px; CTAs ≥44 px tall.
- Contrast: body text ≥4.5:1, large text and UI ≥3:1, checked on tokens in both themes (not only by eye).
- Galleries and horizontal pickers: every overflowed item reachable by mouse, keyboard, and touch; roving tabindex and a live region where selection changes content. Pages still read without JS.

## 6. Performance budget (SITE-59)

Budgets (landing and docs home):
- Lighthouse (`lhci autorun` or `unlighthouse-ci --budget`): Performance ≥0.9 on mobile, Accessibility ≥0.9, SEO ≥0.95, Best Practices ≥0.9.
- Mobile profile: emulate a mid-range phone (e.g. 412×915, DPR ~2.6) with 4× CPU throttling; record a trace. First scroll must not drop a large share of frames; report the dropped-frame ratio.
- Media: poster and thumbnail sizes match rendered size (no 2560-wide posters in 46 px tiles); a lower-resolution video variant for mobile; `preload="none"` + data-src lazy loading that nothing bypasses; only one decoder running at a time; total above-the-fold media weight stated in the report.
- No per-frame `backdrop-filter` blur or other effects that re-raster every frame; count compositor layers and their memory.
- Zero-JS by default; ship JS only for the core interaction, with a no-JS fallback.

If incremental fixes cannot meet the budget, build 2–4 architecture prototypes side by side (e.g. single canvas, worker-driven offscreen rendering, CSS scroll-driven animation + `content-visibility`, one shared decoder) with the same trace method, and let the owner compare (SITE-10).

## 7. Copy measurements (SITE-25, SITE-31)

- Words per landing section and total (default ≤450); rendered page height at 1440 and 360 (defaults ≤3600 / ≤5500 px). Report measured values next to the budget.
- Banned-pattern grep on owned copy: hedging ("experimental", "not production", "preliminary"), change narrative ("now supports", "new in", "migrate from"), checkout installs (`git clone`, `make install`, `go build` in user docs), unshipped features outside "planned", third-party possessives. Scope the grep to site copy, synced docs, and README; CONTRIBUTING is exempt from the checkout rule.
- Guides executed as a reader in a clean environment: flags vs `--help`/`helm show values`, manifests vs schemas, sample output vs real output. Verdict per guide GREEN/BLOCKING with P0/P1/P2 rows and exact replacement text.

## 8. Site PR review (SITE-48, SITE-60)

An independent reviewer checks and returns GREEN or BLOCKING:
- Bun only (no `package-lock.json`, `npx`, `node` scripts).
- Workflow security: actions pinned by SHA, least-privilege `permissions`, no `pull_request_target`, deploy only from the default branch, path filters include every directory the site imports.
- Build-time fetches (stars, versions) have a timeout, optional token, and graceful fallback (including 403 rate limit).
- Sync correctness, SEO tags, fact accuracy against `positioning.yml`, a11y basics.
- Public-repo hygiene: no screenshots, review dumps, local paths, `/tmp` references, secrets, or session artifacts committed; review output directories gitignored.
- IaC PRs (Pages, DNS): import IDs correct, `prevent_destroy` on imported resources, token scope minimal, plan counts (import/add/change/destroy) as expected.

## 9. Live verification after deploy (SITE-61)

```sh
d=https://<domain>
for p in / /docs/ /sitemap-index.xml /robots.txt /llms.txt /og.png /favicon.svg /apple-touch-icon.png /site.webmanifest; do
  printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' "$d$p")" "$p"; done
curl -s -o /dev/null -w '%{http_code}\n' "$d/does-not-exist/"      # 404
curl -sI "http://<domain>/" | head -n 3                             # 301 → https
curl -s "$d/sitemap-0.xml" | grep -c '<loc>'                        # expected page count
gh api repos/<o>/<r>/pages --jq '{cname,https_enforced,status,https_certificate:.https_certificate.state}'
```

Then re-grep live head tags per page (title, description, canonical, og:image, twitter:card, JSON-LD, manifest link), take live screenshots at 1440 and 360, and confirm the analytics beacon is present in production HTML. Report from responses, not memory.
