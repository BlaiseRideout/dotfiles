# ~/.profile: environment shared by login shells, the Hyprland session (on
# nhuto-Mint, build/hyprland/hyprland-session reads it, as GDM doesn't) and the
# terminals. .zshrc and .bashrc read it as well when nothing before them did (a
# Sway login, ssh into zsh), so PATH is the same everywhere. Additions are skipped if PATH already
# has them, so reading it twice is harmless.

# Read already: .zshrc and .bashrc skip it. Exported, so terminals and anything
# else started from the session skip it too (they inherit the result).
export DOTFILES_PROFILE=1

# Ubuntu's default: a login bash reads only this file, so pull in .bashrc
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

path_prepend() { case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH" ;; esac; }
path_append()  { case ":$PATH:" in *":$1:"*) ;; *) PATH="$PATH:$1" ;; esac; }

# Own scripts and programs (pipx, the T3 Code and llama launchers, ...)
[ -d "$HOME/bin" ] && path_prepend "$HOME/bin"
[ -d "$HOME/.local/bin" ] && path_prepend "$HOME/.local/bin"

if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
    export RUSTFLAGS="-C target-cpu=native"
fi

if [ -d /usr/local/go ]; then
    export GOROOT=/usr/local/go
elif [ -d /usr/lib/go ]; then
    export GOROOT=/usr/lib/go   # pacman's go
fi
export GOPATH="$HOME/prog/go"
path_append "$GOROOT/bin"
path_append "$GOPATH/bin"

export JAVA_HOME=/opt/jdk
path_prepend "$JAVA_HOME/bin"

export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_NDK_HOME="$HOME/Android/Ndk"
path_append "$ANDROID_HOME/tools"
path_append "$ANDROID_HOME/tools/bin"
path_append "$ANDROID_HOME/platform-tools"
path_append "$ANDROID_NDK_HOME"
path_append "$ANDROID_HOME/build-tools/26.0.1"

path_append /usr/local/lib

export PATH
unset -f path_prepend path_append

# Share the systemd user agent; preserve agents forwarded over SSH.
if [ -z "$SSH_AUTH_SOCK" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
fi
