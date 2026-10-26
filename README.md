# aliases-setup

Opt-in packages of aliases and functions for **bash and zsh**, on **Linux and macOS**. Enable only the ones you want, add your own or download someone else's, and remove it all cleanly at any time.

```bash
./setup.sh                            # checkbox list: toggle packages on/off, enter to apply
./setup.sh list                       # packages and what each provides
./setup.sh add git nav utils          # enable some directly (or `add --all`)
./setup.sh add https://example.com/my-aliases.sh   # download a package (you review the code first)
./setup.sh remove git                 # disable one
./setup.sh uninstall                  # remove everything this tool added
```

In the checkbox list, `up`/`down` (or `j`/`k`) move, `space` toggles, `a` selects or clears all, `enter` applies and `q`/`esc` cancels. Packages that are already enabled start checked, so unchecking one disables it. It's plain POSIX sh with no dependencies, scrolls in small terminals, and falls back to simple `y/N` prompts on terminals without escape-code support (`TERM=dumb`).

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
| `utils` | `extract` (tar.gz/bz2/xz/zst, zip, gz, bz2, xz, zst, 7z, rar), `backup`, `paths`, `o` (open), `clip` (clipboard) |
| `node` / `python` | npm and pip/venv shortcuts |
| `uv` | `uvs` (sync), `uvr` (run), `uva`/`uvrm` (add/remove), `uvnew`, `uvenv`, `uvup`, ... for [uv](https://docs.astral.sh/uv/) |
| `tmux` | `tn`, `ta`, `tk`, `tl`, `tka` |
| `ibex` | KAUST Ibex: `ibex-cpu`, `ibex-gpu`, `ibex-mover` ssh logins (set `export IBEX_USER=<your-kaust-id>` first), plus Slurm queue, session and quota shortcuts |

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

Run `./setup.sh check mytools` to validate it. A package can use tools you don't have installed: `# REQUIRES:` only makes `add` print a warning, and the commands are still defined (they fail with the usual "command not found" if you run them without the tool, or with a friendlier message where a package checks, like `extract`). The template (`template/package.sh`) documents the conventions: a `# DESCRIPTION:` header, optional `# REQUIRES:` commands, `# DESC:` comments so `myhelp` can describe each command, and portability tips (avoid bash-only syntax; GNU vs BSD flags). To contribute one to this repo, put the file in `packages/` instead. A file in `~/.config/aliases-setup/packages/` with the same name as a built-in one takes precedence.

## Updating

```bash
./setup.sh version              # which version you have
./setup.sh upgrade --check      # is there a newer release? (exit code 10 = yes, 0 = up to date)
./setup.sh upgrade              # show what changed, then update
```

Releases are git tags (`vX.Y.Z`) that CI creates; `upgrade` fast-forwards your checkout to the newest one, so you get exactly the released code rather than whatever is on `main`. It refuses if you have uncommitted changes or local commits that can't be fast-forwarded, and it needs a git checkout of this repo (it prints where to download a release otherwise).

**What happens to packages you already enabled?** They're symlinks into the repo, so an updated package is live in your next shell with nothing to reinstall, and new commands in it (say, new `ibex` aliases) just appear. `upgrade` then tells you which packages were updated, which are new (new packages are never enabled for you), and which were removed upstream while still enabled (`remove` clears those). It also refreshes the copied loader (`~/.config/aliases-setup/init.sh`) and warns about any new name conflicts. Packages you downloaded from a URL are separate: update those with `./setup.sh update`. A plain `git pull` works too; `./setup.sh status` then tells you if the loader needs a refresh (`./setup.sh install`).

## Releases and CI

`.github/workflows/ci.yml` runs on every push and pull request on Linux and macOS: `./setup.sh check --load` plus `tests/smoke.sh` (install, load in bash and zsh, uninstall, confirm your rc files are restored). On `main`, if the number in `VERSION` has no release yet, it creates one with generated notes. **To release: change `VERSION` (e.g. `0.2.0`), merge to `main`.** Both legs must pass before a release is created. If the macOS leg ever fails because the runner image changed rather than your code, re-run it or pin the runner (e.g. `macos-14`).

## Conflicts

Packages load in name order and a later definition silently replaces an earlier one, so two packages defining the same alias or function is a trap. Three places catch it:

- **In the checkbox list:** when two *checked* packages define the same name, both rows get a `!` and a `! conflict: gst (clash,git)` line appears, so you can uncheck one right there. Nothing is applied until you press enter.
- **After `add` / `select`:** a short note lists any conflicts among enabled packages.
- **`./setup.sh conflicts`** (`--all` to analyse every package, enabled or not) prints the full picture and exits non-zero if there are name conflicts:
  - which packages define each name, which one wins, and the exact `./setup.sh remove ...` command to keep each side;
  - different alias names with an identical value (redundant but harmless);
  - names that hide a real program on your `PATH` (like `dc` the calculator), so you know to reach it with `\dc` or `command dc`;
  - names you also defined in your own rc files, and whether yours or the package wins (it depends on whether your line is before or after the aliases-setup block).

`./setup.sh check` also reports conflicts between all packages as warnings, and flags a name defined twice inside one file.

## Checking packages

```bash
./setup.sh check                       # every package, the template, and the tool's own scripts
./setup.sh check git ./mine.sh         # a package name or a file path
./setup.sh check https://example.com/k8s.sh   # download and check without installing
./setup.sh check --load                # also source each file in a throwaway HOME (bash and zsh)
```

It exits non-zero on any error, so it works in CI or a pre-commit hook. **Errors** (the file is rejected): it doesn't parse in bash or zsh; it's empty, binary or an HTML page; it has a top-level `exit` or `set -e/-u/-o`, which would close or alter your shell; with `--load`, it fails or prints anything when sourced. **Warnings**: bash-only or GNU-only constructs that break on macOS or zsh (`echo -e`, `sed -i`, `readlink -f`, arrays, ...), a missing `# DESCRIPTION:`, and commands without a `# DESC:` that `myhelp` can't describe. Tag a deliberate line with `# lint:ok` to silence the portability warnings for it.

Without `--load` nothing in the file is ever executed, so it's safe on untrusted files. `add` runs the same checks before enabling anything and refuses a package with errors, including downloaded ones.

## Sharing and downloading packages

Host a package file anywhere over https (a GitHub repo, a gist) and install it with:

```bash
./setup.sh add https://github.com/someone/dotfiles/blob/main/aliases/k8s.sh   # GitHub page links are converted to raw URLs
./setup.sh add https://example.com/k8s.sh --name kube                          # pick the package name
./setup.sh update                                                              # re-download; shows a diff before applying
```

**A package is code that runs in every shell you open**, so `add <url>` prints the whole file and asks before installing; `update` shows a diff first. Only https is accepted (including redirects), the file must pass `check` (it must parse in bash, and zsh if installed), and downloads are capped at 256 KB. Pass `-y` only for sources you trust. Downloaded files are stored locally, so a later change at the URL never affects you until you run `update`.
