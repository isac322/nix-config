---
description: Apply immediately before creating a pull request, including approval and metadata decisions based on the base repository owner.
alwaysApply: true
---

Before creating a pull request:

1. Determine the base repository and its owner, not the head repository owner.
2. Prepare the final base branch, head branch, title, body, reviewers, and assignees.
3. If the base repository owner is `runbear-io`, ensure `runbear-bot` is included as a reviewer and `isac322` is included as an assignee.
4. If the base repository owner is neither `runbear-io` nor `isac322`, present the final pull request details and obtain the user's explicit approval now, immediately before the creation call. Earlier discussion or approval does not satisfy this requirement.
5. If the base repository owner is `runbear-io` or `isac322`, creation does not require approval.
6. Create the pull request with the finalized arguments.
