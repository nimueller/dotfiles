# Working on this repository

Notes for anyone changing these dotfiles, human or AI. Everything here has to
stay maintainable by hand: plain tools, no generated code nobody can read, and
checks that run the same locally and in CI.

## Layout

| Path | What it holds |
|---|---|
| `flake.nix` | The Home Manager configurations, `nix fmt`, and the devShell with the check tools |
| `home-manager/` | Nix modules: `headless`, `desktop`, `dev`, `theme` |
| `pkgs/` | Small packages; `pkgs/scripts/` are the scripts built into commands (`pkgs/default.nix`) |
| `config/` | Configuration files linked into `~/.config`; `config/quickshell/menus` holds the Quickshell UI and its helper scripts |
| `system/` | The root side on Arch Linux: package lists and `setup.sh` |
| `tests/` | Unit tests of the Python scripts |

## Shell or Python

New scripts and rewrites follow these rules:

- **Python** for anything that parses output, computes, keeps state, handles
  files or runs several processes at once. Examples: `screenshot.py`,
  `shutdown.py`, `backlight.py`, `monitor-caps.py`, `scan.py`,
  `pkgs/scripts/discord-call-logs.py`.
- **Shell** (Bash) for short glue that mostly runs one or two commands, e.g.
  `toggle.sh`, `ipc.sh`, `paste.sh`, `osk.sh`, `stay-awake.sh`.
- **Shell, always**, where Python can't be counted on:
  - `install.sh` bootstraps a fresh machine (`curl … | bash`) and
    `system/setup.sh` runs before the session packages, which bring Python, are
    installed.
  - `system/bluetooth-address.sh` and `system/power-saver-cpu.sh` run as root
    from `/usr/local/lib` at boot, outside of Nix.
  - `pkgs/scripts/lock-screen.sh` is the lock screen: it stays as it is unless
    it can be tested on a real touch device.

## Python

- Only the standard library, apart from what a script's environment provides
  on purpose: PyGObject from the system (`python-gobject` in
  `system/packages/session.txt`), the calendar libraries from
  `quickshell-calendar-python` (`pkgs/default.nix`).
- Interpreter: the helpers in `config/quickshell/menus` run with the system's
  `python3` (`#!/usr/bin/env python3`). Commands in `pkgs/scripts` are built
  with `pkgs.writers.writePython3Bin` (no shebang in the file, `doCheck =
  false`: ruff and pyright check them here instead of flake8). Both are
  Python 3.14.
- Shape of a script, as in `backlight.py` or `screenshot.py`:
  - a module docstring with the usage lines and what the script is for;
    invalid arguments print it;
  - constants at the top, small functions, `main()` under
    `if __name__ == "__main__"`, so the tests can import the file;
  - `subprocess.run([...], check=False)` with a list of arguments, never
    `shell=True` (unless running a command the caller passed as a string, as
    `shutdown.py` does);
  - `pathlib.Path` for files, `os.environ.get(...) or default` for XDG paths.
- New scripts start with `# pyright: strict` and have type annotations; the
  older helpers are checked in pyright's standard mode
  (`pyrightconfig.json`).
- Comments say why, not what, and the interface a script offers to QML or Lua
  (its arguments and output) stays documented in its docstring. When renaming
  a script, update every caller (`grep -rn name.sh`), including comments.

## Checks

`./check.sh` runs everything CI runs (`.github/workflows/install.yml`); the
tools come from the flake's devShell, so they have the versions in
`flake.lock`. `nix develop` gives a shell with the same tools.

| Step | Fix |
|---|---|
| nixfmt, statix, deadnix | `nix fmt`; statix and deadnix by hand |
| shellcheck | by hand |
| ruff, ruff format (`ruff.toml`) | `ruff check --fix .`, `ruff format .` |
| pyright (`pyrightconfig.json`) | by hand |
| Python tests (`tests/`) | by hand |
| qmllint (syntax only) | by hand |

`.github/check-flake.sh` evaluates the flake and every Home Manager
configuration. `git config core.hooksPath .githooks` runs `check.sh` before
each commit.

## Tests

- `tests/test_<script>.py` with `unittest`, run by
  `python3 -m unittest discover -s tests -t tests` (in `nix develop`).
- `tests/helpers.py`'s `load("path/to/script.py")` imports a script by its
  path, also one with a dash in its name.
- Test the pure parts: parsing, arithmetic, file handling in a temporary
  directory. What needs the desktop (Hyprland, notifications, devices) is
  tried by hand.

## Commits and pull requests

The rules in `config/claude/CLAUDE.md` apply (branches and pull requests, PR
description, no private data). Write comments, docs and commit messages in
English, and don't name the owner's own apps, games or hardware in them.
