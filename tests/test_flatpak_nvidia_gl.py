# pyright: strict
import unittest

from helpers import load

flatpak_nvidia_gl = load("pkgs/scripts/flatpak-nvidia-gl.py")
Extension = flatpak_nvidia_gl.Extension

GL = "org.freedesktop.Platform.GL.nvidia-"
GL32 = "org.freedesktop.Platform.GL32.nvidia-"

LISTING = """\
org.freedesktop.Platform.GL.default\t25.08\tflathub\tuser
org.freedesktop.Platform.GL.nvidia-620-70-06\t1.4\tflathub\tsystem
org.freedesktop.Platform.GL.nvidia-620-70-06\t1.4\tflathub\tuser
org.freedesktop.Platform.VAAPI.nvidia\t26.08\tflathub\tsystem
"""


class ExtensionSuffix(unittest.TestCase):
    def test_dots_become_dashes(self) -> None:
        self.assertEqual(flatpak_nvidia_gl.extension_suffix("620.73.04"), "620-73-04")


class ParseRuntimes(unittest.TestCase):
    def test_rows(self) -> None:
        runtimes = flatpak_nvidia_gl.parse_runtimes(LISTING)
        self.assertEqual(len(runtimes), 4)
        self.assertEqual(runtimes[1], Extension(GL + "620-70-06", "1.4", "flathub", "system"))

    def test_skips_incomplete_lines(self) -> None:
        self.assertEqual(flatpak_nvidia_gl.parse_runtimes("\nonly-a-name\n"), [])


class MissingExtensions(unittest.TestCase):
    def test_new_driver_in_both_installations(self) -> None:
        installed = flatpak_nvidia_gl.parse_runtimes(LISTING)
        self.assertEqual(
            flatpak_nvidia_gl.missing_extensions(installed, "620.73.04"),
            [
                Extension(GL + "620-73-04", "1.4", "flathub", "system"),
                Extension(GL + "620-73-04", "1.4", "flathub", "user"),
            ],
        )

    def test_nothing_when_it_matches(self) -> None:
        installed = flatpak_nvidia_gl.parse_runtimes(LISTING)
        self.assertEqual(flatpak_nvidia_gl.missing_extensions(installed, "620.70.06"), [])

    def test_only_where_installed(self) -> None:
        installed = [
            Extension(GL + "620-73-04", "1.4", "flathub", "user"),
            Extension(GL32 + "620-70-06", "1.4", "flathub", "user"),
        ]
        self.assertEqual(
            flatpak_nvidia_gl.missing_extensions(installed, "620.73.04"),
            [Extension(GL32 + "620-73-04", "1.4", "flathub", "user")],
        )

    def test_none_without_nvidia_extensions(self) -> None:
        installed = [Extension("org.freedesktop.Platform.GL.default", "25.08", "flathub", "user")]
        self.assertEqual(flatpak_nvidia_gl.missing_extensions(installed, "620.73.04"), [])


class SystemCommand(unittest.TestCase):
    def test_pkexec_with_remote_and_branch(self) -> None:
        extension = Extension(GL + "620-73-04", "1.4", "flathub", "system")
        self.assertEqual(
            flatpak_nvidia_gl.system_command(extension),
            "pkexec flatpak install --system -y --noninteractive flathub "
            "org.freedesktop.Platform.GL.nvidia-620-73-04//1.4",
        )


if __name__ == "__main__":
    unittest.main()
