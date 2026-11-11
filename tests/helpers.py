# pyright: strict
"""Loads a script as a module: the scripts aren't packages, and many have a
dash in their name. Their `if __name__ == "__main__"` part doesn't run.

The Quickshell helpers import i18n.py from their own folder: it's loaded once
here under that name, and its texts stay English, whatever language the
machine running the tests has chosen."""

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
MENUS = ROOT / "config/quickshell/menus"


def load(path: str) -> ModuleType:
    """load("config/quickshell/menus/backlight.py")"""
    file = ROOT / path
    spec = importlib.util.spec_from_file_location(file.stem.replace("-", "_"), file)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


i18n = load("config/quickshell/menus/i18n.py")
sys.modules["i18n"] = i18n
mock.patch.object(i18n, "language", return_value="en").start()
