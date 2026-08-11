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

  meta = {
    description = "The power of Axiom on the command line";
    homepage = "https://github.com/axiomhq/cli";
    license = lib.licenses.mit;
    mainProgram = "axiom";
    platforms = lib.platforms.unix;
  };
})
