# The one Hindsight memory scope every coding agent on this machine shares.
#
# OMP renders it into its `hindsight` settings (home/agent-instructions.nix);
# agy reaches the same bank through pkgs/agy-hindsight (home/agy.nix). In
# `per-project-tagged` scoping every write goes to one bank, project writes
# carry a `project:<primary checkout name>` tag, and recall reads that tag plus
# untagged global memories. `bank` is OMP's built-in default bank name, which
# OMP uses because no `bankId` is set.
{
  apiUrl = "https://hindsight-api.bhyoo.com";
  bank = "omp";
  scoping = "per-project-tagged";
  globalScope = true;

  # Prints this machine's API token: the login Keychain on macOS, a user-owned
  # SOPS file elsewhere. Clients read it at launch so it never reaches a config
  # file or the Nix store.
  tokenCommand =
    { isDarwin, sops }:
    if isDarwin then
      ''/usr/bin/security find-generic-password -s "hindsight-api.bhyoo.com" -a "$USER" -w''
    else
      ''${sops} --decrypt --extract '["apiToken"]' "$HOME/.config/hindsight/token.sops.yaml"'';
}
