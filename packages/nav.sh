# DESCRIPTION: Directory navigation and nicer ls (GNU and BSD/macOS)

# GNU ls colours with --color, BSD/macOS ls with -G.
_nav_color=-G
if ls --color=auto / >/dev/null 2>&1; then _nav_color=--color=auto; fi
alias ls="ls $_nav_color" # DESC: ls with colours
unset _nav_color

alias ll='ls -lh' # DESC: Long listing
alias la='ls -lAh' # DESC: Long listing including hidden files
alias ..='cd ..' # DESC: Up one directory
alias ...='cd ../..' # DESC: Up two directories
alias ....='cd ../../..' # DESC: Up three directories

mkcd() {
    # DESC: Make a directory and cd into it. Usage: mkcd <dir>
    if [ -z "$1" ]; then echo "Usage: mkcd <dir>" >&2; return 1; fi
    mkdir -p -- "$1" && cd -- "$1" || return
}

up() {
    # DESC: Go up N directories. Usage: up [N]
    local n="${1:-1}" p=""
    case $n in ''|*[!0-9]*) echo "Usage: up [N]" >&2; return 1 ;; esac
    while [ "$n" -gt 0 ]; do p="../$p"; n=$((n - 1)); done
    cd "${p:-.}" || return
}
