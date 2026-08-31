---
description: Block pull request creation unless the immediate approval gate for the finalized arguments and base repository owner is satisfied.
alwaysApply: true
---

# Pull request creation approval guard

- Immediately before the creation call, if the base repository owner is neither `runbear-io` nor `isac322`, require the user's explicit approval for the finalized base branch, head branch, title, body, reviewers, and assignees.
- Earlier, general, pre-finalization, or different-action approval is insufficient. Any material change to the finalized arguments requires new explicit approval.
- If approval is required and absent, do not create the pull request.
