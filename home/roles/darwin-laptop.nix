# home-manager configuration for the edge Macs someone sits in front of.
#
# Desktop applications and interactive desktop integrations live here.
# Everything shared by every Mac is in home/darwin.nix; everything shared by
# every machine is in home/common.nix.
{ lib, pkgs, ... }:

let
  # Laptop-only desktop notification plugin. fetchgit uses Git's smart
  # protocol rather than GitHub's archive endpoint, which is rate-limited on
  # this network; the revision and recursive source hash still make it a fixed
  # Nix input.
  zshAutoNotify = pkgs.fetchgit {
    url = "https://github.com/MichaelAquilina/zsh-auto-notify.git";
    rev = "b51c934d88868e56c1d55d0a2a36d559f21cb2ee";
    hash = "sha256-s3TBAsXOpmiXMAQkbaS5de0t0hNC1EzUUb0ZG+p9keE=";
  };

  # Vorta imports this profile export once from ~/.vorta-init.json. Keep the
  # export repository-less so first launch never needs a URL, password, or
  # keychain entry. Exclusions use ProfileExport's supported ExclusionModel
  # rows; comments and blank lines in the shared Borg file are not patterns.
  borgExcludePatterns = builtins.filter (line: line != "" && !lib.hasPrefix "#" line) (
    lib.splitString "\n" (builtins.readFile ../files/borg-exclude)
  );

  vortaBootstrap = pkgs.writeText "vorta-init.json" (
    builtins.toJSON {
      id = 1;
      name = "Default";
      repo = null;
      ssh_key = null;
      compression = "zstd,3";
      schedule_mode = "off";
      validation_on = true;
      validation_weeks = 3;
      compaction_on = false;
      compaction_weeks = 3;
      prune_on = false;
      new_archive_name = "{hostname}-{now:%Y-%m-%d-%H%M%S}";
      prune_prefix = "{hostname}-";
      pre_backup_cmd = "";
      post_backup_cmd = "";
      dont_run_on_metered_networks = true;

      SourceFileModel = [ ];
      ExclusionModel = map (pattern: {
        name = pattern;
        enabled = true;
        source = "custom";
      }) borgExcludePatterns;
      WifiSettingModel = [ ];
      SchemaVersion = {
        id = 1;
        version = 23;
        changed_at = "2026-08-18 00:00:00";
      };
      SettingsModel = [
        {
          key = "autostart";
          value = true;
          str_value = "";
          label = "Automatically start Vorta at login";
          group = "Startup";
          tooltip = "Add Vorta to the systems autostart list";
          type = "checkbox";
        }
        {
          key = "foreground";
          value = false;
          str_value = "";
          label = "Show main window of Vorta on launch";
          group = "Startup";
          tooltip = "Make Vorta appear on screen instead of minimizing to system tray";
          type = "checkbox";
        }
        {
          key = "check_for_updates";
          value = false;
          str_value = "";
          label = "Check for updates on startup";
          group = "Updates";
          tooltip = "Uses Sparkle to find new updates published on Github.";
          type = "checkbox";
        }
      ];
    }
  );
in
{
  # Do not link ~/.vorta-init.json with home.file: Vorta unlinks a successful
  # import, and Home Manager would recreate it on every activation. Copy it
  # only before Vorta has a database. If a previous managed copy survived a
  # failed or interrupted import, discard it once a database exists so Vorta's
  # overwrite import path can never replace established profiles or settings.
  home.activation.installVortaBootstrap = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    vorta_db="$HOME/Library/Application Support/Vorta/settings.db"
    bootstrap="$HOME/.vorta-init.json"

    if [ -e "$vorta_db" ]; then
      if [ -e "$bootstrap" ] && ${pkgs.diffutils}/bin/cmp --silent ${lib.escapeShellArg vortaBootstrap} "$bootstrap"; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$bootstrap"
      fi
    elif [ ! -e "$bootstrap" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp ${lib.escapeShellArg vortaBootstrap} "$bootstrap"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 600 "$bootstrap"
    fi
  '';

  # Notifications are a desktop concern. The shared shell initialization uses
  # mkAfter (order 1500); order 1600 keeps this after zinit itself is loaded
  # while excluding unattended server Macs and NixOS hosts entirely.
  programs.zsh.initContent = lib.mkOrder 1600 ''
    export AUTO_NOTIFY_ENABLE_SSH=1
    export AUTO_NOTIFY_ENABLE_TRANSIENT=0
    AUTO_NOTIFY_IGNORE=(
      'vim'
      'nvim'
      'less'
      'more'
      'man'
      'tig'
      'watch'
      'git commit'
      'top'
      'htop'
      'ssh'
      'nano'
      'claude'
      'codex'
    )

    zinit ice wait lucid
    zinit light ${zshAutoNotify}
  '';

  # Firefox is the clearest case of "same option, different implementation".
  # On macOS the package is a plain .app bundle from the nixpkgs-firefox-darwin
  # overlay, which home-manager cannot wrap, so the policies have to be
  # delivered through two channels instead. A Linux host would just use
  # `pkgs.firefox` and let home-manager wrap it with the same `policies`.
  programs.firefox =
    let
      policies = {
        DisableAppUpdate = true;
        BackgroundAppUpdate = false;
      };
    in
    {
      enable = true;

      # Baked into the bundle.
      package = pkgs.firefox-bin.override {
        extraFiles."distribution/policies.json".source = pkgs.writeText "policies.json" (
          builtins.toJSON { inherit policies; }
        );
      };

      # Written to ~/Library/Preferences/org.mozilla.firefox.plist along with
      # EnterprisePoliciesEnabled.
      inherit policies;
    };

  # JetBrains Mono Nerd Font. home-manager links fonts into ~/Library/Fonts on
  # darwin, so a package in home.packages is all it takes. The family name is
  # "JetBrainsMono Nerd Font" — the files are JetBrainsMonoNerdFont-*.ttf, and
  # the NL and Mono variants in the same package are separate families.
  home.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.d2coding
  ];

  programs.ghostty = {
    # Ghostty itself is a cask, declared in modules/roles/darwin-laptop.nix.
    # nixpkgs builds it for Linux only — `meta.platforms` has no darwin — and
    # the module documents exactly this case: set package to null where ghostty
    # is unavailable and let something else install it.
    enable = true;
    package = null;

    # Written to ~/.config/ghostty/config. Ghostty is the one terminal here
    # whose settings are a plain text file rather than a GUI preference store,
    # which is why it was chosen over Warp and iTerm2 — the quake window is
    # built in to all three, but only this one is configurable from the repo.
    settings = {
      # Repeating font-family builds a fallback chain: Ghostty moves down the
      # list when a codepoint is missing from the font above. JetBrains Mono has
      # no Hangul, so without a second entry macOS picks something arbitrary.
      #
      # D2Coding is the pairing that keeps the grid intact — its Hangul is
      # exactly twice the ASCII advance, which a proportional Korean face is
      # not, and a terminal notices.
      font-family = [
        "JetBrainsMono Nerd Font"
        "D2CodingLigature Nerd Font"
      ];
      font-size = 14;

      # Closing every window leaves the process running, which is what keeps
      # the global keybinds alive. This is already the macOS default, but the
      # whole arrangement depends on it, so it is stated rather than assumed.
      quit-after-last-window-closed = false;

      # The quake-style drop-down. `global:` makes the binding work while
      # another app is focused, which on macOS needs Ghostty to be granted
      # Accessibility permission — a one-time GUI approval that cannot be
      # declared away.
      #
      # F12 is free: nothing in macOS's own shortcut table binds key code 111,
      # and no symbolic hotkey on this machine uses it.
      #
      # cmd+opt+t opens an ordinary window. `new_window` brings Ghostty to the
      # front when it is not focused, so the binding doubles as "launch it".
      # Splits and movement between them. No `global:` — these only make sense
      # while the terminal is focused.
      #
      # ⌘⌥D needed macOS's Dock-hiding shortcut turned off first; it is a
      # system binding, and those win over an application's. That is handled in
      # modules/keyboard.nix. ⌘⌥R was unclaimed, and macOS uses no ⇧⌥
      # combination at all, so the WASD movement keys were all free.
      #
      # Note the overlap: ⌘⌥D splits downwards while ⇧⌥D moves right, because
      # movement follows WASD and splitting follows the direction's initial.
      keybind = [
        "global:f12=toggle_quick_terminal"
        "global:cmd+opt+t=new_window"
        "cmd+opt+d=new_split:down"
        "cmd+opt+r=new_split:right"
        "shift+opt+w=goto_split:up"
        "shift+opt+a=goto_split:left"
        "shift+opt+s=goto_split:down"
        "shift+opt+d=goto_split:right"
      ];
      # Dragging a selection puts it on the clipboard. `true` is already the
      # default and on macOS falls back to the system clipboard because there
      # is no X11-style selection clipboard here; `clipboard` says so outright
      # rather than depending on that fallback.
      copy-on-select = "clipboard";

      # Translucency. Blur only takes effect while opacity is below 1, so the
      # two go together. 0.9 is deliberately mild — enough to see through,
      # not enough to fight the text. `true` is a blur intensity of 20, which
      # the docs call a good looking default; macOS 26 also accepts
      # `macos-glass-regular` and `macos-glass-clear` for the native glass
      # effect, which is worth trying next to the Tinted setting elsewhere.
      #
      # Two macOS caveats: opacity changes need Ghostty restarted outright,
      # not just reloaded, and opacity is ignored in native fullscreen because
      # the backdrop turns grey there.
      background-opacity = 0.9;
      background-blur = "macos-glass-regular";

      # Unfocused splits fade so the active one is obvious. 0.7 is already the
      # default; 0.6 makes it more legible at a glance. The floor is 0.15.
      unfocused-split-opacity = 0.6;

      # Unlimited is not available — the docs say so outright and call it a
      # planned feature — so this is just a large ceiling. It is bytes per
      # surface, allocated lazily, so a big number costs nothing until the
      # scrollback actually fills. 100 MB against a default of 10 MB.
      scrollback-limit = 100000000;

      # Mousing over a split focuses it, within the focused window only.
      focus-follows-mouse = true;

      quick-terminal-position = "top";
      quick-terminal-screen = "mouse";
      quick-terminal-animation-duration = 0.1;

      # Ghostty describes itself as `xterm-ghostty`, and the terminfo entry for
      # that name exists in exactly one place on this machine: inside
      # Ghostty.app. It is found through the TERMINFO variable Ghostty exports
      # into the shell, so anything that drops the environment loses it — sudo
      # clears it by env_reset, and ssh never forwards it at all. Hence
      # `Error opening terminal: xterm-ghostty` on the far end, and a root-run
      # TUI with no colour on this one. Neither Apple's /usr/share/terminfo nor
      # nixpkgs' ncurses 6.6 has the entry; ncurses ships it as plain `ghostty`,
      # which is a different name and does not answer for this one.
      #
      # The three features below are Ghostty's own answers, all off by default
      # because each shadows a command with a shell function. The list merges
      # with the default rather than replacing it, so cursor, title and path
      # stay on without being named.
      #
      #   sudo         carries TERMINFO across the sudo boundary
      #   ssh-terminfo copies the entry to a host on first connect, using `tic`
      #                there, and remembers it in `ghostty +ssh-cache`
      #   ssh-env      sets COLORTERM and TERM_PROGRAM on the remote, and is
      #                the fallback to xterm-256color when the copy fails
      #
      # Being shell functions, they only cover `ssh` typed at an interactive
      # prompt. git, scp, rsync -e ssh and anything inside a Makefile call the
      # binary directly and are unaffected — which is why the NixOS server
      # installs the terminfo itself, in modules/nixos.nix, rather than relying
      # on this. For a host that is neither ours nor reachable that way:
      #
      #   infocmp -x xterm-ghostty | ssh HOST -- tic -x -
      shell-integration-features = "sudo,ssh-terminfo,ssh-env";
    };
  };
}
