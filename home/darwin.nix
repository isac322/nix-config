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

  # A private key cannot come from nix: the store is world readable, and a key
  # that is identical on every machine defeats the point of per-machine keys.
  # So it is generated once, on first activation, and left alone afterwards —
  # the check is the file's existence, which makes this safe to re-run.
  #
  # ed25519 rather than RSA: shorter, faster, and the modern default.
  #
  # The key is created without a passphrase because activation cannot prompt
  # for one. Adding it afterwards is one command, and the keychain setup above
  # then remembers it for good:
  #
  #   ssh-keygen -p -f ~/.ssh/id_ed25519
  #   ssh-add --apple-use-keychain ~/.ssh/id_ed25519
  home.activation.sshKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      run mkdir -p "$HOME/.ssh"
      run chmod 700 "$HOME/.ssh"
      run ${pkgs.openssh}/bin/ssh-keygen -t ed25519 \
        -f "$HOME/.ssh/id_ed25519" \
        -N "" \
        -C "bhyoo@$(/bin/hostname -s)"
    fi

    # `git log --show-signature` needs to know which keys count as yours;
    # without this file it refuses to verify anything. It is derived from the
    # key above, so it is written here rather than declared — the public key
    # only exists once the key has been made.
    #
    # This lists this machine's key only, which verifies commits signed here.
    # Adding the other Mac's public key would let each verify the other's; that
    # is public data and could live in the repo once both keys exist.
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
      run install -m 0644 /dev/null "$HOME/.ssh/allowed_signers"
      printf '%s %s\n' "bhyoo@bhyoo.com" "$(cat "$HOME/.ssh/id_ed25519.pub")" \
        > "$HOME/.ssh/allowed_signers"
    fi
  '';

  # Commits are signed with the SSH key above rather than a GPG key. Git has
  # supported this since 2.34 and it removes an entire parallel system: no
  # second keypair, no gpg-agent, no pinentry, no keyring to keep in sync
  # across machines. GitHub verifies it the same way, once the public key is
  # added there as a *signing* key rather than an authentication key.
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
