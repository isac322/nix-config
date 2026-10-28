# Linear destination adapter

Linear has workspace-specific teams, projects, labels, and statuses. Discover those values at runtime; never guess IDs or copy a project-specific default into the shared skill.

## Draft artifact

A Linear issue or update should make the current state readable at a glance:

- title: one concrete problem or outcome
- status: observed state, not the desired state
- evidence: only executed or supplied results
- next action: only when supplied or explicitly authorized by the task
- unknowns: owner, team, priority, URL, deployment, and readiness stay unknown when absent

Keep it shorter than a PR body. A request, plan, or acceptance condition must not be written as an observed implementation result. Preserve technical identifiers exactly.

## Modes

- `compose`: make a new issue or update draft from the source ledger.
- `transform`: derive a short status update from an already verified source record, then re-check all claims.
- `edit`: change only the requested fields of an existing artifact.
- `publish`: use the Linear integration only after the requested mutation is authorized and the current team/project context is verified.

Draft mode is read-only. Do not create or update a Linear object while preparing a draft or benchmark artifact.
