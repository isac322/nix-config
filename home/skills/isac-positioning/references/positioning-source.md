# Positioning source file — schema, template, consumers

The single source of truth that POS-34 to POS-40 require. One machine-readable file per repository. Default path: `positioning.yml` at the repository root. If the repository already has a convention (for example `.claude/positioning.yml` or `docs/positioning.yml`), keep that path and do not create a second file.

Rules that apply to every field:

- Every claim-bearing field carries `evidence` (`path:line` or `path:start-end` at `meta.pinned_commit`) or a `proof_page`. A field without either is a draft and must not reach a surface.
- Owned-surface copy (site, README, About, manifests, registry descriptions) is derived from this file or checked against it. The parity gate and its CI script belong to `isac-discovery-surfaces` (DSC). Writers never add a claim that is not in this file.
- Keywords, counts and descriptions live only here. Agent instructions (`AGENTS.md`, `CLAUDE.md`, `.agents/rules/*`) point to this file and never copy its lists.
- Public strings are English unless `identity.languages` says otherwise, and are passed through `writing-clearly-and-concisely` and `humanizer` before they are approved.
- Nothing in this file is promotional channel copy. Launch posts, fact sheets and press text belong to the separate marketing agent, which may read this file but does not write it.

## 1. Template

```yaml
# positioning.yml — single source of truth for positioning. Schema: isac-positioning.
meta:
  schema: 1
  version: 1.0.0            # bump minor on content change, major on schema change
  pinned_commit: <sha>      # every evidence path:line is valid at this commit
  updated: YYYY-MM-DD
  approved_by_owner: false  # set true only after the E2R owner gate (POS-39)

identity:                   # POS-01 answers; owner-decided, never agent-guessed
  name: <product name as written>
  qualifier: <e.g. "for <platform>", "-cli"; required when the bare name collides>
  repo: <owner>/<repo>
  homepage: https://<domain>/
  license: <SPDX id>
  languages: [en]           # public languages; record the i18n decision
  goal: users               # users | contributors | funding (primary)
  fixed_brand_parts: []     # e.g. [logo, wordmark]; the rest is extendable
  legacy_pages: replace     # replace | keep | redirect

category:
  premise: <one sentence that places the project in a category; not a numbered selling point>
  tagline: <≤ 60 chars; hero line / README bold line>
  one_liner: <≤ 120 chars; "helps X who are trying to do Y" + differentiator>
  about_description: <≤ 120 chars recommended (GitHub max 350); identical to README lead and package description where the registry allows>
  meta_description: <150–160 chars; landing meta description>
  registry_description:     # per-registry variants only where a registry imposes limits or a format
    default: <same as about_description>
    # <registry>: <text>     # e.g. helm chart, pypi summary, appstream summary, mcp registry

audience:
  primary: <role + environment, e.g. "platform engineers running self-hosted Kubernetes">
  secondary: [<role>]
  jobs_to_be_done:
    - <when ..., I want to ..., so I can ...>
  surface_priorities:       # POS-18; owner-stated first jobs per surface
    landing: <e.g. "brand recognition first">
  visitor_model:            # POS-16
    - source: <search cluster id | github-readme | registry | forum-link | docs-deeplink>
      who: <role, what they already know>
      questions_60s: [<what is it>, <does it fit my setup>, <how do I try it>]
      first_action: <install command | demo | docs page>
      landing_page: <path>

selling_points:             # POS-20..POS-23; 3–5 items
  - id: SP1
    headline: <≤ 8 words>
    benefit: <one line: why an engineer would switch>
    mechanism: <how it works, one or two sentences>
    evidence: [<path:line>]
    proof_page: <site path that proves it>
    status: shipped         # shipped only; planned items go to `planned`

evidence:                   # POS-22; counts are evidence, never selling points
  counts:
    - key: <e.g. tool_count>
      value: <n>
      source: <path:line or command that computes it>
      shown_on: [<proof page path>]   # never hero, H1, title, About
  validation:               # POS-24; scope stated exactly
    - claim: <e.g. "passes the upstream core conformance suite">
      scope: <local run | upstream submitted | simulated | real infrastructure; what was disabled>
      proof_page: <path>
  proof_inventory:          # POS-17
    claimable: [<fact + evidence>]
    not_claimable: [<fact + why>]
  demo_only_we_can_show: <one sentence; handed to isac-demo-media>

anti_claims:                # POS-25; every surface writer filters against this
  - never_say: <phrase or pattern>
    because: <reason>
    evidence: <path:line | URL | "no evidence exists">
cliches: [<category clichés from POS-08, verbal and visual>]

maturity:                   # POS-29..POS-31 [U]
  real_usage: <who runs it, where, since when — owner-confirmed fact>
  api_stage: <e.g. v1alpha1 | 0.x | stable>
  surfaces:
    site: <shipped facts only; no hedging, no over-claims>
    readme: <same rule>
    registry: <same rule>
  banned_hedges: [experimental, preliminary, "not production"]   # when owner runs it in production
  banned_overclaims: [production-grade, battle-tested, highly available]

planned:                    # POS-30; visible as "planned" in matrix/roadmap only
  - feature: <name>
    tracking: <issue URL>
    never_in: [title, meta, h1, topics, about, social_card, registry_keywords]

baseline:                   # POS-26; the only comparison on main surfaces
  name: <platform default tool or DIY combination>
  documented_limits:
    - limit: <text>
      source: <official docs URL>
      checked_on: YYYY-MM-DD
comparison_pages:           # POS-27; owner decision, off main surfaces
  enabled: false
  pages:
    - query: <exact query, e.g. "<tool> alternative">
      path: <site path>
      where_they_win: [<honest point>]
      checked_on: YYYY-MM-DD
predecessors:               # exact relationship wording, owner-approved
  - name: <project>
    relation: <"inspired by" | "spiritual successor" | "fork of"…>

keywords:                   # POS-12..POS-14
  primary: [<category term>]
  secondary: []
  long_tail: []
  github_topics:            # candidates with populations; DSC selects and applies
    - topic: <topic>
      population: <gh total_count>
      checked_on: YYYY-MM-DD
  registry_keywords:        # DSC applies per-registry limits
    default: []

intent_map:                 # POS-13; one canonical page per cluster
  - cluster: <id>
    stage: problem | solution | product | evaluation
    queries: [<exact phrases practitioners type>]
    signals: [<evidence: autosuggest, topic count, thread URL + score>]
    canonical_page: <path>
    title: <uses the cluster wording>
    h1: <uses the cluster wording>
    meta: <150–160 chars>

third_party_marks:          # POS-32..POS-33
  - mark: <mark as written by its owner>
    owner: <company or foundation>
    guideline_url: <URL>
    first_use_symbol: <™ | ® | none>   # applied on first rendered use when the guideline asks
    referential_form: "<Project> for <Mark>"
    forbidden: [possessive, verb use, logo, brand colors, meta keywords]
    footer: <verbatim non-affiliation text>

objections:                 # POS-28; FAQ material, not reply drafts
  - question: <e.g. "why not <baseline> plus config?">
    answer: <short, factual>
    evidence: [<path:line | proof page>]
    source_threads: [<URL>]

brand:                      # filled by isac-brand-identity; POS does not edit
  guide: assets/brand/README.md
  assets: {}
  palette: {}
  social_preview: <path>
```

## 2. Field constraints

| Field | Constraint | Why |
|---|---|---|
| `category.tagline` | ≤ 60 chars, no metaphor, no count, no third-party mark possessive | Hero and README bold line must read cold |
| `category.about_description` | ≤ 120 chars recommended; identical across About, README lead, package description when limits allow | Registry and GitHub snippets are the first impression |
| `category.meta_description` | 150–160 chars; first plain-prose paragraph of the page may reuse it | Search snippet length |
| `selling_points[].headline` | ≤ 8 words | Scannable in 60 s |
| `selling_points[].evidence` | ≥ 1 `path:line` valid at `pinned_commit` | POS-21 |
| `evidence.counts[].shown_on` | proof pages only | POS-22 |
| `planned[]` | never in title/meta/H1/topics/About/social card/registry keywords | POS-30 [U] |
| `third_party_marks[]` | at most one referential sentence per description; never in keywords | POS-32 |
| `keywords.*` | only here; agent instructions point to this file | POS-14 |

## 3. Consumers

| Consumer | Reads | Writes |
|---|---|---|
| isac-e2e-promo-readiness (E2R) | whole file for the steering report and owner gate | `meta.approved_by_owner` after the gate |
| isac-brand-identity (BRD) | `identity`, `category`, `audience`, `cliches`, `third_party_marks`, `surface_priorities` | `brand` |
| isac-project-site (SITE) | `category`, `audience.visitor_model`, `selling_points`, `evidence`, `anti_claims`, `maturity`, `planned`, `baseline`, `comparison_pages`, `intent_map`, `third_party_marks`, `objections` | nothing; new claims go back to POS |
| isac-discovery-surfaces (DSC) | `category.*description*`, `keywords`, `evidence.counts`, `maturity`, `planned`, `identity` | nothing; its parity script fails CI on drift |
| isac-demo-media (MED) | `evidence.demo_only_we_can_show`, `selling_points`, `audience.visitor_model` | nothing |
| impeccable (via BRD/SITE) | `PRODUCT.md` derived from this file | — |
| marketing agent (out of scope) | read-only | never |

## 4. PRODUCT.md (impeccable) derivation

`impeccable context` looks for a product file. Generate it from this file; keep facts, keywords and counts out of it and point to `positioning.yml` instead.

```markdown
# PRODUCT
Source of truth: positioning.yml (schema 1, version <v>, commit <sha>). Facts, keywords and counts live there.

## Users
<audience.primary>; secondary: <…>. Jobs: <jobs_to_be_done>.

## Purpose
<category.premise>

## Brand commitments
<identity.fixed_brand_parts>, <surface_priorities>, tone in three adjectives, what the brand must never look like (<cliches>).

## Principles
- Every claim cites evidence in positioning.yml.
- Maturity: <maturity.surfaces.site>.

## Anti-claims
See positioning.yml `anti_claims` (<n> entries). Top 5 inline: <…>.
```

## 5. Examples of premise, selling point and anti-claim by project type

Illustrative shapes only; never copy them as claims.

| Type | Premise shape | Selling point shape (headline → mechanism → evidence) | Typical anti-claim |
|---|---|---|---|
| CLI | "<verb> <object> from your terminal" | "One binary, no runtime" → static build → build config line + release asset list | "zero dependencies" when it shells out to other tools |
| Library | "<capability> for <language> with <constraint>" | "No allocation on the hot path" → pooled buffers → source line + benchmark page | "fastest" without a published, reproducible benchmark |
| K8s operator/controller | "<standard API> implementation for <platform>" | "No inbound ports" → outbound tunnel only → controller source line + architecture page | "conformant" before an upstream report is accepted |
| Desktop GUI app | "<app kind> for <desktop environment>" | "Native to <display protocol>" → protocol-level integration → source line + screenshot page | "replacement for <predecessor>" when it is not a fork |
| MCP / AI tool server | "Lets <agent clients> operate <system>" | "Works with any MCP client" → spec-only transport → server source line + client matrix page | "<n> tools" as a headline |
| Web service | "<outcome> for <team type>, self-hostable" | "Your data stays on your server" → no outbound telemetry → config line + privacy page | "enterprise-grade" without the controls to prove it |

## 6. Validation before handoff

- [ ] Every `evidence` path opens at `pinned_commit` and supports the sentence (independent truth reviewer, POS-38).
- [ ] No `planned` item appears in `category`, `keywords`, `intent_map[].title/h1`.
- [ ] No count appears in `category` or `selling_points[].headline`.
- [ ] No third-party competitor name appears in `category` or `selling_points`; comparison only with `baseline`.
- [ ] `third_party_marks` has a fetched guideline URL for every mark used anywhere in the file.
- [ ] `maturity` matches `real_usage` confirmed by the owner.
- [ ] `yq '.' positioning.yml` parses; DSC's parity script can load it.
- [ ] Identity-level fields approved at the E2R gate (POS-39); `meta.approved_by_owner: true`.
