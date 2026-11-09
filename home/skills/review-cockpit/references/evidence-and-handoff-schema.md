# Evidence and handoff schema

This reference defines the repository-agnostic files consumed by the review cockpit and the JSON contracts exposed by its local API. The server reports observed state only. It does not invent QA, review, screenshots, readiness, or merge results. Missing or malformed state is `unknown` unless a contract below says otherwise.

## Workspace layout

A run lives in a scratch directory outside the repository checkout. The exact root is supplied with `--root`.

```text
<scratch>/
├── run-contract.json
├── classification.json                 # present when classification is frozen
├── groups.json
├── decisions.json
├── groups/
│   └── <group-id>/
│       ├── assignment.json
│       ├── status.json
│       ├── qa*.json
│       ├── review*.json
│       ├── provenance*.json
│       └── merge_result.json           # when an execution records a merge result
└── evidence/
    └── ...                             # designated files served as /evidence/...
```

`run-contract.json` records the repository, base branch and SHA, boundary, exclusions, and item metadata. `groups.json` is the source of valid group IDs, titles, items, areas, owners, and input paths. `classification.json` is frozen method provenance and is shown in `methodAudit`; it is not QA. `assignment.json` is planning context and is intentionally excluded from success-state aggregation. Group artifacts may be absent. The server must still return explicit normalized `qa`, `review`, and `status` objects.

Only regular files inside `evidence/` may be served through `/evidence/<relative-path>`. Evidence references are relative to that root. External media links must be approved HTTPS URLs. User-provided text is bounded, redacted for secrets, and stripped of full host paths before it is returned to the browser.

## Status artifacts

A status-bearing JSON artifact may contain:

```json
{
  "state": "passed | pending | unknown | failed",
  "summary": "Observed result, not a plan",
  "details": {},
  "startedAt": "ISO-8601",
  "finishedAt": "ISO-8601",
  "updatedAt": "ISO-8601",
  "command": "exact command, if supplied",
  "commit": "reviewed commit, if supplied",
  "links": ["https://..."],
  "evidence": ["relative file path under evidence root"]
}
```

The input may use `status`, `verdict`, `result`, or `outcome` as the state key. Normalize `passed`, `pass`, `green`, `approved`, `complete`, `completed`, and `ready` to `passed`; `running`, `in_progress`, and `blocked` to `pending`; `missing` to `unknown`; and `fail`, `error`, and `red` to `failed`. Unknown values normalize to `unknown`. The UI may distinguish workflow states such as `awaiting_decision`, `needs_information`, `research_complete`, `implemented_pending_qa`, `approved_not_implemented`, and `merged`, but must not render an unverified state as ready.

QA and independent review are trusted only from dedicated `qa*.json` and `review*.json` artifacts with `executed: true`, a head matching the current reviewed head, and `independent: true` for review. A plan, research note, owner status, or bot-only claim cannot make a group ready.

## Provenance

A PR status or review artifact may provide:

```json
{
  "originalUrl": "https://github.com/.../pull/123",
  "replacementUrl": "https://github.com/.../pull/456",
  "originalAuthor": "source author",
  "attributionMethod": "cherry-pick -x",
  "originalCommentUrl": "https://github.com/.../pull/123#issuecomment-...",
  "originalCommentStatus": "commented | pending | unavailable",
  "noMergeState": "Approval records a decision; nothing is merged.",
  "mergeAuthorization": false
}
```

When no PR provenance overrides it, the server may display `cherry-pick -x` as the default attribution method for a PR group. That is a method assumption, not evidence that a cherry-pick occurred. Replacement and original-comment URLs remain absent unless a real artifact supplies them. `mergeAuthorization` is always false for local decisions.

## `GET /api/report`

The report is the browser's complete read model:

```json
{
  "generatedAt": "ISO-8601",
  "repository": "owner/repo",
  "baseBranch": "main",
  "baseSha": "...",
  "latestRelease": {
    "tag": "v1.2.3",
    "publishedAt": "ISO-8601 or null",
    "url": "https://... or null"
  },
  "boundary": {},
  "areaCatalog": [{"id": "session", "label": "Session"}],
  "harnessCatalog": [{"id": "claude-code", "label": "Claude Code"}],
  "groups": [],
  "summary": {},
  "methodAudit": {},
  "actions": ["add_info", "approve", "defer", "request_changes"]
}
```

`latestRelease` may be `null`. Each group object contains these fields:

- Identity and ownership: `id`, `title`, `area`, `areaLabel`, `owner`, `items`, `currentHead`, `route`, `agentActivity`.
- Briefing: `what`, `why`, `problem`, `importance`, `priority`, `prioritySource`, `evidenceLevel`, `proposedChanges`, `risks`, `blockers`, `nextAction`, `qaPlan`, and `sourceRefs`.
- Decision context: `questions`, `decision`, `qaDecision`, and `prBriefing`.
- Observed execution: `qa`, `review`, `status`, `artifacts`, optional `mergeResult`, and `links`.
- Derived flags: `ready`, `completed`, and `needsDecision`.

`agentActivity` has `active` (`true` when a harness or in-progress job is working on the group), `state` (`"working" | "idle"`), `harnesses` (e.g. `["claude-code"]`, `["codex"]`, `["omp"]`, `["omo"]`, or `["unknown"]` when in-progress without a specific harness name), `harnessLabels`, `label`, `sources` (`"process"`, `"workspace"`), and `summary`.

A question has `id`, `question`, `recommended`, `rationale`, and `options`. Each option has `id`, `label`, and `description`. `decision` stores the owner record when present. `qaDecision` may contain synthetic browser-QA markers, but a synthetic record remains untrusted and does not populate `decision`.

The summary contains `total`, `active`, `completed`, `working`, `idle`, `ready`, `needsDecision`, `decisions`, `syntheticDecisions`, `storedDecisions`, and aggregate `qa`, `review`, and `status` objects. The method audit contains:
```json
{
  "classificationFrozen": true,
  "classificationSource": "classification.json",
  "baseSha": "...",
  "excludedAuthors": ["dependabot[bot]"],
  "excludedCounts": {},
  "excludedNote": "...",
  "includedItems": []
}
```

The classification flag is method provenance, not a readiness signal.

## Derived flags

`ready` is true only when dedicated QA, independent review, and a separate status artifact all normalize to `passed` for the current reviewed head. Recommendations, owner approval, classification, synthetic browser-QA, or a stale artifact cannot make a group ready.

`completed` is true when the group is merged, closed without merge, explicitly completed, or marked `historical-out-of-current-scope`. It is false for active work, including approved-but-not-yet-executed work. The UI hides completed groups by default but keeps them available through `#show-completed`.

`needsDecision` is true only when all of these hold:

1. `completed` is false.
2. The group is not marked `historical-out-of-current-scope`.
3. The group is not an overview-only summary card (`overview: true`, `kind: "overview"`, or a status artifact carrying a `decision_units` summary list).
4. The group does not have a whole-group `defer` decision, and either at least one question ID is unanswered in `decision.answers` or `decision` is `null` while `status.state` is one of `awaiting_decision`, `ready`, `blocked`, `needs_information`, `research_complete`, or `implemented_pending_qa`, or `phase` is `pr-ci-passed`.

An answer is keyed by the stable question ID. A whole-group defer does not erase existing answers, and it satisfies `needsDecision` for the deferred group until the owner reopens it. Synthetic QA records never satisfy owner decisions.

## `POST /api/decisions`

The request records a local decision and never writes to GitHub:

```json
{
  "groupId": "auth-token-refresh",
  "action": "approve | defer | request_changes | add_info",
  "decisionId": "target question id; omit for a whole-group action",
  "optionId": "target option id; required with decisionId",
  "note": "optional reviewer note, max 2,000 characters"
}
```

For a group with questions, targeted `approve`, `request_changes`, or `add_info` requires a valid `decisionId` and matching `optionId`. `defer` without a choice is a whole-group action. A targeted action updates only that question; omitting the target records group-level metadata. The server validates group, question, option, action, origin, body size, and note length before writing.

The stored file retains group metadata and merges per-question answers:

```json
{
  "version": 1,
  "decisions": {
    "auth-token-refresh": {
      "action": "approve",
      "note": "...",
      "mergeAuthorization": false,
      "savedAt": "ISO-8601",
      "answers": {
        "decision-959ccfb0d268": {
          "action": "approve",
          "optionId": "option-b44f48c3fe49",
          "savedAt": "ISO-8601"
        }
      }
    }
  }
}
```

Writes use an advisory lock and atomic replacement. The implementation preserves unknown sibling fields, migrates a legacy flat `decisionId`/`optionId` record under `answers[decisionId]` on the next write, treats malformed `answers` as empty without dropping the rest of the record, and keeps `mergeAuthorization: false`. A null `decisionId` stays group-level. Synthetic browser-QA records retain their `synthetic`, `source`, and `meaning` markers across `add_info` notes and remain untrusted until an owner explicitly records a non-`add_info` decision (`approve`, `defer`, or `request_changes`), which clears the synthetic markers and promotes the record to an owner decision.
This endpoint never creates or updates branches, issues, pull requests, comments, reviews, merges, releases, or closures. A saved approval is a local feedback record; it does not mutate GitHub.

## `GET /api/handoff`

The handoff is a compact execution queue:

```json
{
  "generatedAt": "ISO-8601",
  "repository": "owner/repo",
  "baseBranch": "main",
  "baseSha": "...",
  "counts": {
    "totalGroups": 0,
    "activeGroups": 0,
    "completedGroups": 0,
    "decidedCount": 0,
    "approvedCount": 0,
    "deferredCount": 0,
    "changesRequestedCount": 0,
    "infoRequestedCount": 0,
    "undecidedCount": 0
  },
  "queue": [],
  "undecided": [],
  "resumePrompt": "..."
}
```

`queue` includes groups with recorded owner feedback, excluding synthetic QA records. Each entry has `groupId`, `title`, `area`, `items`, `currentHead`, `ready`, `completed`, `action`, `actionLabel`, `note`, `savedAt`, `answers`, `nextAction`, and `agentInstruction` (a summary of the recorded feedback). Each `answers` entry has `decisionId`, `question`, `action`, `optionId`, and `optionLabel`.

`undecided` contains groups whose `needsDecision` is true, with `groupId`, `title`, `statusState`, `unansweredQuestions`, and `nextAction`. `resumePrompt` formats the recorded feedback and selected options as Markdown so the user can copy or inspect them.
