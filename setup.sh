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

TAB=$(printf '\t')
UPSTREAM_URL='https://github.com/christopher-pedraza/aliases-setup'
YES=0 ALL=0 PURGE=0 LOAD=0 CHECK_ONLY=0 NAME_OPT= SHELL_OPT=
CHK_N=0 CHK_FAIL=0 CHK_ERR=0 CHK_WARN=0 ISSUES=
WORK=
TTY_SAVED=
TUI_ALT=0
trap 'restore_tty; [ -z "$WORK" ] || rm -rf "$WORK"' EXIT

if [ -t 1 ]; then
    ESC=$(printf '\033')
    C_OK="${ESC}[1;32m" C_WARN="${ESC}[1;33m" C_ERR="${ESC}[1;31m" C_DIM="${ESC}[2m" C_OFF="${ESC}[0m"
    C_BOLD="${ESC}[1m" C_INFO="${ESC}[1;36m" C_BLUE="${ESC}[1;34m" C_REV="${ESC}[7m"
else
    C_OK= C_WARN= C_ERR= C_DIM= C_OFF= C_BOLD= C_INFO= C_BLUE= C_REV=
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

# ---------------------------------------------------------------- conflicts
# Packages load in name order and later definitions replace earlier ones
# silently, so two packages defining the same alias/function is a trap.

pkg_defs() { # <pkg>: name<TAB>kind<TAB>value for each top-level alias/function
    awk '
        /^alias / {
            l = $0; sub(/^alias +/, "", l)
            n = l; sub(/=.*/, "", n)
            v = l; sub(/^[^=]*=/, "", v); sub(/ +# DESC:.*/, "", v)
            printf "%s\talias\t%s\n", n, v
        }
        /^[A-Za-z0-9_][A-Za-z0-9_-]*\(\) *\{/ { n = $0; sub(/\(\).*/, "", n); printf "%s\tfunction\t\n", n }
    ' "$(pkg_file "$1")"
}

build_table() { # <packages in load order, space separated>: name pkg kind value
    for _bp in $1; do
        pkg_defs "$_bp" | awk -F'\t' -v p="$_bp" 'BEGIN { OFS = "\t" } { print $1, p, $2, $3 }'
    done
}

enabled_set() {
    for _ep in $(pkg_names); do
        if pkg_enabled "$_ep"; then printf '%s ' "$_ep"; fi
    done
}

find_conflicts() { # <table file>: name<TAB>"pkg (kind), ..."<TAB>winner<TAB>pkg,pkg
    awk -F'\t' '
        {
            n = $1; p = $2; k = $3
            if (!(n in seen)) { seen[n] = 1; order[++c] = n }
            key = n SUBSEP p
            if (!(key in has)) {
                has[key] = 1; np[n]++
                list[n] = list[n] (list[n] != "" ? ", " : "") p " (" k ")"
                pl[n] = pl[n] (pl[n] != "" ? "," : "") p
                last[n] = p
            }
        }
        END { for (i = 1; i <= c; i++) { n = order[i]; if (np[n] > 1) printf "%s\t%s\t%s\t%s\n", n, list[n], last[n], pl[n] } }
    ' "$1" | sort
}

find_same_values() { # <table file>: different alias names with an identical expansion
    awk -F'\t' '
        $3 == "alias" && $4 != "" {
            key = $4 SUBSEP $1
            if (!(key in has)) {
                has[key] = 1; nn[$4]++
                l[$4] = l[$4] (l[$4] != "" ? ", " : "") $1 " (" $2 ")"
                if (!($4 in s)) { s[$4] = 1; o[++c] = $4 }
            }
        }
        END { for (i = 1; i <= c; i++) if (nn[o[i]] > 1) printf "%s\t%s\n", o[i], l[o[i]] }
    ' "$1"
}

find_exe() { # <name>: first executable file with that name on PATH
    _old=$IFS; IFS=:
    for _d in $PATH; do
        if [ -f "$_d/$1" ] && [ -x "$_d/$1" ]; then IFS=$_old; printf '%s\n' "$_d/$1"; return 0; fi
    done
    IFS=$_old
    return 1
}

find_shadows() { # <table file>: aliases/functions that hide a real executable
    while IFS="$TAB" read -r _n _p _k _v; do
        case $_n in _*) continue ;; esac
        if [ "$_k" = alias ]; then   # `alias rm='rm -i'` wraps the command, it doesn't replace it
            case $_v in \'*|\"*) _w=${_v#?} ;; *) _w=$_v ;; esac
            if [ "${_w%% *}" = "$_n" ]; then continue; fi
        fi
        _x=$(find_exe "$_n") || continue
        printf '%s\t%s\t%s\n' "$_n" "$_p" "$_x"
    done < "$1" | sort -u
}

rc_defs() { # <rc file>: name, file, line, before|after the aliases-setup block
    awk -v b="$BEGIN" -v f="$1" '
        $0 == b { begin = NR }
        /^[ \t]*alias +[^=]+=/ { l = $0; sub(/^[ \t]*alias +/, "", l); sub(/=.*/, "", l); nm[++c] = l; ln[c] = NR; next }
        /^[ \t]*(function +)?[A-Za-z0-9_][A-Za-z0-9_-]*[ \t]*\(\)/ {
            l = $0; sub(/^[ \t]*(function +)?/, "", l); sub(/[ \t]*\(\).*/, "", l); nm[++c] = l; ln[c] = NR
        }
        END { for (i = 1; i <= c; i++) printf "%s\t%s\t%d\t%s\n", nm[i], f, ln[i], (begin > 0 && ln[i] > begin ? "after" : "before") }
    ' "$1"
}

pick_conflicts() { # <table file> <selected packages>: conflicts among just those
    awk -F'\t' -v sel="$2" '
        BEGIN { n = split(sel, a, " "); for (i = 1; i <= n; i++) on[a[i]] = 1 }
        ($2 in on) {
            key = $1 SUBSEP $2
            if (!(key in has)) {
                has[key] = 1; np[$1]++
                pl[$1] = pl[$1] (pl[$1] != "" ? "," : "") $2
                if (!($1 in seen)) { seen[$1] = 1; order[++c] = $1 }
            }
        }
        END { for (i = 1; i <= c; i++) if (np[order[i]] > 1) printf "%s\t%s\n", order[i], pl[order[i]] }
    ' "$1"
}

note_conflicts() { # one-glance warning after enabling packages
    ensure_work
    build_table "$(enabled_set)" > "$WORK/defs"
    _c=$(find_conflicts "$WORK/defs")
    if [ -n "$_c" ]; then
        warn "Name conflicts between enabled packages (the later one wins):"
        printf '%s\n' "$_c" | head -n 5 | while IFS="$TAB" read -r _n _e _w _pl; do warn "  $_n: $_e"; done
        warn "See all of them, with fixes: ./setup.sh conflicts   (or toggle packages in ./setup.sh)"
    fi
}

cmd_conflicts() {
    ensure_work
    if [ "$ALL" -eq 1 ]; then _set=$(pkg_names | tr '\n' ' '); _scope="all packages"
    else _set=$(enabled_set); _scope="enabled packages"; fi
    if [ -z "$_set" ]; then info "No enabled packages. Use --all to analyse every package."; return 0; fi
    build_table "$_set" > "$WORK/defs"
    info "${C_DIM}Analysing $_scope: $(printf '%s' "$_set" | sed 's/ *$//; s/ /, /g')${C_OFF}"

    _c=$(find_conflicts "$WORK/defs")
    info ""
    if [ -z "$_c" ]; then
        ok "No name conflicts between packages."
    else
        printf '%s%s name conflict(s): the package loaded last silently wins%s\n\n' "$C_ERR" "$(printf '%s\n' "$_c" | wc -l | tr -d ' ')" "$C_OFF"
        printf '%s\n' "$_c" | while IFS="$TAB" read -r _n _e _w _pl; do
            printf '  %s%-14s%s %s\n' "$C_WARN" "$_n" "$C_OFF" "$_e"
            printf '  %-14s %swins: %s%s\n' "" "$C_DIM" "$_w" "$C_OFF"
            for _k in $(printf '%s' "$_pl" | tr ',' ' '); do
                _o=
                for _x in $(printf '%s' "$_pl" | tr ',' ' '); do
                    if [ "$_x" != "$_k" ]; then _o="$_o $_x"; fi
                done
                printf '  %-14s %skeep %s -> ./setup.sh remove%s%s\n' "" "$C_DIM" "$_k" "$_o" "$C_OFF"
            done
            echo
        done
    fi

    _sv=$(find_same_values "$WORK/defs")
    if [ -n "$_sv" ]; then
        info "${C_WARN}Different names, same value (redundant, harmless):${C_OFF}"
        printf '%s\n' "$_sv" | while IFS="$TAB" read -r _v _l; do printf '  %s  <-  %s\n' "$_v" "$_l"; done
        info ""
    fi

    _sh_=$(find_shadows "$WORK/defs")
    if [ -n "$_sh_" ]; then
        info "${C_WARN}Hides a real program on your PATH (intentional? use \\name or 'command name' to reach it):${C_OFF}"
        printf '%s\n' "$_sh_" | while IFS="$TAB" read -r _n _p _x; do printf '  %-14s (%s) hides %s\n' "$_n" "$_p" "$_x"; done
        info ""
    fi

    : > "$WORK/rc"
    for _rc in $(rc_candidates); do
        if rc_has_block "$_rc"; then rc_defs "$_rc" >> "$WORK/rc"; fi
    done
    _ro=$(awk -F'\t' '
        NR == FNR { if (!(($1, $2) in has)) { has[$1, $2] = 1; n[$1] = n[$1] (n[$1] != "" ? ", " : "") $2 } next }
        ($1 in n) { printf "%s\t%s\t%s\t%s\t%s\n", $1, n[$1], $2, $3, $4 }
    ' "$WORK/defs" "$WORK/rc")
    if [ -n "$_ro" ]; then
        info "${C_WARN}Also defined in your own rc files:${C_OFF}"
        printf '%s\n' "$_ro" | while IFS="$TAB" read -r _n _pk _f _l _pos; do
            if [ "$_pos" = after ]; then _who="yours wins (it comes after the aliases-setup block)"
            else _who="the package wins (your definition comes before the block)"; fi
            printf '  %-14s (%s) also at %s:%s, so %s\n' "$_n" "$_pk" "$_f" "$_l" "$_who"
        done
        info ""
    fi
    [ -z "$_c" ]
}

check_conflicts() { # all packages against each other (used by `check`)
    ensure_work
    build_table "$(pkg_names | tr '\n' ' ')" > "$WORK/defs"
    _c=$(find_conflicts "$WORK/defs")
    CHK_N=$((CHK_N + 1))
    if [ -z "$_c" ]; then
        printf '%s ok %s no name conflicts between packages\n' "$C_OK" "$C_OFF"
    else
        printf '%swarn%s name conflicts between packages (see: ./setup.sh conflicts --all)\n' "$C_WARN" "$C_OFF"
        printf '%s\n' "$_c" | while IFS="$TAB" read -r _n _e _w _pl; do
            printf '       %swarn:%s  %s: %s\n' "$C_WARN" "$C_OFF" "$_n" "$_e"
        done
        CHK_WARN=$((CHK_WARN + $(printf '%s\n' "$_c" | wc -l)))
    fi
}

# ---------------------------------------------------------------- versions and upgrades
# Releases are git tags (vX.Y.Z) created by CI whenever VERSION changes on main.
# A git checkout upgrades by fast-forwarding to the newest tag on `origin`.

cur_version() {
    if [ -f "$REPO/VERSION" ]; then tr -d ' \r\n' < "$REPO/VERSION"; else printf 'unknown'; fi
    return 0
}

ver_num() { # X.Y.Z -> a comparable integer
    printf '%s' "$1" | awk -F. '{ printf "%d", $1 * 1000000 + $2 * 1000 + $3 }'
}

is_checkout() {
    command -v git >/dev/null 2>&1 && [ "$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" = "$REPO" ]
}

latest_remote_tag() { # newest vX.Y.Z tag on origin; returns 2 if origin can't be reached
    _lt=$(git -C "$REPO" ls-remote --tags --refs origin 'v*' 2>/dev/null) || return 2
    printf '%s\n' "$_lt" | sed -n 's#.*refs/tags/##p' | awk '
        /^v[0-9]+\.[0-9]+\.[0-9]+$/ {
            split(substr($0, 2), p, "."); n = p[1] * 1000000 + p[2] * 1000 + p[3]
            if (!seen || n > max) { max = n; best = $0; seen = 1 }
        }
        END { if (seen) print best }'
}

cmd_version() {
    _sha=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true)
    info "aliases-setup $(cur_version)${_sha:+ ($_sha)}"
}

post_upgrade() { # <old commit>
    if [ -f "$CONF/init.sh" ]; then   # the loader is a copy, so refresh it
        cp "$REPO/lib/init.sh" "$CONF/init.sh"
        printf '%s\n' "$REPO" > "$CONF/repo"
        info "Refreshed the loader."
    fi
    _pc=$(git -C "$REPO" diff --name-status "$1" HEAD -- packages | sed 's#packages/##; s#\.sh$##')
    _new=$(printf '%s\n' "$_pc" | awk '$1 == "A" { printf "%s ", $2 }')
    _upd=$(printf '%s\n' "$_pc" | awk '$1 == "M" { printf "%s ", $2 }')
    _gone=$(printf '%s\n' "$_pc" | awk '$1 == "D" { printf "%s ", $2 }')
    if [ -n "$_upd" ]; then
        info "Updated packages: $_upd"
        info "${C_DIM}  (enabled ones are live in your next shell; no reinstall needed)${C_OFF}"
    fi
    if [ -n "$_new" ]; then info "New packages: ${C_OK}${_new}${C_OFF}(enable with ./setup.sh)"; fi
    for _g in $_gone; do
        if pkg_enabled "$_g"; then warn "Package '$_g' was removed upstream but is still enabled: ./setup.sh remove $_g"; fi
    done
    note_conflicts
}

cmd_upgrade() {
    is_checkout || die "This copy isn't a git checkout, so it can't update itself. Get the latest release from $UPSTREAM_URL/releases"
    _cur=$(cur_version)
    _rc=0
    _tag=$(latest_remote_tag) || _rc=$?
    if [ "$_rc" -eq 2 ]; then die "Couldn't reach 'origin' to look for releases. Check your connection and remote."; fi
    if [ -z "$_tag" ]; then info "No releases found on origin yet (current version: $_cur)."; return 0; fi

    _latest=${_tag#v}
    if [ "$(ver_num "$_latest")" -le "$(ver_num "$_cur")" ]; then
        if [ "$_latest" = "$_cur" ]; then ok "You have the latest version ($_cur)."
        else info "You're ahead of the latest release ($_tag); this copy is $_cur."; fi
        return 0
    fi
    info "${C_WARN}Update available: $_cur -> $_latest${C_OFF}"
    if [ "$CHECK_ONLY" -eq 1 ]; then info "Install it with: ./setup.sh upgrade"; return 10; fi

    git -C "$REPO" fetch --quiet origin "refs/tags/$_tag:refs/tags/$_tag" || die "Couldn't fetch $_tag."
    if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]; then
        die "You have uncommitted changes in $REPO. Commit or stash them, then run upgrade again."
    fi
    if ! git -C "$REPO" merge-base --is-ancestor HEAD "$_tag"; then
        die "This copy has commits that aren't in $_tag, so it can't be fast-forwarded. Merge it yourself: git -C '$REPO' merge $_tag"
    fi
    info "Changes:"
    git -C "$REPO" log --oneline "HEAD..$_tag" | head -n 20 | sed 's/^/  /'
    if ! confirm "Update to $_tag?"; then info "Aborted."; return 0; fi

    _old=$(git -C "$REPO" rev-parse HEAD)
    git -C "$REPO" merge --ff-only --quiet "$_tag"
    ok "Updated to $_latest."
    post_upgrade "$_old"
    info "${C_DIM}Open a new shell to pick up the changes.${C_OFF}"
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

    _dups=$(awk '
        /^alias /  { n = $0; sub(/^alias +/, "", n); sub(/=.*/, "", n); c[n]++ }
        /^[A-Za-z0-9_][A-Za-z0-9_-]*\(\) *\{/ { n = $0; sub(/\(\).*/, "", n); c[n]++ }
        END { for (n in c) if (c[n] > 1) out = out (out ? ", " : "") n; print out }
    ' "$_cf")
    [ -z "$_dups" ] || issue_w "defined more than once in this file (the last wins): $_dups"

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
        check_conflicts
        # The tool's own scripts: setup.sh must be POSIX sh, the loader must load in bash and zsh.
        CHK_N=$((CHK_N + 1)); ISSUES=; _e0=$CHK_ERR
        for _sh in sh dash; do check_syntax "$REPO/setup.sh" "$_sh"; done
        if ! printf '%s\n' "$(cur_version)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
            issue_e "VERSION must look like 1.2.3 (got '$(cur_version)'); releases are cut from it"
        fi
        check_syntax "$REPO/lib/init.sh" bash
        check_syntax "$REPO/lib/init.sh" zsh
        if [ "$CHK_ERR" -gt "$_e0" ]; then CHK_FAIL=$((CHK_FAIL + 1)); printf '%sFAIL%s setup.sh, lib/init.sh, VERSION\n' "$C_ERR" "$C_OFF"; else printf '%s ok %s setup.sh, lib/init.sh, VERSION\n' "$C_OK" "$C_OFF"; fi
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

# ---------------------------------------------------------------- interactive selection
# A checkbox list in pure POSIX sh: raw mode via stty, keys via dd, drawing via ANSI escapes.

apply_changes() { # <packages to enable> <packages to disable>, space-separated
    _adds=$1 _rems=$2
    if [ -z "$_adds" ] && [ -z "$_rems" ]; then info "No changes."; return 0; fi
    for _p in $_adds; do pkg_check "$_p"; done
    if [ -n "$_adds" ]; then
        _sh=$(target_shell)
        bootstrap "$_sh"
        for _p in $_adds; do enable_pkg "$_p"; done
    fi
    for _p in $_rems; do
        rm -f "$ENABLED/$_p.sh"
        ok "Disabled $_p"
    done
    if [ -n "$_adds" ]; then reload_hint; fi
    if [ -n "$_rems" ]; then info "${C_DIM}Open shells keep removed aliases until restarted.${C_OFF}"; fi
    note_conflicts
}

can_pick() { # a real terminal that understands ANSI escapes
    if ! { [ -t 0 ] && [ -t 1 ]; }; then return 1; fi
    case ${TERM:-dumb} in dumb|unknown) return 1 ;; esac
    stty -g >/dev/null 2>&1
}

restore_tty() {
    if [ -n "$TTY_SAVED" ]; then
        printf '\033[?25h'
        if [ "${TUI_ALT:-0}" -eq 1 ]; then
            printf '\033[?1049l'
            TUI_ALT=0
        fi
        stty "$TTY_SAVED" 2>/dev/null || stty sane
        TTY_SAVED=
    fi
}

tui_enter() {
    TTY_SAVED=$(stty -g)
    trap 'restore_tty; exit 130' INT TERM HUP
    stty -icanon -echo min 1 time 0
    printf '\033[?1049h\033[?25l\033[H\033[2J'
    TUI_ALT=1
}

tui_suspend() {
    restore_tty
    trap - INT TERM HUP
}

tui_resume() {
    tui_enter
}

term_size() {
    _sz=$(stty size 2>/dev/null || true)
    ROWS=${_sz% *}; COLS=${_sz#* }
    case $ROWS in ''|*[!0-9]*) ROWS=24 ;; esac
    case $COLS in ''|*[!0-9]*) COLS=80 ;; esac
}

tui_busy() { # <message>
    term_size
    printf '\033[H\033[2J\n  %s%s%s\n' "$C_INFO" "$1" "$C_OFF"
}

read_key() { # prints UP DOWN LEFT RIGHT PGUP PGDN TAB SPACE ENTER ALL CHECK UPDATES UPGRADE CONFLICTS STATUS MENU CMD_UP CMD_DOWN QUIT or OTHER
    _h=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case $_h in
        1b) # arrow/nav keys start with ESC [ or ESC O; lone ESC means QUIT
            stty min 0 time 1
            _h2=$(dd bs=1 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
            case $_h2 in
                5b35|5b36)
                    dd bs=1 count=1 2>/dev/null >/dev/null || true
                    stty min 1 time 0
                    case $_h2 in 5b35) echo PGUP ;; 5b36) echo PGDN ;; esac ;;
                5b41|4f41) stty min 1 time 0; echo UP ;;
                5b42|4f42) stty min 1 time 0; echo DOWN ;;
                5b43|4f43) stty min 1 time 0; echo RIGHT ;;
                5b44|4f44) stty min 1 time 0; echo LEFT ;;
                5b5a)      stty min 1 time 0; echo TAB ;;
                5b3*)
                    dd bs=1 count=1 2>/dev/null >/dev/null || true
                    stty min 1 time 0
                    echo OTHER ;;
                '')        stty min 1 time 0; echo QUIT ;;
                *)         stty min 1 time 0; echo OTHER ;;
            esac ;;
        09)          echo TAB ;;
        20)          echo SPACE ;;
        0a|0d)       echo ENTER ;;
        6b)          echo UP ;;        # k
        6a)          echo DOWN ;;      # j
        4b)          echo CMD_UP ;;    # K
        4a)          echo CMD_DOWN ;;  # J
        61)          echo ALL ;;       # a
        63)          echo CHECK ;;     # c
        75)          echo UPDATES ;;   # u
        55)          echo UPGRADE ;;   # U
        78)          echo CONFLICTS ;; # x
        73)          echo STATUS ;;    # s
        6d|3f)       echo MENU ;;      # m or ?
        71|51|04|'') echo QUIT ;;      # q, Q, Ctrl-D, EOF
        *)           echo OTHER ;;
    esac
}

pick_get() { eval "_g=\$$1_$2"; } # <prefix> <index> -> $_g

pkg_commands_file() { # <pkg>: caches color_code<TAB>name<TAB>desc lines in $WORK/cmds/<pkg>.tsv
    _pcf="$WORK/cmds/$1.tsv"
    if [ ! -f "$_pcf" ]; then
        mkdir -p "$WORK/cmds"
        awk '
            function color_code(c) {
                c = tolower(c)
                if (c == "red") return "1;31"
                if (c == "green") return "1;32"
                if (c == "yellow") return "1;33"
                if (c == "blue") return "1;34"
                if (c == "magenta" || c == "purple") return "1;35"
                if (c == "cyan") return "1;36"
                if (c == "white" || c == "bold") return "1"
                if (c == "dim" || c == "gray") return "2"
                return ""
            }
            function emit_cmd(name, desc,    rb, tag, cc) {
                cc = ""
                if (substr(desc, 1, 1) == "[" && (rb = index(desc, "]")) > 2) {
                    tag = substr(desc, 2, rb - 2)
                    cc = color_code(tag)
                    if (cc != "") {
                        desc = substr(desc, rb + 1)
                        sub(/^ +/, "", desc)
                    }
                }
                if (cc == "") {
                    if (desc ~ /^DANGER:/) cc = "1;31"
                    else if (desc ~ /^(WARN|CAUTION):/) cc = "1;33"
                    else if (pkg_color != "") cc = pkg_color
                    else cc = "1;32"
                }
                printf "%s\t%s\t%s\n", cc, name, desc
            }
            /^# COLOR: */ {
                c = $0; sub(/^# COLOR: */, "", c); sub(/ .*/, "", c)
                c = color_code(c)
                if (c != "") pkg_color = c
                next
            }
            fname != "" {
                if ($0 ~ /# DESC:/) {
                    d = $0; sub(/.*# DESC: */, "", d)
                    emit_cmd(fname, d)
                } else {
                    emit_cmd(fname, "(no description)")
                }
                fname = ""; next
            }
            /^[A-Za-z0-9][A-Za-z0-9_-]*\(\) *\{/ {
                fname = $0; sub(/\(\).*/, "", fname); next
            }
            /^alias / {
                n = $0; sub(/^alias +/, "", n); sub(/=.*/, "", n)
                if ($0 ~ /# DESC:/) {
                    d = $0; sub(/.*# DESC: */, "", d)
                } else {
                    d = "(no description)"
                }
                emit_cmd(n, d)
            }
        ' "$(pkg_file "$1")" > "$_pcf"
    fi
    printf '%s\n' "$_pcf"
}

pick_load_data() {
    N=0
    ensure_work
    rm -rf "$WORK/cmds"
    : > "$WORK/pkgs.tsv"
    for _p in $(pkg_names); do
        N=$((N + 1))
        _d=$(pkg_meta "$_p" DESCRIPTION | tr '\t' ' ')
        _l=$(pkg_label "$_p" | tr '\t' ' ')
        _r=$(pkg_meta "$_p" REQUIRES | tr '\t' ' ')
        if pkg_enabled "$_p"; then _on=1; else _on=0; fi
        eval "PN_$N=\$_p PD_$N=\$_d PL_$N=\$_l PR_$N=\$_r PI_$N=$_on PS_$N=$_on"
        printf '%d\t%s\t%s\t%s\t%s\t%d\n' "$N" "$_p" "$_d" "$_l" "$_r" "$_on" >> "$WORK/pkgs.tsv"
    done
    PICK_TBL="$WORK/pick.tbl"
    build_table "$(pkg_names | tr '\n' ' ')" > "$PICK_TBL"
    LAST_INSP_KEY=
}

tui_inspector_build() { # <idx> <width> <conflicts_tsv_text>
    _idx=$1 _iw=$2 _cft=$3
    pick_get PN "$_idx"; _pn=$_g
    pick_get PD "$_idx"; _pd=$_g
    pick_get PL "$_idx"; _pl=$_g
    pick_get PR "$_idx"; _pr=$_g
    pick_get PS "$_idx"; _ps=$_g
    pick_get PI "$_idx"; _pi=$_g

    if [ "$_ps" -eq 1 ] && [ "$_pi" -eq 1 ]; then _st="[enabled]"
    elif [ "$_ps" -eq 1 ] && [ "$_pi" -eq 0 ]; then _st="[will enable]"
    elif [ "$_ps" -eq 0 ] && [ "$_pi" -eq 1 ]; then _st="[will disable]"
    else _st="[available]"
    fi

    _req_str=
    _req_miss=0
    if [ -n "$_pr" ]; then
        for _rq in $_pr; do
            if command -v "$_rq" >/dev/null 2>&1; then
                _req_str="${_req_str:+$_req_str, }$_rq (ok)"
            else
                _req_str="${_req_str:+$_req_str, }$_rq (missing)"
                _req_miss=1
            fi
        done
    fi

    _pconf=$(printf '%s\n' "$_cft" | awk -F'\t' -v p="$_pn" '
        $0 != "" && ("," $4 ",") ~ ("," p ",") {
            out = out (out != "" ? "; " : "") $1 " (" $2 ")"
        }
        END { print out }
    ')

    _cmdf=$(pkg_commands_file "$_pn")
    awk -F'\t' -v w="$_iw" -v pn="$_pn" -v st="$_st" -v lbl="$_pl" -v pd="$_pd" \
        -v rq="$_req_str" -v rqm="$_req_miss" -v pcf="$_pconf" '
        function sp(n,    r) { r = ""; while (n-- > 0) r = r " "; return r }
        function wrap_arr(text, width, arr,    n, words, i, line, word, cnt) {
            if (width < 8) width = 8
            cnt = 0; line = ""
            n = split(text, words, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                word = words[i]
                if (word == "") continue
                while (length(word) > width) {
                    if (line != "") { arr[++cnt] = line; line = "" }
                    arr[++cnt] = substr(word, 1, width)
                    word = substr(word, width + 1)
                }
                if (line == "") line = word
                else if (length(line) + 1 + length(word) <= width) line = line " " word
                else { arr[++cnt] = line; line = word }
            }
            if (line != "") arr[++cnt] = line
            return cnt
        }
        BEGIN {
            esc = sprintf("\033")
            c_ok = esc "[1;32m"; c_warn = esc "[1;33m"; c_dim = esc "[2m"
            c_bold = esc "[1m"; c_info = esc "[1;36m"; c_blue = esc "[1;34m"; c_off = esc "[0m"
            nc = 0; maxn = 0
        }
        {
            nc++
            ck[nc] = $1; cn[nc] = $2; cd[nc] = $3
            if (length($2) > maxn) maxn = length($2)
        }
        END {
            if (w < 16) w = 16
            if (pd != "") {
                m = wrap_arr(pd, w, lines)
                for (i = 1; i <= m; i++) print lines[i]
            } else {
                print c_dim "(no package description)" c_off
            }
            if (rq != "") {
                rc = (rqm == 1 ? c_warn : c_dim)
                m = wrap_arr("Requires: " rq, w, lines)
                for (i = 1; i <= m; i++) print rc lines[i] c_off
            }
            if (pcf != "") {
                m = wrap_arr("! Conflict: " pcf, w, lines)
                for (i = 1; i <= m; i++) print c_warn lines[i] c_off
            }
            print ""
            print c_bold "Commands (" nc "):" c_off

            colw = maxn + 2
            if (colw < 10) colw = 10
            if (colw > 14) colw = 14
            if (colw > w - 12) colw = 8
            dw = w - 2 - colw
            if (dw < 8) dw = 8
            if (nc == 0) {
                print c_dim "  (no aliases or functions defined)" c_off
            }
            for (i = 1; i <= nc; i++) {
                nm = cn[i]
                if (length(nm) >= colw) nm_vis = substr(nm, 1, colw - 1) " "
                else nm_vis = nm sp(colw - length(nm))
                cc = esc "[" ck[i] "m"
                m = wrap_arr(cd[i], dw, lines)
                if (m == 0) {
                    printf "  %s%s%s\n", cc, nm_vis, c_off
                } else {
                    printf "  %s%s%s%s\n", cc, nm_vis, c_off, lines[1]
                    for (j = 2; j <= m; j++) {
                        printf "  %s%s\n", sp(colw), lines[j]
                    }
                }
            }
        }
    ' "$_cmdf" > "$WORK/inspect.body"

    CMD_TOTAL=$(wc -l < "$WORK/inspect.body" | tr -d ' ')
    case $CMD_TOTAL in ''|*[!0-9]*) CMD_TOTAL=0 ;; esac
}

pick_draw() {
    term_size
    # Current selection state
    _sel=; _sel_bits=; _enabled_cnt=0; _i=1
    while [ "$_i" -le "$N" ]; do
        pick_get PS "$_i"; _s=$_g
        if [ "$_s" -eq 1 ]; then
            pick_get PN "$_i"
            _sel="$_sel $_g"
            _enabled_cnt=$((_enabled_cnt + 1))
        fi
        _sel_bits="${_sel_bits}${_s}"
        _i=$((_i + 1))
    done

    _cf=$(pick_conflicts "$PICK_TBL" "$_sel")
    _cpk=" $(printf '%s\n' "$_cf" | cut -f2 | tr ',' ' ' | tr '\n' ' ') "

    _chg=
    _i=1
    while [ "$_i" -le "$N" ]; do
        pick_get PS "$_i"; _s=$_g
        pick_get PI "$_i"; _o=$_g
        pick_get PN "$_i"
        if [ "$_s" -ne "$_o" ]; then
            if [ "$_s" -eq 1 ]; then _chg="$_chg +$_g"; else _chg="$_chg -$_g"; fi
        fi
        _i=$((_i + 1))
    done

    _loader_st="not installed"
    if [ -f "$CONF/init.sh" ]; then _loader_st="installed"; fi

    if [ "$COLS" -ge 76 ] && [ "$ROWS" -ge 14 ]; then
        _mode=split
        _left_w=$((COLS * 38 / 100))
        if [ "$_left_w" -lt 28 ]; then _left_w=28; fi
        if [ "$_left_w" -gt 42 ]; then _left_w=42; fi
        _right_w=$((COLS - _left_w - 4))
        _hdr_h=2
        _ftr_h=4
        _body_h=$((ROWS - _hdr_h - _ftr_h))
        if [ "$_body_h" -lt 4 ]; then _body_h=4; fi
        VIS=$((_body_h - 1))
    else
        _mode=stack
        _left_w=$((COLS - 1))
        _right_w=$((COLS - 1))
        _hdr_h=2
        _ftr_h=3
        _avail=$((ROWS - _hdr_h - _ftr_h))
        if [ "$_avail" -lt 6 ]; then _avail=6; fi
        VIS=$((_avail / 2))
        if [ "$VIS" -lt 3 ]; then VIS=3; fi
        if [ "$VIS" -gt "$N" ]; then VIS=$N; fi
        _cmd_vis=$((_avail - VIS - 2))
        if [ "$_cmd_vis" -lt 1 ]; then _cmd_vis=1; fi
    fi

    if [ "$CUR" -lt "$TOP" ]; then TOP=$CUR; fi
    if [ "$CUR" -ge $((TOP + VIS)) ]; then TOP=$((CUR - VIS + 1)); fi
    if [ "$TOP" -lt 1 ]; then TOP=1; fi

    pick_get PS "$CUR"; _cur_ps=$_g
    pick_get PI "$CUR"; _cur_pi=$_g
    pick_get PN "$CUR"; _cur_pn=$_g
    pick_get PL "$CUR"; _cur_pl=$_g
    _insp_key="${CUR}:${_right_w}:${_cur_ps}:${_cur_pi}:${_cpk}"
    if [ "$_insp_key" != "$LAST_INSP_KEY" ] || [ ! -f "$WORK/inspect.body" ]; then
        tui_inspector_build "$CUR" "$_right_w" "$_cf"
        LAST_INSP_KEY=$_insp_key
    fi

    if [ "$_mode" = split ]; then _rvis=$VIS; else _rvis=$_cmd_vis; fi
    _max_ctop=$((CMD_TOTAL - _rvis + 1))
    if [ "$_max_ctop" -lt 1 ]; then _max_ctop=1; fi
    if [ "$CMD_TOP" -gt "$_max_ctop" ]; then CMD_TOP=$_max_ctop; fi
    if [ "$CMD_TOP" -lt 1 ]; then CMD_TOP=1; fi

    _cf_line=
    if [ -n "$_cf" ]; then
        _cf_line=$(printf '%s\n' "$_cf" | awk -F'\t' '{ printf "%s%s (%s)", (NR > 1 ? "; " : ""), $1, $2 }' | sed 's/^/! conflict: /')
    fi

    awk -F'\t' \
        -v mode="$_mode" -v cols="$COLS" -v rows="$ROWS" \
        -v lw="$_left_w" -v rw="$_right_w" \
        -v n="$N" -v cur="$CUR" -v top="$TOP" -v vis="$VIS" \
        -v ctop="$CMD_TOP" -v ctot="$CMD_TOTAL" -v rvis="$_rvis" \
        -v focus="$FOCUS" -v sbits="$_sel_bits" -v cpk="$_cpk" \
        -v ver="$(cur_version)" -v ldst="$_loader_st" -v enc="$_enabled_cnt" \
        -v updb="$UPDATE_BADGE" -v chg="$_chg" -v cfl="$_cf_line" \
        -v curpn="$_cur_pn" -v curpl="$_cur_pl" -v curps="$_cur_ps" -v curpi="$_cur_pi" \
        -v insp_file="$WORK/inspect.body" '
        function sp(k,    r) { r = ""; while (k-- > 0) r = r " "; return r }
        function hr(k,    r) { r = ""; while (k-- > 0) r = r "-"; return r }
        function fit(s, w) {
            if (w <= 0) return ""
            if (length(s) > w) return (w > 3 ? substr(s, 1, w - 3) "..." : substr(s, 1, w))
            return s sp(w - length(s))
        }
        BEGIN {
            esc = sprintf("\033")
            c_ok = esc "[1;32m"; c_warn = esc "[1;33m"; c_err = esc "[1;31m"
            c_dim = esc "[2m"; c_bold = esc "[1m"; c_info = esc "[1;36m"
            c_rev = esc "[7m"; c_off = esc "[0m"
        }
        {
            idx = $1 + 0
            pn[idx] = $2; pd[idx] = $3; pl[idx] = $4; pi[idx] = $6 + 0
        }
        END {
            rn = 0
            while ((getline line < insp_file) > 0) rlines[++rn] = line
            close(insp_file)

            # Determine current package status badge
            if (curps == 1 && curpi == 1) st = "[enabled]"
            else if (curps == 1 && curpi == 0) st = "[will enable]"
            else if (curps == 0 && curpi == 1) st = "[will disable]"
            else st = "[available]"

            printf "%s[H", esc

            # Header
            hdr_left = "aliases-setup v" ver "  |  loader: " ldst "  |  " enc "/" n " enabled"
            if (updb != "") hdr_left = hdr_left "  |  " updb
            printf "\r%s[K%s%s%s\n", esc, c_bold, fit(hdr_left, cols - 1), c_off
            printf "\r%s[K%s%s%s\n", esc, c_dim, hr(cols - 1), c_off

            if (mode == "split") {
                # Pane headers
                lend = top + vis - 1; if (lend > n) lend = n
                lscroll = (n > vis ? "(" top "-" lend "/" n ")" : "")
                lhdr_txt = "Packages (" n ")"
                lpad = lw - length(lhdr_txt) - length(lscroll)
                if (lpad < 1) lpad = 1
                if (focus == "left") {
                    lhdr = c_info lhdr_txt c_off sp(lpad) c_dim lscroll c_off
                } else {
                    lhdr = c_dim lhdr_txt sp(lpad) lscroll c_off
                }
                if (length(lhdr_txt) + lpad + length(lscroll) > lw) {
                    lhdr = (focus == "left" ? c_info : c_dim) fit(lhdr_txt, lw) c_off
                }

                rend = ctop + rvis - 1; if (rend > rn) rend = rn
                rscroll = (rn > rvis ? "(" ctop "-" rend "/" rn ")" : "")
                rt_plain = curpn "  " st curpl
                if (focus == "right") rcol = c_info
                else if (curps == 1) rcol = c_ok
                else rcol = c_bold
                rpad = rw - length(rt_plain) - length(rscroll)
                if (rpad < 1) {
                    rhdr = rcol fit(rt_plain, rw) c_off
                } else {
                    rhdr = rcol curpn "  " st c_off c_dim curpl sp(rpad) rscroll c_off
                }

                printf "\r%s[K%s %s|%s %s\n", esc, lhdr, c_dim, c_off, rhdr

                for (row = 0; row < vis; row++) {
                    i = top + row
                    if (i <= n) {
                        sel = substr(sbits, i, 1) + 0
                        mark = (i == cur ? ">" : " ")
                        flag = (index(cpk, " " pn[i] " ") > 0 ? "!" : " ")
                        box = (sel == 1 ? "[x]" : "[ ]")
                        nw = 11
                        nm = pn[i]
                        if (length(nm) > nw) nm_fit = substr(nm, 1, nw - 1) "~"
                        else nm_fit = nm sp(nw - length(nm))
                        dw = lw - 19
                        if (dw < 0) dw = 0
                        desc = fit(pd[i] pl[i], dw)

                        cbox = (sel == 1 ? c_ok box c_off : box)
                        cflag = (flag == "!" ? c_warn "!" c_off : " ")
                        if (i == cur) {
                            lrow = c_bold ">" c_off " " cflag " " cbox " " c_info nm_fit c_off " " desc
                        } else {
                            lrow = "  " cflag " " cbox " " nm_fit " " c_dim desc c_off
                        }
                    } else {
                        lrow = sp(lw)
                    }

                    ri = ctop + row
                    rrow = (ri <= rn ? rlines[ri] : "")
                    printf "\r%s[K%s %s|%s %s\n", esc, lrow, c_dim, c_off, rrow
                }
            } else {
                # Compact stacked fallback for narrow terminals
                for (row = 0; row < vis; row++) {
                    i = top + row
                    if (i <= n) {
                        sel = substr(sbits, i, 1) + 0
                        mark = (i == cur ? ">" : " ")
                        flag = (index(cpk, " " pn[i] " ") > 0 ? "!" : " ")
                        box = (sel == 1 ? c_ok "[x]" c_off : "[ ]")
                        cflag = (flag == "!" ? c_warn "!" c_off : " ")
                        desc = fit(pd[i], cols - 20)
                        if (i == cur) printf "\r%s[K%s %s %s %s%-11s%s %s\n", esc, mark, cflag, box, c_info, substr(pn[i], 1, 11), c_off, desc
                        else printf "\r%s[K%s %s %s %-11s %s\n", esc, mark, cflag, box, substr(pn[i], 1, 11), desc
                    } else {
                        printf "\r%s[K\n", esc
                    }
                }
                printf "\r%s[K%s%s%s\n", esc, c_dim, hr(cols - 1), c_off
                printf "\r%s[K%s%s  %s%s\n", esc, c_bold, curpn, st, c_off
                for (row = 0; row < rvis; row++) {
                    ri = ctop + row
                    printf "\r%s[K%s\n", esc, (ri <= rn ? rlines[ri] : "")
                }
            }

            # Footer rule & status line
            printf "\r%s[K%s%s%s\n", esc, c_dim, hr(cols - 1), c_off
            if (cfl != "") {
                st_line = c_warn fit(cfl, cols - 1) c_off
            } else if (chg != "") {
                st_line = c_ok "pending:" chg c_off
            } else {
                st_line = c_dim "pending: no changes   (Tab: scroll commands, m: more actions)" c_off
            }
            printf "\r%s[K%s\n", esc, st_line

            # Button rows (no trailing newline on final row if rows match)
            if (chg != "") apply_btn = c_ok "[Enter] Apply" c_off
            else apply_btn = c_dim "[Enter] Apply" c_off

            b1 = " " c_info "[Space]" c_off " Toggle  " c_info "[a]" c_off " All  " apply_btn "  " c_info "[Tab]" c_off " Scroll cmds  " c_info "[q]" c_off " Quit"
            b2 = " " c_info "[c]" c_off " Verify  " c_info "[u]" c_off " Updates  " c_info "[x]" c_off " Conflicts  " c_info "[s]" c_off " Status  " c_info "[m]" c_off " More actions"
            if (mode == "split") {
                printf "\r%s[K%s\n", esc, b1
                printf "\r%s[K%s%s[J", esc, b2, esc
            } else {
                printf "\r%s[K%s%s[J", esc, b1 "  " c_info "[m]" c_off " Menu", esc
            }
        }
    ' "$WORK/pkgs.tsv"
}

tui_pager() { # <title> <file> [extra_mode: upgrade]
    _ptitle=$1 _pfile=$2 _pextra=${3:-}
    term_size
    _pw=$((COLS - 2)); if [ "$_pw" -lt 20 ]; then _pw=20; fi
    awk -v w="$_pw" '
        {
            gsub(/\t/, "    ")
            line = $0; out = ""; vis = 0
            i = 1; len = length(line)
            while (i <= len) {
                c = substr(line, i, 1)
                if (c == "\033" && substr(line, i + 1, 1) == "[") {
                    j = i + 2
                    while (j <= len && substr(line, j, 1) !~ /[A-Za-z]/) j++
                    out = out substr(line, i, j - i + 1)
                    i = j + 1
                    continue
                }
                if (vis >= w) {
                    print out "\033[0m"
                    out = "  "; vis = 2
                }
                out = out c
                vis++
                i++
            }
            print out "\033[0m"
        }
    ' "$_pfile" > "$WORK/pager.lines"
    _ptot=$(wc -l < "$WORK/pager.lines" | tr -d ' ')
    case $_ptot in ''|*[!0-9]*) _ptot=0 ;; esac
    _ptop=1

    while :; do
        term_size
        _pvis=$((ROWS - 4)); if [ "$_pvis" -lt 3 ]; then _pvis=3; fi
        _pmax=$((_ptot - _pvis + 1)); if [ "$_pmax" -lt 1 ]; then _pmax=1; fi
        if [ "$_ptop" -gt "$_pmax" ]; then _ptop=$_pmax; fi
        if [ "$_ptop" -lt 1 ]; then _ptop=1; fi

        awk -v title="$_ptitle" -v top="$_ptop" -v vis="$_pvis" -v tot="$_ptot" \
            -v cols="$COLS" -v extra="$_pextra" '
            function sp(k,    r) { r = ""; while (k-- > 0) r = r " "; return r }
            function hr(k,    r) { r = ""; while (k-- > 0) r = r "-"; return r }
            BEGIN {
                esc = sprintf("\033")
                c_bold = esc "[1m"; c_dim = esc "[2m"; c_info = esc "[1;36m"; c_ok = esc "[1;32m"; c_off = esc "[0m"
            }
            { lines[NR] = $0 }
            END {
                end = top + vis - 1; if (end > tot) end = tot
                pos = (tot > 0 ? "lines " top "-" end " of " tot : "empty")
                pad = cols - 1 - length(title) - length(pos)
                if (pad < 1) pad = 1
                printf "%s[H\r%s[K%s%s%s%s%s%s%s\n", esc, esc, c_bold, title, c_off, sp(pad), c_dim, pos, c_off
                printf "\r%s[K%s%s%s\n", esc, c_dim, hr(cols - 1), c_off
                for (r = 0; r < vis; r++) {
                    li = top + r
                    printf "\r%s[K%s\n", esc, (li <= tot ? lines[li] : "")
                }
                printf "\r%s[K%s%s%s\n", esc, c_dim, hr(cols - 1), c_off
                ftr = " " c_info "[Up/Down/Space]" c_off " Scroll   " c_info "[q/Esc/Enter]" c_off " Back"
                if (extra == "upgrade") ftr = ftr "   " c_ok "[U] Upgrade now" c_off
                printf "\r%s[K%s%s[J", esc, ftr, esc
            }
        ' "$WORK/pager.lines"

        case $(read_key) in
            UP|CMD_UP)     _ptop=$((_ptop - 1)) ;;
            DOWN|CMD_DOWN) _ptop=$((_ptop + 1)) ;;
            PGUP)          _ptop=$((_ptop - _pvis)) ;;
            PGDN|SPACE)    _ptop=$((_ptop + _pvis)) ;;
            UPGRADE)       if [ "$_pextra" = upgrade ]; then return 10; fi ;;
            QUIT|ENTER)    return 0 ;;
        esac
    done
}

tui_run_check() { # <all | pkg>
    _cs=$1
    tui_busy "Running verification checks (--load)..."
    if [ "$_cs" = all ]; then
        ( LOAD=1; CHK_N=0; CHK_FAIL=0; CHK_ERR=0; CHK_WARN=0; ISSUES=; cmd_check ) > "$WORK/pager.raw" 2>&1 || true
        tui_pager "Verify all packages (check --load)" "$WORK/pager.raw"
    else
        ( LOAD=1; CHK_N=0; CHK_FAIL=0; CHK_ERR=0; CHK_WARN=0; ISSUES=; cmd_check "$_cs" ) > "$WORK/pager.raw" 2>&1 || true
        tui_pager "Verify package: $_cs (check --load)" "$WORK/pager.raw"
    fi
}

tui_check_updates() {
    tui_busy "Checking for updates..."
    : > "$WORK/pager.raw"
    _urc=0
    ( CHECK_ONLY=1; cmd_upgrade ) > "$WORK/upd_repo" 2>&1 || _urc=$?
    printf '%saliases-setup (%s):%s\n' "$C_BOLD" "$(cur_version)" "$C_OFF" >> "$WORK/pager.raw"
    sed 's/^/  /' "$WORK/upd_repo" >> "$WORK/pager.raw"

    _uextra=
    if [ "$_urc" -eq 10 ]; then
        _uextra=upgrade
        UPDATE_BADGE="update available"
    elif [ "$_urc" -eq 0 ]; then
        UPDATE_BADGE="up to date"
    fi

    _has_url=0
    for _uf in "$USER_PKG_DIR"/*.url; do
        if [ -f "$_uf" ]; then _has_url=1; break; fi
    done
    if [ "$_has_url" -eq 1 ]; then
        printf '\n%sDownloaded URL packages:%s\n' "$C_BOLD" "$C_OFF" >> "$WORK/pager.raw"
        for _uf in "$USER_PKG_DIR"/*.url; do
            [ -f "$_uf" ] || continue
            _un=$(basename "$_uf" .url)
            _u=$(cat "$_uf")
            if ( fetch_checked "$_u" "$WORK/upd_${_un}.sh" ) > "$WORK/upd_pkg_out" 2>&1; then
                if [ -f "$USER_PKG_DIR/$_un.sh" ] && cmp -s "$WORK/upd_${_un}.sh" "$USER_PKG_DIR/$_un.sh"; then
                    printf '  %s ok %s %-12s up to date\n' "$C_OK" "$C_OFF" "$_un" >> "$WORK/pager.raw"
                else
                    printf '  %swarn%s %-12s update available (run "Update downloaded URL packages" in [m] Menu)\n' "$C_WARN" "$C_OFF" "$_un" >> "$WORK/pager.raw"
                fi
            else
                printf '  %sFAIL%s %-12s check failed (%s)\n' "$C_ERR" "$C_OFF" "$_un" "$_u" >> "$WORK/pager.raw"
            fi
        done
    fi

    tui_pager "Check for updates" "$WORK/pager.raw" "$_uextra"
    if [ "$?" -eq 10 ]; then
        tui_run_interactive upgrade
    fi
}

tui_run_conflicts() { # <0=enabled, 1=all>
    _ca=$1
    tui_busy "Analysing conflicts..."
    ( ALL=$_ca; cmd_conflicts ) > "$WORK/pager.raw" 2>&1 || true
    if [ "$_ca" -eq 1 ]; then
        tui_pager "Conflicts (all packages)" "$WORK/pager.raw"
    else
        tui_pager "Conflicts (enabled packages)" "$WORK/pager.raw"
    fi
}

tui_run_status() {
    tui_busy "Checking install status..."
    ( cmd_status ) > "$WORK/pager.raw" 2>&1 || true
    tui_pager "Install status" "$WORK/pager.raw"
}

tui_pause() {
    printf '\n%sPress Enter to return to setup...%s' "$C_DIM" "$C_OFF"
    read -r _dummy || true
}

tui_reload_preserving_pending() {
    _keep_on= _keep_off=
    _i=1
    while [ "$_i" -le "$N" ]; do
        pick_get PS "$_i"; _s=$_g
        pick_get PI "$_i"; _o=$_g
        pick_get PN "$_i"
        if [ "$_s" -ne "$_o" ]; then
            if [ "$_s" -eq 1 ]; then _keep_on="$_keep_on $_g"; else _keep_off="$_keep_off $_g"; fi
        fi
        _i=$((_i + 1))
    done
    pick_load_data
    _i=1
    while [ "$_i" -le "$N" ]; do
        pick_get PN "$_i"; _pn=$_g
        case " $_keep_on " in *" $_pn "*) eval "PS_$_i=1" ;; esac
        case " $_keep_off " in *" $_pn "*) eval "PS_$_i=0" ;; esac
        _i=$((_i + 1))
    done
    if [ "$CUR" -gt "$N" ]; then CUR=$N; fi
    if [ "$CUR" -lt 1 ]; then CUR=1; fi
    CMD_TOP=1
}

tui_run_interactive() { # <action> -> returns 2 if uninstalled and TUI should exit
    _act=$1
    tui_suspend
    case $_act in
        upgrade)
            ( cmd_upgrade ) || true
            tui_pause
            tui_resume
            tui_reload_preserving_pending
            ;;
        update_urls)
            ( cmd_update ) || true
            tui_pause
            tui_resume
            tui_reload_preserving_pending
            ;;
        install_loader)
            printf 'Target shell [1=default (%s), 2=bash, 3=zsh, 4=all]: ' "${SHELL_OPT:-auto}"
            read -r _shc || _shc=
            _shv=$SHELL_OPT
            case $_shc in
                2|bash) _shv=bash ;;
                3|zsh)  _shv=zsh ;;
                4|all)  _shv=all ;;
            esac
            ( SHELL_OPT=$_shv; cmd_install ) || true
            tui_pause
            tui_resume
            ;;
        new_pkg)
            printf 'New custom package name: '
            read -r _np || _np=
            if [ -n "$_np" ]; then
                ( cmd_new "$_np" ) || true
                tui_pause
            fi
            tui_resume
            tui_reload_preserving_pending
            ;;
        add_url)
            printf 'HTTPS URL to package (.sh): '
            read -r _au || _au=
            if [ -n "$_au" ]; then
                printf 'Package name (blank to derive from URL): '
                read -r _an || _an=
                (
                    NAME_OPT=$_an
                    _sh=$(target_shell)
                    bootstrap "$_sh"
                    add_url "$_au"
                ) || true
                tui_pause
            fi
            tui_resume
            tui_reload_preserving_pending
            ;;
        uninstall)
            ( cmd_uninstall ) || true
            if [ ! -e "$CONF/init.sh" ] && [ ! -d "$ENABLED" ]; then
                return 2
            fi
            tui_pause
            tui_resume
            tui_reload_preserving_pending
            ;;
    esac
    return 0
}

tui_menu() { # returns 2 if TUI should exit (e.g. after uninstall)
    pick_get PN "$CUR"; _cur_name=$_g
    _mcur=1
    _mn=12
    while :; do
        term_size
        awk -v mcur="$_mcur" -v cols="$COLS" -v rows="$ROWS" -v cpkg="$_cur_name" '
            function sp(k,    r) { r = ""; while (k-- > 0) r = r " "; return r }
            function hr(k,    r) { r = ""; while (k-- > 0) r = r "-"; return r }
            BEGIN {
                esc = sprintf("\033")
                c_bold = esc "[1m"; c_dim = esc "[2m"; c_info = esc "[1;36m"; c_warn = esc "[1;33m"; c_off = esc "[0m"
                item[1]  = "Verify all packages (check --load)"
                desc[1]  = "Syntax, portability lint, DESC metadata, and load test in bash/zsh"
                item[2]  = "Verify highlighted package (" cpkg ")"
                desc[2]  = "Run check --load on the currently selected package"
                item[3]  = "Check for updates (repo + downloaded URLs)"
                desc[3]  = "Compare against newest git release tag and URL sources"
                item[4]  = "Upgrade aliases-setup to latest release"
                desc[4]  = "Fast-forward this checkout to the newest release tag"
                item[5]  = "Update downloaded URL packages"
                desc[5]  = "Re-download URL packages and review diffs before applying"
                item[6]  = "Check conflicts (enabled packages)"
                desc[6]  = "Find duplicate command names and PATH shadows among enabled packages"
                item[7]  = "Check conflicts (all packages)"
                desc[7]  = "Analyse all packages, including ones not currently enabled"
                item[8]  = "Show install status"
                desc[8]  = "Version, loader health, rc blocks, and enabled/available list"
                item[9]  = "Install / refresh shell loader"
                desc[9]  = "Write init.sh and add the managed rc block for bash/zsh/all"
                item[10] = "Create new custom package"
                desc[10] = "Generate a new package file in ~/.config/aliases-setup/packages/"
                item[11] = "Add package from HTTPS URL"
                desc[11] = "Download, validate, inspect code, and enable a remote package"
                item[12] = "Uninstall aliases-setup"
                desc[12] = "Remove rc blocks and loader files"

                printf "%s[H\r%s[K%sActions & Tools%s\n", esc, esc, c_bold, c_off
                printf "\r%s[K%s%s%s\n", esc, c_dim, hr(cols - 1), c_off
                for (i = 1; i <= 12; i++) {
                    if (i == mcur) {
                        printf "\r%s[K  %s> %-44s%s\n", esc, c_info, item[i], c_off
                    } else {
                        printf "\r%s[K    %-44s\n", esc, item[i]
                    }
                }
                printf "\r%s[K%s%s%s\n", esc, c_dim, hr(cols - 1), c_off
                printf "\r%s[K  %s%s%s\n", esc, c_dim, substr(desc[mcur], 1, cols - 4), c_off
                printf "\r%s[K\n", esc
                printf "\r%s[K %s[Up/Down]%s Move   %s[Enter]%s Run   %s[q/Esc]%s Back%s[J", esc, c_info, c_off, c_info, c_off, c_info, c_off, esc
            }
        '

        case $(read_key) in
            UP|CMD_UP)     _mcur=$((_mcur - 1)); if [ "$_mcur" -lt 1 ]; then _mcur=$_mn; fi ;;
            DOWN|CMD_DOWN) _mcur=$((_mcur + 1)); if [ "$_mcur" -gt "$_mn" ]; then _mcur=1; fi ;;
            QUIT|LEFT)     return 0 ;;
            ENTER|SPACE|RIGHT)
                case $_mcur in
                    1)  tui_run_check all ;;
                    2)  tui_run_check "$_cur_name" ;;
                    3)  tui_check_updates ;;
                    4)  tui_run_interactive upgrade ;;
                    5)  tui_run_interactive update_urls ;;
                    6)  tui_run_conflicts 0 ;;
                    7)  tui_run_conflicts 1 ;;
                    8)  tui_run_status ;;
                    9)  tui_run_interactive install_loader ;;
                    10) tui_run_interactive new_pkg ;;
                    11) tui_run_interactive add_url ;;
                    12) if ! tui_run_interactive uninstall; then return 2; fi ;;
                esac
                pick_get PN "$CUR"; _cur_name=$_g
                ;;
        esac
    done
}

pick_packages() {
    pick_load_data
    if [ "$N" -eq 0 ]; then info "No packages found."; return 0; fi

    CUR=1; TOP=1; CMD_TOP=1; CMD_TOTAL=0; FOCUS=left; UPDATE_BADGE=
    tui_enter
    pick_draw
    _done=
    while [ -z "$_done" ]; do
        case $(read_key) in
            UP)
                if [ "$FOCUS" = right ]; then
                    if [ "$CMD_TOP" -gt 1 ]; then CMD_TOP=$((CMD_TOP - 1)); fi
                else
                    CUR=$((CUR - 1)); if [ "$CUR" -lt 1 ]; then CUR=$N; fi
                    CMD_TOP=1
                fi ;;
            DOWN)
                if [ "$FOCUS" = right ]; then
                    CMD_TOP=$((CMD_TOP + 1))
                else
                    CUR=$((CUR + 1)); if [ "$CUR" -gt "$N" ]; then CUR=1; fi
                    CMD_TOP=1
                fi ;;
            CMD_UP|PGUP)
                CMD_TOP=$((CMD_TOP - 5)); if [ "$CMD_TOP" -lt 1 ]; then CMD_TOP=1; fi ;;
            CMD_DOWN|PGDN)
                CMD_TOP=$((CMD_TOP + 5)) ;;
            TAB)
                if [ "$FOCUS" = left ]; then FOCUS=right; else FOCUS=left; fi ;;
            RIGHT)
                FOCUS=right ;;
            LEFT)
                FOCUS=left ;;
            SPACE)
                pick_get PS "$CUR"; eval "PS_$CUR=$((1 - _g))" ;;
            ALL)
                _v=1; _i=1
                while [ "$_i" -le "$N" ]; do pick_get PS "$_i"; if [ "$_g" -eq 0 ]; then _v=0; fi; _i=$((_i + 1)); done
                _i=1  # everything already selected -> clear all, otherwise select all
                while [ "$_i" -le "$N" ]; do eval "PS_$_i=$((1 - _v))"; _i=$((_i + 1)); done ;;
            CHECK)
                tui_run_check all ;;
            UPDATES)
                tui_check_updates ;;
            UPGRADE)
                tui_run_interactive upgrade ;;
            CONFLICTS)
                tui_run_conflicts 0 ;;
            STATUS)
                tui_run_status ;;
            MENU)
                if ! tui_menu; then _done=exit_only; fi ;;
            ENTER)
                _done=apply ;;
            QUIT)
                _done=cancel ;;
        esac
        if [ -z "$_done" ]; then pick_draw; fi
    done
    restore_tty
    trap - INT TERM HUP

    if [ "$_done" = exit_only ]; then return 0; fi
    if [ "$_done" = cancel ]; then info "Cancelled; nothing changed."; return 0; fi
    _adds= _rems=
    _i=1
    while [ "$_i" -le "$N" ]; do
        pick_get PS "$_i"; _s=$_g
        pick_get PI "$_i"; _o=$_g
        pick_get PN "$_i"
        if [ "$_s" -ne "$_o" ]; then
            if [ "$_s" -eq 1 ]; then _adds="$_adds $_g"; else _rems="$_rems $_g"; fi
        fi
        _i=$((_i + 1))
    done
    apply_changes "$_adds" "$_rems"
}

prompt_packages() { # fallback for terminals that can't do the picker: y/N per package
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
    apply_changes "$_picks" ""
}

cmd_select() {
    if ! { [ -t 0 ] && [ -t 1 ]; }; then
        die "Interactive selection needs a terminal. Use: ./setup.sh add <package>... | --all"
    fi
    if can_pick; then pick_packages; else prompt_packages; fi
}

cmd_install() {
    _sh=$(target_shell)
    bootstrap "$_sh"
    ok "Installed the loader for: $_sh"
}

cmd_add() {
    if [ "$ALL" -eq 1 ]; then set -- $(pkg_names); fi
    if [ "$#" -eq 0 ]; then cmd_select; return 0; fi

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
    note_conflicts
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
    info "Version: $(cur_version)"
    if [ -f "$CONF/init.sh" ]; then ok "Loader:  $CONF/init.sh"; else warn "Loader:  not installed"; fi
    _found=0
    for _rc in $(rc_candidates); do
        if rc_has_block "$_rc"; then ok "RC block: $_rc"; _found=1; fi
    done
    if [ "$_found" -eq 0 ]; then warn "RC block: not present in any rc file"; fi
    if [ -f "$CONF/init.sh" ] && ! cmp -s "$REPO/lib/init.sh" "$CONF/init.sh"; then
        warn "Loader:  out of date with this checkout; run ./setup.sh install to refresh it"
    fi
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
  select                      Checkbox list to enable/disable packages (also: run with no command)
  add [pkg|url]... | --all    Enable packages; a https URL downloads one (no args: same as select)
  remove <pkg>... | --all     Disable packages (--purge also deletes custom/downloaded files)
  update [pkg]...             Re-download packages that came from a URL (shows a diff first)
  new <name>                  Create a custom package from the template
  install                     Install the loader only, without enabling packages
  conflicts [--all]           Show aliases/functions defined twice, who wins, and how to fix it
  status                      Show install health
  check [pkg|file|url]...     Check packages for errors (no args: everything). Never runs the code
                              unless --load is given (not allowed on URLs)
  version                     Show the installed version
  upgrade [--check]           Update to the newest release (--check only reports; exit 10 = update available)
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
    if [ "$#" -eq 0 ]; then
        if [ -t 0 ] && [ -t 1 ]; then cmd_select; else usage; fi
        return 0
    fi
    _cmd=$1; shift

    _n=$#; _i=0
    while [ "$_i" -lt "$_n" ]; do
        _a=$1; shift; _i=$((_i + 1))
        case $_a in
            -y|--yes) YES=1 ;;
            --all)    ALL=1 ;;
            --purge)  PURGE=1 ;;
            --load)   LOAD=1 ;;
            --check)  CHECK_ONLY=1 ;;
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
        select|pick)       cmd_select ;;
        conflicts|conflict) cmd_conflicts ;;
        add|enable)        cmd_add "$@" ;;
        remove|rm|disable) cmd_remove "$@" ;;
        update)            cmd_update "$@" ;;
        new)               cmd_new "$@" ;;
        install)           cmd_install ;;
        status)            cmd_status ;;
        check|test)        cmd_check "$@" ;;
        version|--version|-V) cmd_version ;;
        upgrade)           cmd_upgrade ;;
        uninstall)         cmd_uninstall ;;
        help|-h|--help)    usage ;;
        *)                 usage >&2; exit 1 ;;
    esac
}

main "$@"; exit $?
