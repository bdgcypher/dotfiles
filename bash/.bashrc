#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Aliases for common commands
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Aliases for tty applications
alias clocktemp='clocktemp -s false -tu f -lat 37.6774 -lon 113.0618 -c green' # Clock TUI with time, date, temp, calendar, timer, etc...

PS1='[\u@\h \W]\$ '

function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd <"$tmp"
  [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

# Set Neovim as default editor
export EDITOR=nvim

# Import theme colors
(cat ~/.cache/wal/sequences &)
source ~/.cache/wal/colors-tty.sh

# Always start at home directory
cd ~

# Initialize starship prompt
eval "$(starship init bash)"

# Path
export PATH="$HOME/.local/bin:$PATH"
