# Shared by every NixOS host. Host-specific bits live in hosts/<name>/.
{ lib, pkgs, ... }:

let
  caches = import ../lib/caches.nix;
  sshAudit = import ../lib/ssh-audit.nix;

  # `services.openssh.settings` is half typed options and half freeform, and the
  # halves take different shapes. KexAlgorithms, Ciphers and Macs are declared
  # `nullOr (listOf str)` and want a list; everything else falls through to the
  # freeform type, which is atoms only and rejects a list outright. Both end up
  # as the same comma-joined line in sshd_config — the difference is only in who
  # does the joining.
  #
  # Naming the three rather than the many because the three are the ones with a
  # declaration to point at, and a new directive added to lib/ssh-audit.nix is
  # freeform until nixpkgs decides otherwise.
  listValued = [
    "KexAlgorithms"
    "Ciphers"
    "Macs"
  ];
  sshdSettings = lib.mapAttrs (
    name: value:
    if lib.isList value && !(lib.elem name listValued) then lib.concatStringsSep "," value else value
  ) sshAudit.sshdSettings;
in
{
  # No Determinate module here: on NixOS, Nix is part of the system closure and
  # nix.settings writes /etc/nix/nix.conf directly. This is the same
  # configuration the Macs express through `determinateNix.customSettings`.
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = caches.substituters;
    extra-trusted-public-keys = caches.trustedPublicKeys;
    trusted-users = [
      "root"
      "bhyoo"
    ];
  };

  # Collect garbage on a server that nobody logs into to do it by hand.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.optimise.automatic = true;

  users.users.bhyoo = {
    isNormalUser = true;
    description = "Byeonghoon Yoo";
    home = "/home/bhyoo";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  # Required for `users.users.bhyoo.shell = pkgs.zsh` to be a valid login shell.
  programs.zsh.enable = true;

  # This machine is reached from Ghostty, which sets TERM=xterm-ghostty. That
  # name is not in ncurses — 6.6 ships the entry as plain `ghostty`, a
  # different name that does not answer for it — so without this every TUI over
  # ssh dies with `Error opening terminal: xterm-ghostty`.
  #
  # The laptop's Ghostty can push the entry over on first connect
  # (`shell-integration-features = ssh-terminfo`, home/roles/darwin-laptop.nix),
  # but that is a shell function wrapping `ssh`, so it misses anything not
  # typed at a prompt. This is a machine we own, so it carries the entry itself
  # and the answer stops depending on how the connection was opened. 2 kB from
  # cache.nixos.org, built from the same 1.3.1 the laptop runs.
  environment.systemPackages = [ pkgs.ghostty.terminfo ];

  # The same posture as the server Mac: keys only, not as root, and the
  # ssh-audit profile on top. This is the one host where sshd is the only way
  # in, so it is also the one where getting it wrong is unrecoverable remotely.
  #
  # No ordering problem here, unlike macOS. NixOS renders the whole sshd_config
  # itself from these settings, so what is written is what applies — there is no
  # vendor fragment read ahead of ours. `settings` is a freeform submodule, so
  # the directives the module has no named option for pass straight through.
  #
  # nixpkgs already curates some of this through
  # `services.openssh.enableRecommendedAlgorithms`, on by default, and it is
  # close but not the same list: its KexAlgorithms keeps curve25519-sha256 and
  # diffie-hellman-group-exchange-sha256 alongside the post-quantum three, and
  # its Ciphers put aes128-gcm ahead of aes256-ctr. Those are reasonable defaults
  # for a distribution that cannot assume the client. Here every client is a
  # machine in this repo, so the profile wins and the defaults are overridden
  # rather than trusted.
  #
  # `hostKeys` happens to already match the nixpkgs default — rsa 4096 and
  # ed25519, no ecdsa. Declared anyway, so the answer comes from one place and
  # stays true if that default moves.
  services.openssh = {
    enable = true;
    hostKeys = lib.attrValues sshAudit.hostKeys;

    settings = sshdSettings // {
      PasswordAuthentication = false;
      PermitRootLogin = "no";

      # NixOS leaves this at the upstream `yes`, and it is a second door to the
      # same room: PAM offers password authentication through
      # keyboard-interactive, so turning off PasswordAuthentication alone still
      # leaves a password prompt reachable.
      KbdInteractiveAuthentication = false;
    };
  };

  time.timeZone = "Asia/Seoul";
  i18n.defaultLocale = "en_US.UTF-8";

  # NixOS types this as a string; nix-darwin uses an integer. Hence per-platform.
  system.stateVersion = "26.05";
}
