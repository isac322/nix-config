# GitHub repo surface, README, community health, trust signals

Checklists and commands behind DSC-01~31, DSC-43~54. `{o}/{r}` = owner/repo. Commands are read-only unless marked **write**. Every write follows the approval gates in `isac-e2e-promo-readiness` and the IaC-first rule (DSC-19).

## 1. Repo settings: what, where, how

| setting | preferred write path | fallback | verify |
|---|---|---|---|
| description, homepage, topics | IaC (`github_repository`: `description`, `homepage_url`, `topics`) | **write** `gh repo edit {o}/{r} --description … --homepage … --add-topic …` | `gh repo view {o}/{r} --json description,homepageUrl,repositoryTopics` |
| Discussions, Issues, Wiki, Projects | IaC (`has_discussions`, `has_wiki`, …) | **write** `gh api -X PATCH repos/{o}/{r} -F has_discussions=true` | `gh api repos/{o}/{r} --jq '{has_discussions,has_wiki}'` |
| Pages + custom domain | IaC (`github_repository_pages`, `build_type = "workflow"`, `cname`) + `github-pages` environment restricted to protected branches | **write** `gh api -X PUT repos/{o}/{r}/pages -f cname=… -f build_type=workflow` | `gh api repos/{o}/{r}/pages --jq '{cname,https_enforced,status}'` |
| security: Dependabot alerts, private vulnerability reporting, secret scanning | IaC (`vulnerability_alerts`, security_and_analysis) | **write** `gh api -X PUT repos/{o}/{r}/private-vulnerability-reporting` | `gh api repos/{o}/{r}/private-vulnerability-reporting` |
| branch protection / rulesets, Actions permissions, variables | IaC | `gh api` | `gh api repos/{o}/{r}/rulesets` |
| social preview | none (no API) | logged-in browser, Settings → General → Social preview | GraphQL, §4 |

IaC notes (generalized from sessions):
- Import existing repos before managing them; plan must show import + add + small change, never destroy of the repo. Protect the repo resource with `prevent_destroy`.
- Provider quirks happen (e.g. one Pages provider version unset `cname` when `https_enforced` changed in a separate request). After apply, read the live state back; re-apply must report "No changes".
- Custom-domain order: DNS record (DNS-only, not proxied, for Pages certificate issuance) → Pages `cname` → wait for certificate → `https_enforced` → verify `http→https` 301 and 200 on `/`.
- Token scopes: extend an existing fine-grained token in place when a permission (e.g. Pages RW) is missing; document each scope in the variable description (DSC-04).
- The user runs applies that need secrets the agent lacks (`isac-decision-brief` DBR-17).

## 2. README template (evaluator-first)

```
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/logo/lockup-dark.svg">
    <img alt="<Name> — <category>" src="assets/brand/logo/lockup-light.svg" height="96">
  </picture>
</p>
<p align="center"><b><tagline from positioning source></b></p>
<p align="center"><a href="<site>">Website</a> · <a href="#install">Install</a> · <a href="<docs>">Docs</a> · <a href="CHANGELOG.md">Changelog</a></p>
<p align="center"><badges: CI · release · license · Scorecard · registry></p>

<Name> is a <category> for <audience/context>. <mechanism in one sentence>.   ← first ~160 chars = snippet

## Why            problem → mechanism → what it replaces (no hype, cite docs pages)
## Support matrix Shipped | Planned  (platforms, versions, backends, clients)
## Comparison     optional, dated, sourced, fair (where the alternative wins too)
## How it works   one diagram or 5–8 lines
## Install        published artifact only; executed verbatim in a clean env (DSC-09/10)
## Quickstart     smallest real end-to-end result
## Docs · Community · Security · License
```

Examples by project type (the first-line shape stays "X is a Y for Z"):
- CLI: `<name> is a command-line tool for <task> on <platform>.` Install: Homebrew / release binary / distro package.
- Library: `<name> is a <language> library for <task>.` Install: `go get` / `pip install` / `cargo add` / `npm i`.
- K8s operator/controller/CSI: `<name> is a Kubernetes <operator|CSI driver> that <does X> via <mechanism>.` Install: `helm install oci://…` (no checkout), plus `helm template` credential-free preview.
- Desktop GUI app: `<name> is a <thing> for <desktop environment>.` Install: Flathub / distro repos; screenshot below the fold.
- MCP/AI tool server: `<name> is an MCP server that lets agents <do X> in <system>.` Install: every client registration path (plugin marketplace, project `.mcp.json`, desktop config, `uvx`/`npx` one-liner), byte-identical across README and integration docs.
- Web service: `<name> is a self-hosted <category> for <audience>.` Install: container image + compose file.

Checks:
- Dark and light header both render on github.com (look at them).
- No links to missing files or internal docs; images use absolute URLs when the README ships inside a package.
- Heading texts and table row keys unchanged unless intended (SEO anchors).
- No volatile counts, no hedging status block, no change narrative in a first public release, no unshipped feature outside "Planned".
- Clean-env install transcript saved as release evidence (container image, exact commands, output tail).

## 3. About description and topics

Description (≤~160 chars): `<category noun phrase> for <context> — <mechanism/differentiator>`. Planned items never appear. Compare with competitors:
```
gh search repos "<category keywords>" --sort stars --limit 20 --json fullName,description,stargazersCount
```

Topic selection method (≤20):
1. Candidates from `keywords.topics` in the positioning source + ecosystem terms (`kubernetes`, `helm-chart`, `mcp-server`, `kde`, `cli`, language) + implemented technologies + usage context (`self-hosted`, `bare-metal`, only if true for real users).
2. Measure each topic page population: `gh api -X GET search/repositories -f q='topic:<t>' --jq .total_count`.
3. Mix: 3–6 broad topics (exposure) + niche compound topics with small populations where the project can rank near the top (e.g. `<tech>-<protocol>`, `<platform>-<feature>`).
4. Drop: unshipped features [U], synonyms that split the same audience without traffic, misspellings, brand names of third parties unless the project integrates with them (referential use only).
5. Record the table (topic, population, reason, shipped evidence file:line) in the PR description.

## 4. Social preview upload (DSC-18)

1. Image from `isac-brand-identity`: 1280×640 PNG, <1 MB, safe margins (GitHub crops on some surfaces).
2. Read-only check that the browser session has admin on the repo (Settings page loads).
3. View the image yourself before upload.
4. **write** Settings → General → Social preview → Edit → Upload.
5. Verify:
```
gh api graphql -f query='query{repository(owner:"{o}",name:"{r}"){usesCustomOpenGraphImage openGraphImageUrl}}'
```
   `usesCustomOpenGraphImage` must be `true` and `openGraphImageUrl` must point at a new `repository-images` URL; reload and query again; fetch the URL and inspect it.
6. Repeat after any palette/name change (DSC-52).

## 5. Community health and trust signals

| item | file / setting | check |
|---|---|---|
| Community profile | README, LICENSE, CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, SUPPORT.md, `.github/ISSUE_TEMPLATE/*.yml`, `.github/PULL_REQUEST_TEMPLATE.md` (root, `docs/`, or `.github/`) | `gh api repos/{o}/{r}/community/profile --jq .health_percentage` = 100 |
| Issue forms | `bug_report.yml` (repro steps, version, environment required), `feature_request.yml`, `tried_it.yml` (worked / failed at step N, env, version), "How did you find <Name>?" dropdown in each, `config.yml` with `blank_issues_enabled: false` + Discussions + security contact links | render each form on github.com |
| Discussions | Q&A (answerable), Announcements, Ideas, Show and tell | `gh api repos/{o}/{r} --jq .has_discussions` |
| Contributor entry | CONTRIBUTING dev-setup quickstart, labels `good first issue` / `help wanted`, 3–8 scoped issues with file paths and acceptance criteria (owner confirms creation) | `gh issue list -l "good first issue"` |
| Security policy | SECURITY.md (supported versions, report path, response targets), private vulnerability reporting on, site `/.well-known/security.txt` (RFC 9116) | API in §1; `curl -s https://<site>/.well-known/security.txt` |
| Supply chain | SHA256SUMS, cosign signatures, SBOM (SPDX/CycloneDX via syft or goreleaser), GitHub artifact attestations / SLSA provenance, OIDC trusted publishing | `gh release view --json assets`; `gh attestation verify <file> -R {o}/{r}` |
| Scorecard | `ossf/scorecard-action` weekly, `publish_results: true`, README badge | `curl -s https://api.scorecard.dev/projects/github.com/{o}/{r}` returns a score |
| Best Practices | bestpractices.dev self-certification (infra projects) | badge URL resolves |
| Readiness lint | CLOMonitor linter or repolinter rules in CI (readme, license, CoC, contributing, maintainers, security, changelog, roadmap, SBOM, signed releases, token permissions) | CI job |
| License detectability | canonical license text; REUSE headers where the ecosystem expects them | `gh api repos/{o}/{r} --jq .license.spdx_id` ≠ `NOASSERTION`; `licensecheck` match ≈100% |
| Citation | `CITATION.cff` (authors, version, DOI) | `cffconvert --validate`; "Cite this repository" appears |
| Governance | MAINTAINERS / CODEOWNERS, honest solo-maintainer statement, ROADMAP, CHANGELOG (Keep a Changelog) | files exist, linked from README |
| Gated | ADOPTERS (≥1 real external user), FUNDING.yml (owner decision) | — |

License detection diagnosis (DSC-29):
```
# Go example: compare against what the registry proxy has
GOPROXY=https://proxy.golang.org go mod download -json <module>@<version>
# run google/licensecheck (small Go program: licensecheck.Scan(text)) → coverage %, matched IDs
```
If coverage < ~90%: diff against the canonical SPDX text, show the dropped/renamed clauses, offer options to the owner, never edit legal text unilaterally. The fix reaches the registry only with a new tag (DSC-34).

## 6. Parity rule text (AGENTS.md + PR template)

AGENTS.md section (English, adapt names):
```
## Code, docs, website, and listings must match (mandatory)
- The code is the source of truth. Docs, the website, the README, package manifests,
  and registry listings must describe exactly what the code does.
- Any mismatch is a defect equal to a failing test. Fix it in the same PR.
- Before every merge, check parity for everything the PR touches; a mismatch blocks the merge.
- Positioning facts (one-liner, keywords, counts, versions) come only from <positioning source>
  and are synced by <sync script>; never hand-edit generated copies.
- Sources of truth: <API schema / CRD dir>, <generated reference>, <docs/adr/>, <positioning source>.
```
PR template checkboxes:
```
- [ ] Code, docs, website, README, and listings match (parity rule in AGENTS.md)
- [ ] `<sync script> --check` and `<docs/site build + check command>` pass
```

Sync/check script contract (DSC-45/46): reads the positioning source and code (version from the build manifest, counts computed from code), writes or compares README markers, About (via IaC vars), site meta source, package manifests, plugin/marketplace manifests; `--check` exits non-zero with a diff; CI runs it on every PR touching docs, site, manifests, or code that affects counts.

## 7. Post-change live verification (DSC-51)

```
gh repo view {o}/{r} --json description,homepageUrl,repositoryTopics,openGraphImageUrl,usesCustomOpenGraphImage,hasDiscussionsEnabled,licenseInfo
gh api repos/{o}/{r}/community/profile --jq '{health_percentage,files}'
curl -sI https://<homepage>/            # 200, http→https 301
```
Plus every registry/store page and JSON API from `registries.md`, and every distribution channel page. Record per surface: before → after, write method, verify command, result, pending/blocked.
