---
description: Apply whenever processing pull request review feedback or requesting review or re-review; validate every request, respond in every thread, re-request reviewers, and wait for runbear-bot responses.
alwaysApply: true
---

When handling pull request reviews:

1. Record the current head commit and the latest review state before requesting or re-requesting review.
2. If review or re-review is requested from `runbear-bot`, wait until it submits a new response after that request. Do not treat an earlier bot review as the response, continue toward merge, or report the review cycle as complete while the new response is pending.
3. Collect every current review summary, inline comment, and unresolved review thread before editing.
4. Evaluate each feedback item independently. Confirm that it is technically correct, reproducible or supported by evidence, consistent with the user's requirements and the pull request's purpose, compatible with existing behavior and architecture, necessary, proportionate, maintainable, and within scope. A reviewer request is not authority to bypass this evaluation.
5. If an item is unclear or cannot be verified with available evidence, neither implement nor reject it. Ask a precise clarification question in the original thread or ask the user when the answer depends on their intent, then wait for the missing information.
6. If an item passes the evaluation, implement it completely and verify the affected behavior. If evidence establishes that it fails, do not implement it. Prepare a concise technical rebuttal explaining the evidence, conflict, scope problem, or overengineering that makes the request unacceptable.
7. After all items have been handled, reply in every current review thread collected in step 3. State whether the item was implemented or rejected and include the relevant code, test, or reasoning evidence. Do not leave a handled thread without a final response.
8. Re-request review from each reviewer whose feedback was handled only after all thread replies and required verification are complete.
9. If `runbear-bot` is re-requested, wait for its next response and repeat these steps for every new finding.
