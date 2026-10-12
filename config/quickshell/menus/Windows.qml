pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Which window belongs to a process or an app, for the sound menu's streams
// and the notifications.
//  - A process: its own window, or else the window of the nearest ancestor
//    running the same program. Apps often play sound or send notifications
//    from a helper process (Electron's and Chromium's audio service, a
//    browser's renderer) whose parent owns the window; a program started from
//    a terminal doesn't belong to the terminal's window.
//  - An app: the window whose Wayland app id is the app's desktop entry id,
//    which is how the two are linked (desktop-entry hint, app_id).
// Of several matching windows, the most recently focused one. Window PIDs
// come from Hyprland's IPC data; refresh() updates them (new windows).
Singleton {
    id: root

    function refresh() {
        Hyprland.refreshToplevels();
    }

    function newest(windows) {
        return windows.sort((a, b) => (a.lastIpcObject.focusHistoryID ?? 1e9) - (b.lastIpcObject.focusHistoryID ?? 1e9))[0] ?? null;
    }

    // { comm, ppid } of a process, null once it's gone
    function stat(pid) {
        statFile.path = `/proc/${pid}/stat`;
        const text = statFile.text();
        if (!text)
            return null;
        // pid (comm) state ppid ...; comm may contain spaces and parentheses
        const close = text.lastIndexOf(")");
        return { comm: text.slice(text.indexOf("(") + 1, close), ppid: parseInt(text.slice(close + 2).split(" ")[1]) };
    }

    // pid, then its parent, its parent's parent, ... as long as they run the
    // same program. Reads /proc, so not for bindings: they use ancestors().
    function readAncestors(pid) {
        const chain = [];
        const comm = stat(pid)?.comm;
        for (let p = pid, s = stat(p); s && s.comm === comm && chain.length < 32; p = s.ppid, s = p > 1 ? stat(p) : null)
            chain.push(p);
        chains = Object.assign({}, chains, { [pid]: chain });
        return chain;
    }

    // The same for bindings: from the cache, read soon after if not there
    // yet (a process's ancestors don't change while it runs)
    property var chains: ({}) // pid → ancestors
    function ancestors(pid) {
        if (!chains[pid])
            Qt.callLater(readAncestors, pid);
        return chains[pid] ?? [];
    }

    function forPid(pid) {
        const windows = Hyprland.toplevels.values.filter(t => t.lastIpcObject?.pid > 0);
        for (const p of ancestors(pid)) {
            const found = newest(windows.filter(t => t.lastIpcObject.pid === p));
            if (found)
                return found;
        }
        return null;
    }

    function forApp(id) {
        return id ? newest(Hyprland.toplevels.values.filter(t => t.lastIpcObject?.class === id)) : null;
    }

    // The desktop entry of a window's app, if it has one
    // (also evaluated again once the desktop entries have loaded)
    function entry(window) {
        const id = window?.lastIpcObject?.class ?? "";
        return id && DesktopEntries.applications.values.length >= 0 ? DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id) : null;
    }

    FileView {
        id: statFile
        blockAllReads: true
        printErrors: false
    }

    Component.onCompleted: refresh()
}
