---
name: receiving-code-review
description: Use when evaluating and responding to code review feedback before accepting, adapting, rejecting, or implementing it
---

# Receiving Code Review

Treat review feedback as technical input to evaluate, not a command to obey or an argument to win. Understand the requested outcome, check it against the repository, and respond with evidence.

## Scope

This skill covers reusable evaluation, implementation, pushback, and response technique.

Durable `AGENTS` instructions and rules control mandatory PR state workflow, including state capture, complete thread collection, ordering and set semantics, reviewer re-request, bot waiting, completion gates, and merge gates. Follow those policies when they apply. Do not use this skill to replace, weaken, or reconstruct them.

## Authority and evidence

Distinguish the source of an item before deciding what to do:

- **User-authored requirements control intent.** Preserve the user's requested outcome and scope. Clarify genuine ambiguity, verify technical feasibility, and surface conflicts or constraints rather than silently changing the request.
- **External reviewer and bot suggestions are claims to verify.** A suggestion may be correct, partially correct, unnecessary, out of scope, or based on missing context. Check it against the code, tests, documented contracts, supported environments, and the user's requirements.

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

Map interactions among review items. If one item's meaning or correct implementation depends on another, evaluate them as a cluster. Do not make an isolated edit that prejudges an unresolved dependency.

### 4. Verify the claim

Try to reproduce the reported behavior or otherwise establish whether the claim holds. Compare the suggestion with repository conventions and the supported runtime or platform.

Check for consequences beyond the reviewer's example:

- regressions in existing behavior;
- invalid assumptions about callers or data;
- compatibility or performance costs;
- security and failure-mode changes;
- unnecessary features or abstractions;
- conflict with the user's requested outcome.

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

Keep the implementation tied to the verified requirement. Review feedback is not permission for unrelated cleanup or speculative architecture.

### 7. Verify the change

Exercise the observable behavior that the item concerns. Use the smallest convincing reproduction, focused test, build, or runtime check appropriate to the change, then check relevant neighboring behavior for regressions.

A successful edit is not proof. Report only verification that actually ran and describe any remaining limitation precisely.

### 8. Respond

Respond in the thread where the item was raised when the review system supports threads. Keep each response specific to that item or interacting cluster.

- **Implemented:** state what changed and cite the relevant verification.
- **Adapted:** explain the verified concern and why the chosen implementation differs.
- **Clarification needed:** ask one concrete question and name the dependency it blocks.
- **Rejected:** give the shortest sufficient technical reason, backed by code, tests, contracts, or reproduced behavior.

Do not mark an item handled while leaving its disposition implicit.

## Unclear and interacting items

An unclear item does not automatically invalidate unrelated, well-understood feedback. It does block any item whose design, scope, or verification depends on the missing answer. Make that dependency explicit and avoid partial changes that would constrain the eventual resolution.

When several comments describe one root cause, reason about the root cause once, but answer each thread with the disposition relevant to that thread. When comments conflict, identify the conflicting assumptions and resolve them against user intent and repository evidence rather than choosing the more forceful reviewer.

## Evidence-based pushback

Push back when the suggestion would break a supported contract, contradict verified behavior, add unused scope, ignore a required compatibility constraint, or solve a problem the repository does not have.

Good pushback contains:

1. the conclusion;
2. the evidence that supports it;
3. the consequence of following the suggestion; and
4. a focused alternative or question when one is useful.

Keep the tone calm and collaborative. Courtesy and natural thanks are fine; performative agreement is not. Avoid praise that substitutes for analysis, defensive language, status contests, and claims of certainty stronger than the evidence.

If later evidence disproves your position, correct it directly: state what changed your conclusion, adopt the supported disposition, and continue without defending the earlier mistake.
