# aliases-setup

Opt-in packages of aliases and functions for **bash and zsh**, on **Linux and macOS**. Enable only the ones you want, add your own or download someone else's, and remove it all cleanly at any time.

```bash
./setup.sh list                       # packages and what each provides
./setup.sh add git nav utils          # enable some (or `add` alone to pick interactively, `add --all`)
./setup.sh add https://example.com/my-aliases.sh   # download a package (you review the code first)
./setup.sh remove git                 # disable one
./setup.sh uninstall                  # remove everything this tool added
```

After the first `add`, the same commands work from any shell as `aliases-setup <command>`, and `myhelp` (core package) lists every enabled command.

## Packages

| Package | What it gives you |
|---|---|
| `core` | `myhelp`, `reloadalias` |
| `git` | `gst`, `gl`, `gd`, `gcm`, `gcb`, `gundo`, `gprune`, ... |
| `nav` | `..`, `...`, `ll`, `la`, `mkcd`, `up`, coloured `ls` (GNU and BSD) |
| `safety` | Prompt before `rm`/`cp`/`mv`/`ln` overwrite or delete |
| `docker` | `dps`, `dex`, `dlogs`, `dc` (compose v1/v2), `dclean`, ... |
| `net` | `myip`, `localip`, `ports`, `serve`, `headers`, `pingg` |
| `sysinfo` | `memtop`, `cputop`, `meminfo`, `diskhog`, `psg`, human-readable `df`/`du` |
| `pkg` | `pkgup`/`pkgi`/`pkgs`/`pkgr` over apt, dnf, pacman, zypper, apk or Homebrew |
| `utils` | `extract`, `backup`, `paths`, `o` (open), `clip` (clipboard) |
| `node` / `python` | npm and pip/venv shortcuts |
| `tmux` | `tn`, `ta`, `tk`, `tl`, `tka` |
| `ibex` | KAUST Ibex / Slurm queue, session and quota shortcuts |

## How it works

```
~/.bashrc  (bash on Linux)           one marked block, nothing else
~/.bash_profile (bash on macOS)
~/.zshrc   (zsh)
  └─ sources ~/.config/aliases-setup/init.sh          (copied from lib/; interactive shells only)
       └─ sources ~/.config/aliases-setup/enabled/*.sh   (symlinks to package files)
```

- **Least intrusive:** your rc file gets a single block between `# >>> aliases-setup >>>` and `# <<< aliases-setup <<<`, and a one-time backup goes in `~/.config/aliases-setup/backup/`. If the rc file is a symlink (dotfile managers), the real file is edited and the link kept. The default target follows your login shell; use `--shell bash|zsh|all` to choose, or `ALIASES_SETUP_RC=/path` for a specific file.
- **Safe to change later:** enabled packages are symlinks, so edits apply to your next shell. Deleting or renaming a package, or moving the repo, leaves a dangling link that the loader silently skips. Your shell still starts, `list` flags it, and `add` repoints it. `add` refuses a package that doesn't parse.
- **Portable:** `setup.sh` is POSIX `sh` (works with macOS's old bash 3.2, dash, etc.). Packages avoid GNU-only flags and branch on the OS where Linux and macOS differ. On macOS, bash reads `~/.bash_profile` for login shells, so that's what gets the block.
- **Clean removal:** `uninstall` removes the block from every rc file it touched and deletes `~/.config/aliases-setup/`, except your own and downloaded packages (`~/.config/aliases-setup/packages/`) unless you pass `--purge`. Packages in this repo are never touched. Open shells keep their aliases until restarted.

## Writing your own package

```bash
./setup.sh new mytools     # creates ~/.config/aliases-setup/packages/mytools.sh from template/package.sh
$EDITOR ~/.config/aliases-setup/packages/mytools.sh
./setup.sh add mytools
```

The template (`template/package.sh`) documents the conventions: a `# DESCRIPTION:` header, optional `# REQUIRES:` commands, `# DESC:` comments so `myhelp` can describe each command, and portability tips (avoid bash-only syntax; GNU vs BSD flags). To contribute one to this repo, put the file in `packages/` instead. A file in `~/.config/aliases-setup/packages/` with the same name as a built-in one takes precedence.

## Sharing and downloading packages

Host a package file anywhere over https (a GitHub repo, a gist) and install it with:

```bash
./setup.sh add https://github.com/someone/dotfiles/blob/main/aliases/k8s.sh   # GitHub page links are converted to raw URLs
./setup.sh add https://example.com/k8s.sh --name kube                          # pick the package name
./setup.sh update                                                              # re-download; shows a diff before applying
```

**A package is code that runs in every shell you open**, so `add <url>` prints the whole file and asks before installing; `update` shows a diff first. Only https is accepted (including redirects), the file must parse in bash (and zsh if installed), and downloads are capped at 256 KB. Pass `-y` only for sources you trust. Downloaded files are stored locally, so a later change at the URL never affects you until you run `update`.
