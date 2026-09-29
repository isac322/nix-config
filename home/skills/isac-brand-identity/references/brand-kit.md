# Brand kit: layout, generator, file/size matrix, rebrand surfaces

Used by BRD-32–BRD-42. Default location is `assets/brand/` when the repo has no convention [U]. If the repo already has one (e.g. `branding/`, `docs/brand/`), use it and do not create a second.

## 1. Layout

```
assets/brand/
  README.md              usage rules + asset index + regenerate command (§6)
  brand.json             single constants file: palette (roles, hex, dark/light), grid unit, font file paths, names
  generate.<ts|py>       the only generator; reads brand.json, writes everything below + served copies
  src/                   hand-authored path-only SVG masters (mark, mark-small, wordmark)
  mark/                  mark-{color-dark,color-light,mono-black,mono-white,currentcolor}.svg
  logo/                  horizontal-{dark,light,mono}.svg, stacked-{dark,light}.svg, wordmark-{dark,light}.svg
  icon/                  icon-app.svg (+ platform PNG ladders), avatar-512.png
  favicon/               favicon.svg, favicon.ico, apple-touch-icon.png, icon-192.png, icon-512.png, icon-maskable-512.png, site.webmanifest
  social/                github-social-preview.{svg,png}, og.{svg,png}, readme-banner-{dark,light}.svg, release-banner.{svg,png}
  store/                 per-registry/store icons and banners that apply (§4)
  palette/               palette.svg, palette.json, palette.css (tokens consumed by the site and DESIGN.md)
  mascot/                only if a mascot exists; LICENSE note (CC-BY or CC0)
```

Screenshots, recordings and wallpapers belong to `isac-demo-media`; they may live in a sibling folder but are not generated here.

## 2. Generator

Language: the repo's own toolchain. If the repo has none that fits, a Bun TypeScript script or a Python standard-library script. One entry point, one command in the README.

Requirements:

- Reads only `brand.json` and `src/*.svg`. Changing a colour or name is one constant edit + one run.
- Bakes text to paths: author wordmarks as paths; for generated cards with text, lay out with a pinned font file and flatten with usvg (`usvg --skip-system-fonts --use-font-file <font> in.svg out.svg`). No `<text>` element survives in any committed SVG.
- Renders PNG with resvg at exact sizes (`resvg -w 512 -h 512 in.svg out.png`, `--skip-system-fonts --use-font-file` when text remains), then `oxipng -o 4 --strip safe`.
- Builds ICO from the 16/32/48 PNGs (ImageMagick `magick icon-16.png icon-32.png icon-48.png favicon.ico` or a library equivalent).
- Writes the site's served copies (favicon set, manifest, OG image, logo SVGs) byte-identically into the site's public directory, so the site never holds a hand-edited copy.
- Deterministic: a second run changes zero files. Pin tool versions (e.g. `nix shell nixpkgs#resvg nixpkgs#oxipng`, or a lockfile).

Gates (run after every regeneration):

| Gate | Command idea |
|---|---|
| Idempotent | run twice; `git status --porcelain assets/brand` empty after the second run |
| SVG masters unchanged | byte-identical after regen; rasters identical or RMSE within a stated tolerance (e.g. ≤0.03 %) |
| No `<text>` | search committed SVGs for `<text` → 0 hits |
| Sizes | `file *.png` matches the matrix; social preview < 1 MB |
| Served copies | `cmp` each site copy with its kit source |
| Manifest | JSON parses; every icon path exists with the declared size and purpose |
| Palette | no hex outside `brand.json` in kit SVGs; forbidden third-party hexes absent (BRD-31) |
| Eyes | the agent opens every PNG once |

## 3. File / size matrix

Every row is required unless the project type makes it inapplicable; record "n/a because …" rather than silently skipping.

| Asset | Spec | Notes |
|---|---|---|
| Mark | SVG × {color dark, color light, mono black, mono white, `currentColor`} | `currentColor` variant is the one inlined in site/README chrome |
| Small mark | SVG for 16–24 px | simplified geometry, own master |
| Logo horizontal | SVG × {dark, light, mono} | mark + wordmark, text outlined |
| Logo stacked | SVG × {dark, light} | for square slots (landscape tiles, store cards) |
| Wordmark | SVG × {dark, light} | paths only; never re-typeset |
| App icon | `icon-app.svg` on a brand ground, mark at ~60 % inside a circle-safe area | source for every platform icon |
| favicon.svg | mark only, square viewBox, `prefers-color-scheme` media query inside the SVG for dark tabs | must read at 16 px |
| favicon.ico | 16/32/48 frames | legacy browsers and some crawlers |
| apple-touch-icon.png | 180×180, opaque brand ground, ~20 px padding | no transparency |
| Manifest icons | `icon-192.png` (any), `icon-512.png` (any), `icon-maskable-512.png` (purpose `maskable`, content inside the central 80 % circle) | check with a maskable preview |
| site.webmanifest | `name`, `short_name`, `description`, `start_url`, `scope`, `display`, `theme_color`, `background_color`, `icons[]` | colours read from `brand.json`; SITE wires `<link rel="manifest">` |
| theme-color | value(s) from `brand.json`, light and dark (`media="(prefers-color-scheme: dark)"`) | SITE renders the meta tags |
| GitHub social preview | 1280×640 PNG, < 1 MB, solid (non-transparent) background, key content away from edges | uploaded by `isac-discovery-surfaces` via Settings UI; separate from OG |
| OG image | 1200×630 PNG, < ~1 MB, absolute URL | SITE references it in `og:image`/`twitter:image` |
| Avatar | 512×512 PNG, circle-crop safe (mark ≤ ~72 % of width) | GitHub org/user, registries, chat |
| README banner | 1280×320 SVG dark + light, used via `<picture>` with `prefers-color-scheme` | alt text = product name + one-line what-it-is |
| Release banner | 1280×320 PNG | optional; for release pages |
| Palette | `palette.json`, `palette.css`, `palette.svg` swatch sheet with contrast numbers | consumed by DESIGN.md and site tokens |
| Usage doc | `README.md` (§6) | source for a public brand page built by SITE |

## 4. Platform / registry / store icons (add the rows that apply)

Verify current specs at the source before producing; these change.

| Surface | Spec (as last verified) |
|---|---|
| Linux desktop (freedesktop hicolor) | scalable SVG + PNG ladder 16, 22, 24, 32, 48, 64, 128, 256 (512 optional); icon name = reverse-DNS app id; optional `-symbolic` monochrome |
| Flathub / AppStream | icon ≥128 (256/512 recommended), `<branding>` light and dark colours that contrast with the icon, screenshots per `isac-demo-media` |
| macOS app | `.icns` 16–1024 incl. @2x |
| Windows app | `.ico` 16, 24, 32, 48, 64, 256 |
| Android / PWA | adaptive/maskable foreground inside the safe zone |
| KDE Store / similar app stores | logo 256 or 512 |
| Launchpad | icon 14×14, logo 64×64, brand 192×192, each ≤100 KB |
| Artifact Hub (Helm chart) | `icon` URL in `Chart.yaml` pointing to the kit SVG/PNG raw URL |
| OperatorHub | base64 icon in the CSV (`spec.icon`) |
| CNCF-style landscape | SVG with the English project name, no reversed background, stacked variant preferred |
| VS Code Marketplace / Open VSX | PNG icon 128×128+, **no SVG**; `galleryBanner` colour from the palette |
| MCP directories (e.g. Smithery) | icon ≤1 MB, PNG/SVG/WebP |
| Container registries (Docker Hub org) | square avatar from `avatar-512.png` |
| PyPI / npm / crates.io | no icon field; README images must use absolute HTTPS URLs to the kit |

## 5. Rebrand / recolor surface list (BRD-39–BRD-41)

Before editing: re-render the old masters and diff against committed PNGs to recover the exact recipe (AE=0). Then change `brand.json`, regenerate, and walk this list. Every row ends "updated", "n/a" or "handed to <skill>" with evidence.

In-repo (this skill updates):
- kit outputs, site public copies, favicon.ico frames, manifest icons and `theme_color`
- installed app icons (hicolor ladder, `.icns`, `.ico`), window icon, About metadata
- AppStream `<branding>` colours, packaging icon references
- README header/banner, README badge colours that use brand hex
- DESIGN.md tokens, `positioning.yml` `brand:` block, site CSS tokens
- proof: old-hex grep = 0 across the repo (excluding real product captures); pixel scan of rasters for old-palette pixels = 0

Outside the repo (hand to `isac-discovery-surfaces`, then re-verify live):
- GitHub social preview (re-upload; verify GraphQL `openGraphImageUrl` changed and `usesCustomOpenGraphImage: true`)
- GitHub org/user avatar if it uses the mark
- registry/store icons and listing images (Artifact Hub, OperatorHub, Flathub, app stores, MCP directories, VS Code, Launchpad, COPR/OBS/AUR pages that embed images)
- release banners already attached to releases
- external READMEs or docs that hotlink kit images
- social-card caches: re-scrape with the platforms' debuggers after the OG image changes (list them; posting is out of scope)

Registry icons read from published packages may need a no-behaviour-change release; report and ask (BRD-42).

## 6. Usage doc template (`assets/brand/README.md`)

1. **Concept** — one paragraph: the mechanic/culture the mark comes from.
2. **Files** — table: file, use, ground (dark/light/any), min size.
3. **Palette** — role, hex, dark/light variants, contrast table; "graphics only" colours marked.
4. **Typography** — wordmark typeface and licence (wordmark ships outlined; do not re-typeset), site text faces.
5. **Clear space** — e.g. the mark's inner unit on every side.
6. **Minimum sizes** — e.g. small mark 16–24 px, full mark ≥32 px, wordmark ≥80 px wide, horizontal lockup ≥48 px tall.
7. **Do / Don't** — don't recolour outside the palette, stretch, rotate, add effects, re-typeset the wordmark, place on low-contrast grounds, or pair with third-party logos in a way that implies affiliation.
8. **Third-party marks** — referential use rules and the non-affiliation statement (BRD-30).
9. **Licence and trademark** — asset licence (and mascot licence if any), who may use the name/logo and how (a short trademark statement; foundation-style policies are the model).
10. **Regenerate** — the exact command and required tools.

## 7. Sources

- Evil Martians, "How to Favicon" (minimal favicon set, maskable safe zone): https://evilmartians.com/chronicles/how-to-favicon-in-2021-six-files-that-fit-most-needs
- W3C Web App Manifest: https://www.w3.org/TR/appmanifest/
- GitHub social preview docs: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview
- Open Graph protocol: https://ogp.me
- CNCF artwork deliverable matrix: https://github.com/cncf/artwork · https://www.cncf.io/brand-guidelines/
- Linux Foundation trademark usage: https://www.linuxfoundation.org/legal/trademark-usage · Rust trademark policy (hosted policy example): https://rustfoundation.org/policy/rust-trademark-policy/
- Flathub quality guidelines: https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines
- resvg/usvg: https://github.com/linebender/resvg · oxipng: https://github.com/oxipng/oxipng · SVGO: https://github.com/svg/svgo
- Name clearance: https://opensource.guide/starting-a-project/#avoiding-name-conflicts · https://branddb.wipo.int · https://tmsearch.uspto.gov · https://www.tmdn.org/tmview · https://github.com/sherlock-project/sherlock
- Contrast: https://github.com/color-js/color.js · https://github.com/Myndex/apca-w3 · https://github.com/adobe/leonardo
