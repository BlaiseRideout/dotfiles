# Set up the prompt

#autoload -Uz promptinit
#promptinit
#prompt adam1

setopt histignorealldups sharehistory

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

# Use modern completion system
autoload -Uz compinit
compinit

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
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

if which powerline-daemon  >/dev/null 2>&1; then
  powerline-daemon -q
  . /usr/share/powerline/bindings/zsh/powerline.zsh
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

export EDITOR="vim"

stty -ixon
if which tmux >/dev/null 2>&1; then
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

export GOROOT=/usr/local/go
export GOPATH=$HOME/prog/go
export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"

export JAVA_HOME=/opt/jdk
export PATH="$JAVA_HOME/bin:$PATH:"

export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_NDK_HOME=$HOME/Android/Ndk
export PATH="$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin/:$ANDROID_HOME/platform-tools:$ANDROID_NDK_HOME:$ANDROID_HOME/build-tools/26.0.1"

export LD_LIBRARY_PATH="/usr/local/lib"
export PATH="$PATH:/usr/local/lib"

export PATH="$PATH:$HOME/.local/bin"
if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
  export RUSTFLAGS="-C target-cpu=native"
fi

source /usr/share/doc/fzf/examples/completion.zsh

if [ -f "$HOME/.systemspecificrc" ]; then
  source $HOME/.systemspecificrc
fi
