pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The screen recording that runs, from the state file screenshot.py writes
// while wf-recorder records and removes after; the bar shows it and stops
// it.
Singleton {
    id: root

    property bool active: false
    property real started: 0 // s since the epoch
    property real now: Date.now() / 1000
    // 0:42, 1:02:45
    readonly property string elapsed: {
        const s = Math.max(0, Math.floor(now - started));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = String(s % 60).padStart(2, "0");
        return h ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
    }

    function stop() {
        Quickshell.execDetached([Quickshell.shellPath("screenshot.py"), "--stop"]);
    }

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/qs-recording.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.started = JSON.parse(text()).started;
                root.now = Date.now() / 1000;
                root.active = true;
            } catch (e) {
                root.active = false;
            }
        }
        onLoadFailed: root.active = false
    }

    Timer {
        running: root.active
        interval: 1000
        repeat: true
        onTriggered: root.now = Date.now() / 1000
    }
}
