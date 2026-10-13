import QtQuick
import Quickshell
import Quickshell.Io

// The phones paired with KDE Connect, kept current by `kdeconnect.py watch`
// (no polling), which also mounts them for Files' sidebar.
Item {
    id: root

    // [{ id, name, type, reachable, battery (-1: unknown), charging, network, signal, mounted, storage: [[path, name]] }]
    property var devices: []
    readonly property var reachable: devices.filter(d => d.reachable)

    function run(action, device) {
        Quickshell.execDetached(["/usr/bin/python3", Quickshell.shellPath("kdeconnect.py"), action, device.id]);
    }

    Process {
        id: watch
        running: true
        command: ["/usr/bin/python3", Quickshell.shellPath("kdeconnect.py"), "watch"]
        stdout: SplitParser {
            onRead: line => root.devices = JSON.parse(line)
        }
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: watch.running = true
    }
}
