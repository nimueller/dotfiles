# pyright: strict
import signal
import unittest

from helpers import load

shutdown = load("config/quickshell/menus/shutdown.py")


class CrashedTest(unittest.TestCase):
    def test_cancel_exits_normally(self) -> None:
        self.assertFalse(shutdown.crashed(0))
        self.assertFalse(shutdown.crashed(1))

    def test_killed_by_a_signal_is_a_crash(self) -> None:
        self.assertTrue(shutdown.crashed(-signal.SIGABRT))
        self.assertTrue(shutdown.crashed(-signal.SIGSEGV))


if __name__ == "__main__":
    unittest.main()
