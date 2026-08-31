---
description: Block pull request merging unless the user approves the finalized target and merge method immediately before execution.
alwaysApply: true
---

# Pull request merge approval guard

- Do not merge without the user's explicit approval for the finalized repository, pull request, target branch, head commit, merge method, and material merge options immediately before the merge call.
- Earlier, general, pre-finalization, or different-action approval is insufficient, including approval to create, update, review, or approve a pull request and approval for another pull request.
- Any material change after approval requires presenting the new finalized details and obtaining new explicit approval.
- There are no repository-owner exceptions. If explicit approval is absent, do not merge.
