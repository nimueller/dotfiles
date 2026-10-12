import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Wayland

// The notification daemon's state (replaces dunst): receives notifications,
// keeps a history for the notification center (saved across restarts),
// and decides what pops up. The bar's bell reads it directly.
//
// Entries: { key, id, n (live Notification, or null after a restart), app,
// summary, body, icon, urgency (0 low, 1 normal, 2 critical), time (ms),
// pid (the sender's process, from the sender-pid hint libnotify sets),
// desktop (desktop entry id) }
//
// A media player's notification about the track it plays pops up like any
// other but stays out of the history: its sender is the process behind an
// MPRIS player, and it names that player's current track.
Scope {
    id: root

    readonly property int historyLength: 50
    readonly property string historyPath: `${Quickshell.env("HOME")}/.cache/quickshell-notifications.json`

    property var entries: [] // newest first
    property var popups: [] // keys of entries popping up right now
    property bool dnd: false
    // The screen is shared (Privacy.qml): nothing pops up, like with do not
    // disturb, but without touching (and saving) the user's own setting
    property bool sharing: false
    readonly property bool silenced: dnd || sharing
    property int nextKey: 1

    // Icon for a notification: its image, the app icon (name or path), or
    // the icon of its desktop entry. Quickshell hands app icons over as
    // image://icon/<name or path>; paths are kept as file:// so the icon
    // still shows after a restart, names must exist in the icon theme.
    function iconFor(n) {
        for (let c of [n.image, n.appIcon, DesktopEntries.byId(n.desktopEntry)?.icon]) {
            if (!c)
                continue;
            if (c.startsWith("image://icon/"))
                c = c.slice("image://icon/".length);
            if (c.startsWith("/"))
                return `file://${c}`;
            if (c.includes("://"))
                return c;
            const path = Quickshell.iconPath(c, true);
            if (path)
                return path;
        }
        return "";
    }

    function entry(key) {
        return entries.find(e => e.key === key) ?? null;
    }

    function add(n) {
        // An update of a notification that's already here (replaces_id)
        const old = entries.find(e => e.n === n);
        const e = {
            key: old?.key ?? nextKey++,
            id: n.id,
            n,
            app: n.appName || DesktopEntries.byId(n.desktopEntry)?.name || "",
            summary: n.summary,
            body: n.body,
            icon: iconFor(n),
            urgency: n.urgency === NotificationUrgency.Critical ? 2 : n.urgency === NotificationUrgency.Low ? 0 : 1,
            time: Date.now(),
            transient: n.transient,
            pid: Number(n.hints["sender-pid"] ?? 0),
            desktop: n.desktopEntry
        };
        entries = [e, ...entries.filter(x => x.key !== e.key)].slice(0, historyLength);
        // The sender's window, for the popup: it may be new, and short-lived
        // senders (notify-send) are gone in a moment
        Windows.refresh();
        if (e.pid)
            Windows.readAncestors(e.pid);
        trackCheck.restart();
        if (!silenced && !popups.includes(e.key))
            popups = [e.key, ...popups];
        n.closed.connect(() => {
            // The app withdrew it (or it was dismissed): drop the live object
            const current = entry(e.key);
            if (current)
                current.n = null;
            closePopup(e.key);
        });
        changed();
    }

    function closePopup(key) {
        popups = popups.filter(k => k !== key);
        // Transient notifications don't stay in the history
        const e = entry(key);
        if (e?.transient)
            remove(key);
    }

    function closeAllPopups() {
        for (const key of popups.slice())
            closePopup(key);
    }

    function remove(key) {
        const e = entry(key);
        e?.n?.dismiss();
        entries = entries.filter(x => x.key !== key);
        popups = popups.filter(k => k !== key);
        changed();
    }

    function clear() {
        for (const e of entries)
            e.n?.dismiss();
        entries = [];
        popups = [];
        changed();
    }

    // Track announcements -----------------------------------------------------

    // The process behind each MPRIS player: the owner of its D-Bus name
    property var playerPids: ({}) // dbusName → pid
    readonly property var playerNames: Mpris.players.values.map(p => p.dbusName)

    onPlayerNamesChanged: {
        playerPidsProc.command = ["sh", "-c", 'for n; do echo "$n $(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s "$n" | cut -d" " -f2)"; done', "sh", ...playerNames];
        playerPidsProc.running = true;
    }

    Process {
        id: playerPidsProc
        stdout: StdioCollector {
            onStreamFinished: {
                const pids = {};
                for (const line of text.split("\n")) {
                    const [name, pid] = line.split(" ");
                    if (name && parseInt(pid) > 0)
                        pids[name] = parseInt(pid);
                }
                root.playerPids = pids;
            }
        }
    }

    function isTrack(e) {
        if (!e.pid)
            return false;
        const chain = Windows.readAncestors(e.pid);
        return Mpris.players.values.some(p => p.trackTitle && chain.includes(playerPids[p.dbusName]) && [e.summary, e.body].some(t => (t ?? "").includes(p.trackTitle)));
    }

    // Players update their track a moment after (or before) they notify, so
    // check new entries shortly after they arrive. Popping up ones leave the
    // history when they close.
    Timer {
        id: trackCheck
        interval: 2000
        onTriggered: {
            for (const e of root.entries.filter(e => !e.transient && Date.now() - e.time < 10000 && root.isTrack(e))) {
                e.transient = true;
                if (!root.popups.includes(e.key))
                    root.remove(e.key);
            }
        }
    }

    function setDnd(on) {
        dnd = on;
        changed();
    }

    onSilencedChanged: {
        if (silenced)
            popups = [];
    }

    // Click on a notification: run its default action if the app still
    // listens, otherwise bring the app's window up. Then it's done.
    function activate(key) {
        const e = entry(key);
        if (!e)
            return;
        const action = e.n?.actions.find(a => a.identifier === "default");
        if (action)
            action.invoke();
        else
            focusApp(e);
        remove(key);
    }

    function invoke(key, identifier) {
        const e = entry(key);
        e?.n?.actions.find(a => a.identifier === identifier)?.invoke();
        remove(key);
    }

    // The window that sent it (Windows.qml), else one whose app id loosely
    // matches the app ("Thunderbird" matches "org.mozilla.Thunderbird")
    function focusApp(e) {
        const sender = (e.pid ? Windows.forPid(e.pid) : null) ?? Windows.forApp(e.desktop);
        if (sender?.wayland) {
            sender.wayland.activate();
            return;
        }
        const norm = s => (s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
        const app = norm(e.app), desktop = norm(e.n?.desktopEntry);
        const window = ToplevelManager.toplevels.values.find(t => {
            const id = norm(t.appId), short = norm(t.appId.split(".").pop());
            return (desktop && (id === desktop || id.includes(desktop))) || (app && (id.includes(app) || (short.length > 2 && app.includes(short))));
        });
        window?.activate();
    }

    // History file ----------------------------------------------------------------

    function changed() {
        saveTimer.restart();
    }

    FileView {
        id: historyFile
        path: root.historyPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                root.dnd = saved.dnd ?? false;
                root.entries = (saved.entries ?? []).map(e => Object.assign({}, e, { key: root.nextKey++, n: null }));
            } catch (e) {}
        }
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: historyFile.setText(JSON.stringify({
            dnd: root.dnd,
            entries: root.entries.filter(e => !e.transient).map(e => ({
                        id: e.id,
                        app: e.app,
                        summary: e.n?.summary ?? e.summary,
                        body: e.n?.body ?? e.body,
                        // Image data doesn't survive a restart; theme icons and files do
                        icon: e.icon.startsWith("image://") && !e.icon.startsWith("image://icon/") ? "" : e.icon,
                        urgency: e.urgency,
                        time: e.time
                    }))
        }))
    }

    NotificationServer {
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            root.add(n);
        }
    }
}
