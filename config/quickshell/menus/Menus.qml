pragma Singleton

import QtQuick
import Quickshell

// The bar menus and the windows opened from them (<name>.qml), inside the
// resident daemon: each is created when it opens and destroyed when it
// closes, so it starts fresh and nothing of it runs while it's closed, like
// an instance of its own, but it opens without starting quickshell (~1 s).
// The bar calls toggle(), `toggle.sh <name>` does it through IPC (daemon.qml).
//
// A menu can still run on its own (`qs -p audio.qml`, to try it out): then
// `hosted` is false, close() quits and toggle() goes through toggle.sh.
Singleton {
    id: root

    readonly property var names: ["audio", "battery", "battery-history", "bluetooth", "calendar", "kdeconnect", "network", "power", "scan", "settings", "system", "window"]

    // Set by daemon.qml
    property bool hosted: false

    property var loaders: ({}) // name → LazyLoader
    property var closedAt: ({}) // name → ms

    function isOpen(name) {
        return !!loaders[name]?.active;
    }

    function toggle(name) {
        if (!hosted) {
            Quickshell.execDetached([Quickshell.shellPath("toggle.sh"), name]);
            return;
        }
        const loader = loaders[name];
        if (!loader)
            return;
        if (loader.active) {
            // Popups fade their focus out first (Popup.qml)
            if (typeof loader.item?.close === "function")
                loader.item.close();
            else
                close(name);
        } else if (Date.now() - (closedAt[name] ?? 0) > 400) {
            // A click on the bar icon of an open menu first closes it through
            // the focus grab, then toggles: that one mustn't reopen it
            loader.active = true;
        }
    }

    // Destroyed once the handler that closes it has returned
    function close(name) {
        if (!hosted) {
            Qt.callLater(Qt.quit);
            return;
        }
        closedAt = Object.assign({}, closedAt, { [name]: Date.now() });
        Qt.callLater(() => {
            if (loaders[name])
                loaders[name].active = false;
        });
    }

    Variants {
        model: root.names

        delegate: LazyLoader {
            required property string modelData

            source: Qt.resolvedUrl(`${modelData}.qml`)
            Component.onCompleted: root.loaders = Object.assign({}, root.loaders, { [modelData]: this })
        }
    }
}
