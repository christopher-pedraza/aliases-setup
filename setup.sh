#!/usr/bin/env bash
# aliases-setup: opt-in alias/function packages for bash.
# See README.md for the design; run `./setup.sh help` for usage.
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
PKG_DIR="$REPO/packages"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup"
ENABLED="$CONF/enabled"
RC="${ALIASES_SETUP_RC:-$HOME/.bashrc}"
BEGIN='# >>> aliases-setup >>>'
END='# <<< aliases-setup <<<'

if [ -t 1 ]; then
    C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_OK=; C_WARN=; C_ERR=; C_DIM=; C_OFF=
fi
info() { printf '%s\n' "$*"; }
ok()   { printf '%s%s%s\n' "$C_OK" "$*" "$C_OFF"; }
warn() { printf '%s%s%s\n' "$C_WARN" "$*" "$C_OFF" >&2; }
die()  { printf '%s%s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }

# ---------------------------------------------------------------- packages

pkg_names() {
    local f
    for f in "$PKG_DIR"/*.sh; do
        [ -e "$f" ] && basename "$f" .sh
    done
    return 0
}

pkg_meta() { # <pkg> <KEY>
    sed -n "s/^# $2: *//p" "$PKG_DIR/$1.sh" | head -n 1
}

pkg_provides() {
    awk '
        /^[A-Za-z0-9_-]+\(\) *\{/ { n = $0; sub(/\(\).*/, "", n); print n }
        /^alias /                 { n = $0; sub(/^alias +/, "", n); sub(/=.*/, "", n); print n }
    ' "$PKG_DIR/$1.sh" | paste -sd, - | sed 's/,/, /g'
}

pkg_enabled() { [ -L "$ENABLED/$1.sh" ]; }

pkg_check() { # <pkg>; exits on unknown/broken packages
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || die "Invalid package name: $1"
    [ -f "$PKG_DIR/$1.sh" ] || die "Unknown package: $1 (see: ./setup.sh list)"
    bash -n "$PKG_DIR/$1.sh" 2>/dev/null || die "Package '$1' has a syntax error; not enabling it."
}

# ---------------------------------------------------------------- rc file

rc_target() { readlink -f "$RC" 2>/dev/null || printf '%s' "$RC"; }   # follow dotfile-manager symlinks
rc_has_block() { [ -f "$RC" ] && grep -qxF "$BEGIN" "$RC"; }

rc_add_block() {
    local target tmp
    target=$(rc_target)
    [ -e "$target" ] || : > "$target"
    # One-time backup of the original, kept alongside our other state.
    [ -e "$CONF/rc.backup" ] || cp -p "$target" "$CONF/rc.backup"

    tmp=$(mktemp "$target.XXXXXX")
    cp -p "$target" "$tmp"   # keep mode/owner
    {
        cat "$target"
        [ -s "$target" ] && [ -n "$(tail -c1 "$target")" ] && echo
        echo
        echo "$BEGIN"
        echo '# Managed by aliases-setup. Remove with: ./setup.sh uninstall'
        # shellcheck disable=SC2016  # expanded by the user's shell, not now
        echo '[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup/init.sh" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup/init.sh"'
        echo "$END"
    } > "$tmp"
    mv "$tmp" "$target"
}

rc_remove_block() {
    local target tmp
    target=$(rc_target)
    grep -qxF "$END" "$target" || die "Found '$BEGIN' in $RC but no matching end marker; remove the block by hand."
    tmp=$(mktemp "$target.XXXXXX")
    cp -p "$target" "$tmp"
    awk -v b="$BEGIN" -v e="$END" '
        skip           { if ($0 == e) skip = 0; next }
        $0 == b        { skip = 1; pend = 0; next }   # also drops the blank line we added before it
        pend           { print ""; pend = 0 }
        $0 == ""       { pend = 1; next }
        { print }
        END            { if (pend) print "" }
    ' "$target" > "$tmp"
    mv "$tmp" "$target"
}

bootstrap() {
    mkdir -p "$ENABLED"
    cp "$REPO/lib/init.sh" "$CONF/init.sh"      # copied, so the rc line survives the repo moving
    printf '%s\n' "$REPO" > "$CONF/repo"
    if ! rc_has_block; then
        rc_add_block
        info "Added a managed block to $RC (backup: $CONF/rc.backup)"
    fi
}

# ---------------------------------------------------------------- commands

reload_hint() { info "${C_DIM}Open a new shell, or run: source $RC${C_OFF}"; }

cmd_add() {
    local pkgs=("$@") p reply
    if [ "${#pkgs[@]}" -eq 1 ] && [ "${pkgs[0]}" = "--all" ]; then
        mapfile -t pkgs < <(pkg_names)
    elif [ "${#pkgs[@]}" -eq 0 ]; then
        [ -t 0 ] || die "No packages given. Usage: ./setup.sh add <package>... | --all"
        while read -r p; do
            pkg_enabled "$p" && continue
            info ""
            info "${C_OK}$p${C_OFF}: $(pkg_meta "$p" DESCRIPTION)"
            info "  provides: $(pkg_provides "$p")"
            read -r -p "  Enable $p? [y/N] " reply
            case "$reply" in y|Y) pkgs+=("$p") ;; esac
        done < <(pkg_names)
        [ "${#pkgs[@]}" -gt 0 ] || { info "Nothing selected."; return 0; }
    fi

    for p in "${pkgs[@]}"; do pkg_check "$p"; done
    bootstrap
    for p in "${pkgs[@]}"; do
        local req
        for req in $(pkg_meta "$p" REQUIRES); do
            command -v "$req" >/dev/null 2>&1 || warn "Note: '$p' expects '$req', which isn't installed."
        done
        ln -sfn "$PKG_DIR/$p.sh" "$ENABLED/$p.sh"
        ok "Enabled $p"
    done
    reload_hint
}

cmd_remove() {
    [ "$#" -gt 0 ] || die "Usage: ./setup.sh remove <package>..."
    local p
    for p in "$@"; do
        [[ "$p" =~ ^[A-Za-z0-9_-]+$ ]] || die "Invalid package name: $p"
        if [ -L "$ENABLED/$p.sh" ]; then
            rm "$ENABLED/$p.sh"
            ok "Disabled $p"
        else
            warn "$p is not enabled."
        fi
    done
    info "${C_DIM}Already-open shells keep the old aliases until restarted (or run: unalias <name> / unset -f <name>).${C_OFF}"
}

cmd_list() {
    local p mark
    printf '%s%s%s\n' "$C_DIM" "[x] enabled   [ ] available" "$C_OFF"
    while read -r p; do
        if pkg_enabled "$p"; then mark="${C_OK}[x]${C_OFF}"; else mark="[ ]"; fi
        printf '%s %-12s %s\n' "$mark" "$p" "$(pkg_meta "$p" DESCRIPTION)"
        printf '    %s%s%s\n' "$C_DIM" "$(pkg_provides "$p")" "$C_OFF"
    done < <(pkg_names)
    local l
    for l in "$ENABLED"/*.sh; do
        [ -L "$l" ] && [ ! -e "$l" ] && warn "[!] $(basename "$l" .sh): enabled, but its package file is gone (fix: ./setup.sh remove $(basename "$l" .sh))"
    done
    return 0
}

cmd_status() {
    [ -f "$CONF/init.sh" ] && ok "Loader:    $CONF/init.sh" || warn "Loader:    not installed"
    rc_has_block && ok "RC block:  present in $RC" || warn "RC block:  not present in $RC"
    info "Repo:      $(cat "$CONF/repo" 2>/dev/null || echo '-')"
    [ ! -f "$CONF/repo" ] || [ "$(cat "$CONF/repo")" = "$REPO" ] || warn "           (differs from this checkout: $REPO; re-run 'add' to repoint)"
    echo
    cmd_list
}

cmd_uninstall() {
    local assume_yes=0
    [ "${1:-}" = "-y" ] && assume_yes=1
    if [ "$assume_yes" -eq 0 ]; then
        info "This will remove the managed block from $RC and delete $CONF."
        info "Your package files in $PKG_DIR are not touched."
        read -r -p "Continue? [y/N] " reply
        case "$reply" in y|Y) ;; *) info "Aborted."; return 0 ;; esac
    fi
    if rc_has_block; then rc_remove_block; ok "Removed managed block from $RC"; fi
    if [ -d "$CONF" ] && [ "$(basename "$CONF")" = "aliases-setup" ]; then
        rm -rf "$CONF"
        ok "Removed $CONF"
    fi
    info "${C_DIM}Open shells keep their aliases until restarted (e.g. run: exec bash).${C_OFF}"
}

usage() {
    cat <<EOF
Usage: ./setup.sh <command> [args]

  list                  Show available packages and which are enabled
  add [pkg... | --all]  Enable packages (no args: choose interactively)
  remove <pkg>...       Disable packages
  status                Show install health
  uninstall [-y]        Remove everything this tool added to your system

State lives in $CONF (honours XDG_CONFIG_HOME).
The only change to your rc file is one marked block; set ALIASES_SETUP_RC to
target a different file than ~/.bashrc.
EOF
}

main() {
    local cmd="${1:-help}"
    [ "$#" -gt 0 ] && shift
    case "$cmd" in
        list|ls)        cmd_list ;;
        add|enable)     cmd_add "$@" ;;
        remove|rm|disable) cmd_remove "$@" ;;
        status)         cmd_status ;;
        uninstall)      cmd_uninstall "$@" ;;
        help|-h|--help) usage ;;
        *)              usage >&2; exit 1 ;;
    esac
}

main "$@"
