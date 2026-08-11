# home-manager configuration for every Mac.
#
# Desktop applications are not here — they belong to the laptop role, in
# home/roles/darwin-laptop.nix.
{ config, lib, pkgs, ... }:

let

  # One key does everything: SSH authentication, git commit signing, and the
  # PGP signing that Arch packaging needs. The GPG key's authentication subkey
  # is served to SSH by gpg-agent, so there is no separate SSH keypair to
  # create, back up or register per machine — moving the key moves all three.
  #
  # The cost is that macOS points everything at its own ssh-agent. launchd
  # publishes that socket through SSH_AUTH_SOCK to every process in the login
  # session, GUI apps included, so redirecting it takes two independent
  # measures below. Getting only one of them right fails quietly in exactly the
  # places that are hardest to notice.
  sshAuthSock = "/private/var/run/org.nix-community.home.gpg-agent/S.gpg-agent.ssh";

  # gpg-agent holds every secret key but offers only the ones it has been told
  # to offer, and what it wants is a keygrip — a value that comes into being
  # when the key lands on the machine, so it can never be written down here.
  # Reading it back out of the keyring is what removes the last manual step:
  # whichever authentication-capable key is present gets marked, and a second
  # run changes nothing.
  #
  # The mark lives in the private key file as a `Use-for-ssh` attribute, set
  # through gpg-connect-agent's KEYATTR. Appending the keygrip to
  # ~/.gnupg/sshcontrol still works and is what most guides say, but GnuPG's
  # own manual has called that file "deprecated in favor of the "Use-for-ssh"
  # attribute in the key files" since 2.3.7.
  gpgSshAuthorize = pkgs.writeShellApplication {
    name = "gpg-ssh-authorize";
    runtimeInputs = [ pkgs.gnupg ];
    text = ''
      # Field 12 of a sec/ssb record is that key's capabilities, where `a` means
      # authentication; the grp record following it carries its keygrip. So this
      # prints the keygrip of every key allowed to authenticate, and nothing else.
      grips=$(gpg --list-secret-keys --with-keygrip --with-colons 2>/dev/null |
        awk -F: '$1 == "sec" || $1 == "ssb" { auth = ($12 ~ /a/) }
                 $1 == "grp" && auth        { print $10 }') || true

      if [ -z "$grips" ]; then
        echo "gpg-ssh-authorize: no authentication-capable secret key found." >&2
        echo "gpg-ssh-authorize: import one, then run this again." >&2
        exit 0
      fi

      while IFS= read -r grip; do
        [ -n "$grip" ] || continue

        # The attribute name keeps its trailing colon: KEYATTR addresses the
        # raw field name as it appears in the key file. Reading it first keeps
        # a switch that has nothing to do silent.
        if gpg-connect-agent "KEYATTR $grip Use-for-ssh:" /bye 2>/dev/null |
          grep -q '^D yes'; then
          continue
        fi

        gpg-connect-agent "KEYATTR $grip Use-for-ssh: yes" /bye >/dev/null
        echo "gpg-ssh-authorize: $grip is now offered over SSH." >&2
      done <<<"$grips"
    '';
  };
in
{
  imports = [ ./keyboard.nix ];

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings."*" = {
      # Measure one. ssh reads this file no matter who launched it, so this
      # covers anything that shells out to the ssh binary — including the GUI
      # applications that never see a shell's environment.
      IdentityAgent = sshAuthSock;

      # Upstream's defaults, kept verbatim. AddKeysToAgent and UseKeychain are
      # gone: they belong to macOS's ssh-agent, which is no longer in the path.
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

  # Measure two. home-manager only exports SSH_AUTH_SOCK from shell init, which
  # reaches terminals and nothing else; launchd-started applications never read
  # a shell profile. `launchctl setenv` sets it for the whole login session, so
  # anything reading the variable directly finds gpg-agent as well.
  launchd.agents.ssh-auth-sock = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/launchctl"
        "setenv"
        "SSH_AUTH_SOCK"
        sshAuthSock
      ];
      RunAtLoad = true;
    };
  };

  programs.gpg.enable = true;

  # enableSshSupport is what makes the authentication subkey available over the
  # ssh-agent protocol. pinentry_mac is the GPGTools build, so the passphrase
  # goes into the login keychain and is asked for once — covering SSH and
  # signing alike, since they are now the same key.
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry_mac;
    # These only govern the window before the passphrase reaches the keychain,
    # or if "Save in Keychain" is declined. Once stored, pinentry fetches it
    # silently on every expiry and the TTLs stop being observable — GPGTools
    # stores it with "always allow", which is why people running
    # default-cache-ttl 0 still get asked only once.
    defaultCacheTtl = 28800;
    maxCacheTtl = 86400;
  };

  targets.darwin.defaults."org.gpgtools.pinentry-mac" = {
    UseKeychain = true;
    DisableKeychain = false;
  };

  # Nothing is generated here. The key is created once, elsewhere, and carried
  # between machines as an exported .asc — which is the whole point of using
  # one key for everything. An activation script cannot prompt for a
  # passphrase, so importing stays manual; everything after the import does
  # not, and is done here. Importing a key and switching, in either order,
  # ends up in the same place.
  home.activation.gpgKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ${pkgs.gnupg}/bin/gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec'; then
      ${lib.getExe gpgSshAuthorize}
    else
      echo "" >&2
      echo "  No GPG secret key. Commit signing is on and SSH authenticates" >&2
      echo "  through gpg-agent, so both are inert until a key is imported." >&2
      echo "" >&2
      echo "  Importing an existing key from a backup:" >&2
      echo "" >&2
      echo "    gpg --import secret.asc            # the private key" >&2
      echo "    gpg --import-ownertrust trust.asc  # optional, restores trust" >&2
      echo "" >&2
      echo "  Then mark it ultimately trusted, so gpg treats it as yours:" >&2
      echo "" >&2
      echo "    gpg --edit-key bhyoo@bhyoo.com     # then: trust, 5, y, quit" >&2
      echo "" >&2
      echo "  And hand its authentication subkey to SSH. This finds the key on" >&2
      echo "  its own — there is no keygrip to read off a screen:" >&2
      echo "" >&2
      echo "    gpg-ssh-authorize" >&2
      echo "" >&2
      echo "  Check it took: ssh-add -L should list the key." >&2
      echo "" >&2
      echo "  If there is no key yet, create one with an [A] subkey:" >&2
      echo "" >&2
      echo "    gpg --full-generate-key            # ed25519; the user id must be" >&2
      echo "                                       # Byeonghoon Yoo <bhyoo@bhyoo.com>," >&2
      echo "                                       # or git will not find the key" >&2
      echo "    gpg --edit-key bhyoo@bhyoo.com     # addkey, ECC, Authenticate" >&2
      echo "" >&2
      echo "  Export it for the other machines:" >&2
      echo "" >&2
      echo "    gpg --armor --export-secret-keys bhyoo@bhyoo.com > secret.asc" >&2
      echo "    gpg --export-ownertrust > trust.asc" >&2
      echo "" >&2
    fi
  '';

  # Commits are signed with the same GPG key. `user.signingkey` is left unset
  # on purpose: with no key configured and the default openpgp format, git
  # passes the committer identity itself to gpg (`-u "Name <email>"`), which
  # selects the secret key whose user id matches. So the key is found by who
  # the commit says it is from, and no key id — which differs per machine and
  # changes on rotation — has to appear in the configuration. The catch is that
  # the key's user id must be created to match: `Byeonghoon Yoo
  # <bhyoo@bhyoo.com>`, exactly the name and email set in home/common.nix.
  programs.git.settings = {
    commit.gpgsign = true;
    tag.gpgsign = true;
  };

  # The 1Password CLI, on every Mac including the headless one. `op` is a
  # single binary with no system integration, so unlike the desktop app it can
  # come from nixpkgs and be pinned by flake.lock. It does not need the app to
  # work: a service account token authenticates it non-interactively, which is
  # what a machine with nobody at it has to use.
  # gpg-ssh-authorize is on PATH as well as wired into activation, so a key
  # imported between switches can be put to work immediately.
  home.packages = [
    pkgs._1password-cli
    gpgSshAuthorize
  ];
}
