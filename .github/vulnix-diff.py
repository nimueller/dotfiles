# pyright: strict
"""Compares two vulnix --json scans and prints a Markdown pull request comment:
the vulnerabilities a flake.lock update fixes and the ones it brings in.

    python3 vulnix-diff.py OLD.json NEW.json CONFIG > comment.md

Packages are matched by name, so a new version of the same package lines up
with the old one. vulnix matches names and versions against the NVD, so both
scans share most false positives (TeX packages named like other software);
those cancel out here.
"""

import json
import sys
from dataclasses import dataclass, field
from typing import Any

MAX_ROWS = 100
# CVSS v3 severities: (lowest score, icon), from the highest down
SEVERITIES = [(9.0, "🔴"), (7.0, "🟠"), (4.0, "🟡"), (0.0, "⚪")]

# (package, CVE)
Key = tuple[str, str]


@dataclass
class Finding:
    versions: set[str] = field(default_factory=set[str])
    score: float | None = None


@dataclass
class Row:
    score: float | None
    cve: str
    package: str
    versions: str


def load(path: str) -> dict[Key, Finding]:
    with open(path) as f:
        entries: list[dict[str, Any]] = json.load(f)
    found: dict[Key, Finding] = {}
    for entry in entries:
        scores: dict[str, float] = entry.get("cvssv3_basescore") or {}
        whitelisted: list[str] = entry.get("whitelisted", [])
        for cve in entry["affected_by"]:
            if cve in whitelisted:
                continue
            finding = found.setdefault((entry["pname"], cve), Finding())
            finding.versions.add(entry["version"])
            finding.score = scores.get(cve)
    return found


def rows_only_in(scan: dict[Key, Finding], other: dict[Key, Finding]) -> list[Row]:
    rows: list[Row] = []
    for key in scan.keys() - other.keys():
        package, cve = key
        finding = scan[key]
        versions = ", ".join(sorted(finding.versions))
        rows.append(Row(finding.score, cve, package, versions))
    return rows


def score_cell(score: float | None) -> str:
    if score is None:
        return "–"
    icon = next(icon for lowest, icon in SEVERITIES if score >= lowest)
    return f"{icon} {score:.1f}"


def table(rows: list[Row], version_header: str) -> str:
    """The highest scores first; ties by package, then CVE."""
    ordered = sorted(rows, key=lambda row: (-(row.score or 0), row.package, row.cve))
    lines = [
        f"| Score | CVE | Package | {version_header} |",
        "|---|---|---|---|",
    ]
    for row in ordered[:MAX_ROWS]:
        link = f"[{row.cve}](https://nvd.nist.gov/vuln/detail/{row.cve})"
        lines.append(f"| {score_cell(row.score)} | {link} | {row.package} | {row.versions} |")
    hidden = len(ordered) - MAX_ROWS
    if hidden > 0:
        lines.append(f"\n…and {hidden} more (lowest scores).")
    return "\n".join(lines)


def main() -> None:
    old_path, new_path, config = sys.argv[1:4]
    old = load(old_path)
    new = load(new_path)
    fixed = rows_only_in(old, new)
    added = rows_only_in(new, old)

    print(f"## 🛡️ Vulnerability scan: `{config}`\n")
    print(f"**{len(fixed)} fixed, {len(added)} new** ({len(new)} known vulnerabilities in total after this update)\n")
    if added:
        print("### New with this update\n")
        print(table(added, "Version"))
        print()
    if fixed:
        print("<details><summary><b>Fixed by this update</b></summary>\n")
        print(table(fixed, "Version before"))
        print("\n</details>\n")
    print(
        "<sub>Scanned with [vulnix](https://github.com/nix-community/vulnix) "
        "against the NVD. It matches package names and versions, so expect false "
        "positives, and it can't see patches nixpkgs applies without a new "
        "version. Information only: this doesn't decide whether the update is "
        "merged.</sub>"
    )


if __name__ == "__main__":
    main()
