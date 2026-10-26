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

YES=0 ALL=0 PURGE=0 LOAD=0 NAME_OPT= SHELL_OPT=
CHK_N=0 CHK_FAIL=0 CHK_ERR=0 CHK_WARN=0 ISSUES=
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
    run_check "$_f" "$1" 1 || die "Package '$1' failed its checks; not enabling it (see above)."
}

enable_pkg() { # <pkg>
    _f=$(pkg_file "$1")
    for _req in $(pkg_meta "$1" REQUIRES); do
        command -v "$_req" >/dev/null 2>&1 || warn "Note: '$1' expects '$_req', which isn't installed."
    done
    ln -sfn "$_f" "$ENABLED/$1.sh"
    ok "Enabled $1"
}

# ---------------------------------------------------------------- checks
# Static by default: nothing is executed, so it is safe on untrusted files.

issue_e() { ISSUES="${ISSUES}E $1
"; CHK_ERR=$((CHK_ERR + 1)); }
issue_w() { ISSUES="${ISSUES}W $1
"; CHK_WARN=$((CHK_WARN + 1)); }

lint() { # <regex> <message>; comment lines and lines tagged "lint:ok" are exempt
    _hits=$(grep -nE "$1" "$_cf" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v 'lint:ok' | cut -d: -f1 | tr '\n' ',' | sed 's/,$//' || true)
    if [ -n "$_hits" ]; then issue_w "line $_hits: $2"; fi
}

check_syntax() { # <file> <shell> [flag]
    command -v "$2" >/dev/null 2>&1 || return 0
    _out=$("$2" ${3:--n} "$1" 2>&1) || issue_e "$2 syntax error: $(printf '%s' "$_out" | head -n 2 | tr '\n' ' ')"
}

check_load() { # executes the file in a throwaway HOME; it must be silent and succeed
    _lh=$(mktemp -d "${TMPDIR:-/tmp}/aliases-setup-load.XXXXXX")
    for _sh in bash zsh; do
        command -v "$_sh" >/dev/null 2>&1 || continue
        case $_sh in bash) _opt=--norc ;; *) _opt=-f ;; esac
        _rc=0
        _out=$(HOME=$_lh XDG_CONFIG_HOME=$_lh/.config "$_sh" "$_opt" -c '. "$1"' _ "$_cf" 2>&1 </dev/null) || _rc=$?
        if [ "$_rc" -ne 0 ]; then issue_e "loading in $_sh failed (exit $_rc): $(printf '%s' "$_out" | head -n 1)"
        elif [ -n "$_out" ]; then issue_e "loading in $_sh printed output: $(printf '%s' "$_out" | head -n 1)"
        fi
    done
    rm -rf "$_lh"
}

check_file() { # <file>: fills ISSUES and the error/warning counters
    _cf=$1
    if [ ! -s "$_cf" ]; then issue_e "file is empty"; return 0; fi
    if head -c 512 "$_cf" | grep -qiE '<(!doctype|html)'; then
        issue_e "looks like a web page, not a shell script (use the raw file URL)"; return 0
    fi
    if ! tr -d '\000' < "$_cf" | cmp -s - "$_cf"; then issue_e "file is binary"; return 0; fi

    check_syntax "$_cf" bash
    check_syntax "$_cf" zsh

    # Things that would damage the user's shell when sourced.
    _hits=$(grep -nE '^exit([[:space:]]|$)' "$_cf" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//' || true)
    [ -z "$_hits" ] || issue_e "line $_hits: top-level 'exit' would close the user's shell"
    _hits=$(grep -nE '^set[[:space:]]+(-[A-Za-z]*[eu]|-o)' "$_cf" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//' || true)
    [ -z "$_hits" ] || issue_e "line $_hits: top-level 'set -e/-u/-o' would change the user's shell options"

    # Portability between Linux/macOS and bash/zsh.
    lint '(^|[^[:alnum:]_])echo +-e' "echo -e is not portable; use printf"
    lint 'read( +-[A-Za-z]+)* +-[A-Za-z]*p' "read -p is bash-only; use printf then read"
    lint 'mapfile|readarray' "mapfile/readarray are bash 4+ only (macOS has bash 3.2)"
    lint '\$\{![A-Za-z_]' "indirect expansion \${!var} differs between bash and zsh"
    lint 'BASH_SOURCE' "BASH_SOURCE does not exist in zsh"
    lint '(declare|typeset) +-[A-Za-z]*A' "associative arrays are bash 4+ only"
    lint '(^|[[:space:]])[A-Za-z_]+=\(' "arrays are 0-indexed in bash but 1-indexed in zsh"
    lint 'sed +(-[A-Za-z]+ +)*-i' "sed -i differs between GNU and BSD/macOS"
    lint 'readlink +-f' "readlink -f is missing on older macOS"
    lint 'xargs +(-[A-Za-z]+ +)*-r' "xargs -r is GNU-only"
    lint 'date +(-[A-Za-z]+ +)*-d' "date -d is GNU-only"
    lint 'grep +(-[A-Za-z]+ +)*-[A-Za-z]*P' "grep -P is GNU-only"
    lint 'stat +(-[A-Za-z]+ +)*-c' "stat -c is GNU-only (BSD uses -f)"
    lint '(^|[[:space:]])ls[[:space:]].*--(color|group)' "ls --color is GNU-only (BSD uses -G)"
    lint 'ps +.*--sort' "ps --sort is GNU-only"

    if [ -z "$(sed -n 's/^# DESCRIPTION: *//p' "$_cf" | head -n 1)" ]; then
        issue_w "missing '# DESCRIPTION:' header (shown by 'list')"
    fi
    _miss=$(awk '
        fname != "" { if ($0 !~ /# DESC:/) out = out (out ? ", " : "") fname; fname = "" }
        /^[A-Za-z0-9][A-Za-z0-9_-]*\(\) *\{/ { fname = $0; sub(/\(\).*/, "", fname); next }
        /^alias / && !/# DESC:/ { n = $0; sub(/^alias +/, "", n); sub(/=.*/, "", n); out = out (out ? ", " : "") n }
        END { print out }
    ' "$_cf")
    [ -z "$_miss" ] || issue_w "no '# DESC:' comment, so 'myhelp' can't describe: $_miss"

    if [ "$LOAD" -eq 1 ]; then check_load; fi
    return 0
}

run_check() { # <file> <label> [quiet]; prints the result, returns 1 on errors
    CHK_N=$((CHK_N + 1))
    ISSUES=
    _e0=$CHK_ERR
    check_file "$1"
    _failed=0
    if [ "$CHK_ERR" -gt "$_e0" ]; then _failed=1; CHK_FAIL=$((CHK_FAIL + 1)); fi
    if [ -n "$ISSUES" ] || [ "${3:-0}" -ne 1 ]; then
        if [ "$_failed" -eq 1 ]; then printf '%sFAIL%s %s\n' "$C_ERR" "$C_OFF" "$2"
        else printf '%s ok %s %s\n' "$C_OK" "$C_OFF" "$2"; fi
        printf '%s' "$ISSUES" | while IFS= read -r _l; do
            case $_l in
                E\ *) printf '       %serror:%s %s\n' "$C_ERR" "$C_OFF" "${_l#E }" ;;
                W\ *) printf '       %swarn:%s  %s\n' "$C_WARN" "$C_OFF" "${_l#W }" ;;
            esac
        done
    fi
    return "$_failed"
}

check_target() { # <package name | file path | https url>
    case $1 in
        http://*) die "Only https:// URLs are supported: $1" ;;
        https://*)
            [ "$LOAD" -eq 0 ] || die "--load executes code, so it isn't allowed on URLs. Review the file, then add it."
            ensure_work
            _u=$(normalize_url "$1")
            if download "$_u" "$WORK/check.sh"; then run_check "$WORK/check.sh" "$_u" || true
            else CHK_N=$((CHK_N + 1)); CHK_FAIL=$((CHK_FAIL + 1)); CHK_ERR=$((CHK_ERR + 1)); printf '%sFAIL%s %s\n       %serror:%s download failed\n' "$C_ERR" "$C_OFF" "$_u" "$C_ERR" "$C_OFF"
            fi ;;
        */*|*.sh)
            if [ -f "$1" ]; then run_check "$1" "$1" || true
            else CHK_N=$((CHK_N + 1)); CHK_FAIL=$((CHK_FAIL + 1)); CHK_ERR=$((CHK_ERR + 1)); printf '%sFAIL%s %s\n       %serror:%s no such file\n' "$C_ERR" "$C_OFF" "$1" "$C_ERR" "$C_OFF"
            fi ;;
        *)
            if _f=$(pkg_file "$1"); then run_check "$_f" "$1" || true
            else CHK_N=$((CHK_N + 1)); CHK_FAIL=$((CHK_FAIL + 1)); CHK_ERR=$((CHK_ERR + 1)); printf '%sFAIL%s %s\n       %serror:%s unknown package\n' "$C_ERR" "$C_OFF" "$1" "$C_ERR" "$C_OFF"
            fi ;;
    esac
}

cmd_check() {
    if [ "$#" -eq 0 ]; then
        for _p in $(pkg_names); do check_target "$_p"; done
        run_check "$REPO/template/package.sh" "template/package.sh" || true
        # The tool's own scripts: setup.sh must be POSIX sh, the loader must load in bash and zsh.
        CHK_N=$((CHK_N + 1)); ISSUES=; _e0=$CHK_ERR
        for _sh in sh dash; do check_syntax "$REPO/setup.sh" "$_sh"; done
        check_syntax "$REPO/lib/init.sh" bash
        check_syntax "$REPO/lib/init.sh" zsh
        if [ "$CHK_ERR" -gt "$_e0" ]; then CHK_FAIL=$((CHK_FAIL + 1)); printf '%sFAIL%s setup.sh, lib/init.sh\n' "$C_ERR" "$C_OFF"; else printf '%s ok %s setup.sh, lib/init.sh\n' "$C_OK" "$C_OFF"; fi
        printf '%s' "$ISSUES" | while IFS= read -r _l; do printf '       %serror:%s %s\n' "$C_ERR" "$C_OFF" "${_l#E }"; done
    else
        for _t in "$@"; do check_target "$_t"; done
    fi
    command -v zsh >/dev/null 2>&1 || info "${C_DIM}note: zsh isn't installed, so zsh syntax was not checked.${C_OFF}"
    info ""
    info "$CHK_N checked, $CHK_FAIL failed ($CHK_ERR error(s)), $CHK_WARN warning(s)."
    [ "$CHK_ERR" -eq 0 ]
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

fetch_checked() { # <url> <out>: download, then run the shared checks
    download "$1" "$2" || { warn "Download failed: $1"; return 1; }
    run_check "$2" "$1" 1
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
  check [pkg|file|url]...     Check packages for errors (no args: everything). Never runs the code
                              unless --load is given (not allowed on URLs)
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
            --load)   LOAD=1 ;;
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
        check|test)        cmd_check "$@" ;;
        uninstall)         cmd_uninstall ;;
        help|-h|--help)    usage ;;
        *)                 usage >&2; exit 1 ;;
    esac
}

main "$@"
