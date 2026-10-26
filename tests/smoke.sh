#!/bin/sh
# End-to-end smoke test: install into a throwaway HOME, load the packages in
# bash (and zsh if present), then uninstall and confirm the rc files are restored.
# Run it with `sh tests/smoke.sh`; CI runs it on Linux and macOS.
# BASH_BIN picks the bash to test with (CI uses /bin/bash on macOS, which is 3.2).
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
SETUP="$REPO/setup.sh"
BASH_BIN=${BASH_BIN:-bash}
T=$(mktemp -d "${TMPDIR:-/tmp}/aliases-smoke.XXXXXX")
trap 'rm -rf "$T"' EXIT
HOME=$T; export HOME
unset XDG_CONFIG_HOME ZDOTDIR ALIASES_SETUP_RC
CONF=$HOME/.config/aliases-setup

fails=0
t() { # <name> <command...>
    _name=$1; shift
    if "$@" >"$T/out" 2>&1; then
        printf 'ok   %s\n' "$_name"
    else
        printf 'FAIL %s\n' "$_name"; sed 's/^/       /' "$T/out"; fails=$((fails + 1))
    fi
}
norm() { awk '1' "$1"; }   # ignore a missing trailing newline
same() { [ "$(norm "$1")" = "$(norm "$2")" ]; }

# rc files for every shell setup.sh may touch, with content that must survive
for f in .bashrc .bash_profile .zshrc; do printf 'alias keep_%s=true\n# no newline at end' "${f#.}" > "$HOME/$f"; cp "$HOME/$f" "$T/orig$f"; done

load_bash() {
    "$BASH_BIN" --norc -i -c '. "$HOME/.config/aliases-setup/init.sh"
        type tn gst mkcd ibex-cpu >/dev/null && myhelp | grep -q "Git"' </dev/null
}
load_zsh() {
    zsh -f -i -c '. "$HOME/.config/aliases-setup/init.sh"
        whence -w tn gst mkcd ibex-cpu >/dev/null && myhelp | grep -q "Git"' </dev/null
}
restored() {
    for f in .bashrc .bash_profile .zshrc; do same "$T/orig$f" "$HOME/$f" || return 1; done
}

t "version is well formed"        sh -c "grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\$' '$REPO/VERSION'"
t "check --load passes"           "$SETUP" check --load
t "add --all for both shells"     "$SETUP" add --all --shell all -y
t "loader installed"              test -f "$CONF/init.sh"
t "loads in bash"                 load_bash
if command -v zsh >/dev/null 2>&1; then t "loads in zsh" load_zsh; else echo "skip loads in zsh (not installed)"; fi
t "no conflicts between packages" "$SETUP" conflicts --all
t "status runs"                   "$SETUP" status
t "remove one package"            "$SETUP" remove tmux
t "removed package is gone"       sh -c "! test -e '$CONF/enabled/tmux.sh'"
t "new custom package"            "$SETUP" new smoke
t "custom package passes check"   "$SETUP" check smoke --load
t "uninstall --purge"             "$SETUP" uninstall --purge -y
t "config dir removed"            sh -c "! test -e '$CONF'"
t "rc files restored"             restored

if [ "$fails" -ne 0 ]; then printf '\n%d test(s) failed.\n' "$fails"; exit 1; fi
printf '\nAll smoke tests passed.\n'
