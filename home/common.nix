# home-manager configuration shared by every host, macOS and NixOS alike.
# This is the bulk of the setup; the per-platform files add only what genuinely
# cannot be expressed the same way on both.
{
  lib,
  pkgs,
  inputs,
  ...
}:

let
  # llm-agents' own build of its own packages, not its overlay.
  #
  # Both exist and produce the same programs. `overlays.shared-nixpkgs` builds
  # them against our nixpkgs, which shares dependencies with the rest of the
  # system and applies our `nixpkgs.config` — and, as upstream's README says
  # outright, hits their binary cache only while our nixpkgs revision matches
  # theirs. Ours does not. `codex` and `omp` are Rust, so missing the cache
  # means dragging in a toolchain and compiling; omp took long enough to be
  # noticed, which is how this was found.
  #
  # `packages.<system>` is built against the nixpkgs they pinned, so the store
  # path is the one they uploaded and it substitutes every time. What that
  # costs is a second copy of whatever their revision disagrees with ours
  # about — measured before switching, and on this machine it was two store
  # paths, not a second dependency tree. Fine trade for not compiling Rust
  # three times a week on three machines.
  #
  # `nixpkgs.config.allowUnfreePredicate` no longer reaches claude-code as a
  # result; their instantiation allows it themselves. The entry stays in
  # modules/common.nix because it is still what makes the name evaluable if
  # anything here ever refers to nixpkgs' own claude-code.
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # The plugins pkgs/omp-plugins builds, by the name each one takes inside
  # node_modules.
  ompPlugins = {
    "pi-anthropic-web-fetch" = "0.1.0";
    "pi-google-url-context" = "0.1.0";
    "pi-anthropic-web-search" = "0.1.0";
    "pi-google-google-search" = "0.1.0";
    "pi-openai-web-search" = "0.1.0";
    "@isac322/pi-codegraph" = "0.3.1";
    "context-mode" = "1.0.169";
  };

  # omp keeps its own register of which plugins exist, and a package under
  # node_modules is invisible without an entry here. Found by watching what
  # `omp plugin link` writes: the symlink alone left `omp plugin list` empty,
  # and `~/.omp/plugins/package.json` stayed `{"dependencies": {}}` throughout —
  # this file is the whole registry.
  ompPluginsLock = {
    plugins = lib.mapAttrs (_: version: {
      inherit version;
      enabledFeatures = null;
      enabled = true;
    }) ompPlugins;
    settings = { };
  };
in
{
  # Clear what would otherwise make the plugin links below fail on a machine
  # that has run omp before, or that carries an older generation of this
  # configuration. Both cases cost a second switch to notice and a third to fix.
  #
  # `node_modules` has to be a real directory, because each plugin is linked
  # *inside* it. An earlier version of this pointed the directory itself at the
  # store, and a symlink left there makes every per-plugin link fail silently.
  #
  # The register is written by omp on its first run, and home-manager never
  # overwrites a file it did not create — so a machine that has already run omp
  # keeps omp's copy, and every plugin declared here stays invisible. Removing
  # it first is what makes this work from an untouched machine in one switch.
  home.activation.ompPluginsPrepare = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    plugins="$HOME/.omp/plugins"

    if [ -L "$plugins/node_modules" ]; then
      $DRY_RUN_CMD rm -f "$plugins/node_modules"
    fi

    if [ -e "$plugins/omp-plugins.lock.json" ] && [ ! -L "$plugins/omp-plugins.lock.json" ]; then
      $DRY_RUN_CMD rm -f "$plugins/omp-plugins.lock.json"
    fi
  '';

  home.stateVersion = "26.05";

  home.packages = [
    pkgs.ripgrep
    pkgs.htop
    pkgs.fzf
    # From llm-agents rather than nixpkgs: it tracks upstream daily, while the
    # nixpkgs-unstable channel lags master by several days. It builds for
    # aarch64-darwin, x86_64-linux and aarch64-linux, so this line is portable.
    agents.claude-code
    agents.codex
    agents.omp

    # Observability CLIs, for the coding agents above to query telemetry with
    # rather than being handed screenshots of dashboards. They go on every
    # machine for the same reason claude-code does: the agent runs wherever
    # the work is.
    #
    # Two are not the obvious attribute. `promtool` is in prometheus's `cli`
    # output, so plain `pkgs.prometheus` would install the server and no tool
    # at all; `tempo-cli` is a local trim of the Tempo package — see
    # pkgs/overlay.nix. Of the rest only sentry-cli comes from nixpkgs as it
    # is: posthog-cli, axiom-cli and langfuse-cli are absent there and are
    # packaged in pkgs/.
    pkgs.tempo-cli
    pkgs.prometheus.cli
    pkgs.sentry-cli
    pkgs.posthog-cli
    pkgs.axiom-cli
    pkgs.langfuse-cli

    # The services those same agents have to act on rather than just read.
    # All four are in nixpkgs unchanged; two are simply not named after their
    # binary. `gws` is Google's Workspace CLI — @googleworkspace/cli upstream,
    # and `gws` is what it installs — and `stripe-cli` installs `stripe`.
    # agent-browser is Vercel's headless browser, meant to be driven by an
    # agent rather than by a test suite.
    pkgs.wrangler
    pkgs.stripe-cli
    pkgs.agent-browser
    pkgs.gws

    # Every machine, because a cluster is reached from wherever someone happens
    # to be — including the NixOS server, which is a machine that runs services
    # and therefore a machine where something goes wrong.
    #
    # It carries no cluster configuration and none belongs here: k9s reads
    # whatever kubeconfig the environment already points at and talks to the API
    # server itself.
    #
    # One thing it needs that this file cannot give it. Kubernetes dropped the
    # in-tree GCP auth provider in 1.26, so a kubeconfig written by `gcloud
    # container clusters get-credentials` names an external credential plugin,
    # and without gke-gcloud-auth-plugin on PATH k9s fails with "no Auth
    # Provider found" — an error naming neither gcloud nor the plugin. That
    # plugin comes with google-cloud-sdk in home/darwin.nix, so GKE works on the
    # Macs and not on the NixOS server. Other clusters are unaffected.
    pkgs.k9s

    # And the client itself, which until now was not declared anywhere. On the
    # Macs `kubectl` was /usr/local/bin/kubectl, a symlink OrbStack installs into
    # its own app bundle — so the version moved when OrbStack did, and the NixOS
    # server had none at all. That is the same objection this repository makes to
    # rustup and to `omp plugin install`: the tool on a machine was whatever
    # something else last put there rather than what flake.lock pins.
    #
    # This changes which binary answers on the Macs. Nix profiles come before
    # /usr/local/bin on the PATH nix-darwin installs, so `kubectl` becomes the
    # pinned one — 1.36.3 here against OrbStack's 1.33.9. kubectl supports one
    # minor version of skew in either direction against the API server, and
    # OrbStack's own cluster tracks its bundled version, so the gap is worth
    # watching if that cluster is the one being used.
    pkgs.kubectl
  ];

  programs.git = {
    enable = true;
    settings.user = {
      name = "Byeonghoon Yoo";
      email = "bhyoo@bhyoo.com";
    };
  };

  # Bare on purpose. The prompt, colours, completion styling and plugins are
  # not configured here — that is coming separately, through zinit — so
  # nothing in this repo should write shell interactive setup into ~/.zshrc.
  programs.zsh.enable = true;

  # On macOS this shadows Apple's /usr/bin/vim, which cannot be touched: it
  # lives on the sealed read-only system volume. Nix profiles come first on the
  # PATH nix-darwin installs, so this wins. On NixOS there is nothing to shadow.
  programs.vim = {
    enable = true;
    defaultEditor = true;

    # vim-sensible is not listed. home-manager's module sets it in its own
    # `config`, not merely as the option's default, and `plugins` is a list —
    # so definitions concatenate instead of overriding, and naming it here only
    # loads it twice. It supplies the uncontroversial baseline (backspace,
    # smarttab, complete-=i, incsearch, ruler, laststatus, wildmenu, autoread,
    # tabpagemax, formatoptions+=j, matchit ...) so none of that is repeated
    # below. Where the settings here overlap, they win: nixpkgs patches
    # sensible's `s:MaySet` to skip any option already set from /nix/store.
    #
    # Vim ships syntax files for most languages but not for Nix, and this
    # configuration is the thing most often edited here.
    plugins = [ pkgs.vimPlugins.vim-nix ];

    # Only the options home-manager knows about; everything else is extraConfig.
    settings = {
      background = "dark";
      number = true;
      expandtab = true;
      shiftwidth = 2;
      tabstop = 2;
      ignorecase = true;
      smartcase = true;
      hidden = true;
      mouse = "a";
      # Not left to vim-sensible: `set nocompatible` on line 2 of the generated
      # vimrc already moves 'history' to its non-vi default of 200, and because
      # that line lives under /nix/store, sensible's `s:MaySet` treats it as
      # user-set and skips its own history=1000.
      history = 1000;
      undofile = true;
      # Keep scratch files out of the directory being edited. The trailing `//`
      # makes Vim encode the full path into the file name, so same-named files in
      # different directories do not collide.
      undodir = [ "~/.vim/undo//" ];
      directory = [ "~/.vim/swap//" ];
      backupdir = [ "~/.vim/backup//" ];
    };

    extraConfig = ''
      " First: 'encoding' must be set before any option holding multi-byte text
      " (listchars below), otherwise those values are reinterpreted.
      set encoding=utf-8
      set fileformats=unix,dos,mac

      syntax enable
      filetype plugin indent on

      " Colours. `silent!` so a Vim without this scheme still starts cleanly.
      if has('termguicolors') && $COLORTERM =~# 'truecolor\|24bit'
        set termguicolors
      endif
      silent! colorscheme habamax

      " Search. sensible gives incsearch and a <C-L> mapping to clear highlight;
      " hlsearch itself is deliberately not part of its baseline.
      set hlsearch
      nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

      " Indenting
      set autoindent
      set smartindent
      set softtabstop=2
      set shiftround

      " Display. scrolloff/sidescrolloff/listchars override sensible's more
      " conservative values (1, 2, and an ASCII-only listchars).
      set showcmd
      set cursorline
      set scrolloff=3
      set sidescrolloff=5
      set linebreak
      set list
      set listchars=tab:»·,trail:·,nbsp:␣,extends:›,precedes:‹

      " Completion in : and insert mode (sensible enables wildmenu itself).
      set wildmode=longest:full,full
      set completeopt=menuone,longest

      set updatetime=300

      " Share the system clipboard where this Vim was built with support for it.
      " Guarded rather than assumed: a headless server build has -clipboard.
      if has('clipboard')
        set clipboard=unnamed
      endif

      " Reopen a file at the line it was left on.
      autocmd BufReadPost *
        \ if line("'\"") >= 1 && line("'\"") <= line("$") && &filetype !~# 'commit'
        \ |   execute "normal! g`\""
        \ | endif
    '';
  };

  # omp's plugins, decided here rather than by `omp plugin install`.
  #
  # One symlink per plugin, not one for the whole directory, and the difference
  # is not stylistic. omp counts an entry under ~/.omp/plugins/node_modules only
  # when it is a symlink — the shape `omp plugin link` leaves behind. Pointing
  # the directory itself at a store tree put all 144 packages in place and
  # `omp plugin list` reported none of them, because they were then ordinary
  # directories.
  #
  # Their dependencies still resolve: Node walks up from the *real* path of the
  # importing file, which is inside the store tree, where every dependency the
  # lockfile pinned is a sibling. That is why pkgs/omp-plugins builds one tree
  # rather than one derivation per plugin.
  #
  # The trade, unchanged: these entries are store paths, so `omp plugin install`
  # cannot replace them. Adding a plugin is a line in
  # pkgs/omp-plugins/default.nix and a line here.
  home.file = {
    # Vim does not create these itself; without them undo/swap/backup silently
    # fail.
    ".vim/undo/.keep".text = "";
    ".vim/swap/.keep".text = "";
    ".vim/backup/.keep".text = "";
  }
  // {
    # The register, next to the links it describes. Written whole, so it also
    # decides what is *not* installed — a plugin dropped from the set above
    # leaves omp on the next switch rather than lingering.
    ".omp/plugins/omp-plugins.lock.json".text = builtins.toJSON ompPluginsLock;
  }
  // builtins.listToAttrs (
    map (name: {
      name = ".omp/plugins/node_modules/${name}";
      value.source = "${pkgs.omp-plugins}/node_modules/${name}";
    }) (builtins.attrNames ompPlugins)
  );
}
