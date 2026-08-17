# Enable Powerlevel10k instant prompt. Keep this close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Suppress asynchronous output warnings from zinit turbo mode.
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Zinit itself and the Oh My Zsh sources below are installed by Nix. Only the
# third-party plugin checkouts remain in Zinit's user-writable data directory.
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

# Oh My Zsh is sourced from nixpkgs' flake-pinned tree. Using OMZL::/OMZP::
# snippets here made every shell retry GitHub downloads whenever Zinit's
# snippet cache was incomplete, which is exactly how the MBP reached HTTP 429.
typeset -g ZSH="@oh-my-zsh@"
typeset -g ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"
mkdir -p "$ZSH_CACHE_DIR/completions"

# Generated completions take precedence. Plugin directories with static
# completion definitions must also be visible before the deferred compinit.
fpath=(
  "$ZSH_CACHE_DIR/completions"
  "$ZSH/plugins/extract"
  "$ZSH/plugins/docker-compose"
  "$ZSH/plugins/pip"
  "$ZSH/plugins/golang"
  "$ZSH/plugins/terraform"
  $fpath
)

# Zinit intercepts compdef only while it loads a plugin itself. These pinned
# sources are loaded directly, so queue their compdef calls for zicdreplay.
typeset -gi _nix_omz_compdef_shim=0
if (( ! $+functions[compdef] )); then
  compdef() { zicompdef "$@"; }
  _nix_omz_compdef_shim=1
fi

source "$ZSH/lib/functions.zsh"
source "$ZSH/lib/git.zsh"
source "$ZSH/lib/misc.zsh"
source "$ZSH/lib/key-bindings.zsh"
source "$ZSH/lib/directories.zsh"
source "$ZSH/lib/termsupport.zsh"

source "$ZSH/plugins/sudo/sudo.plugin.zsh"
source "$ZSH/plugins/extract/extract.plugin.zsh"
source "$ZSH/plugins/safe-paste/safe-paste.plugin.zsh"
source "$ZSH/plugins/encode64/encode64.plugin.zsh"
source "$ZSH/plugins/urltools/urltools.plugin.zsh"
source "$ZSH/plugins/jsontools/jsontools.plugin.zsh"
source "$ZSH/plugins/docker/docker.plugin.zsh"
source "$ZSH/plugins/kubectl/kubectl.plugin.zsh"
source "$ZSH/plugins/dotenv/dotenv.plugin.zsh"
source "$ZSH/plugins/git/git.plugin.zsh"
source "$ZSH/plugins/npm/npm.plugin.zsh"
source "$ZSH/plugins/docker-compose/docker-compose.plugin.zsh"
source "$ZSH/plugins/python/python.plugin.zsh"
source "$ZSH/plugins/pip/pip.plugin.zsh"
source "$ZSH/plugins/poetry/poetry.plugin.zsh"
source "$ZSH/plugins/virtualenv/virtualenv.plugin.zsh"
source "$ZSH/plugins/gitignore/gitignore.plugin.zsh"
source "$ZSH/plugins/aliases/aliases.plugin.zsh"
source "$ZSH/plugins/alias-finder/alias-finder.plugin.zsh"
source "$ZSH/plugins/aws/aws.plugin.zsh"
source "$ZSH/plugins/golang/golang.plugin.zsh"
source "$ZSH/plugins/helm/helm.plugin.zsh"
source "$ZSH/plugins/history/history.plugin.zsh"
source "$ZSH/plugins/rsync/rsync.plugin.zsh"
source "$ZSH/plugins/gh/gh.plugin.zsh"
source "$ZSH/plugins/terraform/terraform.plugin.zsh"
source "$ZSH/plugins/azure/azure.plugin.zsh"

if (( _nix_omz_compdef_shim )); then
  unfunction compdef
fi
unset _nix_omz_compdef_shim

# @platform-zsh@

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

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
