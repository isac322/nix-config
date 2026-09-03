let
  allHarnesses = [
    "omp"
    "claude"
    "codex"
  ];
  segment = source: class: harnesses: order: {
    inherit
      class
      harnesses
      order
      source
      ;
  };
in
{
  core = segment ./files/agent-instructions/segments/core.md "context" allHarnesses 100;
  claude-tools = segment ./files/agent-instructions/segments/claude-tools.md "context" [
    "claude"
  ] 900;
  codex-tools = segment ./files/agent-instructions/segments/codex-tools.md "context" [ "codex" ] 900;
  omp-tools = segment ./files/agent-instructions/segments/omp-tools.md "context" [ "omp" ] 900;

  guardrails =
    segment ./files/agent-instructions/segments/guardrails.md "persistent" allHarnesses
      100;

  destructive-operations =
    (segment ./files/agent-instructions/segments/destructive-operations.md "onDemand" allHarnesses 100)
    // {
      description = "Apply before deleting data, overwriting unrelated work, or running destructive operations.";
    };
  public-api =
    (segment ./files/agent-instructions/segments/public-api.md "onDemand" allHarnesses 200)
    // {
      description = "Apply before changing a public or exported API.";
    };
  verification =
    (segment ./files/agent-instructions/segments/verification.md "onDemand" allHarnesses 300)
    // {
      description = "Apply when reporting that implementation work is complete or verified.";
    };
  pull-request-creation =
    (segment ./files/agent-instructions/segments/pull-request-creation.md "onDemand" allHarnesses 400)
    // {
      description = "Apply when preparing and creating a GitHub pull request.";
    };
  pull-request-review-handling =
    (segment ./files/agent-instructions/segments/pull-request-review-handling.md "onDemand" allHarnesses
      500
    )
    // {
      description = "Apply when collecting, handling, and responding to GitHub pull request review feedback.";
    };
  pull-request-merge =
    (segment ./files/agent-instructions/segments/pull-request-merge.md "onDemand" allHarnesses 600)
    // {
      description = "Apply when preparing to merge a GitHub pull request.";
    };

  task-intent-boundary =
    (segment ./files/agent-instructions/segments/task-intent-boundary.md "critical" [ "omp" ] 100)
    // {
      description = "Prevent OMP from turning analysis, investigation, review, reporting, confirmation, or dry-run requests into unauthorized implementation.";
    };

  pull-request-creation-approval =
    (segment ./files/agent-instructions/segments/pull-request-creation-approval.md "critical"
      allHarnesses
      400
    )
    // {
      description = "Block pull request creation unless the finalized arguments and base-repository approval gate are satisfied.";
    };
  pull-request-review-guard =
    (segment ./files/agent-instructions/segments/pull-request-review-guard.md "critical" allHarnesses
      500
    )
    // {
      description = "Preserve reviewer-authority and pending runbear-bot guards during pull request review handling.";
    };
  pull-request-merge-authorization =
    (segment ./files/agent-instructions/segments/pull-request-merge-authorization.md "critical"
      allHarnesses
      600
    )
    // {
      description = "Preserve standing merge authorization and block unauthorized pull request merging.";
    };

  response-style = segment ./files/agent-instructions/segments/response-style.md "personality" [
    "omp"
  ] 100;
}
