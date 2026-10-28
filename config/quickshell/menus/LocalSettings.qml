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

    // This machine's location { name, lat, lon }, or null: for the weather
    // (unless the calendar has its own) and the night light (night-light.py
    // reads it from local.lua itself)
    readonly property var location: {
        const l = settings.location;
        return l && typeof l.lat === "number" && typeof l.lon === "number" ? l : null;
    }

    // When SystemWatch.qml warns: memory below percent free, the CPU's
    // pressure above percent for minutes, and the disks with / and the home
    // folder below percent or gb free (whichever is less) at each level, the
    // last one critical
    readonly property var warningDefaults: ({
            memory: { on: true, percent: 8 },
            cpu: { on: true, percent: 80, minutes: 1 },
            disk: { on: true, levels: [{ percent: 10, gb: 20 }, { percent: 5, gb: 10 }, { percent: 3, gb: 5 }] }
        })
    readonly property var warnings: withDefaults(settings.warnings)

    function withDefaults(w) {
        const d = warningDefaults;
        const disk = Object.assign({}, d.disk, w?.disk);
        if (!Array.isArray(disk.levels) || disk.levels.length !== d.disk.levels.length)
            disk.levels = d.disk.levels;
        return { memory: Object.assign({}, d.memory, w?.memory), cpu: Object.assign({}, d.cpu, w?.cpu), disk };
    }

    // Rules for notifications (NotificationStore.qml): { app, text, action }.
    // app is part of the app's name or desktop entry, text part of the
    // summary or body, both ignoring case; an empty one matches anything, a
    // rule with neither is skipped. The first rule that matches decides:
    // "hide" drops the notification, "center" keeps it from popping up,
    // "popup" keeps it out of the notification center.
    readonly property var notificationRules: (settings.notifications?.rules ?? []).filter(r => r.app?.trim() || r.text?.trim())

    // The rule for media players' track announcements (NotificationStore.qml),
    // after the others: an action as above, "" to treat them like any other
    readonly property string trackAction: settings.notifications?.tracks ?? "popup"

    function notificationAction(app, desktop, summary, body) {
        const has = (haystacks, needle) => !needle?.trim() || haystacks.some(h => (h ?? "").toLowerCase().includes(needle.trim().toLowerCase()));
        return notificationRules.find(r => has([app, desktop], r.app) && has([summary, body], r.text))?.action ?? "";
    }

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
