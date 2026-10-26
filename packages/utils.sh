# DESCRIPTION: Everyday helpers: extract archives, back up files, open, clipboard, PATH

extract() {
    # DESC: Extract any common archive. Usage: extract <file>...
    if [ "$#" -eq 0 ]; then echo "Usage: extract <archive>..." >&2; return 1; fi
    local f
    for f in "$@"; do
        if [ ! -f "$f" ]; then echo "extract: '$f' is not a file" >&2; continue; fi
        case $f in
            *.tar.gz|*.tgz)   tar xzf "$f" ;;
            *.tar.bz2|*.tbz2) tar xjf "$f" ;;
            *.tar.xz|*.txz)   tar xJf "$f" ;;
            *.tar)            tar xf "$f" ;;
            *.zip)            unzip "$f" ;;
            *.gz)             gunzip "$f" ;;
            *.bz2)            bunzip2 "$f" ;;
            *.xz)             unxz "$f" ;;
            *.7z)             7z x "$f" ;;
            *.rar)            unrar x "$f" ;;
            *)                echo "extract: don't know how to extract '$f'" >&2 ;;
        esac
    done
}

backup() {
    # DESC: Copy a file to <file>.<timestamp>.bak. Usage: backup <file>
    if [ -z "$1" ]; then echo "Usage: backup <file>" >&2; return 1; fi
    cp -p -- "$1" "$1.$(date +%Y%m%d-%H%M%S).bak"
}

paths() {
    # DESC: Print PATH one entry per line
    printf '%s\n' "$PATH" | tr ':' '\n'
}

o() {
    # DESC: Open a file or URL with the default app. Usage: o [path] (default: .)
    if [ "$(uname -s)" = Darwin ]; then
        open "${1:-.}"
    else
        xdg-open "${1:-.}" >/dev/null 2>&1
    fi
}

clip() {
    # DESC: Copy stdin to the clipboard. Usage: echo hi | clip
    if command -v pbcopy >/dev/null 2>&1; then
        pbcopy
    elif command -v wl-copy >/dev/null 2>&1; then
        wl-copy
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard
    elif command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --input
    else
        echo "clip: install pbcopy, wl-copy, xclip or xsel" >&2
        return 1
    fi
}
