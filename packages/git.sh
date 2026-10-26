# DESCRIPTION: Short git commands for everyday work
# REQUIRES: git

# `gst` rather than `gs`, which would shadow Ghostscript.
alias gst='git status -sb' # DESC: Short status with branch info
alias gl='git log --oneline --graph --decorate -20' # DESC: Compact graph of the last 20 commits
alias gla='git log --oneline --graph --decorate --all' # DESC: Compact graph of all branches
alias gd='git diff' # DESC: Unstaged changes
alias gds='git diff --staged' # DESC: Staged changes
alias ga='git add' # DESC: Stage files. Usage: ga <path>...
alias gaa='git add -A' # DESC: Stage everything
alias gp='git push' # DESC: Push
alias gpl='git pull --ff-only' # DESC: Pull, fast-forward only
alias gsw='git switch' # DESC: Switch branch
alias gbr='git branch --sort=-committerdate' # DESC: Branches, most recently used first
alias gamend='git commit --amend --no-edit' # DESC: Add staged changes to the last commit
alias gundo='git reset --soft HEAD~1' # DESC: Undo the last commit, keeping changes staged

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
    # DESC: cd to the root of the current git repo
    cd "$(git rev-parse --show-toplevel)" || return
}

gprune() {
    # DESC: Delete local branches already merged into the current one
    git branch --merged | grep -vE '^[*+]|(^|[[:space:]])(main|master|develop)$' | while read -r b; do
        git branch -d "$b"
    done
}
