# DESCRIPTION: Peek into data files: JSONL and CSV, plain or compressed (.gz, .zst)
# REQUIRES: jq

_data_cat() { # <file>: print a file, decompressing .gz and .zst on the fly
    case "$1" in
        *.gz) gzip -dc -- "$1" ;;
        *.zst) zstd -dc -- "$1" ;;
        *) cat -- "$1" ;;
    esac
}

_data_file() { # <file> <usage>: complain unless it's a readable file
    if [ -z "$1" ]; then echo "Usage: $2" >&2; return 2; fi
    if [ ! -r "$1" ]; then echo "Can't read: $1" >&2; return 1; fi
}

nlines() {
    # DESC: Count lines (records, for JSONL) in a file, even compressed. Usage: nlines <file>
    _data_file "$1" "nlines <file>" || return
    _data_cat "$1" | wc -l | tr -d ' '
}

jl() {
    # DESC: Pretty-print the first N records of a JSONL file (default 3). Usage: jl <file> [n]
    _data_file "$1" "jl <file> [n]" || return
    _data_cat "$1" | head -n "${2:-3}" | jq .
}

jlkeys() {
    # DESC: Keys and their types across the first N records of a JSONL file (default 1000). Usage: jlkeys <file> [n]
    _data_file "$1" "jlkeys <file> [n]" || return
    _data_cat "$1" | head -n "${2:-1000}" |
        jq -r 'objects | to_entries[] | "\(.key)\t\(.value | type)"' |
        sort | uniq -c | sort -rn | awk '{ printf "%8s  %-30s %s\n", $1, $2, $3 }'
}

csvhead() {
    # DESC: First N rows of a CSV as an aligned table (default 10). Usage: csvhead <file> [n]
    _data_file "$1" "csvhead <file> [n]" || return
    _data_cat "$1" | head -n "${2:-10}" | column -t -s,
}

csvcols() {
    # DESC: Number the columns of a CSV from its header row. Usage: csvcols <file>
    _data_file "$1" "csvcols <file>" || return
    _data_cat "$1" | head -n 1 | tr ',' '\n' | awk '{ printf "%3d  %s\n", NR, $0 }'
}
