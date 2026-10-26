# DESCRIPTION: npm shortcuts
# REQUIRES: node npm

alias ni='npm install' # DESC: npm install
alias nr='npm run' # DESC: npm run <script>
alias nrd='npm run dev' # DESC: npm run dev
alias nrb='npm run build' # DESC: npm run build
alias nrt='npm test' # DESC: npm test
alias nx='npx' # DESC: npx

nid() {
    # DESC: Install as a dev dependency. Usage: nid <pkg>...
    if [ "$#" -eq 0 ]; then echo "Usage: nid <package>..." >&2; return 1; fi
    npm install --save-dev "$@"
}

nreinstall() {
    # DESC: Delete node_modules and install again
    rm -rf node_modules && npm install
}

nver() {
    # DESC: Show node and npm versions
    printf 'node %s\nnpm  %s\n' "$(node -v)" "$(npm -v)"
}
