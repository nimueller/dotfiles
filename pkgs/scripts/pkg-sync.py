"""Compares the installed software with what the dotfiles declare: the pacman
and AUR packages in system/packages/*.txt and the Flatpaks in
home-manager/desktop/flatpak.nix.

  pkg-sync               what differs (the default)
  pkg-sync adopt         pick undeclared packages to add to the lists
  pkg-sync prune         pick undeclared packages to uninstall
  pkg-sync install       install the declared packages that are missing
  pkg-sync aur PKG...    an AUR package's risk check: maintainer, votes,
                         age, sources, install scripts, and its PKGBUILD

The lists are in $DOTFILES (default ~/dotfiles). Flatpaks are installed
and removed by home-manager switch (nix-flatpak); this only reports them.
"""

import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

DOTFILES = os.environ.get("DOTFILES", os.path.expanduser("~/dotfiles"))
LISTS = {name: os.path.join(DOTFILES, "system", "packages", f"{name}.txt") for name in ("session", "apps", "aur")}
# Written by home-manager from the Flatpaks it manages (home-manager/desktop/flatpak.nix)
FLATPAKS = os.path.expanduser("~/.config/pkg-sync/flatpaks")
AUR_RPC = "https://aur.archlinux.org/rpc/v5/info"
AUR_PKGBUILD = "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h={}"

RED, YELLOW, GREEN, BLUE, DIM, BOLD, RESET = (f"\033[{c}m" for c in (31, 33, 32, 34, 2, 1, 0))
if not sys.stdout.isatty():
    RED = YELLOW = GREEN = BLUE = DIM = BOLD = RESET = ""


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=False).stdout.split()


def declared(name):
    """The packages of a list, without comments and blank lines."""
    with open(LISTS[name]) as f:
        return [line.split("#")[0].strip() for line in f if line.split("#")[0].strip()]


def declared_flatpaks():
    try:
        with open(FLATPAKS) as f:
            return [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        return []


class State:
    def __init__(self):
        self.lists = {name: declared(name) for name in LISTS}
        self.repo_declared = set(self.lists["session"]) | set(self.lists["apps"])
        self.aur_declared = set(self.lists["aur"])
        self.installed = set(run("pacman", "-Qq"))
        explicit = set(run("pacman", "-Qqe"))
        self.foreign = set(run("pacman", "-Qqm"))
        # Members of declared groups (a group isn't a package of its own)
        groups = set(run("pacman", "-Qqg", *self.repo_declared)) if self.repo_declared else set()
        known = self.repo_declared | self.aur_declared | groups
        self.undeclared_repo = sorted(explicit - self.foreign - known)
        self.undeclared_aur = sorted((explicit & self.foreign) - known)
        self.missing = {
            name: [p for p in pkgs if p not in self.installed and not run("pacman", "-Qqg", p)]
            for name, pkgs in self.lists.items()
        }
        # In aur.txt, but the package is installed from a repository now (or the other way round)
        self.aur_but_repo = sorted(p for p in self.aur_declared if p in self.installed and p not in self.foreign)
        self.repo_but_aur = sorted(p for p in self.repo_declared if p in self.foreign)
        flatpak = subprocess.run(
            ["flatpak", "list", "--app", "--columns=application,installation"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.flatpaks = dict(line.split("\t") for line in flatpak.stdout.splitlines() if "\t" in line)
        self.flatpaks_declared = declared_flatpaks()


def section(title, items, color, hint=""):
    if not items:
        return
    print(f"\n{BOLD}{color}{title}{RESET} {DIM}({len(items)}){RESET}")
    if hint:
        print(f"{DIM}{hint}{RESET}")
    width = max(len(i) for i in items) + 2
    columns = max(1, min(4, 100 // width))
    for i in range(0, len(items), columns):
        print("  " + "".join(item.ljust(width) for item in items[i : i + columns]))


def status():
    s = State()
    section(
        "Installed, but in no list (official)", s.undeclared_repo, YELLOW, "pkg-sync adopt (apps.txt) or pkg-sync prune"
    )
    section(
        "Installed, but in no list (AUR)",
        s.undeclared_aur,
        RED,
        "pkg-sync adopt (aur.txt, after pkg-sync aur) or prune",
    )
    for name, pkgs in s.missing.items():
        section(f"In {name}.txt, but not installed", pkgs, BLUE, "pkg-sync install")
    section("In aur.txt, but installed from a repository: move to apps.txt", s.aur_but_repo, YELLOW)
    section("In a repository list, but installed from the AUR: move to aur.txt", s.repo_but_aur, YELLOW)
    undeclared_flatpaks = sorted(
        f"{app} ({where})" for app, where in s.flatpaks.items() if app not in s.flatpaks_declared
    )
    section("Flatpaks not declared in flatpak.nix", undeclared_flatpaks, YELLOW)
    section(
        "Flatpaks declared, but not installed",
        sorted(set(s.flatpaks_declared) - set(s.flatpaks)),
        BLUE,
        "home-manager switch installs them",
    )
    clean = not (
        s.undeclared_repo
        or s.undeclared_aur
        or any(s.missing.values())
        or s.aur_but_repo
        or s.repo_but_aur
        or undeclared_flatpaks
        or set(s.flatpaks_declared) - set(s.flatpaks)
    )
    aur = len(s.aur_declared)
    print(f"\n{GREEN if clean else ''}{'In sync. ' if clean else ''}{RESET}", end="")
    print(f"{DIM}{len(s.repo_declared)} official, {aur} AUR, {len(s.flatpaks_declared)} Flatpaks declared{RESET}")


def pick(items, prompt, preview):
    """Packages chosen in fzf (Tab for several, Ctrl+A for all)."""
    if not items:
        print("Nothing to pick.")
        return []
    chosen = subprocess.run(
        ["fzf", "--multi", "--reverse", "--bind=ctrl-a:select-all", f"--prompt={prompt} ", f"--preview={preview}"],
        input="\n".join(items),
        capture_output=True,
        text=True,
        check=False,
    )
    return chosen.stdout.split()


def append(name, pkgs):
    """Adds packages to a list, sorted in below its header comments."""
    with open(LISTS[name]) as f:
        lines = f.read().splitlines()
    header = []
    while lines and lines[0].startswith("#"):
        header.append(lines.pop(0))
    entries = sorted(set(lines + pkgs) - {""})
    with open(LISTS[name], "w") as f:
        f.write("".join(f"{line}\n" for line in header + entries))
    print(f"Added to {name}.txt: {' '.join(pkgs)}")


def adopt():
    s = State()
    labelled = [f"{p}" for p in s.undeclared_repo] + [f"{p} (AUR)" for p in s.undeclared_aur]
    chosen = pick(labelled, "Add to the lists>", "pacman -Qi {1}")
    repo = [p for p in chosen if p in s.undeclared_repo]
    aur = [p for p in chosen if p in s.undeclared_aur]
    for pkg in aur:
        if not aur_check(pkg):
            aur.remove(pkg)
    if repo:
        append("apps", repo)
    if aur:
        append("aur", aur)
    if repo or aur:
        print(f"{DIM}Commit system/packages/ in the dotfiles.{RESET}")


def prune():
    s = State()
    labelled = s.undeclared_repo + [f"{p} (AUR)" for p in s.undeclared_aur]
    chosen = [p for p in pick(labelled, "Uninstall>", "pacman -Qi {1}") if p != "(AUR)"]
    if chosen:
        # -Rns: also unneeded dependencies and saved configuration
        subprocess.run(["sudo", "pacman", "-Rns", *chosen], check=False)


def install():
    s = State()
    repo = s.missing["session"] + s.missing["apps"]
    aur = s.missing["aur"]
    if repo:
        subprocess.run(["sudo", "pacman", "-S", "--needed", *repo], check=False)
    for pkg in aur:
        if aur_check(pkg):
            subprocess.run(["yay", "-S", "--needed", pkg], check=False)
    if not repo and not aur:
        print("Every declared package is installed.")


# AUR risk check -------------------------------------------------------------


def fetch(url):
    with urllib.request.urlopen(url, timeout=15) as response:
        return response.read().decode()


def age(timestamp):
    days = (time.time() - timestamp) / 86400
    return f"{days:.0f} days" if days < 60 else f"{days / 30:.0f} months" if days < 730 else f"{days / 365:.0f} years"


SUSPICIOUS = [
    (r"(curl|wget)[^\n|]*\|\s*(ba|z)?sh", "pipes a download into a shell"),
    (r"base64\s+(-d|--decode)", "decodes base64"),
    (r"\beval\b", "uses eval"),
    (r"chmod\s+[0-7]*[4-7][0-7]{3}|chmod\s+[ug]\+s", "sets setuid/setgid"),
    (r"/etc/(sudoers|profile|ld\.so|cron)", "touches system configuration"),
    (r"systemctl\s+(enable|start)", "enables services itself"),
    (r"\bpython[0-9.]*\s+-c|\bperl\s+-e", "runs inline code"),
]


def aur_check(pkg):
    """Shows the risks of an AUR package; True if the user wants to go on."""
    try:
        info = json.loads(fetch(f"{AUR_RPC}?arg[]={urllib.parse.quote(pkg)}"))["results"]
    except OSError as e:
        print(f"{RED}Couldn't reach the AUR: {e}{RESET}")
        return False
    if not info:
        print(f"{RED}{pkg} isn't in the AUR.{RESET}")
        return False
    p = info[0]
    try:
        pkgbuild = fetch(AUR_PKGBUILD.format(urllib.parse.quote(p["PackageBase"])))
    except OSError:
        pkgbuild = ""

    warnings = []
    if not p.get("Maintainer"):
        warnings.append("orphaned: nobody maintains it, anyone can adopt it and push changes")
    if p.get("OutOfDate"):
        warnings.append(f"flagged out of date {age(p['OutOfDate'])} ago")
    if p["NumVotes"] < 10:
        warnings.append(f"only {p['NumVotes']} votes: few people use it")
    if time.time() - p["FirstSubmitted"] < 90 * 86400:
        warnings.append(f"new: first submitted {age(p['FirstSubmitted'])} ago")
    if time.time() - p["LastModified"] < 7 * 86400:
        warnings.append(f"changed {age(p['LastModified'])} ago: read what changed")
    if re.search(r"^\s*install=", pkgbuild, re.MULTILINE):
        warnings.append("runs an install script (as root) when installed or removed")
    for pattern, what in SUSPICIOUS:
        if re.search(pattern, pkgbuild):
            warnings.append(f"PKGBUILD {what}")
    hosts = sorted({urllib.parse.urlparse(u).hostname or u for u in re.findall(r"https?://[^\s\"')]+", pkgbuild)})

    print(f"\n{BOLD}{p['Name']} {p['Version']}{RESET}  {DIM}AUR{RESET}")
    print(f"  {p.get('Description') or ''}")
    print(f"  Upstream:    {p.get('URL') or '-'}")
    print(f"  Maintainer:  {p.get('Maintainer') or RED + 'none (orphaned)' + RESET}")
    print(f"  Votes:       {p['NumVotes']}, popularity {p['Popularity']:.2f}")
    print(f"  Submitted:   {age(p['FirstSubmitted'])} ago, last changed {age(p['LastModified'])} ago")
    print(f"  Downloads:   {', '.join(hosts) or '-'}")
    print(f"  Page:        https://aur.archlinux.org/packages/{p['Name']}")
    for w in warnings:
        print(f"  {YELLOW}! {w}{RESET}")
    print(
        f"{DIM}  These are hints, not a malware scan: anyone can upload to the AUR, and a harmless-looking"
        f" package can still be malicious. Read the PKGBUILD.{RESET}"
    )
    if not sys.stdin.isatty():
        return False
    answer = input(f"{BOLD}Read the PKGBUILD? [Y/n] {RESET}").strip().lower()
    if answer in ("", "y", "yes"):
        subprocess.run(["less", "-R"], input=pkgbuild, text=True, check=False)
    return input(f"{BOLD}Go on with {p['Name']}? [y/N] {RESET}").strip().lower() in ("y", "yes")


def main():
    args = sys.argv[1:]
    if not args:
        status()
    elif args == ["adopt"]:
        adopt()
    elif args == ["prune"]:
        prune()
    elif args == ["install"]:
        install()
    elif args[0] == "aur" and len(args) > 1:
        for pkg in args[1:]:
            aur_check(pkg)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
