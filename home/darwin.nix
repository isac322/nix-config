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

  # GPG is here for Arch packaging, not for git. `makepkg --sign` and the
  # `validpgpkeys` check in a PKGBUILD are PGP-only — an SSH signature cannot
  # stand in for either, because pacman's trust model is PGP throughout. Commit
  # signing stays on SSH below; the two do not conflict, and having gnupg
  # installed does not make git reach for it.
  programs.gpg.enable = true;

  # The agent caches the passphrase so it is entered once per session rather
  # than once per signature. On darwin home-manager runs it as a launchd agent
  # rather than a systemd unit, and pinentry_mac prompts in a native window
  # that can put the passphrase in the login keychain — the same arrangement
  # SSH gets above.
  #
  # enableSshSupport stays off: macOS's own ssh-agent already holds the SSH
  # keys, and two agents would fight over SSH_AUTH_SOCK.
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry_mac;
    defaultCacheTtl = 28800; # 8h — a working day
    maxCacheTtl = 86400; # 24h
  };

  # nixpkgs' pinentry-mac is the GPGTools build (bundle id
  # org.gpgtools.pinentry-mac), which can put the passphrase in the login
  # keychain — the same place SSH's ends up. With this the cache TTLs above
  # stop being the thing that matters: the passphrase is asked for once and
  # retrieved from the keychain afterwards, rather than re-entered when the
  # cache expires.
  #
  # Both keys are needed. DisableKeychain defaults to true, and while it is
  # set the "Save in Keychain" checkbox never appears no matter what
  # UseKeychain says.
  targets.darwin.defaults."org.gpgtools.pinentry-mac" = {
    UseKeychain = true;
    DisableKeychain = false;
  };

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
