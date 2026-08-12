# home-manager configuration for every Mac.
#
# Desktop applications are not here — they belong to the laptop role, in
# home/roles/darwin-laptop.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let

  # One key does everything: SSH authentication, git commit signing, and the
  # PGP signing that Arch packaging needs. The GPG key's authentication subkey
  # is served to SSH by gpg-agent, so there is no separate SSH keypair to
  # create, back up or register per machine — moving the key moves all three.
  #
  # The cost is that macOS points everything at its own ssh-agent. launchd
  # publishes that socket through SSH_AUTH_SOCK to every process in the login
  # session, GUI apps included, so redirecting it takes three measures below —
  # the same three every guide to this setup lists, only declared rather than
  # pasted into a shell profile.
  #
  # This is the socket gpg-agent actually listens on: GnuPG keeps it in the
  # home directory, and `gpgconf --list-dirs agent-ssh-socket` is how the world
  # finds it. Spelled out here rather than asked at run time because it has to
  # go into files at build time.
  #
  # Explicitly *not* home-manager's socket. `services.gpg-agent` on darwin
  # defines a LaunchAgent that runs `gpg-agent --supervised` behind launchd
  # sockets under /private/var/run — but --supervised implements systemd's
  # socket activation protocol, which wants LISTEN_FDS in the environment and a
  # listening socket on file descriptor 3. launchd hands sockets over its own
  # API instead, so the job dies the moment it starts, every time:
  #
  #   Fatal: file descriptor 3 must be valid in --supervised mode
  #          if LISTEN_FDNAMES is not set
  #
  # and launchd, having created the socket files before running the job, leaves
  # them sitting there answering nothing. Pointing at them does not fail — it
  # hangs, which is the worst way for this to be wrong. That job is turned off
  # below and GnuPG's own startup path used instead.
  sshAuthSock = "${config.programs.gpg.homedir}/S.gpg-agent.ssh";

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
    # writeShellApplication builds PATH out of runtimeInputs alone, so every
    # command the script uses has to be named here — gawk and gnugrep included.
    # Leaving them out is not a build error: shellcheck does not resolve
    # commands, so the first sign is `awk: command not found` at run time.
    runtimeInputs = [
      pkgs.gnupg
      pkgs.gawk
      pkgs.gnugrep
    ];
    text = ''
      # Two steps rather than one pipeline. gpg exits non-zero when the keyring
      # holds no secret key at all, which is an ordinary outcome and has to be
      # tolerated — but `|| true` over the whole pipeline would tolerate awk
      # failing too, and an empty result then reads as "no key found" and sends
      # the reader off to import a key they already have. Only gpg is excused.
      keys=$(gpg --list-secret-keys --with-keygrip --with-colons 2>/dev/null || true)

      # Field 12 of a sec/ssb record is that key's capabilities, where `a` means
      # authentication; the grp record following it carries its keygrip. So this
      # prints the keygrip of every key allowed to authenticate, and nothing else.
      grips=$(printf '%s\n' "$keys" |
        awk -F: '$1 == "sec" || $1 == "ssb" { auth = ($12 ~ /a/) }
                 $1 == "grp" && auth        { print $10 }')

      if [ -z "$grips" ]; then
        echo "gpg-ssh-authorize: no authentication-capable secret key found." >&2
        echo "gpg-ssh-authorize: import one, then run this again." >&2
        exit 0
      fi

      while IFS= read -r grip; do
        [ -n "$grip" ] || continue

        # The attribute name keeps its trailing colon: KEYATTR addresses the
        # raw field name as it appears in the key file. Reading it first means
        # a run with nothing to do writes nothing.
        if gpg-connect-agent "KEYATTR $grip Use-for-ssh:" /bye 2>/dev/null |
          grep -q '^D yes'; then
          continue
        fi

        gpg-connect-agent "KEYATTR $grip Use-for-ssh: yes" /bye >/dev/null
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

  # Measures two and three, which have to happen together and in this order.
  #
  # Two: start the agent. Nothing else will. gpg starts it on demand, but ssh
  # has no idea gpg-agent exists — it opens the socket or gives up — so at
  # login, before any gpg command has run, there is nothing to connect to.
  # `gpgconf --launch` is GnuPG's own answer to this and is what every writeup
  # of this setup puts in a shell profile; a LaunchAgent is where it belongs
  # when the goal is for it to hold for the whole session, not per terminal.
  #
  # Three: publish the socket. home-manager exports SSH_AUTH_SOCK from shell
  # init, which reaches terminals and nothing else, because launchd-started
  # applications never read a shell profile. `launchctl setenv` sets it for the
  # login session, so whatever reads the variable directly finds gpg-agent too.
  #
  # wait4path because /nix/store is on a volume that need not be mounted yet
  # when LaunchAgents start — the same guard home-manager puts on its own.
  launchd.agents.gpg-agent-ssh = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${pkgs.writeShellScript "gpg-agent-ssh-bootstrap" ''
          ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
          /bin/launchctl setenv SSH_AUTH_SOCK ${sshAuthSock}
        ''}"
      ];
      RunAtLoad = true;
    };
  };

  # See the note on sshAuthSock: this LaunchAgent cannot work on macOS, and its
  # sockets are worse than absent because connecting to one hangs. Everything
  # else services.gpg-agent does — writing gpg-agent.conf, exporting
  # SSH_AUTH_SOCK from shell init — is unaffected and still wanted.
  launchd.agents.gpg-agent.enable = lib.mkForce false;

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
    # The SSH path has its own pair of timers, and setting only the two above
    # leaves it on gpg-agent's defaults of 1800 and 7200 seconds — which, with
    # enableSshSupport being the point of this block, is the path that matters
    # most. Same values, so the key behaves the same whichever way it is used.
    defaultCacheTtlSsh = 28800;
    maxCacheTtlSsh = 86400;
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
      echo "    gpg-ssh-authorize                  # same step as above" >&2
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
  # `gh` sits here rather than in home/common.nix because the two Macs are
  # where repositories are worked on; the Linux server runs services and has
  # nothing to open a pull request about. It authenticates on its own — a
  # keyring entry or GH_TOKEN — so nothing about it belongs in this file, and
  # it deliberately does not reuse the SSH key set up above: `gh` speaks the
  # REST API over HTTPS, which is a different credential from the one `git`
  # pushes with.
  # k9s reads whatever kubeconfig the environment already points at and talks
  # to the API server itself, so it carries no cluster configuration and none
  # belongs here. It is on both Macs for the same reason `gh` is: this is where
  # someone is looking at things. Note that `kubectl` on these machines is
  # /usr/local/bin/kubectl, put there by something outside nix — k9s never
  # calls it, but anything that does still gets that one rather than a pinned
  # version. stern is the same shape of tool and the same absence of
  # configuration: it tails logs across pods and containers by regex, which is
  # the one thing k9s is awkward at, and it reads the same kubeconfig.
  #
  # Two of the cloud three are not named what they are called.
  #
  # `gcloud` is the main program of google-cloud-sdk; there is no gcloud
  # attribute. Bare, the package is the CLI and nothing else, and GKE is the
  # one thing that wants more than the CLI: Kubernetes dropped the in-tree GCP
  # auth provider in 1.26, so a kubeconfig written by `gcloud container
  # clusters get-credentials` names an external credential plugin instead.
  # Without gke-gcloud-auth-plugin on PATH, kubectl and k9s fail with "no Auth
  # Provider found" — an error that mentions neither gcloud nor the plugin.
  # Google ships it as a gcloud component, and the documented way to get one is
  # `gcloud components install`, which writes into the package's own directory:
  # impossible against a read-only store path. withExtraComponents is the
  # declarative form and builds the component into the package instead.
  #
  # `helm` is a different program entirely — a GPL-3.0 tool at 0.9.0 that has
  # nothing to do with Kubernetes. Helm the chart manager is kubernetes-helm,
  # whose mainProgram is nonetheless `helm`, so the wrong one installs quietly
  # and only looks wrong when it runs.
  #
  # terraform is unfree; see the note in modules/common.nix.
  # home-manager.useGlobalPkgs is on, so that predicate covers these packages
  # as much as it does the system ones.
  #
  # The language toolchains sit here rather than in home/common.nix because the
  # Macs are where code gets written; the Linux server runs services and has no
  # use for a compiler. Rust is not in this list — only the server Mac was asked
  # for it, so it lives in home/roles/darwin-server.nix.
  #
  # `go` is the whole toolchain — compiler, module tooling, gofmt — and follows
  # whatever nixpkgs currently treats as current, which is what naming it `go`
  # rather than `go_1_26` buys.
  #
  # `nodejs_24` rather than plain `nodejs`, even though the two are the same
  # derivation today. nixpkgs already carries nodejs_25 and nodejs_26, so the
  # default will move off 24 on its own schedule; asking by version means that
  # happens when this line changes and not before.
  #
  # bun is upstream's own binary, not a build from source — nixpkgs marks it
  # binaryNativeCode — because it vendors a patched JavaScriptCore that nothing
  # else here builds. It sits alongside Node rather than replacing it: the two
  # read the same package.json and neither supplies the other. It is also the
  # one package here that does not come from nixpkgs as it stands: nixpkgs is a
  # release behind and the version that was wanted is 1.3.14, so it is
  # overridden in pkgs/overlay.nix, which is where the reasoning lives.
  #
  # uv is the Python half, and the reason no Python interpreter is listed
  # beside it: uv fetches its own, standalone CPython builds under
  # ~/.local/share/uv, and manages virtualenvs against those. That is outside
  # nix by design — it is per-project, moves with pyproject.toml and does not
  # belong in a system closure — but it does mean `uv python install` writes
  # binaries this configuration did not put there. They are ordinary
  # relocatable macOS builds, so unlike on NixOS they simply run.
  home.packages = [
    pkgs._1password-cli
    pkgs.bun
    pkgs.gh
    pkgs.go
    (pkgs.google-cloud-sdk.withExtraComponents [
      pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])
    gpgSshAuthorize
    pkgs.k9s
    pkgs.kubernetes-helm
    pkgs.nodejs_24
    pkgs.stern
    pkgs.terraform
    pkgs.uv
  ];
}
