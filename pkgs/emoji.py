# pyright: strict
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

# A fully-qualified emoji in emoji-test.txt: "<code points> ; fully-qualified # <emoji> E<version> <name>"
LINE = re.compile(r"^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$")
VARIATION_SELECTOR = "️"


def without_variation_selector(emoji: str) -> str:
    """The key both files are matched by: emoji-test.txt has the selector,
    the annotations often don't."""
    return emoji.replace(VARIATION_SELECTOR, "")


def annotation_words(text: str | None) -> set[str]:
    """CLDR's keywords for an emoji, separated by "|"."""
    words = (text or "").split("|")
    return {word.strip().lower() for word in words if word.strip()}


def keywords(paths: list[str]) -> dict[str, set[str]]:
    found: dict[str, set[str]] = {}
    for path in paths:
        for node in ET.parse(path).iter("annotation"):
            emoji = without_variation_selector(node.get("cp", ""))
            found.setdefault(emoji, set()).update(annotation_words(node.text))
    return found


def read_emoji(path: str, words: dict[str, set[str]]) -> list[dict[str, str]]:
    emoji: list[dict[str, str]] = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            match = LINE.match(line)
            if match is None:
                continue
            char, name = match[1], match[2]
            if "skin tone" in name:
                continue
            extra = words.get(without_variation_selector(char), set()) - {name.lower()}
            emoji.append({"e": char, "n": name, "k": " ".join(sorted(extra))})
    return emoji


def main() -> None:
    test, out, *annotations = sys.argv[1:]
    emoji = read_emoji(test, keywords(annotations))
    with open(out, "w", encoding="utf-8") as f:
        json.dump(emoji, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
