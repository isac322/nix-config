# Axiom's CLI, which nixpkgs does not carry.
#
# The binary is called `axiom`, not `axiom-cli`; the attribute is named for
# what it is so it can be found alongside the other CLIs here.
{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  versionCheckHook,
}:

buildGoModule (finalAttrs: {
  pname = "axiom-cli";
  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "axiomhq";
    repo = "cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3JK9HEuVyRTe+HqbJZVDHTkFI054ETkeX2H7yYGxlVE=";
  };

  vendorHash = "sha256-BRvnoyojLcjUVppUaC7zVJasrd50X1gyufCw3hdgEMQ=";

  subPackages = [ "cmd/axiom" ];

  # The same variables goreleaser stamps upstream, minus the ones that would
  # make the build depend on the checkout's git metadata — a fetched tarball has
  # none, and a store path has no commit date. Without at least `release`,
  # `axiom version` reports an empty string.
  ldflags = [
    "-s"
    "-w"
    "-X github.com/axiomhq/pkg/version.release=${finalAttrs.version}"
  ];

  nativeBuildInputs = [ installShellFiles ];

  # Guarded because generating completions means running the binary that was
  # just built, which only works when the build machine can execute it. The
  # completions are a convenience, so a cross build loses them rather than
  # failing.
  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd axiom \
      --bash <($out/bin/axiom completion bash) \
      --zsh <($out/bin/axiom completion zsh) \
      --fish <($out/bin/axiom completion fish)
  '';

  # Runs `axiom --version` and fails the build unless the version string is in
  # the output. That is a real guard here rather than a formality: the ldflags
  # above stamp the version through an import path that lives upstream, and if
  # a refactor moves it the build still succeeds while `axiom version` quietly
  # reports nothing. Guarded on the same condition as postInstall, for the same
  # reason — it runs the binary that was just built.
  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  meta = {
    # Upstream's tagline is "The power of Axiom on the command line", which
    # nixpkgs' rules for descriptions reject on three counts: leading article,
    # marketing rather than fact, trailing period.
    description = "Command-line client for Axiom";
    homepage = "https://github.com/axiomhq/cli";
    license = lib.licenses.mit;
    mainProgram = "axiom";
    platforms = lib.platforms.unix;
    maintainers = [ ];
  };
})
