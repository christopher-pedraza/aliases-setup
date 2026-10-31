# DESCRIPTION: Repeat, retry and wait helpers (a portable watch, and chaining jobs)

every() {
    # DESC: Re-run a command every N seconds, redrawing the screen (like watch). Usage: every <seconds> <command>...
    case "$1" in ''|*[!0-9]*) echo "Usage: every <seconds> <command>..." >&2; return 2 ;; esac
    if [ $# -lt 2 ]; then echo "Usage: every <seconds> <command>..." >&2; return 2; fi
    local n="$1"
    shift
    while :; do
        clear
        printf 'Every %ss: %s    %s\n\n' "$n" "$*" "$(date '+%F %T')"
        "$@"
        sleep "$n" || return 0
    done
}

retry() {
    # DESC: Re-run a command until it succeeds, up to N tries, pausing $RETRY_DELAY (default 3) seconds. Usage: retry <tries> <command>...
    case "$1" in ''|*[!0-9]*|0) echo "Usage: retry <tries> <command>..." >&2; return 2 ;; esac
    if [ $# -lt 2 ]; then echo "Usage: retry <tries> <command>..." >&2; return 2; fi
    local tries="$1" i=1 rc
    shift
    while :; do
        "$@"
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        if [ "$i" -ge "$tries" ]; then
            echo "[retry] giving up after $i tries (exit $rc)" >&2
            return "$rc"
        fi
        echo "[retry] try $i/$tries failed (exit $rc); again in ${RETRY_DELAY:-3}s" >&2
        i=$((i + 1))
        sleep "${RETRY_DELAY:-3}" || return 130
    done
}

after() {
    # DESC: Wait for a process to finish, then run a command. Usage: after <pid> <command>...
    case "$1" in ''|*[!0-9]*) echo "Usage: after <pid> <command>..." >&2; return 2 ;; esac
    if [ $# -lt 2 ]; then echo "Usage: after <pid> <command>..." >&2; return 2; fi
    local pid="$1"
    shift
    if ! ps -p "$pid" >/dev/null 2>&1; then echo "after: no process $pid" >&2; return 1; fi
    echo "[after] waiting for $pid, then: $*" >&2
    while ps -p "$pid" >/dev/null 2>&1; do
        sleep "${AFTER_POLL:-5}" || return 130
    done
    "$@"
}
