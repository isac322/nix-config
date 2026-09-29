# Technical SEO checklist (SITE-19, SITE-20, SITE-34, SITE-40~43, SITE-49~51)

Run against the built output (`site/dist/`) in CI and against the live domain after deploy. Values are defaults; the rule in SKILL.md owns the intent.

## 1. Per-page head

| Item | Requirement | Check |
|---|---|---|
| `<html lang>` | Matches the public-language decision | grep `dist/**/*.html` |
| `<title>` | Exactly one, unique across the site, ≤60 chars, keyword first. Docs form `H1 \| Project`, so the source H1 is usually ≤49 chars | script over `dist/` |
| `meta[name=description]` | Exactly one, unique, 150–160 chars (≤155 preferred). On synced docs it is the first plain-prose paragraph, so no links or code in that paragraph | script |
| `link[rel=canonical]` | Absolute, self-referencing, production host, https, trailing-slash form matches the router | script |
| Open Graph | `og:title`, `og:description`, `og:type`, `og:url`, `og:image` (absolute https URL, 1200×630, <1 MB, returns 200), `og:site_name` | script + `curl -I` |
| Twitter | `twitter:card=summary_large_image` (falls back to OG for the rest) | script |
| Icons | `favicon.svg` (prefers-color-scheme aware), `.ico` 16/32/48, `apple-touch-icon` 180, `site.webmanifest` with 192/512/maskable-512, `theme-color` light + dark. Assets come from BRD's kit | `curl` 200 each |
| Indexing | No `noindex` on production pages; `noindex` only on preview builds | script |
| Title/metaphor | No brand metaphor, hedging, or "planned" feature in title/meta/H1 (SITE-26, SITE-27) | banned-pattern grep |

Title patterns by project type (examples, not requirements):
- CLI: `tool — fast log search for the terminal`
- Library: `lib — typed HTTP client for Rust`
- K8s operator/controller: `operator — Kubernetes operator for <external system>`
- Desktop GUI app: `app — <function> for <desktop environment>`
- MCP/AI tool server: `server — MCP server for <domain> automation`
- Web service: `service — self-hosted <category> with <differentiator>`

Third-party trademarks: referential "for" phrasing only, ® or ™ on the first rendered use, never in keywords beyond one referential sentence (SITE-43).

## 2. Structured data (JSON-LD)

Landing page, one `<script type="application/ld+json">` graph:
- `SoftwareApplication`: `name`, `description` (same sentence as the meta description), `applicationCategory` (e.g. `DeveloperApplication`), `operatingSystem`, `offers` `{price: 0, priceCurrency: USD}`, `softwareVersion` only if fetched at build time, `downloadUrl` pointing to the published artifact page.
- `SoftwareSourceCode`: `codeRepository`, `programmingLanguage`, `license` (SPDX URL), `runtimePlatform`, `author`, `sameAs` (repo, package registry pages).
- Optional `WebSite`. Docs pages: `BreadcrumbList` if the theme does not already emit it.

Never:
- `aggregateRating` or `review` without a real, sourced rating (OSS projects usually cannot qualify; fabricated ratings risk penalties).
- `FAQPage` markup to chase rich results. Since 2023 FAQ rich results only show for authoritative government/health sites. Add it only if the FAQ page genuinely exists, and treat it as entity data, not a ranking lever.

Check: every JSON-LD block parses (`jq`), required fields present, spot-check the landing in the Rich Results Test before launch (manual, not CI-able).

## 3. Crawl files

- `sitemap-index.xml` + `sitemap-0.xml` via `@astrojs/sitemap` with `site` set to the production origin. Every `<loc>` is https on the canonical host, returns 200, and is not `noindex`. Redirect stubs are excluded (`filter`). Keep `lastmod` truthful or omit it; Google ignores `priority`/`changefreq`.
- `robots.txt`: `Sitemap: https://<domain>/sitemap-index.xml`, no accidental `Disallow: /`. Allow search and AI-search crawlers (e.g. `OAI-SearchBot`, `PerplexityBot`, `Google-Extended` as the owner decides). If a CDN fronts the site, check that its "block AI bots" toggle is not silently on.
- `llms.txt` at the site root (or `/docs/llms.txt` on a subpath): `# Project` H1, a `>` blockquote summary that states "X is a Y for Z" identically to the landing and README first line, H2 sections listing `[name](url): note` links, an `## Optional` section. Generate with a Starlight plugin (e.g. `starlight-llms-txt`), optionally `llms-full.txt`. Every listed link returns 200. Treat it as agent usability, not a ranking signal.
- `404.astro` returns HTTP 404 on unknown paths (check `curl -o /dev/null -w '%{http_code}'`), links home and docs, keeps nav and theme.
- `/.well-known/security.txt` (RFC 9116: `Contact`, `Expires`, `Preferred-Languages`, `Canonical`) when the project has a security policy.
- `rel="me"` links to the project's own profiles once they exist (lets Mastodon-style profiles verify the domain later).

## 4. Redirects (SITE-34)

- Astro `redirects: { '/old/': '/new/' }`. On GitHub Pages these are meta-refresh stubs, the only redirect Pages supports; use a host with header redirects only if the owner approves moving hosts.
- After every route move: old URL serves the stub, stub target returns 200, stub path is absent from the sitemap, repo-wide grep for the old path returns 0.

## 5. Search intent and keywords (consumed from POS)

- Read `positioning.yml` `intent_map`: one canonical page per cluster (problem-aware, solution-aware, product-aware phrasing). Title, meta, H1 of that page use the cluster's exact words. Do not make two pages compete for one cluster.
- Free signals only unless the owner approves spend: GitHub topic/search counts (`gh api search/repositories -f q=topic:<t>`), autocomplete, Trends for synonym choice, and, after launch, Search Console queries ("high impressions, low CTR" → retitle).
- Page consistency: the landing meta description, README first paragraph, GitHub About, and registry descriptions stay identical or intentionally aligned. DSC owns that gate; SITE only keeps its copy sourced from `positioning.yml`.

## 6. Domain, hosting, indexing (SITE-44~46, SITE-50)

- Custom domain instead of `<user>.github.io/<repo>`: owns root `robots.txt`/`sitemap.xml`, portable canonical, clean Search Console Domain property.
- IaC order: DNS CNAME (CDN proxy off) + Search Console TXT → account/org verified domain → deploy → cert issued → `https_enforced` set together with `cname` → verify via `gh api repos/<o>/<r>/pages --jq '{cname,https_enforced,status}'` and `curl -I http://<domain>/` → 301.
- Search Console: Domain property via DNS TXT, submit `sitemap-index.xml`, URL Inspection "Request indexing" for the home page (manual). Bing Webmaster Tools: import from GSC. IndexNow ping from the deploy job is optional.

## 7. Analytics (SITE-49~51)

- Free, cookieless, no consent banner: the host/CDN's web-analytics beacon, GoatCounter (public dashboard possible), or self-hosted Umami. Pick one.
- Inject only when a build env var is set (e.g. `PUBLIC_ANALYTICS_TOKEN`), so forks and PR builds send nothing. Check the beacon appears in the production HTML and not in PR artifacts.
- If the tool lacks UTM support, attribution uses referrer only; note it in the handoff.
- GitHub traffic API keeps 14 days. Archiving it needs a scheduled job and often a new token; ask the owner before adding it (SITE-51).

## 8. CI verification script (run on `dist/` in the site PR job)

1. Build strict: `bun run build` with zero warnings; `bunx astro check`; `tsc --noEmit --strict` on copy modules; docs sync reports 0 unmapped pages.
2. Head tags per page (table in §1): one title, one description, absolute canonical, OG/Twitter set, no `noindex`; titles and descriptions unique and within length.
3. JSON-LD parses; required fields present; no `aggregateRating`/`review`.
4. Sitemap valid XML, host/https correct, no redirect stubs; robots has `Sitemap:`.
5. `llms.txt` present with H1 and summary; its links resolve.
6. OG image exists, 1200×630, <1 MB.
7. Link check: see `site-qa.md` §4.
8. Post-deploy job: `curl -I` for `/`, one docs page, sitemap, robots, llms.txt, og image, icons, manifest (200), a random path (404), `http://` (301).

## Sources

Google Search Central (title links, snippets, canonicalization, sitemaps, robots, software-app and FAQ structured data, 2023 HowTo/FAQ change), schema.org `SoftwareApplication`/`SoftwareSourceCode`, ogp.me, X cards markup, llmstxt.org, RFC 9116, Astro sitemap/redirects docs, Starlight docs, GitHub Pages custom-domain docs.
