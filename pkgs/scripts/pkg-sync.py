# pyright: strict
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
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

DOTFILES = Path(os.environ.get("DOTFILES") or Path.home() / "dotfiles")
LIST_NAMES = ("session", "apps", "aur")
LISTS = {name: DOTFILES / "system" / "packages" / f"{name}.txt" for name in LIST_NAMES}
REPOSITORY_LISTS = ("session", "apps")
# Written by home-manager from the Flatpaks it manages (home-manager/desktop/flatpak.nix)
FLATPAKS = Path.home() / ".config/pkg-sync/flatpaks"
AUR_RPC = "https://aur.archlinux.org/rpc/v5/info"
AUR_PKGBUILD = "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h={}"
AUR_PAGE = "https://aur.archlinux.org/packages/{}"
AUR_LABEL = "(AUR)"
FETCH_TIMEOUT = 15
DAY = 86400
FEW_VOTES = 10
NEW_DAYS = 90
RECENT_DAYS = 7
SECTION_WIDTH = 100
MAX_COLUMNS = 4
YES = ("y", "yes")

IS_TERMINAL = sys.stdout.isatty()


def color(code: int) -> str:
    """An ANSI color, or nothing when the output isn't a terminal."""
    if not IS_TERMINAL:
        return ""
    return f"\033[{code}m"


RED = color(31)
GREEN = color(32)
YELLOW = color(33)
BLUE = color(34)
BOLD = color(1)
DIM = color(2)
RESET = color(0)

SUSPICIOUS = [
    (r"(curl|wget)[^\n|]*\|\s*(ba|z)?sh", "pipes a download into a shell"),
    (r"base64\s+(-d|--decode)", "decodes base64"),
    (r"\beval\b", "uses eval"),
    (r"chmod\s+[0-7]*[4-7][0-7]{3}|chmod\s+[ug]\+s", "sets setuid/setgid"),
    (r"/etc/(sudoers|profile|ld\.so|cron)", "touches system configuration"),
    (r"systemctl\s+(enable|start)", "enables services itself"),
    (r"\bpython[0-9.]*\s+-c|\bperl\s+-e", "runs inline code"),
]
INSTALL_SCRIPT = re.compile(r"^\s*install=", re.MULTILINE)
URL = re.compile(r"https?://[^\s\"')]+")


def run(*arguments: str) -> list[str]:
    """A command's output, split into words."""
    result = subprocess.run(arguments, capture_output=True, text=True, check=False)
    return result.stdout.split()


def without_comment(line: str) -> str:
    return line.split("#")[0].strip()


def declared(name: str) -> list[str]:
    """The packages of a list, without comments and blank lines."""
    lines = LISTS[name].read_text().splitlines()
    packages = [without_comment(line) for line in lines]
    return [package for package in packages if package]


def declared_flatpaks() -> list[str]:
    try:
        lines = FLATPAKS.read_text().splitlines()
    except FileNotFoundError:
        return []
    return [line.strip() for line in lines if line.strip()]


def installed_flatpaks() -> dict[str, str]:
    """The installed Flatpak apps, {app id: installation}."""
    result = subprocess.run(
        ["flatpak", "list", "--app", "--columns=application,installation"],
        capture_output=True,
        text=True,
        check=False,
    )
    flatpaks: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if "\t" in line:
            app, installation = line.split("\t", 1)
            flatpaks[app] = installation
    return flatpaks


def group_members(groups: set[str]) -> set[str]:
    """The packages of pacman groups; empty for names that aren't groups."""
    if not groups:
        return set()
    return set(run("pacman", "-Qqg", *groups))


def is_group(name: str) -> bool:
    return bool(run("pacman", "-Qqg", name))


@dataclass
class State:
    lists: dict[str, list[str]]
    repository_declared: set[str]
    aur_declared: set[str]
    undeclared_repository: list[str]
    undeclared_aur: list[str]
    missing: dict[str, list[str]]
    # In aur.txt, but installed from a repository now, or the other way round
    aur_but_repository: list[str]
    repository_but_aur: list[str]
    flatpaks: dict[str, str]
    flatpaks_declared: list[str]

    @property
    def undeclared_flatpaks(self) -> list[str]:
        undeclared = [app for app in self.flatpaks if app not in self.flatpaks_declared]
        return sorted(f"{app} ({self.flatpaks[app]})" for app in undeclared)

    @property
    def missing_flatpaks(self) -> list[str]:
        return sorted(set(self.flatpaks_declared) - set(self.flatpaks))

    @property
    def is_in_sync(self) -> bool:
        differences = [
            self.undeclared_repository,
            self.undeclared_aur,
            *self.missing.values(),
            self.aur_but_repository,
            self.repository_but_aur,
            self.undeclared_flatpaks,
            self.missing_flatpaks,
        ]
        return not any(differences)


def read_state() -> State:
    lists = {name: declared(name) for name in LISTS}
    repository_declared = {package for name in REPOSITORY_LISTS for package in lists[name]}
    aur_declared = set(lists["aur"])
    installed = set(run("pacman", "-Qq"))
    explicit = set(run("pacman", "-Qqe"))
    foreign = set(run("pacman", "-Qqm"))
    # Members of declared groups (a group isn't a package of its own)
    known = repository_declared | aur_declared | group_members(repository_declared)
    missing = {
        name: [package for package in packages if package not in installed and not is_group(package)]
        for name, packages in lists.items()
    }
    return State(
        lists=lists,
        repository_declared=repository_declared,
        aur_declared=aur_declared,
        undeclared_repository=sorted(explicit - foreign - known),
        undeclared_aur=sorted((explicit & foreign) - known),
        missing=missing,
        aur_but_repository=sorted(package for package in aur_declared if package in installed - foreign),
        repository_but_aur=sorted(package for package in repository_declared if package in foreign),
        flatpaks=installed_flatpaks(),
        flatpaks_declared=declared_flatpaks(),
    )


# ---------- Status ----------


def section(title: str, items: list[str], title_color: str, hint: str = "") -> None:
    """A heading and the items in up to MAX_COLUMNS columns; nothing for
    no items."""
    if not items:
        return
    print(f"\n{BOLD}{title_color}{title}{RESET} {DIM}({len(items)}){RESET}")
    if hint:
        print(f"{DIM}{hint}{RESET}")
    width = max(len(item) for item in items) + 2
    columns = max(1, min(MAX_COLUMNS, SECTION_WIDTH // width))
    for start in range(0, len(items), columns):
        row = items[start : start + columns]
        print("  " + "".join(item.ljust(width) for item in row))


def status() -> None:
    state = read_state()
    section(
        "Installed, but in no list (official)",
        state.undeclared_repository,
        YELLOW,
        "pkg-sync adopt (apps.txt) or pkg-sync prune",
    )
    section(
        "Installed, but in no list (AUR)",
        state.undeclared_aur,
        RED,
        "pkg-sync adopt (aur.txt, after pkg-sync aur) or prune",
    )
    for name, packages in state.missing.items():
        section(f"In {name}.txt, but not installed", packages, BLUE, "pkg-sync install")
    section("In aur.txt, but installed from a repository: move to apps.txt", state.aur_but_repository, YELLOW)
    section("In a repository list, but installed from the AUR: move to aur.txt", state.repository_but_aur, YELLOW)
    section("Flatpaks not declared in flatpak.nix", state.undeclared_flatpaks, YELLOW)
    section(
        "Flatpaks declared, but not installed",
        state.missing_flatpaks,
        BLUE,
        "home-manager switch installs them",
    )
    counts = (
        f"{len(state.repository_declared)} official, "
        f"{len(state.aur_declared)} AUR, "
        f"{len(state.flatpaks_declared)} Flatpaks declared"
    )
    in_sync = "In sync. " if state.is_in_sync else ""
    in_sync_color = GREEN if state.is_in_sync else ""
    print(f"\n{in_sync_color}{in_sync}{RESET}{DIM}{counts}{RESET}")


# ---------- Adopt, prune, install ----------


def pick(items: list[str], prompt: str, preview: str) -> list[str]:
    """Words of the lines chosen in fzf (Tab for several, Ctrl+A for all)."""
    if not items:
        print("Nothing to pick.")
        return []
    chosen = subprocess.run(
        [
            "fzf",
            "--multi",
            "--reverse",
            "--bind=ctrl-a:select-all",
            f"--prompt={prompt} ",
            f"--preview={preview}",
        ],
        input="\n".join(items),
        capture_output=True,
        text=True,
        check=False,
    )
    return chosen.stdout.split()


def append(name: str, packages: list[str]) -> None:
    """Adds packages to a list, sorted in below its header comments."""
    lines = LISTS[name].read_text().splitlines()
    header: list[str] = []
    while lines and lines[0].startswith("#"):
        header.append(lines.pop(0))
    entries = sorted(set(lines + packages) - {""})
    LISTS[name].write_text("".join(f"{line}\n" for line in header + entries))
    print(f"Added to {name}.txt: {' '.join(packages)}")


def labelled(repository: list[str], aur: list[str]) -> list[str]:
    """Lines for fzf: AUR packages marked as such."""
    return repository + [f"{package} {AUR_LABEL}" for package in aur]


def adopt() -> None:
    state = read_state()
    lines = labelled(state.undeclared_repository, state.undeclared_aur)
    chosen = pick(lines, "Add to the lists>", "pacman -Qi {1}")
    repository = [package for package in chosen if package in state.undeclared_repository]
    aur_chosen = [package for package in chosen if package in state.undeclared_aur]
    aur = [package for package in aur_chosen if aur_check(package)]
    if repository:
        append("apps", repository)
    if aur:
        append("aur", aur)
    if repository or aur:
        print(f"{DIM}Commit system/packages/ in the dotfiles.{RESET}")


def prune() -> None:
    state = read_state()
    lines = labelled(state.undeclared_repository, state.undeclared_aur)
    chosen = [word for word in pick(lines, "Uninstall>", "pacman -Qi {1}") if word != AUR_LABEL]
    if chosen:
        # -Rns: also unneeded dependencies and saved configuration
        subprocess.run(["sudo", "pacman", "-Rns", *chosen], check=False)


def install() -> None:
    state = read_state()
    repository = [package for name in REPOSITORY_LISTS for package in state.missing[name]]
    aur = state.missing["aur"]
    if not repository and not aur:
        print("Every declared package is installed.")
        return
    if repository:
        subprocess.run(["sudo", "pacman", "-S", "--needed", *repository], check=False)
    for package in aur:
        if aur_check(package):
            subprocess.run(["yay", "-S", "--needed", package], check=False)


# ---------- AUR risk check ----------


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=FETCH_TIMEOUT) as response:
        body = cast(bytes, response.read())
    return body.decode()


def age(timestamp: float) -> str:
    days = (time.time() - timestamp) / DAY
    if days < 60:
        return f"{days:.0f} days"
    if days < 730:
        return f"{days / 30:.0f} months"
    return f"{days / 365:.0f} years"


def aur_info(package: str) -> dict[str, Any] | None:
    """The AUR's information on a package, None if it isn't there.
    Raises OSError when the AUR can't be reached."""
    url = f"{AUR_RPC}?arg[]={urllib.parse.quote(package)}"
    results: list[dict[str, Any]] = json.loads(fetch(url))["results"]
    if not results:
        return None
    return results[0]


def pkgbuild_of(info: dict[str, Any]) -> str:
    """The package's PKGBUILD, "" when it can't be fetched (the warnings
    then only cover the AUR's information)."""
    url = AUR_PKGBUILD.format(urllib.parse.quote(info["PackageBase"]))
    try:
        return fetch(url)
    except OSError:
        return ""


def is_newer_than(timestamp: float, days: int) -> bool:
    return time.time() - timestamp < days * DAY


def warnings_for(info: dict[str, Any], pkgbuild: str) -> list[str]:
    warnings: list[str] = []
    if not info.get("Maintainer"):
        warnings.append("orphaned: nobody maintains it, anyone can adopt it and push changes")
    if info.get("OutOfDate"):
        warnings.append(f"flagged out of date {age(info['OutOfDate'])} ago")
    if info["NumVotes"] < FEW_VOTES:
        warnings.append(f"only {info['NumVotes']} votes: few people use it")
    if is_newer_than(info["FirstSubmitted"], NEW_DAYS):
        warnings.append(f"new: first submitted {age(info['FirstSubmitted'])} ago")
    if is_newer_than(info["LastModified"], RECENT_DAYS):
        warnings.append(f"changed {age(info['LastModified'])} ago: read what changed")
    if INSTALL_SCRIPT.search(pkgbuild):
        warnings.append("runs an install script (as root) when installed or removed")
    for pattern, what in SUSPICIOUS:
        if re.search(pattern, pkgbuild):
            warnings.append(f"PKGBUILD {what}")
    return warnings


def download_hosts(pkgbuild: str) -> list[str]:
    urls: list[str] = URL.findall(pkgbuild)
    hosts = {urllib.parse.urlparse(url).hostname or url for url in urls}
    return sorted(hosts)


def print_report(info: dict[str, Any], pkgbuild: str) -> None:
    maintainer = info.get("Maintainer") or f"{RED}none (orphaned){RESET}"
    hosts = ", ".join(download_hosts(pkgbuild)) or "-"
    print(f"\n{BOLD}{info['Name']} {info['Version']}{RESET}  {DIM}AUR{RESET}")
    print(f"  {info.get('Description') or ''}")
    print(f"  Upstream:    {info.get('URL') or '-'}")
    print(f"  Maintainer:  {maintainer}")
    print(f"  Votes:       {info['NumVotes']}, popularity {info['Popularity']:.2f}")
    print(f"  Submitted:   {age(info['FirstSubmitted'])} ago, last changed {age(info['LastModified'])} ago")
    print(f"  Downloads:   {hosts}")
    print(f"  Page:        {AUR_PAGE.format(info['Name'])}")
    for warning in warnings_for(info, pkgbuild):
        print(f"  {YELLOW}! {warning}{RESET}")
    print(
        f"{DIM}  These are hints, not a malware scan: anyone can upload to the AUR, and a harmless-looking"
        f" package can still be malicious. Read the PKGBUILD.{RESET}"
    )


def ask(question: str) -> str:
    return input(f"{BOLD}{question} {RESET}").strip().lower()


def aur_check(package: str) -> bool:
    """Shows the risks of an AUR package; True if the user wants to go on."""
    try:
        info = aur_info(package)
    except OSError as error:
        print(f"{RED}Couldn't reach the AUR: {error}{RESET}")
        return False
    if info is None:
        print(f"{RED}{package} isn't in the AUR.{RESET}")
        return False
    pkgbuild = pkgbuild_of(info)
    print_report(info, pkgbuild)
    if not sys.stdin.isatty():
        return False
    if ask("Read the PKGBUILD? [Y/n]") in ("", *YES):
        subprocess.run(["less", "-R"], input=pkgbuild, text=True, check=False)
    return ask(f"Go on with {info['Name']}? [y/N]") in YES


def main() -> None:
    arguments = sys.argv[1:]
    if not arguments:
        status()
    elif arguments == ["adopt"]:
        adopt()
    elif arguments == ["prune"]:
        prune()
    elif arguments == ["install"]:
        install()
    elif arguments[0] == "aur" and len(arguments) > 1:
        for package in arguments[1:]:
            aur_check(package)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
