# DESCRIPTION: Run heavy commands safely: memory/CPU/time limits, saved output, timing
# REQUIRES: systemd-run
#
# `safe` puts a command in its own systemd scope (systemd-run --user --scope), so a
# runaway job gets killed at its limit instead of freezing the machine or invoking the
# system-wide OOM killer on your desktop. Limits need Linux with a systemd user session;
# elsewhere `safe` refuses to run (use -U for "no limits") but `logrun`, `timed` and
# `alertme` work anywhere.
#
#   safe -m 100G -o audit.log uv run lccd-sft audit --run-id m1-001
#
# Defaults: SAFE_MEM (80% of RAM) and SAFE_SWAP (0, so it can't swap the box to death).

_safe_fmt() { # <seconds>: 75 -> 1m15s
    local s=$1
    if [ "$s" -ge 3600 ]; then printf '%dh%02dm%02ds' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
    elif [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60))
    else printf '%ds' "$s"; fi
}

_safe_launch() { # <command>...: reads mem swap cpu tmo nic limits from the calling safe()
    if [ -n "$nic" ]; then set -- nice -n "$nic" "$@"; fi
    if [ -n "$limits" ]; then
        systemd-run --user --scope --quiet --collect --unit="safe-$$-$RANDOM" \
            -pMemoryMax="$mem" -pMemorySwapMax="$swap" \
            ${cpu:+-pCPUQuota=$cpu} ${tmo:+-pRuntimeMaxSec=$tmo} -- "$@"
    else
        "$@"
    fi
}

safe() {
    # DESC: Run a command with memory/CPU/time limits. Usage: safe [-m MEM] [-c CPUS] [-t TIME] [-o LOG] <command>... (-h for all options)
    local mem="${SAFE_MEM:-80%}" swap="${SAFE_SWAP:-0}" cpu="" tmo="" log="" app="" nic="" limits=1
    local rc t0 banner
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                cat >&2 <<'EOF'
Usage: safe [options] [--] <command> [args...]
  -m MEM    memory limit, e.g. 100G, 8G or 50%   (default: $SAFE_MEM or 80%)
  -s SWAP   swap limit                           (default: $SAFE_SWAP or 0 = no swap)
  -c CPUS   use at most this many cores (whole number)
  -t TIME   stop the command after this long, e.g. 90s, 30m, 2h
  -n        low priority (nice 10), keeps the machine responsive
  -o FILE   also save stdout+stderr to FILE (replaces it); -a appends instead
  -l        like -o, with an automatic name: <command>-<date>-<time>.log
  -U        no limits (just log/time); same as `logrun`
Past the memory limit the kernel kills the job (exit 137). `oomlog` shows why,
`safels` lists running jobs with their memory use. A saved log is piped, so
programs that check for a terminal may turn off colours and progress bars.
EOF
                return 0 ;;
            -m|-s|-c|-t|-o)
                if [ $# -lt 2 ]; then echo "safe: $1 needs a value (safe -h)" >&2; return 2; fi
                case "$1" in
                    -m) mem=$2 ;;
                    -s) swap=$2 ;;
                    -t) tmo=$2 ;;
                    -o) log=$2 ;;
                    -c) case "$2" in ''|*[!0-9]*|0) echo "safe: -c wants a whole number of cores" >&2; return 2 ;; esac
                        cpu="$(($2 * 100))%" ;;
                esac
                shift 2 ;;
            -a) app=1; shift ;;
            -l) log="${log:-auto}"; shift ;;
            -n) nic=10; shift ;;
            -U) limits=""; shift ;;
            --) shift; break ;;
            -*) echo "safe: unknown option $1 (safe -h)" >&2; return 2 ;;
            *) break ;;
        esac
    done
    if [ $# -eq 0 ]; then echo "Usage: safe [options] <command>... (safe -h)" >&2; return 2; fi
    if [ -n "$limits" ] && ! command -v systemd-run >/dev/null 2>&1; then
        echo "safe: systemd-run not found, so limits can't be applied. Use -U (or logrun) to run without them." >&2
        return 1
    fi
    if [ "$log" = auto ]; then
        log="$(printf '%s %s %s' "$1" "${2:-}" "${3:-}" | tr -cs 'A-Za-z0-9' '-' | cut -c1-40 | sed 's/-$//')-$(date +%Y%m%d-%H%M%S).log"
    fi

    if [ -n "$limits" ]; then
        banner="limits: mem=$mem swap=$swap${cpu:+ cpu=$cpu}${tmo:+ time=$tmo}${nic:+ nice=$nic}"
    else
        banner="no limits"
    fi
    banner="$banner${log:+ log=$log}"
    printf '[safe] %s\n' "$banner" >&2

    t0=$SECONDS
    if [ -n "$log" ]; then
        [ -n "$app" ] || : > "$log" || return
        printf '# %s\n# %s\n# %s\n' "$(date '+%F %T')" "$banner" "$*" >> "$log" || return
        ( set -o pipefail; _safe_launch "$@" 2>&1 | tee -i -a "$log" ) # lint:ok
        rc=$?
    else
        _safe_launch "$@"
        rc=$?
    fi

    printf '[safe] exit %s after %s\n' "$rc" "$(_safe_fmt $((SECONDS - t0)))" >&2
    case "$rc" in
        137) [ -n "$limits" ] && echo "[safe] killed (SIGKILL), most likely by the memory limit ($mem). Raise it with -m, or run: oomlog" >&2 ;;
        143) [ -n "$tmo" ] && echo "[safe] stopped by the time limit ($tmo)" >&2 ;;
        130) echo "[safe] interrupted" >&2 ;;
    esac
    [ -n "$log" ] && printf '# exit %s after %s\n' "$rc" "$(_safe_fmt $((SECONDS - t0)))" >> "$log"
    return "$rc"
}

logrun() {
    # DESC: Run a command, show and save its output (stdout+stderr) to a log. Usage: logrun [-o file] [-a] <command>...
    safe -U -l "$@"
}

timed() {
    # DESC: Run a command and report how long it took. Usage: timed <command>...
    if [ $# -eq 0 ]; then echo "Usage: timed <command>..." >&2; return 2; fi
    local t0=$SECONDS rc
    "$@"
    rc=$?
    printf '[timed] exit %s after %s\n' "$rc" "$(_safe_fmt $((SECONDS - t0)))" >&2
    return "$rc"
}

alertme() {
    # DESC: Run a command, then ring the bell and send a desktop notification. Usage: alertme <command>...
    if [ $# -eq 0 ]; then echo "Usage: alertme <command>..." >&2; return 2; fi
    local rc msg
    timed "$@"
    rc=$?
    msg="exit $rc: $*"
    printf '\a'
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Command finished" "$msg"
    elif command -v osascript >/dev/null 2>&1; then
        osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Command finished"' -e 'end run' "$msg"
    fi
    return "$rc"
}

safels() {
    # DESC: List running `safe` jobs with current/peak memory and their limit
    local u any=""
    for u in $(systemctl --user list-units --type=scope --no-legend --plain 'safe-*' 2>/dev/null | awk '{print $1}'); do
        any=1
        systemctl --user show "$u" -p ActiveEnterTimestamp -p MemoryCurrent -p MemoryPeak -p MemoryMax |
            awk -F= -v u="$u" '
                function h(b) { if (b !~ /^[0-9]+$/) return b; return sprintf("%.1fG", b / 1073741824) }
                $1 == "ActiveEnterTimestamp" { since = $2 }
                $1 == "MemoryCurrent" { cur = h($2) }
                $1 == "MemoryPeak" { peak = h($2) }
                $1 == "MemoryMax" { max = ($2 == "infinity" ? $2 : h($2)) }
                END { printf "%s\n  started %s\n  memory now %s, peak %s, limit %s\n", u, since, cur, peak, max }'
    done
    [ -n "$any" ] || echo "No safe jobs running."
}

oomlog() {
    # DESC: Recent kernel out-of-memory kills. Usage: oomlog [since, default "1 day ago"]
    journalctl -k --no-pager --since "${1:-1 day ago}" 2>&1 |
        grep -Ei 'out of memory|oom-kill|killed process|memory cgroup' || echo "No OOM kills found (or no permission: join the systemd-journal group)."
}
