# aliases-setup loader. Installed by setup.sh and sourced from your rc file.
# Safe to edit or delete; `setup.sh uninstall` removes it.

# Only load in interactive shells (aliases are useless elsewhere, and this
# keeps scp/rsync/ssh-command sessions untouched).
case $- in *i*) ;; *) return 0 ;; esac

_as_home="${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup"

# Dangling symlinks (package removed or repo moved) fail the -r test and are
# skipped silently, so a stale entry can never break shell startup.
for _as_pkg in "$_as_home"/enabled/*.sh; do
    [ -r "$_as_pkg" ] && . "$_as_pkg"
done

# Convenience wrapper: `aliases-setup list|add|remove|...`
aliases-setup() {
    local repo
    repo=$(cat "$_as_home/repo" 2>/dev/null)
    if [ -x "$repo/setup.sh" ]; then
        "$repo/setup.sh" "$@"
    else
        echo "aliases-setup: repository not found (was it moved?). Re-run setup.sh from its new location." >&2
        return 1
    fi
}

unset _as_pkg
