# Pull request creation workflow

When creating a GitHub pull request:

1. Determine the base repository and its owner, not the head repository owner. Record the explicit `OWNER/REPO` and head branch for the parent agent; do not infer a PR target by scanning `Closes` text or issue references.
2. Prepare every branch, title, body, reviewer, assignee, and repository-specific metadata needed for the final creation call.
3. Apply the active pull request creation approval guard to the finalized arguments.
4. Create the pull request only with those finalized arguments after the approval and metadata requirements are satisfied. Hand the parent agent the actual PR URL, base repository, head branch, and head SHA. If creation or lookup yields no unambiguous target, report it as unresolved, not complete; do not substitute an issue URL or another PR.
5. Watch required checks with `github-pr-wait wait PR_URL --until required-checks --expected-head SHA --timeout SECONDS`, following the shared wait outcome/deadline rules in the pull request review guard. Fix failures until every required check passes and review feedback is resolved. A created pull request is done only in this merge-ready state; merging stays governed by the merge authorization guard.
