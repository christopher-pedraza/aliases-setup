# DESCRIPTION: Help menu and shortcuts for managing your aliases

myhelp() {
    # DESC: Show all commands from enabled packages
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup/enabled" f
    echo "=================== CUSTOM COMMANDS ==================="
    for f in "$dir"/*.sh; do
        [ -r "$f" ] || continue
        awk -v mod="$(basename "$f" .sh)" '
            function emit(color, name, desc) {
                if (!shown++) printf "\n\033[1;36m--- %s ---\033[0m\n", toupper(substr(mod,1,1)) substr(mod,2)
                printf "  \033[%sm%-15s\033[0m %s\n", color, name, desc
            }
            fname != "" && /# DESC:/ { sub(/.*# DESC: */, ""); emit("1;32", fname, $0); fname = ""; next }
            { fname = "" }
            /^[A-Za-z0-9_-]+\(\) *\{/ { fname = $0; sub(/\(\).*/, "", fname); next }
            /^alias .*# DESC:/ {
                name = $0; sub(/^alias +/, "", name); sub(/=.*/, "", name)
                desc = $0; sub(/.*# DESC: */, "", desc)
                emit("1;34", name, desc)
            }
        ' "$f"
    done
    echo ""
    echo "======================================================="
}

alias reloadalias='source ~/.bashrc' # DESC: Reload your shell config
