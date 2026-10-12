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

MAX_ROWS = 100


def load(path):
    """{(package, CVE): (version, score)}"""
    found = {}
    with open(path) as f:
        for entry in json.load(f):
            scores = entry.get("cvssv3_basescore") or {}
            for cve in entry["affected_by"]:
                if cve in entry.get("whitelisted", []):
                    continue
                key = (entry["pname"], cve)
                versions = found.get(key, (set(), None))[0]
                versions.add(entry["version"])
                found[key] = (versions, scores.get(cve))
    return found


def score_cell(score):
    if score is None:
        return "–"
    icon = "🔴" if score >= 9 else "🟠" if score >= 7 else "🟡" if score >= 4 else "⚪"
    return f"{icon} {score:.1f}"


def table(rows, version_header):
    rows = sorted(rows, key=lambda r: (-(r[0] or 0), r[2], r[1]))
    lines = [
        f"| Score | CVE | Package | {version_header} |",
        "|---|---|---|---|",
    ]
    for score, cve, package, version in rows[:MAX_ROWS]:
        link = f"[{cve}](https://nvd.nist.gov/vuln/detail/{cve})"
        lines.append(f"| {score_cell(score)} | {link} | {package} | {version} |")
    if len(rows) > MAX_ROWS:
        lines.append(f"\n…and {len(rows) - MAX_ROWS} more (lowest scores).")
    return "\n".join(lines)


def main():
    old_path, new_path, config = sys.argv[1:4]
    old, new = load(old_path), load(new_path)

    fixed = []
    for key in old.keys() - new.keys():
        package, cve = key
        fixed.append((old[key][1], cve, package, ", ".join(sorted(old[key][0]))))

    added = []
    for key in new.keys() - old.keys():
        package, cve = key
        added.append((new[key][1], cve, package, ", ".join(sorted(new[key][0]))))

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
