pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// What can go from the disk (cleanup.py), for the cleanup menu. Here and not
// in the menu, so a cleanup that takes minutes goes on after it closes.
Singleton {
    id: root

    property var items: [] // [{ id, title, detail, bytes, blocked }]
    property real free: 0 // bytes
    property bool scanned: false
    property string error: ""
    property var queue: [] // ids still to clean
    property string cleaning: "" // id
    readonly property bool scanning: scanner.running
    readonly property bool busy: cleaner.running

    function size(bytes) {
        const gib = 1073741824;
        if (bytes >= 10 * gib)
            return `${Math.round(bytes / gib)} GB`;
        return bytes >= gib ? `${(bytes / gib).toFixed(1)} GB` : `${Math.round(bytes / 1048576)} MB`;
    }

    function refresh() {
        if (!busy)
            scanner.running = true;
    }

    function clean(ids) {
        if (busy)
            return;
        error = "";
        queue = ids;
        next();
    }

    function next() {
        if (!queue.length) {
            cleaning = "";
            refresh();
            return;
        }
        cleaning = queue[0];
        queue = queue.slice(1);
        cleaner.command = [Quickshell.shellPath("cleanup.py"), "clean", cleaning];
        cleaner.running = true;
    }

    Process {
        id: scanner

        command: [Quickshell.shellPath("cleanup.py"), "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.items = r.items;
                    root.free = r.free;
                    root.scanned = true;
                } catch (e) {
                    root.error = "Couldn't look at the disk";
                }
            }
        }
    }

    Process {
        id: cleaner

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (JSON.parse(text).error)
                        root.error = JSON.parse(text).error;
                } catch (e) {
                    root.error = "The cleanup failed";
                }
            }
        }
        // Only now, when it's no longer running, can the next one start
        onExited: root.next()
    }
}
