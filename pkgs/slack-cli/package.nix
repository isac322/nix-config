# Slack's own CLI for building Slack apps.
#
# This shadows a nixpkgs attribute of the same name, and that is the point.
# `pkgs.slack-cli` in nixpkgs is rockymadden/slack-cli — an unrelated bash
# script that posts to an incoming webhook, last touched in February 2023 —
# which happens to claim the obvious name. The program meant by "the Slack CLI"
# today is slackapi/slack-cli: Salesforce's Go tool for creating, running and
# deploying Slack apps, and the one `brew install slack-cli` installs. Both
# install a binary called `slack`, so getting the wrong one is not a build
# error; it is `slack app` reporting an unknown argument.
#
# Delete this if nixpkgs ever adopts the official CLI under this name.
{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  git,
  installShellFiles,
}:

buildGoModule (finalAttrs: {
  pname = "slack-cli";
  version = "4.6.0";

  src = fetchFromGitHub {
    owner = "slackapi";
    repo = "slack-cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-KMkzI9Cfbq9/se6RFVr2kocNEk4eAnuOeXOnHlGtues=";
  };

  vendorHash = "sha256-Rir4CEVNWcKSwrYDM5O7ywgbTAQeUJmhgVMTR+IOla4=";

  # The main package is the repository root, so there is no subPackages here.
  # Upstream's Makefile builds exactly this with `go build -o bin/slack`.

  # Upstream stamps the version from `git describe`, which a fetched tarball
  # cannot answer — there is no .git in a store path. Left alone the variable
  # keeps its in-source default of "v0.0.0-dev", and the CLI compares that
  # default against the latest release on every run to decide whether to print
  # an upgrade notice: an unstamped build nags forever and reports the wrong
  # thing to `slack version`. The `v` prefix is upstream's own convention; the
  # package strips it from `version` and the code puts it back, so it is
  # written out here rather than derived.
  ldflags = [
    "-s"
    "-w"
    "-X github.com/slackapi/slack-cli/internal/version.Version=v${finalAttrs.version}"
  ];

  # The CLI reaches for ~/.slack on startup — it is where it keeps credentials
  # and config — and the sandbox has no home directory, so every package under
  # cmd/ fails with home_directory_access_failed before it runs a single
  # assertion. A scratch HOME is enough; nothing here inspects it. The install
  # check below sets up its own for the same reason rather than inheriting this
  # one, which would leave it depending on doCheck being on.
  preCheck = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
  '';

  # `slack doctor` reports the versions of the tools a Slack app project needs,
  # and cmd/doctor's tests exercise that by asking the real ones. git is the
  # only one they insist on — the rest are reported as absent without failing.
  nativeCheckInputs = [ git ];

  nativeBuildInputs = [ installShellFiles ];

  # Go names the binary after the last element of the module path, which here
  # is the repository name and not the command's. Upstream's Makefile builds
  # `bin/slack`, Homebrew installs `slack`, and every doc, error message and
  # completion script says `slack`; only the file this produces disagrees.
  #
  # Then the completions. Cobra's completion command is registered but hidden
  # (HiddenDefaultCmd in cmd/root.go), so it never appears in `slack --help`
  # while still working when asked for by name. Guarded on canExecute because
  # generating them means running the binary just built; a cross build loses
  # the completions rather than failing over a convenience.
  postInstall = ''
    mv $out/bin/slack-cli $out/bin/slack
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd slack \
      --bash <($out/bin/slack completion bash --skip-update) \
      --zsh <($out/bin/slack completion zsh --skip-update) \
      --fish <($out/bin/slack completion fish --skip-update)
  '';

  # This guards the ldflags above: if the version import path moves upstream,
  # the build still succeeds and the only symptom is a binary that thinks it is
  # v0.0.0-dev. The `v` is part of what is checked, since that prefix is the
  # part written out by hand.
  #
  # Written out rather than left to versionCheckHook, which takes a single
  # argument: this needs two — `version` because there is no `--version` flag,
  # and `--skip-update` because the command otherwise asks GitHub for the
  # latest release, from a sandbox with no network. The cd is for the same kind
  # of reason: on any hiccup the CLI writes a slack-debug-<date>.log beside
  # itself, and the source directory it would land in is read-only by then.
  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    cd "$TMPDIR"
    $out/bin/slack version --skip-update | grep -qF "v${finalAttrs.version}"
    runHook postInstallCheck
  '';

  # The CLI reports usage to Slack unless told not to, and both invocations the
  # build makes — generating the completions, checking the version — would try
  # it from a sandbox with no network and wait on the attempt.
  # Upstream's own Makefile sets the same variable for the same reason. This is
  # the build environment only; it says nothing about what the installed binary
  # does, which stays the user's choice.
  env.SLACK_DISABLE_TELEMETRY = "true";

  meta = {
    description = "Command-line tool for creating, developing and deploying Slack apps";
    homepage = "https://github.com/slackapi/slack-cli";
    license = lib.licenses.asl20;
    mainProgram = "slack";
    platforms = lib.platforms.unix;
    maintainers = [ ];
  };
})
