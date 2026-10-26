# DESCRIPTION: Disk, memory and process helpers (Linux and macOS)

alias df='df -h' # DESC: Human-readable disk free
alias du='du -h' # DESC: Human-readable disk usage

psg() {
    # DESC: Search running processes. Usage: psg <pattern>
    if [ -z "$1" ]; then echo "Usage: psg <pattern>" >&2; return 1; fi
    ps aux | grep -i -- "$1" | grep -v "grep -i"
}

memtop() {
    # DESC: Top 10 processes by memory
    printf '%7s %5s %5s %s\n' PID %CPU %MEM COMMAND
    ps -Ao pid,pcpu,pmem,comm | sort -k3 -nr | head -n 10
}

cputop() {
    # DESC: Top 10 processes by CPU
    printf '%7s %5s %5s %s\n' PID %CPU %MEM COMMAND
    ps -Ao pid,pcpu,pmem,comm | sort -k2 -nr | head -n 10
}

meminfo() {
    # DESC: Show memory usage
    if command -v free >/dev/null 2>&1; then
        free -h
    else
        vm_stat
    fi
}

diskhog() {
    # DESC: Largest items in a directory. Usage: diskhog [dir]
    find "${1:-.}" -mindepth 1 -maxdepth 1 -exec du -sh {} + 2>/dev/null | sort -rh | head -n 15
}
