# ~/.bashrc: executed by bash(1) for non-login shells
# see /usr/share/doc/bash/examples/startup-files (in thm package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color) color_prompt=yes;;
    xterm-256color) color_prompt=yes;;
    screen-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    export PS1="${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\$(date "+%H.%M")\[\033[00m\]:\[\033[01;31m\]\w\[\033[01;33m\]\$(__git_ps1)\[\033[00m\]\012\$ "
else
    export PS1="${debian_chroot:+($debian_chroot)}\u@\h:\$(date "+%H.%M"):\w\$(__git_ps1)\012\$ "
fi

unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    #alias grep='grep --color=auto'
    #alias fgrep='fgrep --color=auto'
    #alias egrep='egrep --color=auto'
fi

# some more ls aliases
#alias ll='ls -l'
#alias la='ls -A'
#alias l='ls -CF'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

function cs {
	cd $1
	ls
}

alias incognito="set +o history;clear"
alias uncognito="set -o history;clear"

export EDITOR="vim"

stty -ixon

# record terminal sessions
#if [ "$(ps -ocommand= -p $PPID | awk '{print $1}')" != "script" ]; then
#	filename="$(date +"%Y-%m-%d_%H-%M-%S")_$(printf "%05d" ${RANDOM})_shell"
#	script -t 2>$HOME/.shell_logs/$filename.time $HOME/.shell_logs/$filename.script
#	exit
#fi

shopt -s globstar

# ssh-agent configuration
if [[ -z "$(pgrep ssh-agent)" ]]; then
  rm -rf /tmp/ssh-*
  eval $(ssh-agent -s) > /dev/null
else
  export SSH_AGENT_PID=$(pgrep ssh-agent | head -n 1)
  export SSH_AUTH_SOCK=$(find /tmp/ssh-* -name agent.* 2>&1 | grep -v "Permission Denied" | head -n 1)
fi

if [[ ! -z $SSH_AGENT_PID ]]; then ssh-add -L > /dev/null || ssh-add; fi

# TMUX
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
. "$HOME/.cargo/env"
