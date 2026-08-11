# home-manager configuration for every Mac.
#
# Desktop applications are not here — they belong to the laptop role, in
# home/roles/darwin-laptop.nix.
{ config, lib, pkgs, ... }:

{
  imports = [ ./keyboard.nix ];

  # SSH keys are held by the ssh-agent macOS already runs under launchd, with
  # the passphrase in the login keychain. AddKeysToAgent hands the key over the
  # first time it is used; UseKeychain is the macOS-only half that makes the
  # passphrase persist, so it is asked for once ever rather than once per
  # login. Both together are what "stop typing it" means here.
  #
  # enableDefaultConfig is off because it writes its own `*` block and would
  # collide with this one. Its values are reproduced below, with AddKeysToAgent
  # flipped — the rest are upstream's defaults, kept so nothing changes by
  # accident.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings."*" = {
      AddKeysToAgent = "yes";
      UseKeychain = "yes";

      ForwardAgent = false;
      Compression = false;
      ServerAliveInterval = 0;
      ServerAliveCountMax = 3;
      HashKnownHosts = false;
      UserKnownHostsFile = "~/.ssh/known_hosts";
      ControlMaster = "no";
      ControlPath = "~/.ssh/master-%r@%n:%p";
      ControlPersist = "no";
    };
  };

  # The key is deliberately *not* generated here. A passphrase is the point of
  # the keychain setup above, and an activation script cannot prompt for one —
  # generating it non-interactively would mean an unprotected key on disk. So
  # this only reports what is missing and how to make it.
  #
  # `allowed_signers` is derived from the public key when one exists: it is
  # what `git log --show-signature` consults to decide whose signatures count,
  # and it cannot be declared because the key does not exist until it is made.
  # The instructions below include the one line that writes it, so creating a
  # key does not strand you needing another activation to finish the job; this
  # step then keeps it in sync on every later switch.
  home.activation.sshKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      echo "" >&2
      echo "  No SSH key at ~/.ssh/id_ed25519. Commit signing is on, so commits" >&2
      echo "  will fail until one exists. To create it:" >&2
      echo "" >&2
      echo "    ssh-keygen -t ed25519 -C \"bhyoo@\$(hostname -s)\"" >&2
      echo "    ssh-add --apple-use-keychain ~/.ssh/id_ed25519" >&2
      echo "    printf '%s %s\\n' bhyoo@bhyoo.com \"\$(cat ~/.ssh/id_ed25519.pub)\" > ~/.ssh/allowed_signers" >&2
      echo "" >&2
      echo "  Give it a passphrase — the keychain remembers it, so it is asked" >&2
      echo "  for once and never again. The third line is what this step would" >&2
      echo "  have written; running it here avoids a second darwin-rebuild." >&2
      echo "" >&2
    else
      printf '%s %s\n' "bhyoo@bhyoo.com" "$(cat "$HOME/.ssh/id_ed25519.pub")" \
        > "$HOME/.ssh/allowed_signers"
      chmod 0644 "$HOME/.ssh/allowed_signers"
    fi
  '';

  #
  # Absolute paths on purpose: git expands `~` for some config values and not
  # others, and allowedSignersFile is one of the ones that has bitten people.
  programs.git.settings = {
    gpg.format = "ssh";
    gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
    user.signingkey = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
    commit.gpgsign = true;
    tag.gpgsign = true;
  };

  # The 1Password CLI, on every Mac including the headless one. `op` is a
  # single binary with no system integration, so unlike the desktop app it can
  # come from nixpkgs and be pinned by flake.lock. It does not need the app to
  # work: a service account token authenticates it non-interactively, which is
  # what a machine with nobody at it has to use.
  home.packages = [ pkgs._1password-cli ];
}
