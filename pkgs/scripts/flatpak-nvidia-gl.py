# pyright: strict
"""Installs the Flatpak GL extension that matches the loaded NVIDIA driver:

  flatpak-nvidia-gl     checks once; run at login (home-manager/desktop)

Flatpak apps only get the NVIDIA driver through an extension named after its
exact version (org.freedesktop.Platform.GL.nvidia-620-73-04). Flatpak picks
that version from the loaded kernel module, not from the installed driver.
The update (Updates.qml) runs `flatpak update` right after pacman, while the
old module is still loaded, so after a driver update the matching extension
only comes with the next `flatpak update` after the reboot; until then the
apps (the browser) draw without the GPU.

Looks at each installation that has an NVIDIA GL extension at all and
installs the missing one from the remote and branch of the old one. The user
installation is handled here; for the system installation, which needs root,
a notification says what to run. Old extensions stay until the cleanup
(`flatpak uninstall --unused`). Exits 1 when an install failed (no network
yet at login): the service tries again.

Built with writePython3Bin (pkgs/default.nix), so the file has no shebang.
"""

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

NVIDIA_MODULE_VERSION = Path("/sys/module/nvidia/version")
# The 32-bit one (GL32) only where a 32-bit one was installed before
EXTENSION_PREFIXES = [
    "org.freedesktop.Platform.GL.nvidia-",
    "org.freedesktop.Platform.GL32.nvidia-",
]
USER = "user"
SYSTEM = "system"
APP_NAME = "Flatpak"
ICON = "video-display"


@dataclass(frozen=True)
class Extension:
    name: str
    branch: str
    origin: str
    installation: str


def extension_suffix(driver_version: str) -> str:
    """The driver version as the extensions spell it: 620.73.04 -> 620-73-04"""
    return driver_version.replace(".", "-")


def parse_runtimes(listing: str) -> list[Extension]:
    """flatpak list --runtime --columns=application,branch,origin,installation"""
    extensions: list[Extension] = []
    for line in listing.splitlines():
        fields = line.split("\t")
        if len(fields) != 4:
            continue
        name, branch, origin, installation = fields
        extensions.append(Extension(name, branch, origin, installation))
    return extensions


def missing_extensions(installed: list[Extension], driver_version: str) -> list[Extension]:
    """The matching extensions to install, one per prefix and installation
    that has an older one, from that one's remote and branch"""
    suffix = extension_suffix(driver_version)
    missing: list[Extension] = []
    for prefix in EXTENSION_PREFIXES:
        nvidia = [extension for extension in installed if extension.name.startswith(prefix)]
        for installation in sorted({extension.installation for extension in nvidia}):
            missing.extend(missing_in(nvidia, installation, prefix + suffix))
    return missing


def missing_in(nvidia: list[Extension], installation: str, wanted: str) -> list[Extension]:
    """The wanted extension, modeled on the last old one, when this
    installation lacks it"""
    present = [extension for extension in nvidia if extension.installation == installation]
    if any(extension.name == wanted for extension in present):
        return []
    model = present[-1]
    return [Extension(wanted, model.branch, model.origin, installation)]


def loaded_driver_version() -> str | None:
    try:
        return NVIDIA_MODULE_VERSION.read_text().strip() or None
    except OSError:
        # No NVIDIA module loaded: nothing to match
        return None


def installed_runtimes() -> list[Extension]:
    result = subprocess.run(
        ["flatpak", "list", "--runtime", "--columns=application,branch,origin,installation"],
        capture_output=True,
        text=True,
        check=False,
    )
    return parse_runtimes(result.stdout)


def ref_of(extension: Extension) -> str:
    """The name with its branch: several branches can be on the remote"""
    return f"{extension.name}//{extension.branch}"


def install(extension: Extension) -> bool:
    command = [
        "flatpak",
        "install",
        f"--{extension.installation}",
        "-y",
        "--noninteractive",
        extension.origin,
        ref_of(extension),
    ]
    return subprocess.run(command, check=False).returncode == 0


def system_command(extension: Extension) -> str:
    return f"pkexec flatpak install --system -y --noninteractive {extension.origin} {ref_of(extension)}"


def notify(summary: str, body: str) -> None:
    subprocess.run(["notify-send", "-a", APP_NAME, "-i", ICON, summary, body], check=False)


def handle(extension: Extension) -> bool:
    """Installs one into the user installation, or asks for the system one;
    False when an install failed"""
    if extension.installation == SYSTEM:
        notify("NVIDIA driver for Flatpak missing (system)", system_command(extension))
        return True
    if install(extension):
        notify("NVIDIA driver for Flatpak installed", "Restart Flatpak apps to use the GPU again.")
        return True
    print(f"Installing {extension.name} failed", file=sys.stderr)
    return False


def main(args: list[str]) -> int:
    if args:
        print(__doc__, file=sys.stderr)
        return 2
    driver_version = loaded_driver_version()
    if driver_version is None:
        return 0
    results = [handle(extension) for extension in missing_extensions(installed_runtimes(), driver_version)]
    if all(results):
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
