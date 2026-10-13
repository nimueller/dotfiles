"""The emoji list for the launcher's emoji search (config/quickshell/menus/Launcher.qml).

Reads Unicode's emoji-test.txt (the emoji in their usual order, with names) and CLDR's
annotations (search keywords) and writes a JSON list of {"e": emoji, "n": name, "k": keywords}.
Skin tone variants are left out; the plain emoji stands for them.

    python3 emoji.py emoji-test.txt out.json annotations.xml...
"""

import json
import re
import sys
import xml.etree.ElementTree as ET

LINE = re.compile(r"^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$")


def keywords(paths: list[str]) -> dict[str, set[str]]:
    found: dict[str, set[str]] = {}
    for path in paths:
        for node in ET.parse(path).iter("annotation"):
            words = {w.strip().lower() for w in (node.text or "").split("|") if w.strip()}
            # Without the variation selector, as in emoji-test.txt's names it's optional
            found.setdefault(node.get("cp", "").replace("\ufe0f", ""), set()).update(words)
    return found


def main() -> None:
    test, out, *annotations = sys.argv[1:]
    words = keywords(annotations)
    emoji = []
    with open(test, encoding="utf-8") as f:
        for line in f:
            match = LINE.match(line)
            if not match or "skin tone" in match[2]:
                continue
            char, name = match[1], match[2]
            extra = words.get(char.replace("\ufe0f", ""), set()) - {name.lower()}
            emoji.append({"e": char, "n": name, "k": " ".join(sorted(extra))})
    with open(out, "w", encoding="utf-8") as f:
        json.dump(emoji, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
