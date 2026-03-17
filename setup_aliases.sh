#!/bin/bash

# Define paths
BASHRC="$HOME/.bashrc"
BASHRC_D="$HOME/.bashrc.d"
ALIAS_FILE="$BASHRC_D/alias"

echo "1. Creating $BASHRC_D directory..."
mkdir -p "$BASHRC_D"

echo "2. Checking if $BASHRC sources $BASHRC_D..."
# If the sourcing logic isn't in .bashrc, append it
if ! grep -q "\.bashrc\.d" "$BASHRC"; then
    cat << 'EOF' >> "$BASHRC"

# Source all files in ~/.bashrc.d/
if [ -d ~/.bashrc.d ]; then
  for file in ~/.bashrc.d/*; do
    [ -f "$file" ] && . "$file"
  done
fi
EOF
    echo "   -> Added sourcing logic to $BASHRC."
else
    echo "   -> Sourcing logic already exists in $BASHRC. Skipping."
fi

echo "3. Creating the alias file at $ALIAS_FILE..."
# Using 'EOF' in quotes prevents the variables (like $1 or $HOME) from being expanded right now
cat << 'EOF' > "$ALIAS_FILE"
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

myhelp() {
    # DESC: Show this help menu
    echo "------------------- CUSTOM COMMANDS -------------------"
    
    # Path to this file
    local ALIAS_FILE="$HOME/.bashrc.d/alias"

    # 1. Get Functions
    grep -E "^[a-z].*\(\) \{" "$ALIAS_FILE" | sed 's/() {//' | while read -r name; do
        desc=$(grep -A 1 "$name()" "$ALIAS_FILE" | grep "# DESC:" | sed 's/.*# DESC: //')
        [ -n "$desc" ] && printf "\033[1;32m%-15s\033[0m %s\n" "$name" "$desc"
    done

    # 2. Get Aliases
    grep "^alias " "$ALIAS_FILE" | while read -r line; do
        name=$(echo "$line" | sed 's/alias //;s/=.*//')
        desc=$(echo "$line" | sed 's/.*# DESC: //')
        [[ "$line" == *"# DESC:"* ]] && printf "\033[1;34m%-15s\033[0m %s\n" "$name" "$desc"
    done
    echo "-------------------------------------------------------"
}

# --- Aliases ---
alias tl='tmux ls' # DESC: List all active tmux sessions
alias tka='tmux kill-server' # DESC: Kill ALL tmux sessions
alias editalias='nano ~/.bashrc.d/alias' # DESC: Edit these shortcuts
alias reloadalias='source ~/.bashrc' # DESC: Reload changes
EOF

echo "4. Reloading the shell environment..."
# Replace the currently running script shell with a fresh interactive bash shell 
# so the aliases are immediately available.
exec bash
