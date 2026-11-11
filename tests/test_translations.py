# pyright: strict
"""The German translation (translations/de.json) against the texts the shell
passes to I18n.tr() in QML and to tr() in the Python helpers."""

import ast
import datetime as dt
import io
import json
import re
import tokenize
import unittest
from collections.abc import Callable
from unittest import mock

from helpers import MENUS, i18n

GERMAN: dict[str, str] = json.loads((MENUS / "translations/de.json").read_text())
QML_CALL = re.compile(r"\bI18n\.tr\(")
PYTHON_CALL = re.compile(r"(?<![\w.])tr\(")
QML_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')
PLACEHOLDER = re.compile(r"%\d")


def first_argument(source: str, start: int) -> str:
    """The text of a call's first argument, from just after its "(": up to
    the comma or parenthesis that ends it, skipping over strings and
    nested parentheses"""
    depth = 0
    quote = ""
    i = start
    while i < len(source):
        char = source[i]
        if quote:
            if char == "\\":
                i += 1
            elif char == quote:
                quote = ""
        elif char in "\"'`":
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}" and depth > 0:
            depth -= 1
        elif char in ",)" and depth == 0:
            return source[start:i]
        i += 1
    return source[start:]


def js_string(literal: str) -> str:
    """The value of a "…" literal; escapes other than \\n stand for the character"""
    escaped = {"n": "\n", "t": "\t"}
    return re.sub(r"\\(.)", lambda match: escaped.get(match[1], match[1]), literal[1:-1])


def qml_strings(text: str) -> list[str]:
    return [js_string(literal) for literal in QML_STRING.findall(text)]


def python_strings(source: str) -> list[str]:
    """Every plain string literal, f-strings' parts left out"""
    tokens = tokenize.generate_tokens(io.StringIO(source).readline)
    literals = [token.string for token in tokens if token.type == tokenize.STRING]
    values = [ast.literal_eval(literal) for literal in literals]
    return [value for value in values if isinstance(value, str)]


def called_texts(
    source: str, call: re.Pattern[str], strings: Callable[[str], list[str]]
) -> list[tuple[str, list[str]]]:
    """(argument, its string literals) for each call's first argument"""
    found: list[tuple[str, list[str]]] = []
    for match in call.finditer(source):
        argument = first_argument(source, match.end())
        found.append((argument, strings(argument)))
    return found


class Sources:
    def __init__(self) -> None:
        self.qml = {path.name: path.read_text() for path in sorted(MENUS.glob("*.qml"))}
        self.python = {path.name: path.read_text() for path in sorted(MENUS.glob("*.py"))}

    def calls(self) -> list[tuple[str, str, list[str]]]:
        """(file, first argument, its literals) of every call that translates"""
        result: list[tuple[str, str, list[str]]] = []
        for name, text in self.qml.items():
            result += [(name, arg, texts) for arg, texts in called_texts(text, QML_CALL, qml_strings)]
        for name, text in self.python.items():
            if name == "i18n.py":
                continue
            result += [(name, arg, texts) for arg, texts in called_texts(text, PYTHON_CALL, python_strings)]
        return result

    def literals(self) -> set[str]:
        found: set[str] = set()
        for text in self.qml.values():
            found.update(qml_strings(text))
        for text in self.python.values():
            found.update(python_strings(text))
        return found


SOURCES = Sources()


class Translation(unittest.TestCase):
    def test_every_text_is_translated(self) -> None:
        missing = [
            f"{name}: {text!r}" for name, _argument, texts in SOURCES.calls() for text in texts if text not in GERMAN
        ]
        self.assertEqual(missing, [])

    def test_no_template_literals(self) -> None:
        # A text built in place can't be looked up: %1, %2, … instead
        built = [f"{name}: {argument}" for name, argument, _texts in SOURCES.calls() if "`" in argument]
        self.assertEqual(built, [])

    def test_every_translation_is_used(self) -> None:
        # Texts that are looked up through a variable (a dictionary's
        # values, constants) count when they're a literal anywhere
        literals = SOURCES.literals()
        unused = [text for text in GERMAN if text not in literals]
        self.assertEqual(unused, [])

    def test_placeholders_match(self) -> None:
        different = [
            text
            for text, german in GERMAN.items()
            if sorted(PLACEHOLDER.findall(text)) != sorted(PLACEHOLDER.findall(german))
        ]
        self.assertEqual(different, [])


class Language(unittest.TestCase):
    def test_system_language(self) -> None:
        self.assertEqual(i18n.system_language({"LANG": "de_DE.UTF-8"}), "de")
        self.assertEqual(i18n.system_language({"LANG": "de_DE.UTF-8", "LC_MESSAGES": "en_GB.UTF-8"}), "en")
        self.assertEqual(i18n.system_language({"LC_ALL": "", "LANG": "de_AT.UTF-8"}), "de")
        self.assertEqual(i18n.system_language({"LANG": "fr_FR.UTF-8"}), "en")
        self.assertEqual(i18n.system_language({}), "en")

    def test_chosen_language(self) -> None:
        lua = 'hl.env("A", "b")\n-- settings: {"language": "de", "bar": {}}\n'
        self.assertEqual(i18n.chosen_language(lua), "de")
        self.assertEqual(i18n.chosen_language("-- settings: {}\n"), "system")
        self.assertEqual(i18n.chosen_language("-- settings: {broken\n"), "system")
        self.assertEqual(i18n.chosen_language(""), "system")

    def test_fill(self) -> None:
        self.assertEqual(i18n.fill("%1 of %2", (3, "x")), "3 of x")
        self.assertEqual(i18n.fill("%1 %%2", (50, ", left")), "50 %, left")
        self.assertEqual(i18n.fill("%1 and %2", ("a",)), "a and %2")

    def test_german(self) -> None:
        with mock.patch.object(i18n, "language", return_value="de"):
            self.assertEqual(i18n.tr("Couldn't write %1", "a.pdf"), "Konnte a.pdf nicht schreiben")
            self.assertEqual(i18n.tr("Not a translated text"), "Not a translated text")
            self.assertEqual(i18n.long_date(dt.date(2026, 3, 2)), "Montag, 2. März")

    def test_english(self) -> None:
        self.assertEqual(i18n.tr("Couldn't write %1", "a.pdf"), "Couldn't write a.pdf")
        self.assertEqual(i18n.long_date(dt.date(2026, 3, 2)), "Monday, 2 March")


if __name__ == "__main__":
    unittest.main()
