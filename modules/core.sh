# --- Functions ---

myhelp() {
    # DESC: Show this categorized help menu dynamically
    echo "=================== CUSTOM COMMANDS ==================="
    
    for file in ~/.bashrc.d/*.sh; do
        [ -f "$file" ] || continue
        
        # Format module name (e.g., tmux.sh -> Tmux)
        filename=$(basename "$file")
        mod_name="${filename%.sh}"
        mod_name="$(tr '[:lower:]' '[:upper:]' <<< ${mod_name:0:1})${mod_name:1}"
        
        echo ""
        echo -e "\033[1;36m--- $mod_name ---\033[0m"
        
        # 1. Get Functions
        grep -E "^[a-zA-Z0-9_-]+\(\) \{" "$file" | sed 's/() {//' | while read -r name; do
            desc=$(grep -A 1 "$name()" "$file" | grep "# DESC:" | sed 's/.*# DESC: //')
            [ -n "$desc" ] && printf "  \033[1;32m%-15s\033[0m %s\n" "$name" "$desc"
        done

        # 2. Get Aliases
        grep "^alias " "$file" | while read -r line; do
            name=$(echo "$line" | sed 's/alias //;s/=.*//')
            desc=$(echo "$line" | sed 's/.*# DESC: //')
            [[ "$line" == *"# DESC:"* ]] && printf "  \033[1;34m%-15s\033[0m %s\n" "$name" "$desc"
        done
    done
    echo ""
    echo "======================================================="
}

# --- Aliases ---
alias editalias='nano ~/.bashrc.d/' # DESC: Open the bashrc.d folder to edit files
alias reloadalias='source ~/.bashrc' # DESC: Reload changes
