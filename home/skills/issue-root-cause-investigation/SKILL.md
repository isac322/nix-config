---
name: issue-root-cause-investigation
description: Use when triaging, reproducing, validating, deduplicating, or finding the root cause of bug reports and issues, especially when comparing released artifacts with tags and current main.
---

# Issue Root-Cause Investigation

Determine whether each reported problem is real, current, historical, environmental, duplicated, expected behavior, or unsupported. Reproduce the observable behavior, identify the mechanism, and preserve enough provenance that another investigator can audit the conclusion.

## Non-negotiable output

Every atomic claim must receive its own verdict, evidence, root cause or bounded hypothesis, version status, relations, limitations, and recommended disposition.

A claim that is fixed must also include complete **fix provenance**. Never write only “fixed on main,” “main fixed, unreleased,” “already fixed,” or “resolved.” Those phrases hide where the fix came from and whether users can obtain it.

For every fixed claim, record:

- upstream or fork repository;
- pull request number and URL, or `PR 없음` when no PR exists;
- the commit that changes the behavior;
- the merge, squash, or rebase result commit on the target branch;
- merge time and base branch;
- the first release tag or version containing the fix, or `없음`;
- the latest published artifact version, such as PyPI, npm, container image, package repository, or binary release;
- whether that published artifact contains the fix;
- any backport or release PR that changes availability.

An open PR, a closed-but-unmerged PR, or a PR merged only in a fork is not an upstream fix. State its actual status.

## Verdict taxonomy

Use one verdict per atomic claim:

- **CONFIRMED_CURRENT:** reproduced or mechanically proved in the current supported code/artifact.
- **CONFIRMED_HISTORICAL_FIXED:** valid historical defect whose fix is verified.
  - Add **RELEASED** when a published artifact contains it.
  - Add **UNRELEASED** only with complete fix provenance.
- **PARTIALLY_FIXED:** one mechanism or symptom is fixed, but material reported behavior remains.
- **DUPLICATE:** the same proven root cause as a canonical issue. Name the canonical issue and shared mechanism.
- **ENVIRONMENTAL:** the primary cause is outside the project’s code or supported contract.
- **NOT_REPRODUCED:** the reported observation did not reproduce; state which hypotheses were disproved and which environment gaps remain.
- **NOT_A_BUG:** behavior matches the current contract or an intentional upstream boundary.
- **FEATURE_REQUEST:** the requested capability is absent but no existing contract is broken.
- **INCONCLUSIVE:** available evidence cannot distinguish the remaining explanations.

Do not give a compound issue one verdict. Split it into atomic claims first.

## Investigation record

Maintain this record for every issue or atomic claim:

```text
Issue / claim:
Genre:
Reported environment:
Reported version and install method:
Observation:
Reporter hypothesis:
Expected contract:
Published artifact result:
Release-tag result:
Current-main result:
Reproduction commands and outputs:
Root cause or bounded hypotheses:
Disproved hypotheses:
Fix provenance:
  Repository:
  PR:
  Behavior-changing commit:
  Target-branch result commit:
  Merge time / base:
  First containing release:
  Latest published artifact:
  Published fix availability:
Duplicate / related issues:
Evidence grade:
Limitations:
User impact:
Recommended disposition:
Reusable lesson:
```

Use exact dates and commit SHAs. Link the PR when the reporting surface supports links.

## Workflow

### 1. Inventory the full surface

1. List every open issue in scope.
2. Read the complete issue body, comments, linked pull requests, commits, releases, and external reports.
3. Record the inventory at the start and refresh it before completion.
4. Assign each issue an independent investigation when parallel work is requested.

Do not sample “important” issues or silently omit proposals and environment reports.

### 2. Split observations from hypotheses

Extract separately:

- the observable symptom;
- reproduction steps;
- expected result;
- reporter’s causal explanation;
- proposed fix;
- environmental facts.

Treat the symptom as a claim to reproduce. Treat the causal explanation and proposed fix as hypotheses to test.

For compound reports, create a claim table before investigating. Claims that touch different code paths, contracts, or mechanisms require separate verdicts.

### 3. Compare three code states and fix provenance

Always compare:

1. the actual published artifact, including wheel/package metadata and installed source;
2. the release tag corresponding to that artifact;
3. current `main` or the requested HEAD.

Then trace any behavior difference to its origin:

1. use blame/log/bisect to identify the behavior-changing commit;
2. map that commit to its upstream PR;
3. verify whether it was merged, rebased, squashed, or cherry-picked;
4. determine which release tag first contains the target-branch result commit;
5. query the real distribution channel to see whether that release is published.

“Present in source” and “available to users” are different states. A local checkout, default branch, release tag, and package registry may all behave differently.

### 4. Search for duplicates by mechanism

Group issues by proven mechanism, not title or visible symptom. Useful keys include:

- crash frame and faulting instruction;
- call site and malformed value;
- protocol event or missing state transition;
- dependency-resolution path;
- blocking primitive and process ownership;
- coordinate-space mismatch;
- permission or namespace boundary.

Use the earliest report as the canonical issue unless project policy says otherwise. A later report may remain the evidence of record when it contains stronger proof.

Issues fixed in one PR are not automatically duplicates. One PR may repair several unrelated root causes.

### 5. Establish the contract

Before calling behavior a bug, establish what the project and upstream platform promise:

- public API and tool descriptions;
- documentation and supported environments;
- source-level invariants;
- upstream protocol, ABI, permission, and security rules;
- existing tests and product decisions.

An unsupported capability can be a useful feature request without being a defect. An upstream security boundary is not a project bug unless the project promises to bypass or abstract it.

### 6. Build an expressive reproduction environment

Prefer the repository’s existing Docker, VM, E2E, or CLI harness. Install missing packages inside a disposable environment when needed.

Before interpreting a clean run, verify that the test bed can express the reported condition:

- architecture and pointer width;
- Python and native-library versions;
- compositor and toolkit versions;
- GPU, DRM, display backend, and fractional scaling;
- live physical seat versus virtual compositor;
- D-Bus, mount, user, PID, and network namespaces;
- multi-monitor geometry and per-output scale;
- package resolver and distribution channel.

A clean run in an incapable environment is not evidence against the issue.

### 7. Use deterministic subsystem probes

Choose the smallest probe that isolates the mechanism.

#### FFI and native crashes

- Audit `argtypes`, `restype`, ownership, sentinel types, and variadic boundaries.
- Inject a pointer with non-zero high bits or use a tiny C shim.
- Capture register values, fault address, and first dereference with a debugger.
- Vary Python, libffi, and native-library versions to separate mechanism from correlation.

#### Hangs and timeouts

- Replace the child binary with controlled variants: immediate exit, sleep forever, create socket, keep pipe open, or fork descendants.
- Record elapsed time, process tree, PGID/session ownership, file descriptors, pipe holders, and every blocking primitive.
- Verify both the deadline and cleanup path. Child exit does not imply pipe EOF.

#### Subprocess environment leaks

- Put a fake helper first in `PATH` and dump its actual environment.
- Check display, D-Bus, HOME, XDG, credentials, and proxy variables.
- Trace every environment merge. A lower layer can reintroduce variables removed by an upper builder.

#### D-Bus and sockets

- Inspect process arguments, socket files, listeners, ownership, and `/proc/<pid>/ns/*`.
- Use the correct bus name, object, and method.
- Distinguish a daemon visible in the process namespace from a socket visible in the caller’s mount or network namespace.

#### Wayland focus and coordinates

- Compare accessibility rectangles, compositor geometry, screenshot pixels, input-device regions, and output scale.
- Use `WAYLAND_DEBUG=1` or an equivalent event probe for enter/leave and focus transitions.
- Verify effects through independent application state, not a tool’s success string.
- Name every coordinate space: surface-local, compositor-global logical, output-local, and physical framebuffer pixels.

#### Dependencies and packaging

- Inspect published package metadata, not only repository declarations.
- Resolve in a clean environment without an existing lock or cache assumption.
- Reproduce the import/start failure.
- Compare the release artifact with current main.
- Record the PR and first published version containing the bound or migration.

### 8. Verify fixes bidirectionally

A verified fix requires:

1. pre-fix code or artifact fails under the reproduction;
2. post-fix code succeeds under the same reproduction;
3. the healthy path still works;
4. adjacent failure modes do not merely move the symptom;
5. fix provenance is complete;
6. release availability is separately verified.

Do not accept a PR description or commit message as proof. Reproduce the behavior or establish it mechanically.

### 9. Grade evidence

- **A:** direct reproduction on the real path or mechanical proof such as registers, bytes, resolver output, or protocol events.
- **B:** controlled proxy reproduction or authoritative upstream-source proof, with environment limits stated.
- **C:** core symptom not reproduced; some hypotheses supported or disproved.
- **D:** inference dominates; verdict remains provisional.

The verdict must not be stronger than the evidence grade permits.

### 10. Report relations precisely

Use distinct relation labels:

- **duplicate:** same root cause;
- **same workflow:** blocks the same user journey through a different mechanism;
- **prerequisite:** one issue prevents reproduction or use of another;
- **adjacent contract:** shares a boundary such as coordinates, permissions, or lifecycle;
- **compound subclaim:** one part of a multi-problem issue.

Explain why each relation applies. Do not use “related” without a mechanism.

## Completion criteria

The investigation is complete only when:

- every issue and atomic claim has a verdict;
- the root cause is independently observed or the remaining uncertainty is bounded;
- pre-fix and post-fix behavior are compared for every fixed claim;
- published artifact, release tag, and current main are distinguished;
- every fixed claim has complete PR/commit/release/artifact provenance;
- duplicates and related issues are grouped by mechanism;
- the test bed’s ability to express each defect is documented;
- direct verification and skipped or unrepresentable conditions are listed;
- the final issue inventory still matches the requested scope.

## Anti-patterns

Never:

- promote a version correlation into a root cause;
- trust a fix PR or commit message without verifying its effect;
- inspect only current main and declare the user problem fixed;
- write “main fixed, unreleased” without the fixing PR, commits, first containing release, and current artifact status;
- treat an open, unmerged, closed-without-merge, or fork-only PR as an upstream resolution;
- group duplicates by title or symptom;
- give a compound report one verdict;
- trust a success string instead of an independent observable;
- treat `poll() is None` as proof of success;
- infer bind failure solely from a missing socket;
- use a clean run on another architecture or incapable environment as disproof;
- claim fractional-scale, GPU, DRM, physical-seat, or namespace behavior was tested when the environment could not express it;
- verify only the failure direction and skip the healthy path;
- assume child exit guarantees pipe EOF or cleanup;
- omit limitations, disproved hypotheses, or release availability.
