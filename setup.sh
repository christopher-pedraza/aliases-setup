#!/bin/sh
# aliases-setup: opt-in alias/function packages for bash and zsh.
# Written in POSIX sh on purpose so it behaves the same on Linux, macOS and BSD
# (no arrays, no mapfile, no readlink -f). Run `./setup.sh help` for usage.
set -eu

# ---------------------------------------------------------------- setup

resolve() { # follow symlinks without `readlink -f` (missing on older macOS)
    _p=$1
    while [ -L "$_p" ]; do
        _l=$(readlink "$_p")
        case $_l in
            /*) _p=$_l ;;
            *)  _p=$(dirname "$_p")/$_l ;;
        esac
    done
    printf '%s\n' "$_p"
}

REPO=$(cd "$(dirname "$(resolve "$0")")" && pwd -P)
PKG_DIR="$REPO/packages"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup"
ENABLED="$CONF/enabled"
USER_PKG_DIR="$CONF/packages"       # custom and downloaded packages live here
OS=$(uname -s)
BEGIN='# >>> aliases-setup >>>'
END='# <<< aliases-setup <<<'

YES=0 ALL=0 PURGE=0 NAME_OPT= SHELL_OPT=
WORK=
trap '[ -z "$WORK" ] || rm -rf "$WORK"' EXIT

if [ -t 1 ]; then
    ESC=$(printf '\033')
    C_OK="${ESC}[1;32m" C_WARN="${ESC}[1;33m" C_ERR="${ESC}[1;31m" C_DIM="${ESC}[2m" C_OFF="${ESC}[0m"
else
    C_OK= C_WARN= C_ERR= C_DIM= C_OFF=
fi
info() { printf '%s\n' "$*"; }
ok()   { printf '%s%s%s\n' "$C_OK" "$*" "$C_OFF"; }
warn() { printf '%s%s%s\n' "$C_WARN" "$*" "$C_OFF" >&2; }
die()  { printf '%s%s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }

confirm() { # <prompt>
    if [ "$YES" -eq 1 ]; then return 0; fi
    [ -t 0 ] || die "Not a terminal; re-run with -y to confirm non-interactively."
    printf '%s [y/N] ' "$1"
    read -r _reply || _reply=
    case $_reply in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

valid_name() { # letters, digits, _ and - only
    case $1 in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
}

ensure_work() {
    if [ -z "$WORK" ]; then WORK=$(mktemp -d "${TMPDIR:-/tmp}/aliases-setup.XXXXXX"); fi
}

# ---------------------------------------------------------------- packages

pkg_names() {
    for _f in "$PKG_DIR"/*.sh "$USER_PKG_DIR"/*.sh; do
        if [ -f "$_f" ]; then
            _n=$(basename "$_f" .sh)
            if valid_name "$_n"; then printf '%s\n' "$_n"; fi
        fi
    done | sort -u
}

pkg_file() { # custom packages shadow built-in ones of the same name
    if [ -f "$USER_PKG_DIR/$1.sh" ]; then printf '%s\n' "$USER_PKG_DIR/$1.sh"
    elif [ -f "$PKG_DIR/$1.sh" ]; then printf '%s\n' "$PKG_DIR/$1.sh"
    else return 1
    fi
}

pkg_label() {
    if [ -f "$USER_PKG_DIR/$1.url" ]; then printf ' (downloaded)'
    elif [ -f "$USER_PKG_DIR/$1.sh" ]; then printf ' (custom)'
    fi
}

pkg_meta() { # <pkg> <KEY>
    sed -n "s/^# $2: *//p" "$(pkg_file "$1")" | head -n 1
}

pkg_provides() {
    awk '
        /^[A-Za-z0-9][A-Za-z0-9_-]*\(\) *\{/ { n = $0; sub(/\(\).*/, "", n); print n }
        /^alias /                 { n = $0; sub(/^alias +/, "", n); sub(/=.*/, "", n); print n }
    ' "$(pkg_file "$1")" | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 } END { print "" }'
}

pkg_enabled() { [ -L "$ENABLED/$1.sh" ]; }

pkg_check() { # <pkg>: must exist and parse
    valid_name "$1" || die "Invalid package name: $1"
    _f=$(pkg_file "$1") || die "Unknown package: $1 (see: ./setup.sh list)"
    bash -n "$_f" 2>/dev/null || die "Package '$1' has a syntax error; not enabling it."
}

enable_pkg() { # <pkg>
    _f=$(pkg_file "$1")
    for _req in $(pkg_meta "$1" REQUIRES); do
        command -v "$_req" >/dev/null 2>&1 || warn "Note: '$1' expects '$_req', which isn't installed."
    done
    ln -sfn "$_f" "$ENABLED/$1.sh"
    ok "Enabled $1"
}

# ---------------------------------------------------------------- shells and rc files

rc_zsh() { printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc"; }
rc_bash() {
    if [ "$OS" = Darwin ]; then
        # macOS terminals start login shells, which skip ~/.bashrc.
        for _f in .bash_profile .bash_login .profile; do
            if [ -f "$HOME/$_f" ]; then printf '%s\n' "$HOME/$_f"; return 0; fi
        done
        printf '%s\n' "$HOME/.bash_profile"
    else
        printf '%s\n' "$HOME/.bashrc"
    fi
}

rc_files() { # <bash|zsh|all>: files to manage, one per line
    if [ -n "${ALIASES_SETUP_RC:-}" ]; then printf '%s\n' "$ALIASES_SETUP_RC"; return 0; fi
    case $1 in
        bash) rc_bash ;;
        zsh)  rc_zsh ;;
        all)  rc_bash; rc_zsh ;;
    esac
}

rc_candidates() { # every file we might have edited, for status/uninstall
    [ -z "${ALIASES_SETUP_RC:-}" ] || printf '%s\n' "$ALIASES_SETUP_RC"
    for _f in .bashrc .bash_profile .bash_login .profile; do printf '%s\n' "$HOME/$_f"; done
    rc_zsh
}

detect_shell() {
    case ${SHELL:-} in
        */zsh)  echo zsh ;;
        */bash) echo bash ;;
        *) die "Unsupported login shell '${SHELL:-unknown}'. Use --shell bash|zsh|all." ;;
    esac
}

rc_target() { resolve "$1"; } # edit the real file when the rc is a symlink (dotfile managers)
rc_has_block() { [ -f "$1" ] && grep -qxF "$BEGIN" "$1"; }

rc_add_block() { # <rc file>
    _t=$(rc_target "$1")
    [ -e "$_t" ] || : > "$_t"
    # One-time backup of the original.
    if [ ! -e "$CONF/backup/$(basename "$_t")" ]; then cp -p "$_t" "$CONF/backup/$(basename "$_t")"; fi

    _tmp=$(mktemp "$_t.XXXXXX")
    cp -p "$_t" "$_tmp"          # keeps mode and owner
    {
        cat "$_t"
        if [ -s "$_t" ] && [ -n "$(tail -c1 "$_t")" ]; then echo; fi
        echo
        echo "$BEGIN"
        echo '# Managed by aliases-setup; remove with: ./setup.sh uninstall'
        echo 'if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup/init.sh" ]; then . "${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup/init.sh"; fi'
        echo "$END"
    } > "$_tmp"
    mv "$_tmp" "$_t"
}

rc_remove_block() { # <rc file>
    _t=$(rc_target "$1")
    grep -qxF "$END" "$_t" || die "Found '$BEGIN' in $1 but no end marker; remove the block by hand."
    _tmp=$(mktemp "$_t.XXXXXX")
    cp -p "$_t" "$_tmp"
    awk -v b="$BEGIN" -v e="$END" '
        skip     { if ($0 == e) skip = 0; next }
        $0 == b  { skip = 1; pend = 0; next }   # also drops the blank line added before the block
        pend     { print ""; pend = 0 }
        $0 == "" { pend = 1; next }
        { print }
        END      { if (pend) print "" }
    ' "$_t" > "$_tmp"
    mv "$_tmp" "$_t"
}

bootstrap() { # <bash|zsh|all>: loader + rc blocks, idempotent
    mkdir -p "$ENABLED" "$CONF/backup"
    cp "$REPO/lib/init.sh" "$CONF/init.sh"     # copied, so rc lines survive the repo moving
    printf '%s\n' "$REPO" > "$CONF/repo"
    rc_files "$1" | while read -r _rc; do
        if ! rc_has_block "$_rc"; then
            rc_add_block "$_rc"
            info "Added a managed block to $_rc"
        fi
    done
}

target_shell() {
    if [ -n "$SHELL_OPT" ]; then printf '%s\n' "$SHELL_OPT"; else detect_shell; fi
}

# ---------------------------------------------------------------- downloads

normalize_url() { # turn GitHub "blob" page links into raw file links
    case $1 in
        https://github.com/*/blob/*)
            printf '%s\n' "$1" | sed -e 's#^https://github.com/#https://raw.githubusercontent.com/#' -e 's#/blob/#/#' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

name_from_url() {
    _u=${1%%\?*}; _u=${_u%%#*}; _u=${_u##*/}; _u=${_u%.sh}
    printf '%s' "$_u" | tr -c 'A-Za-z0-9_-' '-'
}

download() { # <url> <out>; https only, including redirects
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --proto-redir '=https' --max-time 30 --max-filesize 262144 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only -T 30 -O "$2" "$1"
    else
        die "Downloading needs curl or wget."
    fi
}

validate_download() { # <file>
    [ -s "$1" ] || { warn "The downloaded file is empty."; return 1; }
    if head -c 512 "$1" | grep -qiE '<(!doctype|html)'; then
        warn "That looks like a web page, not a shell script (use the raw file URL)."; return 1
    fi
    tr -d '\000' < "$1" | cmp -s - "$1" || { warn "The file is binary."; return 1; }
    bash -n "$1" || { warn "Syntax error in the downloaded file."; return 1; }
    if command -v zsh >/dev/null 2>&1; then zsh -n "$1" || { warn "Syntax error (zsh)."; return 1; }; fi
}

fetch_checked() { # <url> <out>
    download "$1" "$2" || { warn "Download failed: $1"; return 1; }
    validate_download "$2"
}

add_url() { # <url>
    case $1 in
        https://*) ;;
        *) die "Only https:// URLs are supported: $1" ;;
    esac
    _url=$(normalize_url "$1")
    _name=${NAME_OPT:-$(name_from_url "$_url")}
    valid_name "$_name" || die "Can't derive a package name from $_url; pass --name <name>."
    [ ! -f "$PKG_DIR/$_name.sh" ] || die "'$_name' is a built-in package name; pass --name <other>."
    if [ -f "$USER_PKG_DIR/$_name.sh" ] && [ ! -f "$USER_PKG_DIR/$_name.url" ]; then
        die "'$_name' is one of your custom packages; pass --name <other>."
    fi

    ensure_work
    fetch_checked "$_url" "$WORK/new.sh" || exit 1
    info "${C_WARN}This code will run in every interactive shell you open. Review it:${C_OFF}"
    info "---------------- $_url ($(wc -l < "$WORK/new.sh" | tr -d ' ') lines)"
    cat "$WORK/new.sh"
    info "----------------"
    if ! confirm "Install and enable '$_name'?"; then info "Aborted."; return 0; fi

    mkdir -p "$USER_PKG_DIR"
    cp "$WORK/new.sh" "$USER_PKG_DIR/$_name.sh"
    printf '%s\n' "$_url" > "$USER_PKG_DIR/$_name.url"
    enable_pkg "$_name"
}

# ---------------------------------------------------------------- commands

reload_hint() { info "${C_DIM}Open a new shell, or run: reloadalias (core package) / exec \$SHELL${C_OFF}"; }

cmd_install() {
    _sh=$(target_shell)
    bootstrap "$_sh"
    ok "Installed the loader for: $_sh"
}

cmd_add() {
    if [ "$ALL" -eq 1 ]; then set -- $(pkg_names); fi
    if [ "$#" -eq 0 ]; then
        [ -t 0 ] || die "No packages given. Usage: ./setup.sh add <package|https-url>... | --all"
        _picks=
        for _p in $(pkg_names); do
            if pkg_enabled "$_p"; then continue; fi
            info ""
            info "${C_OK}$_p${C_OFF}$(pkg_label "$_p"): $(pkg_meta "$_p" DESCRIPTION)"
            info "  provides: $(pkg_provides "$_p")"
            printf '  Enable %s? [y/N] ' "$_p"
            read -r _r || _r=
            case $_r in y|Y) _picks="$_picks $_p" ;; esac
        done
        [ -n "$_picks" ] || { info "Nothing selected."; return 0; }
        set -- $_picks
    fi

    _sh=$(target_shell)
    _names= _urls=
    for _a in "$@"; do
        case $_a in
            http://*|https://*) _urls="$_urls $_a" ;;
            *) pkg_check "$_a"; _names="$_names $_a" ;;
        esac
    done

    bootstrap "$_sh"
    for _p in $_names; do enable_pkg "$_p"; done
    for _u in $_urls; do add_url "$_u"; done
    reload_hint
}

cmd_remove() {
    if [ "$ALL" -eq 1 ]; then set -- $(pkg_names); fi
    [ "$#" -gt 0 ] || die "Usage: ./setup.sh remove <package>... | --all   (--purge also deletes custom/downloaded files)"
    for _p in "$@"; do
        valid_name "$_p" || die "Invalid package name: $_p"
        if [ -L "$ENABLED/$_p.sh" ]; then
            rm "$ENABLED/$_p.sh"
            ok "Disabled $_p"
        elif [ "$ALL" -eq 0 ]; then
            warn "$_p is not enabled."
        fi
        if [ "$PURGE" -eq 1 ] && [ -f "$USER_PKG_DIR/$_p.sh" ]; then
            rm -f "$USER_PKG_DIR/$_p.sh" "$USER_PKG_DIR/$_p.url"
            info "Deleted $USER_PKG_DIR/$_p.sh"
        fi
    done
    info "${C_DIM}Open shells keep old aliases until restarted (or: unalias <name> / unset -f <name>).${C_OFF}"
}

cmd_list() {
    printf '%s%s%s\n' "$C_DIM" "[x] enabled   [ ] available" "$C_OFF"
    for _p in $(pkg_names); do
        if pkg_enabled "$_p"; then _mark="${C_OK}[x]${C_OFF}"; else _mark="[ ]"; fi
        printf '%s %-12s %s%s\n' "$_mark" "$_p" "$(pkg_meta "$_p" DESCRIPTION)" "$(pkg_label "$_p")"
        printf '    %s%s%s\n' "$C_DIM" "$(pkg_provides "$_p")" "$C_OFF"
    done
    for _l in "$ENABLED"/*.sh; do
        if [ -L "$_l" ] && [ ! -e "$_l" ]; then
            warn "[!] $(basename "$_l" .sh): enabled, but its file is gone (fix: ./setup.sh remove $(basename "$_l" .sh))"
        fi
    done
}

cmd_status() {
    if [ -f "$CONF/init.sh" ]; then ok "Loader:  $CONF/init.sh"; else warn "Loader:  not installed"; fi
    _found=0
    for _rc in $(rc_candidates); do
        if rc_has_block "$_rc"; then ok "RC block: $_rc"; _found=1; fi
    done
    if [ "$_found" -eq 0 ]; then warn "RC block: not present in any rc file"; fi
    info "Repo:    $(cat "$CONF/repo" 2>/dev/null || echo '-')"
    if [ -f "$CONF/repo" ] && [ "$(cat "$CONF/repo")" != "$REPO" ]; then
        warn "         (differs from this checkout, $REPO; re-run 'add' to repoint)"
    fi
    info ""
    cmd_list
}

cmd_new() {
    [ "$#" -eq 1 ] || die "Usage: ./setup.sh new <name>"
    valid_name "$1" || die "Invalid package name: $1"
    _t="$USER_PKG_DIR/$1.sh"
    [ ! -e "$_t" ] || die "$_t already exists."
    mkdir -p "$USER_PKG_DIR"
    sed "s/__NAME__/$1/g" "$REPO/template/package.sh" > "$_t"
    ok "Created $_t"
    info "Edit it, then enable it with: ./setup.sh add $1"
    info "(To contribute it to this repo instead, move it into $PKG_DIR/.)"
}

cmd_update() {
    ensure_work
    if [ "$#" -eq 0 ]; then
        set --
        for _u in "$USER_PKG_DIR"/*.url; do
            if [ -f "$_u" ]; then set -- "$@" "$(basename "$_u" .url)"; fi
        done
    fi
    [ "$#" -gt 0 ] || { info "No downloaded packages to update."; return 0; }
    for _p in "$@"; do
        valid_name "$_p" || die "Invalid package name: $_p"
        [ -f "$USER_PKG_DIR/$_p.url" ] || { warn "$_p wasn't downloaded from a URL; skipping."; continue; }
        _url=$(cat "$USER_PKG_DIR/$_p.url")
        if ! fetch_checked "$_url" "$WORK/$_p.sh"; then continue; fi
        if cmp -s "$WORK/$_p.sh" "$USER_PKG_DIR/$_p.sh"; then
            info "$_p is up to date."
            continue
        fi
        info "${C_WARN}Changes to '$_p' from $_url:${C_OFF}"
        diff -u "$USER_PKG_DIR/$_p.sh" "$WORK/$_p.sh" || true
        if confirm "Apply this update to '$_p'?"; then
            cp "$WORK/$_p.sh" "$USER_PKG_DIR/$_p.sh"
            ok "Updated $_p"
        fi
    done
}

cmd_uninstall() {
    _rcs=$(for _rc in $(rc_candidates); do if rc_has_block "$_rc"; then printf '%s\n' "$_rc"; fi; done)
    _custom=$(ls "$USER_PKG_DIR"/*.sh 2>/dev/null | wc -l | tr -d ' ')
    info "This will:"
    if [ -n "$_rcs" ]; then
        printf '%s\n' "$_rcs" | sed 's/^/  - remove the managed block from /'
    fi
    info "  - delete the loader, enabled links and rc backups in $CONF"
    if [ "$PURGE" -eq 1 ]; then
        info "  - ${C_ERR}also delete your $_custom custom/downloaded package(s)${C_OFF}"
    elif [ "$_custom" -gt 0 ]; then
        info "  - keep your $_custom custom/downloaded package(s) in $USER_PKG_DIR (use --purge to delete)"
    fi
    info "Packages in this repo are not touched."
    if ! confirm "Continue?"; then info "Aborted."; return 0; fi

    if [ -n "$_rcs" ]; then
        printf '%s\n' "$_rcs" | while read -r _rc; do
            # Re-check: two paths can be the same file (symlinked rc).
            if rc_has_block "$_rc"; then
                rc_remove_block "$_rc"
                ok "Removed managed block from $_rc"
            fi
        done
    fi
    rm -rf "$ENABLED" "$CONF/init.sh" "$CONF/repo" "$CONF/backup"
    if [ "$PURGE" -eq 1 ] && [ "$(basename "$CONF")" = "aliases-setup" ]; then
        rm -rf "$CONF"
    else
        rmdir "$CONF" 2>/dev/null || true
    fi
    ok "Uninstalled."
    info "${C_DIM}Open shells keep their aliases until restarted (e.g. run: exec \$SHELL).${C_OFF}"
}

usage() {
    cat <<EOF
Usage: ./setup.sh <command> [options]

  list                        Show packages and which are enabled
  add [pkg|url]... | --all    Enable packages; a https URL downloads one (no args: pick interactively)
  remove <pkg>... | --all     Disable packages (--purge also deletes custom/downloaded files)
  update [pkg]...             Re-download packages that came from a URL (shows a diff first)
  new <name>                  Create a custom package from the template
  install                     Install the loader only, without enabling packages
  status                      Show install health
  uninstall                   Remove what this tool added (--purge also deletes custom packages)

Options:
  --shell bash|zsh|all        Which shell's rc file to manage (default: your login shell)
  --name <name>               Package name to use when adding a URL
  -y, --yes                   Don't ask for confirmation

State lives in $CONF (honours XDG_CONFIG_HOME).
Your rc file only ever gets one marked block. Set ALIASES_SETUP_RC to manage a specific file.
EOF
}

main() {
    if [ "$#" -eq 0 ]; then usage; return 0; fi
    _cmd=$1; shift

    _n=$#; _i=0
    while [ "$_i" -lt "$_n" ]; do
        _a=$1; shift; _i=$((_i + 1))
        case $_a in
            -y|--yes) YES=1 ;;
            --all)    ALL=1 ;;
            --purge)  PURGE=1 ;;
            --name|--shell)
                [ "$#" -gt 0 ] || die "$_a needs a value."
                if [ "$_a" = --name ]; then NAME_OPT=$1; else SHELL_OPT=$1; fi
                shift; _i=$((_i + 1)) ;;
            -*) die "Unknown option: $_a (see: ./setup.sh help)" ;;
            *)  set -- "$@" "$_a" ;;
        esac
    done
    case $SHELL_OPT in ''|bash|zsh|all) ;; *) die "--shell must be bash, zsh or all." ;; esac

    case $_cmd in
        list|ls)           cmd_list ;;
        add|enable)        cmd_add "$@" ;;
        remove|rm|disable) cmd_remove "$@" ;;
        update)            cmd_update "$@" ;;
        new)               cmd_new "$@" ;;
        install)           cmd_install ;;
        status)            cmd_status ;;
        uninstall)         cmd_uninstall ;;
        help|-h|--help)    usage ;;
        *)                 usage >&2; exit 1 ;;
    esac
}

main "$@"
