---
name: receiving-code-review
description: Use when evaluating and responding to code review feedback before accepting, adapting, rejecting, or implementing it
---

# Receiving Code Review

Treat review feedback as technical input to evaluate, not a command to obey or an argument to win. Understand the requested outcome, check it against the repository, and respond with evidence.

## Scope

This skill covers reusable evaluation, implementation, pushback, and response technique.

The active pull request review policy owns mandatory reviewer authority, state capture, complete thread collection, reviewer re-request, `runbear-bot` waiting, completion gates, and merge gates. Follow that policy when it applies. Do not use this skill to replace, weaken, or reconstruct it.

## Evidence standard

Evaluate technical claims against the code, tests, documented contracts, supported environments, repository decisions, and the user's requested outcome. A suggestion may be correct, partially correct, unnecessary, out of scope, or based on missing context.

Neither confidence nor politeness is evidence. Prefer reproducible behavior, source code, tests, specifications, and explicit project decisions.

## Evaluation stages

Apply these stages to each item or to a group of items that must be reasoned about together.

### 1. Read

Read the full item and its surrounding context before reacting. Identify the claimed problem, requested change, cited evidence, and affected behavior.

Do not begin from the reviewer's proposed patch alone. The proposal may solve the wrong problem even when the underlying finding is valid.

### 2. Understand

Restate the item as an observable requirement:

- What behavior is allegedly wrong?
- Under which inputs, platforms, or states?
- What result should replace it?
- Is the reviewer reporting a defect, requesting a design change, or expressing a preference?

If the intended behavior is ambiguous, ask a precise question. Do not guess at an interpretation that changes scope or product intent.

### 3. Dependency map

Trace the relevant code and constraints before judging the suggestion. Inspect callers, callees, data flow, public contracts, tests, configuration, compatibility requirements, and nearby decisions that explain the current implementation.

Map interactions among review items. Treat items as independent only when their behavior, contracts, implementation, and verification do not depend on one another. If independence cannot be established, evaluate them as a cluster and do not make an isolated edit that prejudges an unresolved dependency.

### 4. Verify the claim

Try to reproduce the reported behavior or otherwise establish whether the claim holds. Compare the suggestion with repository conventions and the supported runtime or platform.

Check for consequences beyond the reviewer's example:

- regressions in existing behavior;
- invalid assumptions about callers or data;
- compatibility or performance costs;
- security and failure-mode changes;
- unnecessary features or abstractions;
- conflict with the user's requested outcome.

When a suggestion asks to make something "proper," "professional," generic, or extensible, trace actual callers and product requirements before adding scope. If the behavior is unused, consider removing the unused path when removal is in scope; otherwise decline the expansion. If it is used, implement only the verified need rather than the reviewer's speculative end state.

If available evidence cannot establish the answer, say what is missing and seek the narrowest clarification or experiment that can resolve it.

### 5. Disposition

Choose and record a technical disposition:

- **Accept:** the finding and proposed direction are correct.
- **Adapt:** the finding is correct, but a different implementation better preserves contracts or scope.
- **Clarify:** intent, evidence, or an interacting dependency remains unresolved.
- **Reject:** evidence shows the suggestion is incorrect, harmful, unnecessary, or outside the authorized scope.

Do not implement merely to appear cooperative. Do not reject merely because the current code is familiar.

### 6. Implement

For accepted or adapted items, fix the underlying problem rather than suppressing its symptom. Reuse established patterns, update affected callers, and remove code made obsolete by the change when that removal is in scope.

For multiple items, resolve blocking clarifications first, then order implementation by dependency. Address correctness, security, and broken behavior before cosmetic cleanup. Implement the smallest coherent item or interacting cluster and verify it before continuing, so failures remain attributable.

Keep the implementation tied to the verified requirement. Do not batch unrelated fixes, and do not treat review feedback as permission for unrelated cleanup or speculative architecture.

### 7. Verify the change

Exercise the observable behavior that the item concerns. Use the smallest convincing reproduction, focused test, build, or runtime check appropriate to the change, then check relevant neighboring behavior for regressions.

A successful edit is not proof. Report only verification that actually ran and describe any remaining limitation precisely.

### 8. Respond

Respond in the thread where the item was raised when the review system supports threads. Keep each response specific to that item or interacting cluster. Lead with the disposition, evidence, or result rather than praise or gratitude. On GitHub, reply inside an inline comment thread (`gh api repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies`) rather than posting a top-level pull request comment.

- **Implemented:** state what changed and cite the relevant verification.
- **Adapted:** explain the verified concern and why the chosen implementation differs.
- **Clarification needed:** ask one concrete question and name the dependency it blocks.
- **Rejected:** give the shortest sufficient technical reason, backed by code, tests, contracts, or reproduced behavior.

Do not mark an item handled while leaving its disposition implicit.

## Unclear and interacting items

An unclear item blocks itself and every item whose design, scope, implementation, or verification depends on the missing answer. Before progressing with another item, establish that independence from the code and requirements rather than assuming it. If independence remains uncertain, treat the items as one cluster and wait. Do not make partial changes that would constrain the eventual resolution.

When several comments describe one root cause, reason about the root cause once, but answer each thread with the disposition relevant to that thread. When comments conflict, identify the conflicting assumptions and resolve them against user intent and repository evidence rather than choosing the more forceful reviewer.

## Evidence-based pushback

Push back when the suggestion would break a supported contract, contradict verified behavior, add unused scope, ignore a required compatibility constraint, or solve a problem the repository does not have.

Good pushback contains:

1. the conclusion;
2. the evidence that supports it;
3. the consequence of following the suggestion; and
4. a focused alternative or question when one is useful.

Keep the tone calm and collaborative. A brief courtesy may follow a substantive response, but generic thanks or praise must not serve as the acknowledgment. Avoid performative agreement, defensive language, status contests, and claims of certainty stronger than the evidence.

If later evidence disproves your position, correct it directly: state what changed your conclusion, adopt the supported disposition, and continue without defending the earlier mistake or writing a long apology.

## Compact examples

### Compatibility

Reviewer: "Remove this legacy branch."

Check the supported deployment targets before changing it. If the branch is still required, reject removal with the compatibility evidence. If the branch is required but contains the reported defect, adapt the suggestion by fixing that defect without dropping support.

### Unused expansion

Reviewer: "Implement proper metrics storage, filtering, and export."

Trace callers and the product contract first. If nothing uses the endpoint, propose removing the unused path or leaving it unchanged rather than building an unrequested subsystem. If it is used, implement only the metrics behavior the caller requires.

### Unclear interaction

Items 2 and 3 both change an API contract, and item 2 is ambiguous. Treat them as one blocked cluster. A separate typo fix may proceed only after verifying that it does not depend on or constrain that contract.
