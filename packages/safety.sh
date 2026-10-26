# DESCRIPTION: Ask before overwriting or deleting files
#
# Bypass any of these for one command with a backslash, e.g. \rm file

# GNU rm has -I (one prompt for 3+ files); BSD/macOS rm only has -i.
_safety_rm='rm -i'
if rm --version >/dev/null 2>&1; then _safety_rm='rm -I'; fi
alias rm="$_safety_rm" # DESC: Prompt before deleting
unset _safety_rm

alias cp='cp -i' # DESC: Prompt before overwriting
alias mv='mv -i' # DESC: Prompt before overwriting
alias ln='ln -i' # DESC: Prompt before replacing links
alias mkdir='mkdir -p' # DESC: Create parent directories, no error if it exists
