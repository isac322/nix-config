# home-manager configuration shared by every host, macOS and NixOS alike.
# This is the bulk of the setup; the per-platform files add only what genuinely
# cannot be expressed the same way on both.
{ pkgs, ... }:

{
  home.stateVersion = "26.05";

  home.packages = [
    pkgs.ripgrep
    pkgs.htop
    pkgs.fzf
    # From llm-agents rather than nixpkgs: it tracks upstream daily, while the
    # nixpkgs-unstable channel lags master by several days. It builds for
    # aarch64-darwin, x86_64-linux and aarch64-linux, so this line is portable.
    pkgs.llm-agents.claude-code
    pkgs.llm-agents.omp

    # Observability CLIs, for the coding agents above to query telemetry with
    # rather than being handed screenshots of dashboards. They go on every
    # machine for the same reason claude-code does: the agent runs wherever
    # the work is.
    #
    # Two are not the obvious attribute. `promtool` is in prometheus's `cli`
    # output, so plain `pkgs.prometheus` would install the server and no tool
    # at all; `tempo-cli` is a local trim of the Tempo package — see
    # pkgs/overlay.nix. The remaining three are upstream as-is, except that
    # posthog-cli and axiom-cli had to be packaged here — see pkgs/.
    pkgs.tempo-cli
    pkgs.prometheus.cli
    pkgs.sentry-cli
    pkgs.posthog-cli
    pkgs.axiom-cli
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

  # Vim does not create these itself; without them undo/swap/backup silently fail.
  home.file = {
    ".vim/undo/.keep".text = "";
    ".vim/swap/.keep".text = "";
    ".vim/backup/.keep".text = "";
  };
}
