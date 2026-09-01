# Pull request review workflow

When handling GitHub pull request reviews:

1. Before requesting or re-requesting review, record the current head commit and latest review state.
2. At the start of each review-handling cycle, collect every current review summary, inline comment, and unresolved review thread before editing.
3. Apply the active pull request review guard, and use the `receiving-code-review` skill to evaluate each item, choose its disposition, implement accepted or adapted changes, verify affected behavior, and prepare evidence-backed responses.
4. After every item collected at the cycle's start has a final disposition and required verification is complete, reply in every collected thread with the relevant implementation, verification, clarification, or rejection evidence.
5. Only after those replies and verification are complete, re-request review from each reviewer whose feedback was handled.
6. When a new review response arrives, begin a new cycle and repeat this workflow for every new finding.
