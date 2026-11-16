# Runbear infrastructure and telemetry

When inspecting runtime metrics, agent traces, errors, billing, cloud resources, or Kubernetes clusters for Runbear services, or reading or writing Notion content:

## Internal endpoints: Cloudflare Access
- Internal HTTP endpoints under `runbear.io`, including Tempo (`https://tempo.runbear.io`), Thanos (`https://thanos-query.runbear.io`), Grafana, and Argo CD, sit behind Cloudflare Access. A connected WARP client does not admit a request by itself; every request needs a per-user Access JWT in the `cf-access-token` header.
- Get the JWT with `t=$(timeout 60 cloudflared access login --no-verbose --auto-close <https-url>)`. It prints only the token and reuses the caches in `~/.cloudflared` without a browser while the organization session (about 30 days) is valid; per-host tokens last 24 hours and are renewed the same way.
- If that command times out or returns no JWT, the organization session expired. Run `cloudflared access login --auto-close <https-url>` in the background, write the login URL it prints to a mode-`0600` temporary file, have the `browser` subagent approve it as `isac@runbear.io`, then fetch the JWT again.
- Pass the JWT through each tool's native header option (see the routing table); for any other HTTP API use `cloudflared access curl <https-url> [curl args]`. Never print, log, or store the JWT elsewhere; `~/.cloudflared` is its only store.
- A redirect to `runbear.cloudflareaccess.com`, an HTML "Cloudflare Access" sign-in page, or a CLI error such as `invalid character '<'` means a missing or expired Access JWT. Network timeouts, connection refused, or DNS resolution errors still point to WARP; verify with `warp-cli status`.
- Read macOS Keychain items only through the absolute path `/usr/bin/security`. Its Apple signature stays stable across Nix rebuilds, so macOS does not ask for approval again (nix-config ADR 0033).

## PostgreSQL access

Use the local Cloud SQL Proxy endpoint for the target environment:

| Environment | Local endpoint | Cloud SQL instance |
|---|---|---|
| Prod | `127.0.0.1:15432` | `runbear:us-east4:runbear-prod-pg` |
| Staging | `127.0.0.1:15433` | `runbear:us-east4:runbear-staging-pg` |

Connect with `psql` by supplying the database and read-only account:

```sh
psql -h 127.0.0.1 -p 15432 -U <user> -d <database> # Prod
psql -h 127.0.0.1 -p 15433 -U <user> -d <database> # Staging
```

If a proxy is not accepting connections, restart only the affected environment:

| Platform | Prod | Staging |
|---|---|---|
| macOS | `launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.cloud-sql-proxy-prod"` | `launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.cloud-sql-proxy-staging"` |
| Linux | `systemctl --user restart cloud-sql-proxy-prod.service` | `systemctl --user restart cloud-sql-proxy-staging.service` |

## Telemetry and data retrieval routing

| Target | Tool | Command / Pattern | Key rules |
|---|---|---|---|
| K8s cluster metrics | `promtool` | `promtool query instant --http.config.file=<(printf 'http_headers:\n  cf-access-token:\n    secrets: ["%s"]\n' "$t") https://thanos-query.runbear.io '<promql>'` | `$t` is the Access JWT for `https://thanos-query.runbear.io` (see above). Example: `'up'` |
| Agent traces (Langfuse) | `langfuse` | `langfuse api observations list ...` | Retrieve keys from macOS Keychain (see below) |
| Agent traces (Tempo) | `tempo-cli` | `tempo-cli query api search-tags tempo.runbear.io --org-id=product-prod --secure --header=cf-access-token=$t` | `$t` is the Access JWT for `https://tempo.runbear.io`. Product traces use tenant `product-prod` (Prod) or `product-staging` (Staging) |
| Errors & stack traces | `sentry` | `sentry issues list ...` | Authenticate with `skill://sentry-cli-login` when required |
| Billing & customers | `stripe` | `stripe ...` / `stripe --live ...` | Default is Test. Use `--live` only when investigating Prod |
| Secrets & credentials | `op` | `op item get ...` / `op read ...` | Source session cache or sign in via Keychain (see below) |
| Notion pages, data sources & files | `ntn` | `ntn pages ...` / `ntn datasources ...` / `ntn files ...` / `ntn api v1/...` | Use for all Notion work instead of browser automation or web fetching. Check `ntn whoami`; authenticate with `ntn login` when required. Discover endpoints with `ntn api ls` and read request shapes with `ntn api <path> -X <METHOD> --spec` or `--docs` instead of guessing or fetching web docs |

### Langfuse credentials
Keys differ between Dev and Prod. Retrieve them from macOS Keychain without committing secrets:
- Dev environments (local, dev, staging):
  - Public Key: `/usr/bin/security find-generic-password -s "langfuse-dev-public-key" -w`
  - Secret Key: `/usr/bin/security find-generic-password -s "langfuse-dev-secret-key" -w`
- Prod environment:
  - Public Key: `/usr/bin/security find-generic-password -s "langfuse-prod-public-key" -w`
  - Secret Key: `/usr/bin/security find-generic-password -s "langfuse-prod-secret-key" -w`
Pass via `--public-key` / `--secret-key` flags or export as `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY`.

### 1Password CLI credentials
When accessing secrets or credentials via `op` CLI:
- If `~/.config/op/session.env` exists and is recent, source it before calling `op`:
  ```sh
  [ -r ~/.config/op/session.env ] && . ~/.config/op/session.env
  ```
- If not signed in, session is missing, or commands fail with `not currently signed in` or `no active session found`, sign in non-interactively using the master password in macOS Keychain:
  ```sh
  eval "$(/usr/bin/security find-generic-password -s "op-master-password" -a "isac@runbear.io" -w 2>/dev/null | TMPDIR="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || echo /tmp)" op signin 2>/dev/null)"
  ```
- When calling `op` directly from scripts where `TMPDIR` is redirected (e.g. `/data/tmp`), prefix `op` with the macOS user temp directory so `com.agilebits.op.501` session files are discovered:
  ```sh
  TMPDIR="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || echo /tmp)" op <command>
  ```
- Never print or commit the master password, session tokens, or plaintext secrets retrieved from 1Password.
- Shared Runbear service logins live in 1Password rather than in personal accounts; for example, Pylon uses `bear@runbear.io`. Look the item up with `op item list` / `op item get` before asking the user.

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
