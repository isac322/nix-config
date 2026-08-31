---
description: Preserve direct pull request merge instructions as standing authorization; otherwise block merging until the user approves the finalized target.
alwaysApply: true
---

# Pull request merge approval guard

- A direct user instruction to merge the pull request for the current work, whether it already exists or will be created from that work, or an explicitly identified set is sufficient standing authorization. Do not ask the user to repeat it merely because the pull request number or other final details were established later.
- Without standing merge authorization, do not merge until the finalized repository, pull request, target branch, head commit, merge method, and material options have been presented and explicitly approved. Creating, updating, reviewing, or approving a pull request does not authorize merging.
- With standing authorization, present the finalized details as a notification and merge without another question after required reviews and checks complete.
- Require new explicit approval only for a material discrepancy: a different repository, pull request, authorized set, or base branch; a head change after the final merge notification; an unexpected or non-default merge method; administrator bypass; merge queue or auto-merge instead of immediate merge; or unapproved head-branch deletion. Authorization never transfers to an unmentioned pull request, and a later specific instruction to ask at each stage takes precedence.
- There are no repository-owner exceptions.
