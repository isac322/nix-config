# PostHog's own CLI, which nixpkgs does not carry.
#
# The source is taken from crates.io rather than GitHub: the CLI lives inside
# the PostHog monorepo, so a git checkout would fetch an enormous tree to build
# one small binary, and the published crate is the same code with a Cargo.lock
# already in it.
{
  lib,
  rustPlatform,
  fetchCrate,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "posthog-cli";
  version = "0.5.11";

  src = fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-IPJfr5bJjrYeg9HcZcmcrj7hQ2So2kaLW0cnCJQtmUU=";
  };

  cargoHash = "sha256-CngA8eLSGMNkMssWmjrS+kE1Act53LdV/YBkxlhGSh8=";

  # No shell completions: the clap definition has no `completions` subcommand
  # to generate them from.

  # No system TLS to link against: the dependency tree resolves to rustls, with
  # no openssl-sys anywhere in Cargo.lock. That is what keeps this buildable on
  # darwin and linux from the same expression.

  # Cheap sanity check that the binary starts and is the version claimed —
  # worth having when the version is only ever bumped by hand.
  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    description = "Command line interface for PostHog";
    homepage = "https://github.com/PostHog/posthog/tree/master/rust/cli";
    license = lib.licenses.mit;
    mainProgram = "posthog-cli";
    platforms = lib.platforms.unix;
    # Empty rather than absent: nixpkgs requires the attribute on new packages,
    # and there is no handle in the pinned tree to put in it.
    maintainers = [ ];
  };
})
