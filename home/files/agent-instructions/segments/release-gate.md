# Release gate

Before tagging or publishing a release:

1. Run the repository's own release checks on the release commit.
2. Read everything merged since the latest release tag, choose the next version from it, and compare behavior against that release.
3. If you find a regression or a new bug, do not release. Report each problem to the user and wait for instructions.
4. A behavior change since the last release that fixes a bug, is more intuitive, or follows a standard is an improvement, not a regression. Keep it; do not revert it.
