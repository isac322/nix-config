# Pull request merge workflow

Before merging a GitHub pull request:

1. Resolve the explicit PR URL, base `OWNER/REPO`, head branch, and head SHA from the parent handoff or an exact lookup. Missing or ambiguous targets remain unresolved; never discover a target by scanning `Closes` text or issue references. Finalize the merge target, head state, method, and material options required by the active authorization guard.
2. Confirm that required reviews, checks, and conflict resolution are complete. Use `github-pr-wait wait PR_URL --until required-checks --expected-head SHA --timeout SECONDS` when checks remain pending, under the shared wait rules in the pull request review guard. CLI success neither grants merge authorization nor proves that review feedback is resolved.
3. Apply the active pull request merge authorization guard and present the finalized details as it directs.
4. For an authorized set of pull requests, itemize the final details and merge them in the required order.
5. Merge only the finalized target with the authorized method and options.
6. Return the actual result and target identity to the parent agent. If merge observation is needed, use `github-pr-wait wait PR_URL --until merged --expected-head SHA --timeout SECONDS`; it observes only and never merges. Before watching deployment, verify that the target PR is actually merged and that its actual merge SHA is nonempty. A merged fact with a null merge SHA is insufficient to select a deployment target; never substitute the PR head or a test-merge SHA.
7. Keep merge execution, merge-result evaluation, and deployment watching as separate decisions. Never chain a merge failure into deployment watching with `;`, `||`, or an unconditional shell continuation. For a verified deployment run belonging to the actual merge SHA, use a standalone native `gh run watch RUN_ID --repo OWNER/REPO --exit-status` with an explicit outer deadline. No wait command authorizes automatic merging, auto-merge, or deployment.
