# Pull request creation approval guard

- If the base repository owner is `runbear-io`, the finalized reviewers must include `runbear-bot` and the finalized assignees must include `isac322`.
- If the base repository owner is neither `runbear-io` nor `isac322`, immediately before creation present the finalized base branch, head branch, title, body, reviewers, and assignees and obtain the user's explicit approval.
- Earlier, general, pre-finalization, or different-action approval is insufficient.
- If the base repository owner is `runbear-io` or `isac322`, creation does not require approval.
- Any material change to the finalized arguments after approval requires presenting the new details and obtaining new explicit approval.
- Do not create the pull request until every required reviewer, assignee, and approval condition is satisfied.
