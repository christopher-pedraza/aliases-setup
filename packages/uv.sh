# DESCRIPTION: uv (fast Python package and project manager) shortcuts
# REQUIRES: uv

alias uvs='uv sync' # DESC: Install the project's dependencies (uv sync)
alias uvr='uv run' # DESC: Run a command in the project environment. Usage: uvr <command>
alias uva='uv add' # DESC: Add a dependency. Usage: uva <package>...
alias uvrm='uv remove' # DESC: Remove a dependency. Usage: uvrm <package>...
alias uvl='uv lock' # DESC: Update the lockfile
alias uvtree='uv tree' # DESC: Show the dependency tree
alias uvpi='uv pip install' # DESC: pip-style install into the active environment
alias uvti='uv tool install' # DESC: Install a Python command-line tool. Usage: uvti <tool>
alias uvtl='uv tool list' # DESC: List installed tools
alias uvpl='uv python list' # DESC: List available Python versions

uvnew() {
    # DESC: Create a new project and cd into it. Usage: uvnew <name>
    if [ -z "$1" ]; then echo "Usage: uvnew <name>" >&2; return 1; fi
    uv init "$1" && cd "$1" || return
}

uvenv() {
    # DESC: Create (if missing) and activate a venv with uv. Usage: uvenv [dir]
    local dir="${1:-.venv}"
    if [ ! -d "$dir" ]; then uv venv "$dir" || return; fi
    . "$dir/bin/activate"
}

uvup() {
    # DESC: Upgrade every dependency in the lockfile and re-sync
    uv lock --upgrade && uv sync
}
