# Logo / icon / palette critique rubric

Used by BRD-18–BRD-25. Two independent critics score every candidate, then the orchestrator merges. Critics never see each other's output before submitting. Design craft judgment still runs through `impeccable` (critique/`detect`); this rubric adds the mark-specific checks impeccable does not cover.

## 1. Contact sheet (input every critic receives)

One PNG/HTML sheet per candidate, rendered with resvg from the SVG master — never a screenshot of a design tool.

| Row | Content |
|---|---|
| Size ladder | 16, 24, 32, 48, 128, 256 px, each on dark and light ground; the 16–24 px cells use the small master |
| Avatar crop | 512 px square masked to a circle (GitHub/registry/social avatars) |
| Lockup | horizontal lockup at 28 px nav height; stacked lockup at 128 px |
| One-colour | mono black, mono white, `currentColor` on a mid-tone ground |
| Favicon tab | 16 px inside a mock browser tab strip, dark and light UI |
| Context mocks | see §2 for the project type |
| Neighbours | the mark at the platform's real icon sizes next to the icons it will actually sit beside (label hand-drawn neighbours "approximation") |

The sheet header states which impeccable steps ran (BRD-10) and the grid unit used.

## 2. Context mocks by project type

Show the mark where a user will actually meet it. Pick every row that applies.

| Project type | Mocks to include |
|---|---|
| CLI / TUI | terminal title bar and prompt at 14 px text size; README header on GitHub dark and light; shell-completion or `--version` banner if one exists |
| Library / SDK | README badge row; docs sidebar logo at 24–32 px; package-registry page header crop |
| K8s operator / controller | README header; Artifact Hub / OperatorHub card (icon at 64–128 px on white); architecture diagram node; landscape-style square tile |
| Desktop GUI app | real launcher/dock/panel at the platform's sizes (e.g. 22/44 px panel, 48 px app grid), window title bar, app store tile; next to the default apps of that desktop |
| MCP / AI tool server | MCP client server list row (16–24 px), registry card, README header |
| Web service | browser tab, bookmark bar, PWA home-screen icon (maskable crop), landing hero |
| All | GitHub social preview card, org/repo avatar circle, README header dark/light |

## 3. Critic A — brand

Score each 1–5, one line of evidence each.

1. **Memorability / silhouette** — recognisable as a filled silhouette at 32 px; describable in five words.
2. **Mechanism fit** — carries the product's signature mechanic or the audience's cultural material (BRD-12, BRD-14), not only the name.
3. **Distinctiveness vs category defaults** — differs from the category rut (e.g. hexagon/cube for infra, shield for security, sparkle or gradient blob for AI, whale/ship for containers, generic gear for tooling) and from the neighbours row.
4. **Premium feel** — would a professional identity designer ship it; no "cheap" cues (uneven weights, clip-art gradients, default drop shadows).
5. **Wordmark pairing** — mark and wordmark share stroke logic, proportion and one idea; lockup reads as one unit.
6. **Literalness budget** — at most one literal reading of the name across the candidate set unless the owner asked for literal (BRD-13).
7. **Brand checklist** — passes the 8–12 verifiable checks written for this project (BRD-22).

## 4. Critic B — craft and legibility

1. **16 px legibility** — the small master is still identifiable at 16 px on both grounds; no detail thinner than 1 px at that size; counters stay open.
2. **Even-grid geometry** — drawn on a declared grid (e.g. 32 or 64 units), coordinates on whole or half units, stroke widths from one scale, corner radii from one set, optical (not only mathematical) centring.
3. **Pixel alignment** — horizontal/vertical edges land on pixel boundaries at 16/32/48 px; no half-pixel blur.
4. **Optical weight** — consistent stroke weight across mark and wordmark; the mark does not look heavier or lighter than neighbour icons at the same size.
5. **Crop safety** — survives circle avatar crop and the maskable safe zone (central circle, 80 % diameter) without clipping meaning.
6. **One-colour and reversed** — works in mono black, mono white and `currentColor`; no meaning carried only by colour.
7. **Contrast** — every mark/ground pair used in the kit meets 3:1 (graphics) and the wordmark meets 4.5:1 where it acts as text; numbers recorded (BRD-27).

## 5. Mandatory flags (either critic)

- **Confusable universal symbols** — power button (IEC 5009 circle-and-line), plug/socket, wall/brick, play/pause, hamburger menu, refresh arrows, download tray, Wi-Fi/signal bars, warning triangle, close ×, bookmark, location pin. A candidate that reads as one of these is flagged regardless of score.
- **Platform/third-party resemblance** — shape motif or colour close to a platform or foundation mark the project refers to (BRD-30, BRD-31). Flag with the guideline clause.
- **Existing-logo collision** — reverse-image or visual search hit on a known project/company logo in the same space.
- **AI-slop tells** — symmetric gradient orb, neon glow on dark, isometric cube stacks, generic "network node" dots-and-lines, sparkle/star accents, letter-in-rounded-square default monogram, cream + terracotta default palette, over-used geometric sans wordmark with no customisation, meaningless swooshes, fake 3D bevels.
- **Raster or `<text>` in the master** — masters must be path-only SVG.

## 6. Output format per critic

```
Candidate ranking: <best → worst, all candidates>
Per candidate: <score table §3 or §4>, flags (§5), one-line verdict
Merged-pick recommendation: <id> because <evidence>
Refinements (≤3, exact geometry): e.g. "corner rx 3 → 2 on the outer frame", "end the accent stroke at x=24", "move the counter 1 unit up to open it at 16 px"
```

## 7. Merge procedure

1. Collect both rankings. If they disagree, pick the candidate that passes every §5 flag and has the higher minimum of the two scores, then apply both critics' refinements (≤3 each, no new ideas).
2. Re-render the sheet once, inspect once, fix once, confirm once (bounded verification, BRD-09).
3. Put the merged pick and the runners-up on the comparison page with scores and flags visible (BRD-24). Keep every earlier variant.
4. If the owner rejects all, do not refine further — go back to the style/literalness question (BRD-25).

## 8. Palette critique (BRD-26–BRD-28)

| Check | Pass condition |
|---|---|
| Origin | palette traces to the name's meaning or product character; rationale in one line |
| Ecosystem accent | the platform's default accent is absent from brand roles (allowed only for focus/active affordances) |
| Roles | 5–7 named colours with roles; exactly one accent |
| Contrast | table of every text/ground pair in both themes: WCAG ratio and APCA Lc; body ≥4.5:1, large text/graphics ≥3:1 |
| Context | judged in context mocks (site hero dark, README header light, ecosystem panel, icon ladder), not as swatches |
| Distinctiveness | differs from the neighbours row and the category's usual colour |

Tools: color.js or apca-w3 for contrast math, Adobe Leonardo for contrast-targeted ramps, OKLCH for ramp generation.
