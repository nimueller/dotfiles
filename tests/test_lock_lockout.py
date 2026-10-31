# pyright: strict
import unittest

from helpers import load

lockout = load("pkgs/scripts/lock-lockout.py")

PAM = """#%PAM-1.0
auth  required  pam_faillock.so  preauth  dir=/run/faillock-lock deny=5 unlock_time=60
auth  [success=1 default=bad]  pam_unix.so  try_first_pass nullok
auth  [default=die]  pam_faillock.so  authfail dir=/run/faillock-lock deny=5 unlock_time=60
"""


def tally(*records: tuple[int, int]) -> bytes:
    """(status, time) records as pam_faillock writes them"""
    return b"".join(lockout.RECORD.pack(b"hyprlock", 0, status, when) for status, when in records)


class Options(unittest.TestCase):
    def test_pam_line_over_faillock_conf(self) -> None:
        conf = lockout.settings("# comment\ndeny = 4  # tries\nfail_interval = 300\n")
        opts = lockout.options(conf, lockout.preauth(PAM))
        self.assertEqual(
            (opts.dir, opts.deny, opts.fail_interval, opts.unlock_time), ("/run/faillock-lock", 5, 300, 60)
        )

    def test_without_preauth_line(self) -> None:
        self.assertIsNone(lockout.preauth("auth include login\n"))
        opts = lockout.options({}, {})
        self.assertEqual((opts.dir, opts.deny, opts.unlock_time), ("/run/faillock", 3, 600))


class Left(unittest.TestCase):
    opts = lockout.Options(deny=3, fail_interval=900, unlock_time=60)

    def test_invalid_records_dont_count(self) -> None:
        times = lockout.failures(tally((1, 100), (0, 110), (1, 120)))
        self.assertEqual(times, [100, 120])
        self.assertEqual(lockout.left(times, self.opts, 125), 0)

    def test_locked_from_the_latest_failure(self) -> None:
        times = lockout.failures(tally((1, 100), (1, 110), (1, 120)))
        self.assertEqual(lockout.left(times, self.opts, 130.5), 50)
        self.assertEqual(lockout.left(times, self.opts, 181), 0)

    def test_old_failures_dont_count(self) -> None:
        self.assertEqual(lockout.left([0, 1000, 1010], self.opts, 1020), 0)

    def test_text(self) -> None:
        self.assertEqual(lockout.text(0), "")
        self.assertIn("wait 42 s", lockout.text(42))
        self.assertIn("wait 9:05 min", lockout.text(545))


if __name__ == "__main__":
    unittest.main()
