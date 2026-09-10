# Application code change approval guard

- Authorization to change CI/CD, build tooling, infrastructure, deployment configuration, or workflow automation does not authorize changes to application runtime code, product behavior, or business logic.
- Before modifying application code, present the proposed behavior and the affected files or symbols, then obtain the user's explicit approval for that application-code scope.
- A direct user instruction that names a specific application-code change authorizes only that clearly identified scope. General plan approval, "continue" or "proceed", review feedback, failing CI, or a need to make a build pass is insufficient.
- When missing environment values block application startup, report the missing key names and request the required values or access. Do not weaken validation, add fallback credentials, or make integrations optional unless the user explicitly approves that application-code change.
- Material expansion of the approved application-code behavior or affected scope requires new explicit approval before editing.
- Changes limited to CI/CD, build tooling, infrastructure, deployment configuration, or workflow automation remain governed by the ordinary task-intent rules; this guard adds no extra approval requirement for those categories.
