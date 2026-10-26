# DESCRIPTION: One set of package-manager commands for apt, dnf, pacman, zypper, apk and Homebrew

# Run a command as root unless we already are (brew must NOT run as root).
# Native managers are tried before brew so Linuxbrew doesn't hijack apt/dnf systems.
_pkg_su() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# _pkg <update|install|search|remove> [args...]
_pkg() {
    local action="$1"
    shift
    if command -v apt >/dev/null 2>&1; then
        case $action in
            update)  _pkg_su apt update && _pkg_su apt upgrade ;;
            install) _pkg_su apt install "$@" ;;
            search)  apt search "$@" ;;
            remove)  _pkg_su apt remove "$@" ;;
        esac
    elif command -v dnf >/dev/null 2>&1; then
        case $action in
            update)  _pkg_su dnf upgrade ;;
            install) _pkg_su dnf install "$@" ;;
            search)  dnf search "$@" ;;
            remove)  _pkg_su dnf remove "$@" ;;
        esac
    elif command -v pacman >/dev/null 2>&1; then
        case $action in
            update)  _pkg_su pacman -Syu ;;
            install) _pkg_su pacman -S "$@" ;;
            search)  pacman -Ss "$@" ;;
            remove)  _pkg_su pacman -Rs "$@" ;;
        esac
    elif command -v zypper >/dev/null 2>&1; then
        case $action in
            update)  _pkg_su zypper refresh && _pkg_su zypper update ;;
            install) _pkg_su zypper install "$@" ;;
            search)  zypper search "$@" ;;
            remove)  _pkg_su zypper remove "$@" ;;
        esac
    elif command -v apk >/dev/null 2>&1; then
        case $action in
            update)  _pkg_su apk update && _pkg_su apk upgrade ;;
            install) _pkg_su apk add "$@" ;;
            search)  apk search "$@" ;;
            remove)  _pkg_su apk del "$@" ;;
        esac
    elif command -v brew >/dev/null 2>&1; then
        case $action in
            update)  brew update && brew upgrade ;;
            install) brew install "$@" ;;
            search)  brew search "$@" ;;
            remove)  brew uninstall "$@" ;;
        esac
    else
        echo "No supported package manager found (brew, apt, dnf, pacman, zypper, apk)." >&2
        return 1
    fi
}

pkgup() {
    # DESC: Update package lists and upgrade installed packages
    _pkg update
}

pkgi() {
    # DESC: Install packages. Usage: pkgi <name>...
    if [ "$#" -eq 0 ]; then echo "Usage: pkgi <package>..." >&2; return 1; fi
    _pkg install "$@"
}

pkgs() {
    # DESC: Search for a package. Usage: pkgs <term>
    if [ "$#" -eq 0 ]; then echo "Usage: pkgs <term>" >&2; return 1; fi
    _pkg search "$@"
}

pkgr() {
    # DESC: Remove packages. Usage: pkgr <name>...
    if [ "$#" -eq 0 ]; then echo "Usage: pkgr <package>..." >&2; return 1; fi
    _pkg remove "$@"
}
