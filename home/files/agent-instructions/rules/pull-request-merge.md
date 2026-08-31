---
description: Apply immediately before merging a GitHub pull request; the merge must not proceed without the user's explicit approval for the finalized target and merge method.
alwaysApply: true
---

Before merging a GitHub pull request:

1. Finalize the exact repository, pull request number and title, target branch, head commit, merge method, and any material merge options.
2. Present those finalized details to the user.
3. Obtain the user's explicit approval now, immediately before the merge call. Proceed only if the user explicitly says that this finalized pull request may be merged.
4. Treat earlier, general, or pre-finalization approval as insufficient. Approval to create, update, review, or approve a pull request does not authorize merging it, and approval for another pull request does not transfer.
5. If any material detail changes after approval, present the new finalized details and obtain new explicit approval.
6. Apply this requirement without repository-owner exceptions. If explicit approval is absent, do not merge the pull request.
