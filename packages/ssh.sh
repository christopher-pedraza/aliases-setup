# DESCRIPTION: SSH helpers: tmux sessions on remote hosts, port forwarding, keys, host list
# REQUIRES: ssh

sshtmux() {
    # DESC: SSH to a host and attach to (or create) a tmux session that survives disconnects. Usage: sshtmux <host> [session]
    if [ -z "$1" ]; then echo "Usage: sshtmux <host> [session]" >&2; return 2; fi
    local host="$1" name="${2:-main}"
    case "$name" in *[!A-Za-z0-9._-]*) echo "sshtmux: session name may only use letters, digits, . _ -" >&2; return 2 ;; esac
    ssh -t "$host" "tmux new-session -A -s $name"
}

sshtun() {
    # DESC: Forward a remote port to this machine, e.g. Jupyter. Usage: sshtun <local_port> <host> [remote_port] [remote_host]
    case "$1" in ''|*[!0-9]*) echo "Usage: sshtun <local_port> <host> [remote_port] [remote_host]" >&2; return 2 ;; esac
    if [ -z "$2" ]; then echo "Usage: sshtun <local_port> <host> [remote_port] [remote_host]" >&2; return 2; fi
    local rport="${3:-$1}" rhost="${4:-localhost}"
    printf 'http://localhost:%s -> %s:%s via %s   (Ctrl-C to stop)\n' "$1" "$rhost" "$rport" "$2" >&2
    ssh -N -o ExitOnForwardFailure=yes -L "$1:$rhost:$rport" "$2"
}

sshhosts() {
    # DESC: List the hosts defined in ~/.ssh/config
    awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i }' "$HOME/.ssh/config" 2>/dev/null | sort
}

sshkeys() {
    # DESC: Keys loaded in the ssh-agent, and the public keys in ~/.ssh
    local f
    echo "--- loaded in the agent ---"
    ssh-add -l 2>&1
    echo "--- ~/.ssh/*.pub ---"
    for f in "$HOME"/.ssh/*.pub; do
        [ -e "$f" ] && ssh-keygen -lf "$f"
    done
}

sshgen() {
    # DESC: Create a new ed25519 key in ~/.ssh and print the public half. Usage: sshgen [name]
    local name="${1:-id_ed25519}" f
    f="$HOME/.ssh/$name"
    if [ -e "$f" ]; then echo "sshgen: $f already exists" >&2; return 1; fi
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$f" -C "$(id -un)@$(hostname)" || return
    echo "Public key ($f.pub):"
    cat "$f.pub"
}
