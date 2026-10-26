# DESCRIPTION: Python, pip and virtualenv shortcuts
# REQUIRES: python3

alias py='python3' # DESC: python3
alias pipi='python3 -m pip install' # DESC: pip install into the active environment
alias pir='python3 -m pip install -r requirements.txt' # DESC: Install requirements.txt
alias pipfz='python3 -m pip freeze' # DESC: List installed packages (pip freeze)

venv() {
    # DESC: Create (if missing) and activate ./.venv. Usage: venv [dir]
    local dir="${1:-.venv}"
    if [ ! -d "$dir" ]; then python3 -m venv "$dir" || return; fi
    . "$dir/bin/activate"
}
