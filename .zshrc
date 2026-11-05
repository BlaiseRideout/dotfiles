# Oh My Zsh is installed by Home Manager. Keep the existing Powerline prompt.
export ZSH="$HOME/.local/share/zsh/oh-my-zsh"
ZSH_THEME=""
# Nix manages updates; don't try to update the read-only package in place.
zstyle ':omz:update' mode disabled
plugins=(git)
if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit
  compinit
fi

# Use emacs keybindings even if our EDITOR is set to vi.
bindkey -e

# Shared history with duplicates removed; a leading space keeps a command private.
HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history
setopt histignorealldups sharehistory histignorespace histreduceblanks
setopt auto_cd auto_pushd pushd_ignore_dups

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

if [ -f /usr/share/powerline/bindings/zsh/powerline.zsh ]; then
  if which powerline-daemon  >/dev/null 2>&1; then
    powerline-daemon -q
    . /usr/share/powerline/bindings/zsh/powerline.zsh
  fi
fi

if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    #alias grep='grep --color=auto'
    #alias fgrep='fgrep --color=auto'
    #alias egrep='egrep --color=auto'
fi

alias incognito="set +o history;clear"
alias uncognito="set -o history;clear"

alias vi="nvim"
alias vim="nvim"
export EDITOR="nvim"
export VISUAL="nvim"

if [[ -t 0 && -t 1 ]]; then
  stty -ixon
fi

# PATH and the Go/Java/Android/Rust variables live in ~/.profile, shared with
# the graphical sessions; read it here if the session didn't
if [[ -z $DOTFILES_PROFILE && -f ~/.profile ]]; then
  emulate sh -c '. ~/.profile'
fi

# Not in ~/.profile: it would reach the whole graphical session, Nix apps included
export LD_LIBRARY_PATH="/usr/local/lib"

# fzf's key bindings and completion, from fzf itself (0.48+), else from
# Ubuntu's package (0.44; nhuto-Mint gets a current fzf from Nix)
if [[ -t 0 && -t 1 ]]; then
  if fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  else
    source /usr/share/doc/fzf/examples/completion.zsh
    source /usr/share/doc/fzf/examples/key-bindings.zsh
  fi
  bindkey '^Y' fzf-file-widget
fi

if [ -f "$HOME/.systemspecificrc" ]; then
  source $HOME/.systemspecificrc
fi

autoload -U select-word-style
select-word-style bash

if [[ -t 0 && -t 1 ]] && which tmux >/dev/null 2>&1; then
	if [[ -z "$TMUX" ]] ;then
		ID="$(tmux ls | grep -vm1 attached | cut -d: -f1)" # get the id of a deattached session
		if [[ -z "$ID" ]] ;then # if not available create a new one
			tmux new-session
			exit
		else
			tmux attach-session -t "$ID" # if available attach to it
			exit
		fi
	fi
fi

setopt interactivecomments

# Alt-arrows
bindkey "^[[1;3C" forward-word
bindkey "^[[1;3D" backward-word
# Ctrl-arrows
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word

if which zoxide >/dev/null 2>&1; then
  eval "$(zoxide init --cmd cd zsh)"
fi

export KITTY_INSTALLATION_DIR=/usr/lib/kitty
if [[ -d "$KITTY_INSTALLATION_DIR" ]]; then
  export KITTY_SHELL_INTEGRATION="enabled"
  autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
  kitty-integration
  unfunction kitty-integration
fi

# Fish-style suggestions: Right/End accepts the suggestion, Alt-Right a word.
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
if [[ -r "$HOME/.local/share/zsh/autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$HOME/.local/share/zsh/autosuggestions/zsh-autosuggestions.zsh"
fi

# Load highlighting after widgets, then history search as its upstream recommends.
if [[ -r "$HOME/.local/share/zsh/syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$HOME/.local/share/zsh/syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
if [[ -r "$ZSH/plugins/history-substring-search/history-substring-search.plugin.zsh" ]]; then
  source "$ZSH/plugins/history-substring-search/history-substring-search.plugin.zsh"
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey '^[OA' history-substring-search-up
  bindkey '^[OB' history-substring-search-down
  bindkey '^P' history-substring-search-up
  bindkey '^N' history-substring-search-down
fi
