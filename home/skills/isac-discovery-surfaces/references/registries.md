# Registry and store listing metadata (DSC-32~42)

Metadata files are the listing. Fill every field the registry renders, run the validator, then check the **rendered page** after the next release. Registries read metadata from the published package, so metadata changes appear only after a release (DSC-34). Submission to curated directories and any outreach is the marketing agent's job; this file covers metadata readiness only.

Common fields for every ecosystem (source: positioning source, DSC-45): one-liner/summary, long description (README), keywords/categories, homepage, repository, documentation, issues, changelog, license (SPDX), icon/logo, screenshots, brand color. Identifier == repo URL/namespace (DSC-33).

## 0. Which surfaces apply (by project type)

| project type | primary surfaces |
|---|---|
| Go library / CLI | pkg.go.dev, Go Report Card, GitHub Releases (goreleaser), Homebrew tap/core, distro packages, container image |
| Python library / CLI / MCP server | PyPI, MCP registry + MCP directories, conda-forge (optional), Homebrew |
| JS/TS package / MCP server | npm, MCP registry, JSR (optional) |
| Rust crate / CLI | crates.io, docs.rs, Homebrew, distro packages |
| K8s operator / controller / CSI | Helm OCI chart, Artifact Hub, container registry annotations, OperatorHub (OLM bundle, if used), Krew (kubectl plugin), ecosystem lists (e.g. official driver/implementation tables) |
| Desktop Linux app | Flathub + AppStream, distro channels (AUR, COPR, OBS, PPA), KDE Store/GNOME extensions, Repology, Snap |
| Editor extension | VS Code Marketplace, Open VSX |
| Web service | container registry (GHCR/Docker Hub), Helm/compose, Artifact Hub if charted |
| All | awesome-lists and catalogs (readiness only), AlternativeTo-type directories (readiness only) |

## 1. Per-ecosystem checklist

### Go — pkg.go.dev
- Module path in `go.mod` == repo path (`github.com/<owner>/<repo>[/vN]`); `/vN` suffix for v2+. Mismatch → pkg.go.dev 404. Rename by regenerating code (protobuf `go_package`, codegen, scaffolding metadata such as `PROJECT`), not hand edits; do not touch API group/domain identifiers.
- LICENSE must be recognized by pkgsite's allowlist, or README and API docs are hidden ("License UNKNOWN"). Diagnose with `google/licensecheck` (repo-surface §5).
- README.md renders on the module page; doc comments on package and exported symbols; runnable `Example*` functions.
- Refresh: `GOPROXY=https://proxy.golang.org go list -m <module>@<version>`. Bad versions: `retract` in `go.mod`; never re-tag.
- Verify: `curl -s https://pkg.go.dev/<module>@<version>` shows license and README; badge `https://pkg.go.dev/badge/<module>.svg`.

### Python — PyPI
- `pyproject.toml`: `description`, `readme` (content-type set), `license` (SPDX expression; `License ::` classifiers are deprecated), `keywords`, Trove `classifiers` (Development Status honest, Environment, Framework, Intended Audience, Operating System, Programming Language, Topic), `[project.urls]` with well-known labels (Homepage, Source, Documentation, Changelog, Issues, Funding).
- README images/links absolute. Validate: `uv build && twine check dist/*`.
- Dependency bounds are install UX (DSC-41): upper bounds where a known major break exists.
- Publish via OIDC trusted publishing on tag (`pypa/gh-action-pypi-publish`); tokenless.
- Verify: `curl -s https://pypi.org/pypi/<name>/json | jq '.info|{summary,project_urls,license_expression,classifiers}'` and the rendered page.
- Clean-env install of the README command (`uv tool install <name>` / `pipx install <name>`) with no local wheel (DSC-09). If deps are sdist-only on Linux, add per-distro build prerequisites to README.

### JavaScript — npm
- `package.json`: `description`, `keywords[]`, `homepage`, `repository` `{type,url}` (run `npm pkg fix`), `bugs`, `license` (SPDX), `funding`, `bin`, `engines`, `files`.
- README images absolute. Publish with `npm publish --provenance` from CI (provenance badge). MCP servers: `mcpName` field for registry ownership.
- Verify: `npm view <name> description keywords homepage repository` and the rendered page.

### Rust — crates.io
- `Cargo.toml`: `description` (required), `keywords` (≤5, slug form), `categories` (fixed slug list), `license`, `repository`, `homepage`, `documentation`, `readme`, `rust-version`.
- docs.rs builds automatically; set `[package.metadata.docs.rs]` features if needed.
- Verify: `cargo publish --dry-run`; `curl -s https://crates.io/api/v1/crates/<name> -A <ua> | jq .crate`.

### Helm chart — OCI + Artifact Hub
- `Chart.yaml`: `description` (plain, no marketing punctuation), `home`, `icon` (absolute raw URL of the brand mark), `sources`, `keywords`, `maintainers`, `kubeVersion`, `annotations`:
  - `artifacthub.io/license`, `artifacthub.io/category` (fixed list: e.g. `storage`, `networking`, `security`, `monitoring-logging`, `integration-delivery`, `database`, `streaming-messaging`, `ai-machine-learning`), `artifacthub.io/links` (Homepage, Documentation, Source, Support), `artifacthub.io/prerelease`, `artifacthub.io/operator`, `artifacthub.io/screenshots`, `artifacthub.io/changes` (structured changelog), `artifacthub.io/images` (for security scan).
- `artifacthub-repo.yml` (`repositoryID`, `owners`) → Verified publisher / ownership claim. For OCI repos push it to the `artifacthub.io` tag:
  `oras push <registry>/<ns>/<chart>:artifacthub.io --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml` — do it in the release workflow, not once by hand.
- `.helmignore` excludes repo-only files. Chart README ships in the package: absolute URLs only, OCI install only (`helm install oci://…`, `helm show chart` for the latest version).
- Register the repo in Artifact Hub (browser, one-time). Metadata updates appear only with a new chart version.
- Validate: `helm lint`, `helm template oci://… --version <v>` without a cluster, values JSON schema. Verify: `curl -s 'https://artifacthub.io/api/v1/packages/helm/<repo>/<chart>' | jq '{version,description,logo_image_id,links,license}'`.

### Container images
- OCI annotations: `org.opencontainers.image.{title,description,source,url,documentation,licenses,version,revision}`. `source` links GHCR packages to the repo.
- Docker Hub description does not auto-sync; sync README via CI action if Docker Hub is used.
- Multi-arch manifests; digest pinning documented; signatures + SBOM attestations (DSC-27).

### OperatorHub / Krew (if used)
- OperatorHub: OLM bundle CSV `metadata.annotations` (categories, containerImage, description, repository, support, capabilities), base64 icon, `spec.minKubeVersion`; `operator-sdk bundle validate`. Keep max/min K8s version annotations accurate.
- Krew: plugin manifest (`shortDescription` ≤50 chars, `homepage`, `platforms[]` with sha256); `krew-release-bot` for bumps.

### Desktop Linux — AppStream / Flathub
- `<id>.metainfo.xml`: `<name>` (<20 chars, just the name), `<summary>` (10–35 chars, sentence case, no trailing period, no "app/tool/client", no toolkit words), `<description>`, `<icon type="stock"><app-id></icon>`, `<branding>` light and dark `primary` colors (from the brand kit), `<screenshots>` (16:9, ≥1 default, captions, raw URLs pinned to a tag/branch that exists, no window shadows, real product), `<url type="homepage|bugtracker|vcs-browser|help|donation">`, `<releases>`, `<content_rating type="oars-1.1">`, `<developer id=…>`, `<launchable>`, `<provides>`.
- `.desktop` Icon == app id; hicolor PNG ladder (16…512) + scalable SVG installed; package depends on `hicolor-icon-theme` where required; window icon and About dialog (homepage, bug URL) use the same id.
- Validate: `appstreamcli validate --pedantic`, `desktop-file-validate`, `flatpak-builder-lint manifest|repo`. Flathub quality guidelines (homepage banner eligibility) are the bar, not only validity.
- Flathub policy: AI-generated submission PRs are banned — the agent prepares manifest and metadata; a human submits.
- KDE Store / Pling: logo 256/512, screenshots 1920×1080, banner; OCS categories. Repology picks up AUR/COPR/OBS automatically; embed its badge when coverage is real.

### Distro channels — AUR, COPR, OBS, PPA
| channel | metadata | write path | verify |
|---|---|---|---|
| AUR | `PKGBUILD` `pkgdesc`, `url`, `license`; `.SRCINFO` regenerated (`makepkg --printsrcinfo`); keywords | git push over SSH to `aur@aur.archlinux.org:<pkg>.git` (runs in an Arch container) | package page or fresh clone; RPC can be cached |
| COPR | project description (brand card at top), instructions (real newlines, one-line `dnf copr enable`), homepage, `appstream: true` | `copr-cli modify` or API v3 `POST /api_3/project/edit` (`~/.config/copr`) | rendered project page |
| OBS | `project.meta.xml` / package `_meta` title, description, url | `osc meta prj|pkg -e` or API PUT; keep build repositories intact | rendered page; `osc results` |
| PPA (Launchpad) | PPA displayname/description, links; logo lives on the owner profile, not the PPA | Launchpad web (login) + API for re-read | Launchpad API read |
| spec / debian | `URL:`, `Homepage:`, `Summary:`, descriptions | repo PR | `rpmspec -P`, `lintian` |

Pitfalls: literal `\n` stored in text fields; indexing flags off; empty keywords; package signing subkey not on a keyserver (silent PPA drop); stale caches. Never change source URLs that affect builds when editing metadata.

### Homebrew
- Formula `desc` (≤80 chars, no article/brand repetition), `homepage`, `license`; build from a stable tagged release with SHA-256; `brew audit --strict --new <formula>`, `brew test`.
- Own tap = zero gate (`brew install <owner>/<tap>/<name>`); core needs notability and passes CI — core submission is a release/packaging decision for the owner.

### MCP registries
- Official registry: `server.json` (`name` namespace-bound to auth: `io.github.<owner>/<name>` via GitHub OAuth, or `com.<domain>/<name>` via DNS/HTTP verification), `description`, `repository`, `version` == package version, `packages[]` pointing to the backing registry.
- Ownership proof in the backing package: PyPI/NuGet README line `mcp-name: <server-name>`; npm `mcpName`; OCI label.
- Before publishing, search for existing entries with your name: `curl -s 'https://registry.modelcontextprotocol.io/v0/servers?search=<name>'`. A fork may hold its own namespace legitimately; the fix is claiming yours plus ownership proof, not a takedown. Report misleading third-party descriptions to the owner as a separate decision.
- Tooling: `mcp-publisher init|login|validate|publish`. The registry API is still preview; re-verify after publish.
- Directories that index from GitHub or the official registry (Smithery, Glama, PulseMCP, mcp.so, Docker MCP catalog): clean README, topics (`mcp`, `mcp-server`), tool list, install snippets, optional `.well-known/mcp/server-card.json`; claim pages need a login (DSC-05). Plugin/marketplace manifests (e.g. agent plugin `marketplace.json`, `plugin.json`) are version-synced from the build manifest with `--check` (DSC-45).

### VS Code Marketplace / Open VSX
- `package.json`: `publisher` (immutable), `displayName`, `description`, `icon` (PNG, **no SVG**), `categories`, `keywords`, `galleryBanner` colors from the brand kit, `repository`, `homepage`, `bugs`, `qna`, badges only from approved providers.
- README/CHANGELOG images HTTPS and non-SVG unless from a trusted badge provider. Verified publisher needs domain control.
- `vsce package` / `vsce publish` (Entra ID workload identity; `--azure-credential`), `ovsx publish` for Open VSX with the same artifact.

### Awesome-lists and catalogs (readiness only, DSC-42)
- For each candidate list: its contributing rules (age, stars, CI, license, "no AI-generated PRs"), whether comparable projects are listed, and the exact one-line entry in that list's format (`- [Name](url) - Description.`).
- Catalogs with hard prerequisites (star thresholds, submitted conformance reports, maintained-status criteria): record the prerequisite and keep the item pending until true. Never fake status.
- Output: a readiness table (list, requirement, met?, entry line, assets). Filing the PR or submission belongs to the marketing agent.

## 2. Distribution coverage policy (DSC-38~40)

AGENTS.md section template:
```
## Distribution support policy
- Targets: <channel → distro/version list>. The README install matrix mirrors this list.
- EOL does not remove a target. Retire a target only when the build breaks or a required
  dependency bump is blocked. Platform-forced removals (EOL chroots deleted, obsolete series
  rejected) are decided per channel.
- New platform versions are tracked by .github/workflows/distro-release-watch.yml, which opens
  one idempotent issue per missing (distro, version).
- Every advertised target is tested by installing the published package in a container.
```
Watcher contract: scheduled weekly; data from endoflife.date + channel APIs (COPR mock chroots, Launchpad series, etc.); one issue per missing pair with a hidden marker and label; edits the body on diff; closes when every channel builds; no duplicates.

Release-step check: compare channel targets (chroots, series, OBS repositories) with the README matrix; fail on mismatch.

## 3. Release-coupled refresh (DSC-34)

- Metadata-only changes (description, icon, links, license text fix, module path) need a new version to reach registries. Propose a no-behavior-change release with the reason; owner approves.
- Bump every version string (build manifest, chart `version`/`appVersion`, install snippets); keep historical mentions deliberately, each with a reason.
- Before tagging, check for a concurrent release/tag from another session (base unchanged, tag free).
- After release, verify each registry page and JSON API (§1) and record before → after.
