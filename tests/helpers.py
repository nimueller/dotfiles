# pyright: strict
"""Loads a script as a module: the scripts aren't packages, and many have a
dash in their name. Their `if __name__ == "__main__"` part doesn't run."""

import importlib.util
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parent.parent


def load(path: str) -> ModuleType:
    """load("config/quickshell/menus/backlight.py")"""
    file = ROOT / path
    spec = importlib.util.spec_from_file_location(file.stem.replace("-", "_"), file)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
