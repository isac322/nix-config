# Repository Instructions

## GitHub-backed flake inputs

- Every direct or transitive GitHub-backed flake input MUST use the Git fetcher: `git+https://github.com/<owner>/<repo>.git`.
- Add `shallow=1` to GitHub Git URLs. Direct inputs may preserve a mutable upstream branch with `ref=...`.
- Every transitive override MUST use the exact `rev` from its parent flake's lock file. NEVER let a transitive override follow `HEAD` or a branch independently; that changes the parent's package graph and can invalidate its binary cache.
- NEVER add a `github:` flake reference. If an upstream flake declares one, override that nested input from this repository's root `flake.nix`, including deep transitive paths.
- Preserve each input's `flake` setting. Source trees such as Agent Skills and `flake-compat` remain `flake = false`.
- Before changing fetcher type for an existing revision, resolve both fetchers at that exact revision and compare `narHash`. Investigate every mismatch before accepting store-path churn.
- After every lock update, verify that neither `original.type` nor `locked.type` is `github`:

  ```sh
  jq -e '[.nodes[] | select(.original.type == "github" or .locked.type == "github")] | length == 0' flake.lock
  ```

- Upstream input names and revisions are part of the override contract. When a parent flake updates, inspect its new lock file and update the nested override revisions in the same change. Handle added or renamed inputs before accepting the new root lock graph.
- This policy governs flake inputs. Fixed-output package sources such as `fetchFromGitHub` and GitHub release assets are outside the flake lock graph and do not require transport conversion unless the task explicitly includes them.

## Configuration ownership

- Declare every persistent setting, package, service, launchd job, and agent configuration in this repository and apply it with a switch on every host its layer covers. NEVER fix a deployed or generated file by hand; change the Nix source that produces it.
- Before writing custom code, use an existing nix-darwin, Home Manager, or nixpkgs option, package, or plugin, or the tool's own native configuration. Write new packaging or scripts only when none exists, and state why.

## Versions and updates

- NEVER pin a package, app, plugin, or service to a fixed version outside the shared update state (`flake.lock`, `pkgs/release-snapshots.json`). Exact revisions required by the GitHub-backed flake input rules above are lock state, not pins.
- `nix run .#update-packages` MUST advance every versioned artifact, and each host MUST install the build for its own platform. When one artifact's version follows another (for example a browser core bundled by its API server), derive it from the upstream declaration during the update instead of hard-coding it.
- If a new release breaks the build, fix the cause; NEVER pin back to the previous version.
