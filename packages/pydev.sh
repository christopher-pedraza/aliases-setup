# DESCRIPTION: Python dev loop: pytest shortcuts (uv-aware), profiling with py-spy, cache cleanup
# REQUIRES: python3

_py_run() { # <module> [args...]: through uv in a uv project (has uv.lock), else python3 -m
    if [ -f uv.lock ] && command -v uv >/dev/null 2>&1; then
        uv run python -m "$@"
    else
        python3 -m "$@"
    fi
}

pt() {
    # DESC: Run pytest, quiet. Usage: pt [pytest args]
    _py_run pytest -q "$@"
}

ptf() {
    # DESC: Re-run only the tests that failed last time, stop at the first failure
    _py_run pytest -q --lf -x "$@"
}

ptk() {
    # DESC: Run tests whose name matches an expression. Usage: ptk <expr> [pytest args]
    if [ -z "$1" ]; then echo "Usage: ptk <expr> [pytest args]" >&2; return 2; fi
    local expr="$1"
    shift
    _py_run pytest -q -k "$expr" "$@"
}

ptd() {
    # DESC: Stop at the first failure and drop into the debugger (pdb)
    _py_run pytest -x --pdb "$@"
}

ptc() {
    # DESC: Run pytest with a coverage report (needs pytest-cov)
    _py_run pytest -q --cov --cov-report=term-missing "$@"
}

pyprof() {
    # DESC: Profile a command into a flamegraph profile-<time>.svg (py-spy; may need sudo). Usage: pyprof python3 script.py
    if [ $# -eq 0 ]; then echo "Usage: pyprof <command>..." >&2; return 2; fi
    if ! command -v py-spy >/dev/null 2>&1; then echo "pyprof: py-spy not found (uv tool install py-spy)" >&2; return 1; fi
    py-spy record -o "profile-$(date +%Y%m%d-%H%M%S).svg" -- "$@"
}

pytop() {
    # DESC: Live view of where a running Python process spends time (py-spy; may need sudo). Usage: pytop <pid>
    if [ -z "$1" ]; then echo "Usage: pytop <pid>" >&2; return 2; fi
    if ! command -v py-spy >/dev/null 2>&1; then echo "pytop: py-spy not found (uv tool install py-spy)" >&2; return 1; fi
    py-spy top --pid "$1"
}

_py_caches() { # <find action...>: cache directories under ., skipping .git, venvs and node_modules
    find . \( -name .git -o -name .venv -o -name venv -o -name node_modules \) -prune -o \
        -type d \( -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache -o -name .ruff_cache \) -prune "$@"
}

pyclean() {
    # DESC: Delete __pycache__, .pytest_cache, .mypy_cache and .ruff_cache under the current directory
    local n
    n=$(_py_caches -print | wc -l | tr -d ' ')
    _py_caches -exec rm -rf {} +
    echo "Removed $n cache director$([ "$n" = 1 ] && echo y || echo ies)"
}
