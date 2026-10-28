---
name: destination-aware-writing
description: Use when a coding agent must create, edit, transform, review, or publish human-readable artifacts for multiple destinations, especially GitHub PRs or issues, Linear updates or issues, BearDrive reports, or workplace reports. Select the right destination contract and writing mode instead of copying one document everywhere.
license: MIT
---

# Destination-aware writing

This is the routing and composition layer for coding-task writing. It does not replace narrower owners:

- `writing-clearly-and-concisely`: clear, concise prose
- `humanizer`: remove AI-writing patterns without changing meaning
- `comment-writer`: warm, direct comments
- `isac-github-publishing`: GitHub language, sanitization, duplicate checks, approval, and posting
- global verification and approval rules: what may be claimed or published

## 1. Make a writing card

Before drafting, identify:

```text
artifacts: github_pr | github_issue | linear_issue | linear_update | beardrive_report | workplace_report | comment
mode: compose | edit | transform | content_plan | review | publish
locale, reader, authority: draft | publish
sources: diff, tests, command output, issue, review, decision, report
```

Use destinations named by the user. If choosing a destination would change the result and it was not specified, ask. Never invent a team, project, owner, priority, issue number, URL, deployment state, or publication target.

Modes:

- `compose`: new artifact from verified source material
- `edit`: change only the requested part of an existing artifact
- `transform`: restate the same source record for another destination, reader, locale, or length
- `content_plan`: decide sections and emphasis before rendering a report
- `review`: check a draft against source facts and destination contract
- `publish`: external write only after the applicable approval and destination rules pass

A request to implement, make a PR, update Linear, and report to BearDrive normally means `compose` PR, `compose` or `transform` Linear, `content_plan` then `compose` BearDrive, and a cross-artifact review. The earlier local-edit examples cover only `edit`; they are not the default.

## 2. Freeze facts before prose

Classify every source item:

| kind | meaning |
|---|---|
| `request` | desired behavior or acceptance condition |
| `observation` | result from an executed command, test, or inspected source |
| `implementation` | fact from a diff or code inspection |
| `unknown` | not supplied or not tested |
| `inference` | interpretation, explicitly labeled |
| `contradicted` | rejected by a source; do not present as current fact |

A request is never evidence. A plan is never a test result. A successful local command is not proof of a remote side effect. Preserve source references, identifiers, revision, and uncertainty through every transformation. Do not use a prose draft as the source for another artifact.

## 3. Apply one destination contract

Read the relevant reference when needed: `references/github.md`, `references/linear.md`, or `references/beardrive.md`.

- **GitHub**: delegate public-text mechanics to `isac-github-publishing`; use the repository's caller template. A PR normally covers Summary, Changes, Validation, Risks/limitations, and Not verified. Do not add `Fixes #N` or test/deployment claims without evidence.
- **Linear**: write a short status-first artifact with current state, evidence, next action only if supplied, and unknowns. Discover workspace IDs at runtime; never guess them. Draft mode is read-only.
- **BearDrive**: create semantic content (`title`, `audience`, `purpose`, `summary`, `sections`, `unknowns`, `source_refs`, optional supplied priority). The renderer owns HTML/CSS/layout. Do not output renderer markup or call `bdrive init`, authentication, or sync for a draft.
- **Workplace report**: lead with conclusion/status, then impact, completed work, evidence, risks, next actions, and relevant unknowns.

Use the same verified facts, but reorganize them for the destination. Do not copy a PR body into Linear or a report into a PR.

## 4. Fan out and validate

For multiple artifacts:

1. Draft each independently from the frozen source record.
2. Compare status, facts, unknowns, identifiers, and revision across artifacts.
3. Check required sections, language, reader focus, and length.
4. Reject any request, plan, or inference presented as an observation.
5. Keep the run `draft` or `blocked` when a source, destination, worker result, or revision is missing.

When installed, run the deterministic local gate before saying `ready`:

```sh
jevify-writing plan task.json
jevify-writing validate bundle.json
```

The bundle records destinations, source/current revision, typed claims with source references, and one semantic artifact per destination. The gate blocks stale revisions, missing or duplicate fan-out artifacts, unknown claim references, unsupported assertions, invalid statuses, and BearDrive markup. If the command is unavailable, report `validation: not run`.

## 5. Polish last

After fact and destination checks, apply `writing-clearly-and-concisely` and `humanizer`. Use concrete verbs, specific nouns, and only necessary structure. Remove repetition, generic praise, staged openings, inflated claims, and process narration. Then compare the final prose with the source record again; natural wording that changes evidence status is wrong.

Report every artifact separately:

```text
artifact: ...
mode: draft | ready | blocked | published
sources: ...
validation: passed | failed | not run
publish: allowed | not requested | blocked
```

Never call a draft published, a plan implemented, or a local render synchronized.
