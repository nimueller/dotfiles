pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// This machine's settings for the shell, from config/hypr/local.lua: the
// "-- settings:" line that Machine Settings (settings.qml) writes. Read
// again whenever the file changes.
Singleton {
    id: root

    property var settings: ({})

    // The focused window's title in the bar
    readonly property bool windowTitle: settings.bar?.windowTitle ?? false

    // The main monitor (notifications): the screen whose model and serial
    // number are in its description, else the one on its port, else the first
    readonly property var mainMonitor: (settings.monitors ?? []).find(m => m.main) ?? null
    readonly property var mainScreen: {
        const m = mainMonitor;
        const byDesc = m && Quickshell.screens.find(s => s.model && s.serialNumber && m.desc.includes(s.model) && m.desc.includes(s.serialNumber));
        return byDesc ?? (m && Quickshell.screens.find(s => s.name === m.name)) ?? Quickshell.screens[0];
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.config/hypr/local.lua`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const line = text().match(/^-- settings: (.*)$/m);
            try {
                root.settings = line ? JSON.parse(line[1]) : {};
            } catch (e) {}
        }
        onLoadFailed: root.settings = {}
    }
}
