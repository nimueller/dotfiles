pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Laptop and touch mode as Hyprland applied them (config/hypr/modes.lua,
// which writes this file at every config load): detected from the
// hardware or forced in Machine Settings. Touch makes the bar and the
// buttons bigger and adds the launcher, close and keyboard buttons to the
// bar; laptop adds the battery menu and its warnings.
Singleton {
    id: root

    property bool laptop: false
    property bool touch: false
    property var detected: ({ laptop: false, touch: false })

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/dotfiles-modes.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const m = JSON.parse(text());
                root.laptop = !!m.laptop;
                root.touch = !!m.touch;
                root.detected = m.detected ?? root.detected;
            } catch (e) {}
        }
    }
}
