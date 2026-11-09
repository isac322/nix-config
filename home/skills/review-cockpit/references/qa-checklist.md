# Review cockpit QA checklist

Run this checklist against an isolated scratch workspace. Replace `<scratch>` and `<port>` with values from the current run. Do not use a production decisions file for persistence tests.

## 1. Launch and bind checks

1. Initialize or upgrade a scratch workspace outside the checkout.
2. Start the server on the desired bind address (`127.0.0.1` by default):

   ```sh
   SKILL_DIR="${REVIEW_COCKPIT_SKILL_DIR:-$HOME/.agents/skills/review-cockpit}"
   ROOT=<scratch>
   PORT=<port>
   python3 "$SKILL_DIR/scripts/cockpit.py" serve \
     --root "$ROOT" --bind 127.0.0.1 --port "$PORT"
   ```

   Do not bind to `0.0.0.0` or `::`.
3. Confirm the root resolves to the intended scratch workspace and that the server does not serve files outside it.
## 2. API and security smoke checks

Run the following checks against the loopback service:

```sh
BASE="http://127.0.0.1:<port>"
curl -fsS "$BASE/" > /tmp/review-cockpit-index.html
curl -fsS "$BASE/api/report" > /tmp/review-cockpit-report.json
curl -fsS "$BASE/api/handoff" > /tmp/review-cockpit-handoff.json
```

Validate the returned JSON rather than assuming a fixture count:

- `report` has `generatedAt`, `repository`, `baseBranch`, `baseSha`, `latestRelease`, `boundary`, `areaCatalog`, `groups`, `summary`, `methodAudit`, and the four allowed `actions`.
- Every group has explicit `qa`, `review`, and `status` objects, briefing fields, a route, and `ready`, `completed`, and `needsDecision` flags.
- `methodAudit.classificationFrozen` and `classificationSource` match the run's frozen classification state.
- `ready` is false whenever dedicated QA, independent review, or the current-head status artifact is not `passed`.
- `handoff` has `counts`, `queue`, `undecided`, and `resumePrompt`; synthetic QA records do not appear as owner-authorized queue entries.

Check host and origin rejection. A non-allowed host and a disallowed `Origin` must receive `403`:

```sh
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Host: example.invalid:<port>" "$BASE/api/report"

curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Origin: https://example.invalid" \
  -H "Content-Type: application/json" \
  --data '{"groupId":"not-a-group","action":"defer"}' \
  "$BASE/api/decisions"
```

Check evidence containment and input validation:

```sh
curl -sS -o /dev/null -w "%{http_code}\n" "$BASE/evidence/../run-contract.json"
curl -sS -o /dev/null -w "%{http_code}\n" "$BASE/evidence/%2e%2e/run-contract.json"
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Content-Type: application/json" \
  --data '{"groupId":"not-a-group","action":"approve"}' \
  "$BASE/api/decisions"
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Content-Type: application/json" \
  --data '{"groupId":"some-group","action":"merge"}' \
  "$BASE/api/decisions"
```

The traversal and malformed-request cases must return `404` or `400` as appropriate; they must never expose a file or write a decision. Verify that oversized request bodies, invalid question IDs, invalid option IDs, malformed JSON, and notes longer than the documented limit are rejected before any write. Inspect report text for redaction of secrets and full host paths.

## 3. Decision persistence and multi-question regression

Run the deterministic self-test suite, which exercises an isolated disposable workspace on a free loopback port and optionally validates an existing scratch root read-only when `--live-root` is provided:

```sh
SKILL_DIR="${REVIEW_COCKPIT_SKILL_DIR:-$HOME/.agents/skills/review-cockpit}"
python3 "$SKILL_DIR/scripts/self_test.py" --help
python3 "$SKILL_DIR/scripts/self_test.py" \
  --live-root "$ROOT"
```
The script must verify all of the following:

- Saving question A and then question B leaves both keyed answers after a fresh `GET /api/report`.
- A whole-group defer leaves both answers intact.
- Changing only question A leaves question B unchanged.
- `add_info` preserves answers and synthetic browser-QA markers.
- Unknown or malformed groups, questions, options, origins, and oversized bodies are rejected before a file write.
- Concurrent posts for two distinct question IDs retain both answers through the advisory lock and atomic replacement.
- A legacy flat answer is migrated under its question ID without dropping unknown sibling fields; a null `decisionId` remains group-level.
- Every stored decision has `mergeAuthorization: false` and does not trigger a GitHub mutation.

After the script, fetch `/api/handoff` again and confirm that selected options and unanswered-question counts agree with the persisted state.

## 4. Real-browser UX checks

Use a real browser at both desktop and mobile widths. Inspect the actual page, not only API responses.

### Navigation and filters

- Keyboard tab order reaches search, area/status/priority filters, each group row, the audit toggle, evidence links, question options, and decision buttons.
- The selected group is visible, has `aria-current`, and always has visible focus.
- Search, area, status, priority, `#show-completed`, and `#needs-decision-only` update the list and count.
- `n` moves to the next undecided group.
- Theme defaults to `system`; `시스템`, `라이트`, and `다크` select system, light, and dark.
- Empty filter results, long titles, missing artifacts, failed artifacts, and a 320px viewport do not clip or overlap.
- Reduced-motion mode keeps route state and feedback visible without relying on decorative motion.

### Evidence and decision boundary

- The detail view contains what, why, importance, problem, route, current head, QA, independent review, method audit, owner briefing, options/trade-offs, blockers, and the decision boundary.
- Pending, blocked, needs-information, awaiting-decision, and missing-artifact states remain distinct; none renders as ready.
- Supplied screenshots and recordings open only through `/evidence/` or approved HTTPS URLs. No fabricated media appears.
- PR groups show original URL, replacement URL when supplied, original author, attribution method, original comment status, and explicit no-merge state.
- Replacement-PR approval is visually distinct from merge authorization. No control is labeled or described as a merge control.
- The header and Agent Resume Handoff drawer explain that local decisions authorize later agent work only after the global execution guards pass.

### Multi-question and completed groups

- Each question displays its recommended default separately from its saved answer.
- Choosing one option targets only that question; whole-group defer has no question target.
- An unsaved draft remains visible during navigation and refresh until it is saved, and navigation itself never persists a decision.
- After a group is recorded as merged, explicitly completed, closed without merge, or historical out of scope, refresh hides it by default; `#show-completed` restores it.
- For merged groups, the reviewed-head fact equals `mergeResult.reviewed_head` and the SHA remains fully readable and wrapped at narrow detail widths. No `overflow: hidden` hides identifiers, filenames, SHAs, or evidence links.

## 5. Cleanup and evidence record

Record the launch commands, browser URL, commit/base SHA, API responses, self-test output, and browser observations in the run's evidence or handoff notes. Keep the evidence under the designated root. When the owner signals that the task is finished, confirm each cleanup-ledger identifier still belongs to this run, then remove only those processes, tabs, and scratch resources.
