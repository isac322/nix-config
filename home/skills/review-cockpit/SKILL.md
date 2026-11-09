---
name: review-cockpit
description: Use when a repository owner wants a visual browser cockpit to inspect open issues and pull requests, see whether any agent harness (Claude Code, Codex, OMP, OMO, OpenCode) is currently working on them, review their purpose, status, evidence, and options in one place, and submit structured owner feedback for the agent to receive immediately; including "리뷰 콕핏", "콕핏 만들어줘", "콕핏 띄워줘", "리뷰용 페이지 만들어줘", "이슈·PR 콕핏", "이슈랑 PR 한눈에 보게 웹으로 만들어줘", or "review cockpit".
---

# Review cockpit

Use this skill to build a visual browser cockpit for a repository's open issues and pull requests and to collect the owner's structured feedback (`approve`, `defer`, `request_changes`, `add_info`, selected options, and notes).

This skill **only** handles:
1. Preparing and serving the visual review cockpit from workspace data (including live detection of whether any local agent harness is currently working on each item).
2. Collecting the owner's recorded feedback and delivering it back to the waiting agent as soon as the owner clicks **피드백 제출 (에이전트 전달)**.

It does **not** prescribe how issues/PRs are triaged or implemented and does **not** mutate GitHub state by itself. Once the owner submits feedback in the cockpit, the waiting agent receives the submitted payload and proceeds according to the user's intent.

## Skill path resolution

Resolve `SKILL_DIR` to the directory containing this `SKILL.md` (for example `~/.agents/skills/review-cockpit`, `~/.claude/skills/review-cockpit`, `.agents/skills/review-cockpit`, or `.claude/skills/review-cockpit`).

## Workflow

### 1. Initialize or refresh a cockpit workspace

Create or update a scratch workspace outside the repository checkout:

```sh
SKILL_DIR="<directory-containing-this-SKILL.md>"
python3 "$SKILL_DIR/scripts/cockpit.py" init \
  --root <scratch> [--repo owner/repo]
```

- If `--repo` is omitted, `cockpit.py` detects `owner/repo` from the current git remote.
- By default, `init` fetches open issues and pull requests via `gh api`, filters out items authored by the repository owner or known automation bots (`--include-owner` and `--include-bots` override this), and clusters items that reference one another (`#<number>`) into connected groups in `<scratch>/groups.json`.
- To refresh web assets or synchronize an existing workspace without losing recorded data or feedback, pass `--from-workspace <existing-root>`.

### 2. Populate group context and visual evidence

For each group in `<scratch>/groups/<group-id>/`, populate the structured JSON files and place any screenshots, recordings, or logs under `<scratch>/evidence/` as described in [Evidence and handoff schema](references/evidence-and-handoff-schema.md):
- `status.json`: plain-language summary (`what`, `why`, `problem`, `importance`), `proposedChanges`, `risks`, `blockers`, `nextAction`, and optional `decisions` (questions with options, trade-offs, and a recommended option).
- `qa*.json` and `review*.json`: optional verification results and links to `/evidence/<relative-path>` or `https://` artifacts.
- `activity.json` (optional): explicit harness activity state (`cockpit.py activity --root <scratch> --group <id> --state working|idle [--harness claude-code|codex|omp|omo|opencode|...] [--pid <pid>]`). In addition to `activity.json`, the server automatically inspects the host machine's running harness processes (`claude`, `codex`, `omp`, `omo`, `opencode`, `aider`, `cursor`, `goose`) and their working directories/arguments to detect whether an issue/PR is currently being worked on.

Validate the workspace contract before serving:

```sh
python3 "$SKILL_DIR/scripts/cockpit.py" validate --root <scratch>
```

### 3. Serve the review cockpit and wait for owner submission

Launch the local HTTP server (`--bind` defaults to `127.0.0.1`, `--port` defaults to `8787`):

```sh
python3 "$SKILL_DIR/scripts/cockpit.py" serve \
  --root <scratch> [--bind 127.0.0.1] [--port 8787]
```

To automatically receive the owner's feedback the moment they click **피드백 제출 (에이전트 전달)** (`POST /api/submit`) in the browser, run the submission watcher (in the background or foreground as supported by the harness):

```sh
python3 "$SKILL_DIR/scripts/cockpit.py" wait \
  --root <scratch> --format prompt
```

### 4. Inspect or export collected feedback at any time

```sh
python3 "$SKILL_DIR/scripts/cockpit.py" handoff --root <scratch> --format prompt
python3 "$SKILL_DIR/scripts/cockpit.py" handoff --root <scratch> --format json
python3 "$SKILL_DIR/scripts/cockpit.py" status --root <scratch>
```

## References

- [Evidence and handoff schema](references/evidence-and-handoff-schema.md)
- [QA checklist](references/qa-checklist.md)
