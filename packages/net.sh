# DESCRIPTION: Network info and quick local servers (Linux and macOS)

alias pingg='ping -c 4 1.1.1.1' # DESC: Quick connectivity check (4 pings to 1.1.1.1)

myip() {
    # DESC: Show your public IP address
    curl -fsS https://api.ipify.org && echo
}

localip() {
    # DESC: Show your local (LAN) IP address
    if [ "$(uname -s)" = Darwin ]; then
        ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1
    else
        hostname -I 2>/dev/null | awk '{ print $1 }'
    fi
}

ports() {
    # DESC: List listening TCP/UDP ports
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn
    elif command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP -sTCP:LISTEN
    else
        netstat -an | grep LISTEN
    fi
}

serve() {
    # DESC: Serve the current directory over HTTP. Usage: serve [port]
    python3 -m http.server "${1:-8000}"
}

headers() {
    # DESC: Show HTTP response headers. Usage: headers <url>
    if [ -z "$1" ]; then echo "Usage: headers <url>" >&2; return 1; fi
    curl -sSIL "$1"
}
