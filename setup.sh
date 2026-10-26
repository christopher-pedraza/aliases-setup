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
trap 'restore_tty; [ -z "$WORK" ] || rm -rf "$WORK"' EXIT

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
        stty "$TTY_SAVED" 2>/dev/null || stty sane
        printf '\033[?25h'
        TTY_SAVED=
    fi
}

read_key() { # prints UP DOWN SPACE ENTER ALL QUIT or OTHER
    _h=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case $_h in
        1b) # an arrow key is ESC [ A / ESC O A; a lone ESC means "cancel"
            stty min 0 time 1
            _h2=$(dd bs=1 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
            stty min 1 time 0
            case $_h2 in
                5b41|4f41) echo UP ;;
                5b42|4f42) echo DOWN ;;
                '')        echo QUIT ;;
                *)         echo OTHER ;;
            esac ;;
        20)       echo SPACE ;;
        0a|0d)    echo ENTER ;;
        6b)       echo UP ;;      # k
        6a)       echo DOWN ;;    # j
        61)       echo ALL ;;     # a
        71|51|04|'') echo QUIT ;; # q, Q, Ctrl-D, end of input
        *)        echo OTHER ;;
    esac
}

pick_get() { eval "_g=\$$1_$2"; } # <prefix> <index> -> $_g

pick_draw() {
    if [ "$PICK_DRAWN" -eq 1 ]; then printf '\033[%dA' "$PICK_LINES"; fi
    PICK_DRAWN=1
    _w=$((COLS - 1))
    _dw=$((COLS - 22)); if [ "$_dw" -lt 10 ]; then _dw=10; fi

    # Which selected packages define the same name?
    _sel=; _i=1
    while [ "$_i" -le "$N" ]; do
        pick_get PS "$_i"
        if [ "$_g" -eq 1 ]; then pick_get PN "$_i"; _sel="$_sel $_g"; fi
        _i=$((_i + 1))
    done
    _cf=$(pick_conflicts "$PICK_TBL" "$_sel")
    _cpk=" $(printf '%s\n' "$_cf" | cut -f2 | tr ',' ' ' | tr '\n' ' ') "

    if [ "$CUR" -lt "$TOP" ]; then TOP=$CUR; fi
    if [ "$CUR" -ge $((TOP + VIS)) ]; then TOP=$((CUR - VIS + 1)); fi

    printf '\r\033[K%sSelect packages%s\n' "${ESC}[1m" "$C_OFF"
    printf '\r\033[K%s%s%s\n' "$C_DIM" "$(printf '%s' "up/down or j/k: move   space: toggle   a: all/none   enter: apply   q: cancel   !: conflict" | cut -c1-"$_w")" "$C_OFF"

    _i=$TOP
    while [ "$_i" -lt $((TOP + VIS)) ]; do
        pick_get PN "$_i"; _n=$_g
        pick_get PD "$_i"; _d=$_g
        pick_get PL "$_i"; _l=$_g
        pick_get PS "$_i"; _s=$_g
        if [ "$_s" -eq 1 ]; then _box="${C_OK}[x]${C_OFF}"; else _box="[ ]"; fi
        _text=$(printf '%s%s' "$_d" "$_l" | cut -c1-"$_dw")
        case $_cpk in *" $_n "*) _flag="${C_WARN}!${C_OFF}" ;; *) _flag=' ' ;; esac
        if [ "$_i" -eq "$CUR" ]; then
            printf '\r\033[K> %s %s %s%-12s%s %s\n' "$_flag" "$_box" "${ESC}[1m" "$_n" "$C_OFF" "$_text"
        else
            printf '\r\033[K  %s %s %-12s %s\n' "$_flag" "$_box" "$_n" "$_text"
        fi
        _i=$((_i + 1))
    done

    if [ "$TOP" -gt 1 ] || [ $((TOP + VIS - 1)) -lt "$N" ]; then
        printf '\r\033[K%s  (%d-%d of %d)%s\n' "$C_DIM" "$TOP" $((TOP + VIS - 1)) "$N" "$C_OFF"
    else
        printf '\r\033[K\n'
    fi

    pick_get PP "$CUR"
    printf '\r\033[K%s\n' "$(printf 'provides: %s' "$_g" | cut -c1-"$_w")"

    if [ -n "$_cf" ]; then
        printf '\r\033[K%s%s%s\n' "$C_WARN" "$(printf '%s\n' "$_cf" | awk -F'\t' '{ printf "%s%s (%s)", (NR > 1 ? "; " : ""), $1, $2 }' | sed 's/^/! conflict: /' | cut -c1-"$_w")" "$C_OFF"
    else
        printf '\r\033[K\n'
    fi

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
    if [ -z "$_chg" ]; then _chg=" no changes"; fi
    printf '\r\033[K%s\n' "$(printf 'pending:%s' "$_chg" | cut -c1-"$_w")"
}

pick_packages() {
    N=0
    for _p in $(pkg_names); do
        N=$((N + 1))
        _d=$(pkg_meta "$_p" DESCRIPTION)
        _l=$(pkg_label "$_p")
        _v=$(pkg_provides "$_p")
        if pkg_enabled "$_p"; then _on=1; else _on=0; fi
        eval "PN_$N=\$_p PD_$N=\$_d PL_$N=\$_l PP_$N=\$_v PI_$N=$_on PS_$N=$_on"
    done
    if [ "$N" -eq 0 ]; then info "No packages found."; return 0; fi

    _sz=$(stty size 2>/dev/null || true)
    ROWS=${_sz% *}; COLS=${_sz#* }
    case $ROWS in ''|*[!0-9]*) ROWS=24 ;; esac
    case $COLS in ''|*[!0-9]*) COLS=80 ;; esac
    VIS=$((ROWS - 7)); if [ "$VIS" -gt "$N" ]; then VIS=$N; fi; if [ "$VIS" -lt 3 ]; then VIS=3; fi
    if [ "$VIS" -gt "$N" ]; then VIS=$N; fi
    PICK_LINES=$((VIS + 6)); PICK_DRAWN=0; CUR=1; TOP=1
    ensure_work
    PICK_TBL="$WORK/pick.tbl"
    build_table "$(pkg_names | tr '\n' ' ')" > "$PICK_TBL"

    TTY_SAVED=$(stty -g)
    trap 'restore_tty; exit 130' INT TERM HUP
    stty -icanon -echo min 1 time 0
    printf '\033[?25l'
    pick_draw
    _done=
    while [ -z "$_done" ]; do
        case $(read_key) in
            UP)    CUR=$((CUR - 1)); if [ "$CUR" -lt 1 ]; then CUR=$N; fi ;;
            DOWN)  CUR=$((CUR + 1)); if [ "$CUR" -gt "$N" ]; then CUR=1; fi ;;
            SPACE) pick_get PS "$CUR"; eval "PS_$CUR=$((1 - _g))" ;;
            ALL)   _v=1; _i=1
                   while [ "$_i" -le "$N" ]; do pick_get PS "$_i"; if [ "$_g" -eq 0 ]; then _v=0; fi; _i=$((_i + 1)); done
                   _i=1  # everything already selected -> clear all, otherwise select all
                   while [ "$_i" -le "$N" ]; do eval "PS_$_i=$((1 - _v))"; _i=$((_i + 1)); done ;;
            ENTER) _done=apply ;;
            QUIT)  _done=cancel ;;
        esac
        if [ -z "$_done" ]; then pick_draw; fi
    done
    restore_tty
    printf '\033[%dA\r\033[J' "$PICK_LINES"   # erase the picker
    trap - INT TERM HUP

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
