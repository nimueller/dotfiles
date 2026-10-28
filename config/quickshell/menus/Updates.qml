pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Waiting updates from pacman, the AUR and Flatpak, and the age of the
// dotfiles' flake.lock (updates.py), for the bar's update chip and the
// system menu. Checked a minute after the start and then every hour; the
// system menu asks again when it opens (refresh()), and so does the
// terminal of the update when it closes.
Singleton {
    id: root

    property var pacman: null // counts, null while unknown or without the tool
    property var aur: null
    property var flatpak: null
    property string aurHelper: "" // yay or paru, "" without one
    property var flakeAge: null // days
    property bool flakeStale: false
    property bool checked: false // at least once
    readonly property bool checking: helper.running

    readonly property int total: (pacman ?? 0) + (aur ?? 0) + (flatpak ?? 0)

    function refresh() {
        helper.running = true;
    }

    // pacman and the AUR together through the helper, then Flatpak; in a
    // terminal, which checks again once it's closed
    function update() {
        const system = aurHelper ? `${aurHelper} -Syu` : "sudo pacman -Syu";
        updater.command = ["kitty", "--hold", "sh", "-c", `${system}; flatpak update`];
        updater.running = true;
    }

    Process {
        id: helper

        command: [Quickshell.shellPath("updates.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try {
                    r = JSON.parse(text);
                } catch (e) {
                    return;
                }
                root.pacman = r.pacman;
                root.aur = r.aur;
                root.flatpak = r.flatpak;
                root.aurHelper = r.aurHelper ?? "";
                root.flakeAge = r.flakeAge;
                root.flakeStale = !!r.flakeStale;
                root.checked = true;
            }
        }
    }

    Process {
        id: updater
        onExited: root.refresh()
    }

    // Not right at login, when the network may not be up yet
    Timer {
        interval: 60000
        running: true
        onTriggered: {
            root.refresh();
            interval = 3600000;
            repeat = true;
            restart();
        }
    }
}
