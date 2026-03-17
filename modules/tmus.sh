# --- Functions ---

tn() {
    # DESC: New tmux session. Usage: tn <name>
    if [ -z "$1" ]; then tmux new-session; else tmux new-session -s "$1"; fi
}

ta() {
    # DESC: Attach to tmux. Usage: ta <name> (or last)
    if [ -z "$1" ]; then tmux attach-session; else tmux attach-session -t "$1"; fi
}

tk() {
    # DESC: Kill tmux session. Usage: tk <name>
    if [ -z "$1" ]; then echo "Provide name"; else tmux kill-session -t "$1"; fi
}

# --- Aliases ---
alias tl='tmux ls' # DESC: List all active tmux sessions
alias tka='tmux kill-server' # DESC: Kill ALL tmux sessions
