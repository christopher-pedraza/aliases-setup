# DESCRIPTION: One line describing __NAME__ (shown by `setup.sh list`)
# REQUIRES:
#
# ---------------------------------------------------------------------------
# aliases-setup package template. Delete these comments once you're done.
#
# HOW IT WORKS
#   - This file is sourced by every interactive bash/zsh shell once the package
#     is enabled (`./setup.sh add __NAME__`). Edits apply to the next shell.
#   - Header fields (all optional):
#       DESCRIPTION  shown in `list`
#       REQUIRES     space-separated commands; `add` warns if one is missing
#   - `myhelp` (core package) lists any function whose FIRST body line is a
#     `# DESC:` comment, and any alias with a trailing `# DESC:` comment.
#
# SHARE IT
#   - Host the file anywhere over https, e.g. a GitHub repo or gist; others
#     install it with:  ./setup.sh add https://.../__NAME__.sh
#   - Or open a PR adding it to packages/ in this repo.
#
# WRITING PORTABLE CODE (works on Linux + macOS, in bash + zsh)
#   - Define only aliases, functions and simple variables. No output, prompts
#     or slow commands at load time; they run on every new shell.
#   - Avoid bash-only features: arrays, `read -p`, `${!var}`, BASH_SOURCE,
#     `echo -e`. Use `printf` instead of `echo -e`.
#   - macOS has BSD tools: `sed -i`, `ls --color`, `ps --sort`, `readlink -f`,
#     `xargs -r` and `date -d` are GNU-only. Branch on `uname -s` when needed.
#   - Prefix private helpers with `_` and no DESC so they stay out of `myhelp`.
#   - Quote "$@" and "$1". Single-quote aliases that use $VARS so they expand
#     when run, not when the shell starts.
# ---------------------------------------------------------------------------

__NAME__hello() {
    # DESC: Example function. Usage: __NAME__hello [name]
    printf 'Hello, %s!\n' "${1:-world}"
}

alias __NAME__ll='ls -lah' # DESC: Example alias
