# Runbear infrastructure and telemetry

When inspecting runtime metrics, agent traces, errors, billing, cloud resources, or Kubernetes clusters for Runbear services:

## Network pre-requisite: Cloudflare WARP
- Internal endpoints such as Thanos (`https://thanos-query.runbear.io`) and Tempo (`tempo.runbear.io`) require Cloudflare WARP.
- If queries to internal endpoints fail with network timeouts, connection refused, or DNS resolution errors, it is likely a Cloudflare WARP connection or login issue. Verify with `warp-cli status`.

## Telemetry and data retrieval routing

| Target | Tool | Command / Pattern | Key rules |
|---|---|---|---|
| K8s cluster metrics | `promtool` | `promtool query instant https://thanos-query.runbear.io '<promql>'` | Requires CF WARP. Example: `'up'` |
| Agent traces (Langfuse) | `langfuse` | `langfuse api observations list ...` | Retrieve keys from macOS Keychain (see below) |
| Agent traces (Tempo) | `tempo-cli` | `tempo-cli query api search-tags tempo.runbear.io --org-id=single-tenant --secure` | Requires CF WARP |
| Errors & stack traces | `sentry` | `sentry issues list ...` | Authenticate with `skill://sentry-cli-login` when required |
| Billing & customers | `stripe` | `stripe ...` / `stripe --live ...` | Default is Test. Use `--live` only when investigating Prod |

### Langfuse credentials
Keys differ between Dev and Prod. Retrieve them from macOS Keychain without committing secrets:
- Dev environments (local, dev, staging):
  - Public Key: `security find-generic-password -s "langfuse-dev-public-key" -w`
  - Secret Key: `security find-generic-password -s "langfuse-dev-secret-key" -w`
- Prod environment:
  - Public Key: `security find-generic-password -s "langfuse-prod-public-key" -w`
  - Secret Key: `security find-generic-password -s "langfuse-prod-secret-key" -w`
Pass via `--public-key` / `--secret-key` flags or export as `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY`.

### Stripe environment
- Default CLI invocations run against the testing environment.
- Never pass `--live` unless explicitly instructed to inspect or operate on production billing data.

## Cloud infrastructure (GCP & GKE)

### Google Cloud CLI (`gcloud`)
- Use `gcloud` CLI for GCP resource inspection, BigQuery, and project management.
- When login or ADC credentials expire (401, `invalid_grant`, reauth required), automate authentication using `skill://gcloud-camofox-adc-auth`.

### Kubernetes (`kubectl` & GKE)
- Switch cluster contexts via `kubectl config use-context <context>`.
- Available Runbear cluster contexts:
  - `runbear-operation` (or `ops`, `gke-ops`)
  - `runbear-staging`
  - `runbear-prod`
- **Production Safety Guard**: In the `runbear-prod` context, perform **read-only operations only** (`get`, `describe`, `logs`). Never execute mutating commands (`apply`, `delete`, `patch`, `scale`, `edit`, etc.) without the user's explicit prior approval.
