# DESCRIPTION: Help menu and a reload shortcut for aliases-setup

myhelp() {
    # DESC: [cyan] Show or search commands from enabled packages. Usage: myhelp [-a] [-p] [-s] [pkg|query...]
    if [ -n "${ZSH_VERSION-}" ]; then setopt localoptions nullglob; fi
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup"
    local enabled_dir="$conf/enabled" user_dir="$conf/packages" repo=""
    local show_all=0 list_pkgs=0 force_search=0 tty=0 cols=0
    local f tab

    [ -r "$conf/repo" ] && repo=$(cat "$conf/repo" 2>/dev/null)
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -a|--all)      show_all=1; shift ;;
            -p|--packages) list_pkgs=1; shift ;;
            -s|--search)   force_search=1; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: myhelp [options] [package | search terms...]

  myhelp                 Show all commands from enabled packages
  myhelp <pkg>           Show commands in a specific package (e.g. myhelp git)
  myhelp <term>...       Search command names, descriptions, and packages
  myhelp -p              List enabled packages with command counts
  myhelp -a [filter]     Include available (disabled) packages from the repo
  myhelp -s <term>...    Search everywhere even if <term> matches a package name

Colors: cyan = inspect/read-only, green = action, yellow = caution/cleanup, red = danger
EOF
                return 0 ;;
            --) shift; break ;;
            -*)
                echo "myhelp: unknown option '$1' (see: myhelp -h)" >&2
                return 1 ;;
            *) break ;;
        esac
    done

    if [ -t 1 ]; then
        tty=1
        cols=${COLUMNS:-0}
        case $cols in ''|*[!0-9]*|0)
            cols=$(stty size 2>/dev/null | awk '{ print $2 }')
            case $cols in ''|*[!0-9]*|0) cols=80 ;; esac ;;
        esac
    fi
    tab=$(printf '\t')

    {
        for f in "$enabled_dir"/*.sh; do
            [ -r "$f" ] && printf '%s\t%s\tenabled\n' "$(basename "$f" .sh)" "$f"
        done
        if [ "$show_all" -eq 1 ]; then
            for f in "$user_dir"/*.sh; do
                [ -r "$f" ] && printf '%s\t%s\tavailable\n' "$(basename "$f" .sh)" "$f"
            done
            if [ -n "$repo" ]; then
                for f in "$repo"/packages/*.sh; do
                    [ -r "$f" ] && printf '%s\t%s\tavailable\n' "$(basename "$f" .sh)" "$f"
                done
            fi
        fi
    } | awk -F'\t' '!seen[$1]++' | sort -t"$tab" -k1,1 | awk -F'\t' \
        -v tty="$tty" -v cols="$cols" -v list_pkgs="$list_pkgs" \
        -v force_search="$force_search" -v show_all="$show_all" \
        -v query="$*" '
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
        function cwrap(code, txt) {
            if (!tty) return txt
            return "\033[" code "m" txt "\033[0m"
        }
        function wrap_desc(txt, indent, width,    n, w, i, line, out) {
            if (!tty || width <= indent + 12) return txt
            n = split(txt, w, /[ \t]+/)
            line = ""; out = ""
            for (i = 1; i <= n; i++) {
                if (w[i] == "") continue
                if (line == "") {
                    line = w[i]
                } else if (indent + length(line) + 1 + length(w[i]) <= width) {
                    line = line " " w[i]
                } else {
                    out = out (out != "" ? "\n" pad(indent) : "") line
                    line = w[i]
                }
            }
            if (line != "") out = out (out != "" ? "\n" pad(indent) : "") line
            return out
        }
        function pad(n,    r) { r = ""; while (n-- > 0) r = r " "; return r }
        function parse_cmd(name, desc, pkg_color,    rb, tag, cc) {
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
            cmd_n++
            c_pkg[cmd_n] = npkg
            c_cc[cmd_n] = cc
            c_name[cmd_n] = name
            c_desc[cmd_n] = desc
            p_cnt[npkg]++
        }
        function match_all(hay,    i) {
            hay = tolower(hay)
            for (i = 1; i <= nw; i++) {
                if (index(hay, words[i]) == 0) return 0
            }
            return 1
        }
        function pkg_title(idx,    t) {
            t = toupper(substr(p_name[idx], 1, 1)) substr(p_name[idx], 2)
            if (p_state[idx] == "available") return "--- " t " (available) ---"
            return "--- " t " ---"
        }
        BEGIN {
            npkg = 0; cmd_n = 0
            nw = split(tolower(query), words, /[ \t]+/)
            if (nw == 1 && words[1] == "") nw = 0
        }
        {
            npkg++
            p_name[npkg] = $1
            p_file[npkg] = $2
            p_state[npkg] = $3
            p_desc[npkg] = ""
            p_req[npkg] = ""
            p_cnt[npkg] = 0
            pkg_color = ""
            fname = ""
            while ((getline line < $2) > 0) {
                if (line ~ /^# DESCRIPTION: */ && p_desc[npkg] == "") {
                    d = line; sub(/^# DESCRIPTION: */, "", d); p_desc[npkg] = d; continue
                }
                if (line ~ /^# REQUIRES: */ && p_req[npkg] == "") {
                    r = line; sub(/^# REQUIRES: */, "", r); p_req[npkg] = r; continue
                }
                if (line ~ /^# COLOR: */) {
                    c = line; sub(/^# COLOR: */, "", c); sub(/ .*/, "", c)
                    c = color_code(c)
                    if (c != "") pkg_color = c
                    continue
                }
                if (fname != "" && line ~ /# DESC:/) {
                    d = line; sub(/.*# DESC: */, "", d)
                    parse_cmd(fname, d, pkg_color)
                    fname = ""; continue
                }
                fname = ""
                if (line ~ /^[A-Za-z0-9_-]+\(\) *\{/) {
                    fname = line; sub(/\(\).*/, "", fname); continue
                }
                if (line ~ /^alias .*# DESC:/) {
                    nm = line; sub(/^alias +/, "", nm); sub(/=.*/, "", nm)
                    ds = line; sub(/.*# DESC: */, "", ds)
                    parse_cmd(nm, ds, pkg_color)
                }
            }
            close($2)
        }
        END {
            if (npkg == 0) {
                print "No enabled packages. Enable some with: aliases-setup"
                exit 0
            }
            if (list_pkgs) {
                print "=================== PACKAGES =========================="
                for (i = 1; i <= npkg; i++) {
                    if (nw > 0 && !match_all(p_name[i] " " p_desc[i])) continue
                    st = (p_state[i] == "available" ? " [available]" : "")
                    printf "  %s %-10s %s%s\n", cwrap("1;36", sprintf("%-13s", p_name[i])), "(" p_cnt[i] " cmds)", p_desc[i], cwrap("2", st)
                }
                print "======================================================="
                exit 0
            }

            exact_pkg = 0
            if (!force_search && nw == 1) {
                for (i = 1; i <= npkg; i++) {
                    if (tolower(p_name[i]) == words[1]) { exact_pkg = i; break }
                }
            }

            shown_cmds = 0; shown_pkgs = 0
            if (nw == 0) print "=================== CUSTOM COMMANDS ==================="
            for (i = 1; i <= npkg; i++) {
                if (exact_pkg > 0 && i != exact_pkg) continue
                pkg_printed = 0
                for (j = 1; j <= cmd_n; j++) {
                    if (c_pkg[j] != i) continue
                    if (exact_pkg == 0 && nw > 0) {
                        if (!match_all(p_name[i] " " p_desc[i] " " c_name[j] " " c_desc[j])) continue
                    }
                    if (!pkg_printed) {
                        pkg_printed = 1; shown_pkgs++
                        printf "\n%s", cwrap("1;36", pkg_title(i))
                        if ((exact_pkg > 0 || nw > 0) && p_desc[i] != "") {
                            printf "  %s", cwrap("2", p_desc[i])
                        }
                        printf "\n"
                        if (exact_pkg > 0 && p_req[i] != "") {
                            printf "  %s\n", cwrap("2", "Requires: " p_req[i])
                        }
                        if (exact_pkg > 0 && p_state[i] == "available") {
                            printf "  %s\n", cwrap("1;33", "Not enabled yet. Enable with: aliases-setup add " p_name[i])
                        }
                    }
                    nm_pad = sprintf("%-15s", c_name[j])
                    printf "  %s %s\n", cwrap(c_cc[j], nm_pad), wrap_desc(c_desc[j], 18, cols)
                    shown_cmds++
                }
            }
            if (shown_cmds == 0) {
                printf "No matching commands for \"%s\".\n", query
                if (!show_all) {
                    print cwrap("2", "Tip: try `myhelp -a " query "` to search disabled packages, or `myhelp -p` to list packages.")
                }
                exit 1
            }
            if (nw == 0) {
                printf "\n=======================================================\n"
                printf "%s\n", cwrap("2", shown_cmds " commands in " shown_pkgs " packages  |  myhelp <pkg|term> to filter  |  myhelp -h for options")
            } else {
                printf "\n%s\n", cwrap("2", shown_cmds " command(s) in " shown_pkgs " package(s)")
            }
        }
    '
}

reloadalias() {
    # DESC: Reload enabled packages in this shell (removed ones need a new shell)
    . "${XDG_CONFIG_HOME:-$HOME/.config}/aliases-setup/init.sh"
}
