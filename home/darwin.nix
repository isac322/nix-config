# home-manager configuration for every Mac.
#
# Desktop applications are not here — they belong to the laptop role, in
# home/roles/darwin-laptop.nix.
{ lib, pkgs, ... }:

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
  '';

  programs.gpg.enable = true;

  # gpg-agent caches the passphrase so it is entered once per session rather
  # than per signature. On darwin home-manager runs it as a launchd agent
  # rather than a systemd unit.
  #
  # pinentry_mac is the piece that matters on macOS: it prompts in a native
  # window and can put the passphrase in the login keychain, which is the same
  # arrangement SSH gets above.
  #
  # enableSshSupport stays off on purpose. It would make gpg-agent serve SSH
  # keys too, which is the usual Linux arrangement, but here macOS's own
  # ssh-agent already holds them and two agents would fight over SSH_AUTH_SOCK.
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry_mac;
    defaultCacheTtl = 28800; # 8h — a working day
    maxCacheTtl = 86400; # 24h
  };

  # The 1Password CLI, on every Mac including the headless one. `op` is a
  # single binary with no system integration, so unlike the desktop app it can
  # come from nixpkgs and be pinned by flake.lock. It does not need the app to
  # work: a service account token authenticates it non-interactively, which is
  # what a machine with nobody at it has to use.
  home.packages = [ pkgs._1password-cli ];
}
