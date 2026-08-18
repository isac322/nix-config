---
name: gcloud-camofox-adc-auth
description: Use when GCP/Vertex/BigQuery calls fail with 401, invalid_grant, reauth required, ADC expired, or when running gcloud login with Camofox browser automation and interactive 2FA
---

# GCloud Camofox ADC Authentication Flow

Automate Google Cloud CLI login and Application Default Credentials (ADC) refresh using Camofox browser while properly delegating secondary authentication (2FA).

## Workflow

### 1. Pre-flight Token Guard (Crucial for Periodic Runs)
Before opening the browser or initiating re-auth, verify if the existing ADC token is still valid:
```bash
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "ADC token is already valid. No login required."
  exit 0
fi
```
Only proceed to step 2 if the token print fails or credentials have expired.

### 2. Initiate Login Process
Launch `gcloud auth login --update-adc` in a managed background process (`hub` start) or capture the OAuth URL:
```bash
# gcloud starts local redirect server on localhost:8085
```
Retrieve the OAuth authorization URL from process stdout/logs (`https://accounts.google.com/o/oauth2/auth?...`).

### 3. Camofox Browser Automation
1. **Create Tab**: Call `camofox_create_tab` with the authorization URL.
2. **Email Entry**:
   - Take snapshot with `camofox_snapshot`.
   - Snapshot ref IDs (e.g. `e1`, `e2`) change per session; inspect snapshot output dynamically to find the email input field (or use selector `input[type="email"]` / `#identifierId`).
   - Type email (`isac@runbear.io`) and submit (press Enter or click Next).
3. **Password Entry**:
   - Retrieve password from macOS Keychain:
     ```bash
     security find-generic-password -a "isac@runbear.io" -s "google-login" -w
     ```
     *(If Keychain is locked or lookup fails with error code 36, prompt the user to unlock the keychain or enter password).*
   - Type into `input[type="password"]` and submit.
4. **2-Step Verification (2FA)**:
   - **DO NOT** attempt to bypass or simulate hardware 2FA / push notifications.
   - Prompt the user using `ask` tool with clear instructions (e.g. tap 'Yes' on Galaxy Tab S7+ or mobile device).
   - Wait for user confirmation.
5. **Consent Approval**:
   - On Google Cloud SDK consent screen, locate the "Allow" button.
   - Click "Allow" using `camofox_evaluate` or `camofox_click`.
6. **Cleanup**: Close the browser tab with `camofox_close_tab`.

### 4. Quota Project & Verification
1. Confirm active account:
   ```bash
   gcloud auth list
   ```
2. Set Quota Project for ADC (avoids `USER_PROJECT_DENIED` 403 errors in client SDKs like BigQuery, Vertex AI, Storage):
   ```bash
   gcloud auth application-default set-quota-project <PROJECT_ID>
   ```
3. Test Python SDK resolution and API execution (using `uv run` to ensure required dependencies):
   ```bash
   uv run --with google-auth --with requests python3 -c '
   import google.auth
   from google.auth.transport.requests import AuthorizedSession

   credentials, project = google.auth.default()
   print("Credentials type:", type(credentials).__name__)
   print("Quota project ID:", getattr(credentials, "quota_project_id", None))

   authed_session = AuthorizedSession(credentials)
   # Test calling a project API (e.g. BigQuery or Resource Manager)
   resp = authed_session.get("https://bigquery.googleapis.com/bigquery/v2/projects/" + credentials.quota_project_id + "/datasets")
   print("API Status Code:", resp.status_code)
   '
   ```

## Execution with OMP
When running or triggering this skill via OMP CLI, use **Gemini 3.7 Flash**:
```bash
omp --model gemini-3.7-flash "skill://gcloud-camofox-adc-auth 스킬을 실행해줘"
```
