# aliases-setup loader, sourced from your rc file (bash and zsh).
# Installed by setup.sh; safe to edit or delete. `setup.sh uninstall` removes it.

# Interactive shells only: aliases are useless elsewhere, and this leaves
# scp/rsync/ssh-command sessions untouched.
case $- in *i*) ;; *) return 0 ;; esac

_as_home="${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup"

_as_load() {
    # zsh aborts on a glob with no match; bash just keeps the pattern literal.
    if [ -n "${ZSH_VERSION-}" ]; then setopt localoptions nullglob; fi
    for _as_pkg in "$_as_home"/enabled/*.sh; do
        # Dangling symlinks (package deleted, repo moved) fail -r and are
        # skipped, so a stale entry can never break shell startup.
        if [ -r "$_as_pkg" ]; then . "$_as_pkg"; fi
    done
}
_as_load
unset -f _as_load
unset _as_pkg

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
