pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Laptop and touch mode as Hyprland applied them (config/hypr/modes.lua,
// which writes this file at every config load): detected from the
// hardware or forced in Machine Settings. Touch makes the bar and the
// buttons bigger and adds the launcher, close and keyboard buttons to the
// bar; laptop adds the battery menu and its warnings. Tablet mode (the
// switch of a convertible, also from modes.lua) makes the menus bigger
// (Popup.qml).
Singleton {
    id: root

    property bool laptop: false
    property bool touch: false
    property var detected: ({ laptop: false, touch: false })
    property bool tablet: false

    // A compact bar on narrow screens (below 1700 logical pixels, like a
    // 13" laptop at scale 2): Bluetooth, the on-screen keyboard and power
    // move from the bar into the system menu, so the tray keeps clear of
    // the clock
    function compactBar(screen) {
        return (screen?.width ?? 0) > 0 && screen.width < 1700;
    }

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

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/dotfiles-tablet`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.tablet = text().trim() === "true"
        onLoadFailed: root.tablet = false
    }
}
