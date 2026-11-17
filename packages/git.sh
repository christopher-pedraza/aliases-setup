# DESCRIPTION: Short git commands for everyday work
# REQUIRES: git

# `gst` rather than `gs`, which would shadow Ghostscript.
alias gst='git status -sb' # DESC: [cyan] Short status with branch info
alias gl='git log --oneline --graph --decorate -20' # DESC: [cyan] Compact graph of the last 20 commits
alias gla='git log --oneline --graph --decorate --all' # DESC: [cyan] Compact graph of all branches
alias gd='git diff' # DESC: [cyan] Unstaged changes
alias gds='git diff --staged' # DESC: [cyan] Staged changes
alias ga='git add' # DESC: Stage files. Usage: ga <path>...
alias gaa='git add -A' # DESC: Stage everything
alias gp='git push' # DESC: Push
alias gpl='git pull --ff-only' # DESC: Pull, fast-forward only
alias gsw='git switch' # DESC: Switch branch
alias gbr='git branch --sort=-committerdate' # DESC: [cyan] Branches, most recently used first
alias gamend='git commit --amend --no-edit' # DESC: [yellow] Add staged changes to the last commit
alias gundo='git reset --soft HEAD~1' # DESC: [yellow] Undo the last commit, keeping changes staged

gcm() {
    # DESC: Commit with a message. Usage: gcm <message...>
    if [ "$#" -eq 0 ]; then echo "Usage: gcm <message>" >&2; return 1; fi
    git commit -m "$*"
}

gcb() {
    # DESC: Create and switch to a branch. Usage: gcb <name>
    if [ -z "$1" ]; then echo "Usage: gcb <branch>" >&2; return 1; fi
    git switch -c "$1"
}

groot() {
    # DESC: [cyan] cd to the root of the current git repo
    cd "$(git rev-parse --show-toplevel)" || return
}

gprune() {
    # DESC: [yellow] Delete local branches already merged into the current one
    git branch --merged | grep -vE '^[*+]|(^|[[:space:]])(main|master|develop)$' | while read -r b; do
        git branch -d "$b"
    done
}

guser() {
    # DESC: Show or configure git user.name and user.email (default --global). Usage: guser [--local|--global] [<name> <email>]
    local scope="" name email label
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -l|--local)  scope="--local"; shift ;;
            -g|--global) scope="--global"; shift ;;
            -h|--help)
                echo "Usage: guser [--local|--global] [<name> <email>]"
                return 0
                ;;
            --) shift; break ;;
            -*)
                echo "guser: unknown option '$1'" >&2
                echo "Usage: guser [--local|--global] [<name> <email>]" >&2
                return 1
                ;;
            *) break ;;
        esac
    done
    if [ "$#" -eq 0 ]; then
        if [ -n "$scope" ]; then
            name=$(git config "$scope" user.name 2>/dev/null) || name=""
            email=$(git config "$scope" user.email 2>/dev/null) || email=""
            label=" (${scope#--})"
        else
            name=$(git config user.name 2>/dev/null) || name=""
            email=$(git config user.email 2>/dev/null) || email=""
            label=""
        fi
        printf 'user.name%s:  %s\n' "$label" "${name:-(not set)}"
        printf 'user.email%s: %s\n' "$label" "${email:-(not set)}"
        return 0
    fi
    if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: guser [--local|--global] [<name> <email>]" >&2
        return 1
    fi
    scope="${scope:---global}"
    git config "$scope" user.name "$1" && git config "$scope" user.email "$2" || return
    printf 'Set %s git identity: %s <%s>\n' "${scope#--}" "$1" "$2"
}
