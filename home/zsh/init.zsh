# Enable Powerlevel10k instant prompt. Keep this close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Suppress asynchronous output warnings from zinit turbo mode.
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# zinit itself is installed by Nix on every host. Plugin checkouts remain
# user-writable runtime state under zinit's normal data directory.
source @zinit@/share/zinit/zinit.zsh

# Powerlevel10k.
zinit ice depth=1
zinit light romkatv/powerlevel10k

# Plugins loaded through zinit turbo mode.
zinit ice wait lucid atload"_zsh_autosuggest_start"
zinit light zsh-users/zsh-autosuggestions

zinit ice wait"0c" lucid
zinit light zdharma-continuum/fast-syntax-highlighting

zinit ice wait lucid blockf
zinit light zsh-users/zsh-completions

zinit ice wait lucid
zinit light zsh-users/zsh-history-substring-search

zinit ice wait lucid
zinit light Aloxaf/fzf-tab

zinit ice wait lucid
zinit light wfxr/forgit

zinit ice wait lucid
zinit light hlissner/zsh-autopair

zinit ice wait lucid
zinit light MichaelAquilina/zsh-you-should-use

zinit ice wait lucid
zinit light zdharma-continuum/history-search-multi-word

# Shared Oh My Zsh libraries and snippets. SSH_AUTH_SOCK, gpg-agent startup and
# GPG_TTY are owned by the platform Home Manager modules, so the gpg-agent and
# ssh-agent snippets are deliberately absent.
zinit for \
  OMZL::functions.zsh \
  OMZL::clipboard.zsh \
  OMZL::git.zsh \
  OMZL::misc.zsh \
  OMZL::key-bindings.zsh \
  OMZL::directories.zsh \
  OMZL::termsupport.zsh \
  OMZP::sudo \
  OMZP::extract \
  OMZP::copybuffer \
  OMZP::copypath \
  OMZP::copyfile \
  OMZP::colored-man-pages \
  OMZP::command-not-found \
  OMZP::safe-paste \
  OMZP::encode64 \
  OMZP::urltools \
  OMZP::jsontools \
  OMZP::docker \
  OMZP::kubectl \
  OMZP::dotenv \
  OMZP::git \
  OMZP::npm \
  OMZP::docker-compose \
  OMZP::python \
  OMZP::pip \
  OMZP::poetry \
  OMZP::virtualenv \
  OMZP::gitignore \
  atload'
    alias l="eza -1 --icons"
    alias la="eza -la --icons --group-directories-first --header --git"
    alias ll="eza -l --icons --group-directories-first --header --git"
    alias ls="eza --icons --group-directories-first"
    alias lt="eza --tree --icons --level=2"
    alias lr="eza -lrRs=mod"
    alias ldot="eza -ld .*"
    alias lS="eza -lrs=size"
    alias lart="eza -1as=mod"
    alias lrt="eza -1rs=mod"
    alias -g CA="2>&1 | bat -A"
    alias -g G="| rg"
    alias -g L="| bat"
    alias -g LL="2>&1 | bat"
    alias help="tldr"
  ' \
  OMZP::common-aliases \
  OMZP::rust \
  OMZP::aliases \
  OMZP::alias-finder \
  OMZP::aws \
  OMZP::golang \
  OMZP::helm \
  OMZP::history \
  OMZP::rsync \
  OMZP::gh \
  OMZP::terraform \
  OMZP::azure \
  OMZP::gcloud

# systemd is meaningful on the NixOS host and absent on macOS. The old
# Arch-specific snippet is not valid on any host managed by this repository.
if [[ "$OSTYPE" == linux* ]]; then
  zinit ice wait lucid
  zinit snippet OMZP::systemd
fi

# Third-party plugins.
zinit ice wait lucid
zinit light ntnyq/omz-plugin-pnpm

zinit ice wait lucid
zinit light lukechilds/zsh-better-npm-completion

# compinit compatible with zinit turbo mode. Home Manager's eager compinit is
# disabled so completion is initialized exactly once here.
zinit ice wait lucid atinit"zicompinit; zicdreplay" as"null"
zinit light zdharma-continuum/null

# History settings. These intentionally override Home Manager's baseline after
# the Oh My Zsh history library has loaded.
HISTFILE="${HISTFILE:-${ZDOTDIR:-$HOME}/.zsh_history}"
HISTSIZE=50000
SAVEHIST=10000
setopt extended_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_verify
setopt share_history

ZSH_DOTENV_PROMPT=false

# fd + ripgrep integration for fzf.
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --strip-cwd-prefix --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"

# bat as the manual-page renderer.
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export MANROFFOPT="-c"

# Modern CLI aliases.
alias cat='bat --paging=never'
alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --group-directories-first --header --git'
alias la='eza -la --icons --group-directories-first --header --git'
alias lt='eza --tree --icons --level=2'
alias l='eza -1 --icons'
alias tree='eza --tree --icons'
alias du='dust'
alias df='duf'
alias dig='doggo'
alias top='btm'
alias ps='procs'
alias help='tldr'

alias lr='eza -lrRs=mod'
alias ldot='eza -ld .*'
alias lS='eza -lrs=size'
alias lart='eza -1as=mod'
alias lrt='eza -1rs=mod'

alias -g CA='2>&1 | bat -A'
alias -g G='| rg'
alias -g L='| bat'
alias -g LL='2>&1 | bat'

# lazygit with directory changes propagated back to the shell.
lg() {
  export LAZYGIT_NEW_DIR_FILE=~/.lazygit/newdir
  lazygit "$@"
  if [[ -f "$LAZYGIT_NEW_DIR_FILE" ]]; then
    cd "$(cat "$LAZYGIT_NEW_DIR_FILE")" || return
    rm -f "$LAZYGIT_NEW_DIR_FILE"
  fi
}

source <(fzf --zsh)
eval "$(zoxide init zsh)"
eval "$(navi widget zsh)"

# These wrappers protect the KDE session on Linux. They are not installed on
# macOS, where kwin_wayland does not exist and the native commands stay intact.
if [[ "$OSTYPE" == linux* ]]; then
  killall() {
    if [[ "$*" == *"kwin_wayland"* ]]; then
      echo "ERROR: DO NOT use killall on kwin_wayland; it will crash the KDE Plasma desktop."
      echo "Use kill-virtual-kwin for virtual KWin sessions."
      return 1
    fi
    command killall "$@"
  }

  pkill() {
    if [[ "$*" == "kwin_wayland" || "$*" == "-9 kwin_wayland" ]]; then
      echo "ERROR: DO NOT use pkill on kwin_wayland; it will crash the KDE Plasma desktop."
      echo "Use kill-virtual-kwin for virtual KWin sessions."
      return 1
    fi
    command pkill "$@"
  }
fi

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
