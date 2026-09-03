# Pull request review workflow

When handling GitHub pull request reviews:

1. At the start of each review-handling cycle, collect every current review summary, inline comment, and unresolved review thread before editing.
2. Apply the active pull request review guard, and use the `receiving-code-review` skill to evaluate each item, choose its disposition, implement accepted or adapted changes, verify affected behavior, and prepare evidence-backed responses.
3. After every item collected at the cycle's start has a final disposition and required verification is complete, reply in every collected thread with the relevant implementation, verification, clarification, or rejection evidence.
4. After any review-state or head-commit change, re-evaluate the active pull request review guard and perform every request, re-request, response, and wait transition it requires.
