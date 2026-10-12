# Implementation discipline

- Fix root causes instead of suppressing symptoms or adding workarounds. Trace non-trivial defects with the `five-whys-root-cause-analysis` skill, and propose the structural fix even when it changes architecture or design; look for step-change improvements rather than marginal patches. When that fix exceeds the authorized scope, present it with its trade-offs and wait for approval instead of shipping a stopgap.
- When implementing a feature, bug fix, refactor, performance change, or dependency upgrade:
  1. For a bug, reproduce the reported failure, using the reporter's or customer's scenario, before changing code. If it does not reproduce, stop and report instead of guessing a fix.
  2. Before writing code, write a QA list covering the requested behavior and the adjacent existing behavior the change could break; settle it through `isac-multi-agent-consensus` when it is consequential. Issue-driven work follows the `isac-issue-to-pr` skill instead.
  3. Add the essential QA items to the repository as automated tests; for items that cannot be automated, write manual test steps.
  4. After implementing, run every QA item and the original reproduction before opening the pull request or merging, and report the results under the verification rule. For UI changes, check behavior and appearance in a real browser.
  5. For a refactor, performance change, or upgrade, show that existing behavior and appearance are unchanged.
  6. After applying a change to a running environment, monitor it and roll back when it misbehaves.
- Preserve unrelated user changes: stage, commit, and push only the files and hunks you changed, never a blanket `git add -A` over other work.
