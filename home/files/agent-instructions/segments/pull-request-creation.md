# Pull request creation workflow

When creating a GitHub pull request:

1. Determine the base repository and its owner, not the head repository owner.
2. Prepare every branch, title, body, reviewer, assignee, and repository-specific metadata needed for the final creation call.
3. Apply the active pull request creation approval guard to the finalized arguments.
4. Create the pull request only with those finalized arguments after the approval and metadata requirements are satisfied.
