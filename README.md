# aliases-setup

Opt-in packages of bash aliases and functions. Enable only the ones you want; remove them or the whole tool at any time.

```bash
./setup.sh list              # see packages and what each provides
./setup.sh add tmux core     # enable some (or `add` alone to pick interactively, `add --all` for everything)
./setup.sh remove tmux       # disable one
./setup.sh status            # check install health
./setup.sh uninstall         # remove everything this tool added
```

After the first `add`, the same commands are available from any shell as `aliases-setup <command>`, and `myhelp` lists every enabled command.

## How it works

```
~/.bashrc                              one marked block, nothing else
  └─ sources ~/.config/aliases-setup/init.sh        (copied from lib/, guarded: interactive shells only)
       └─ sources ~/.config/aliases-setup/enabled/*.sh   (symlinks into this repo's packages/)
```

- **Least intrusive:** `~/.bashrc` gets a single block between `# >>> aliases-setup >>>` / `# <<< aliases-setup <<<`. A one-time backup is kept in `~/.config/aliases-setup/rc.backup`. If `~/.bashrc` is a symlink (dotfile managers), the target is edited and the link is preserved. Nothing touches `~/.bashrc.d`.
- **Safe to change later:** enabled packages are symlinks to `packages/*.sh`, so editing a package takes effect in the next shell. Deleting or renaming a package, or moving the repo, leaves a dangling link that the loader silently skips, so your shell still starts. `list` flags such links, and `add` re-points them. `add` refuses packages that fail `bash -n`.
- **Clean removal:** `uninstall` deletes the marked block and `~/.config/aliases-setup/`; your repo is untouched. Already-open shells keep their aliases until restarted.
- Honours `XDG_CONFIG_HOME`. Set `ALIASES_SETUP_RC=/path/to/file` to manage a file other than `~/.bashrc`.

## Writing a package

Drop a `.sh` file in `packages/`:

```bash
# DESCRIPTION: One line shown by `list`
# REQUIRES: git            (optional; warns on `add` if missing)

gs() {
    # DESC: Shown by myhelp (comment on the line after the function)
    git status "$@"
}
alias gl='git log --oneline' # DESC: Shown by myhelp (trailing comment)
```

Keep packages to plain `alias`/function definitions: they are sourced into your interactive shell, so avoid side effects at load time.
