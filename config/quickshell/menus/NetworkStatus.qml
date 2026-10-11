import QtQuick
import Quickshell.Io

// What the bar shows for the network: the connected device's type and
// connection name, kept current by `nmcli monitor` (no polling).
Item {
    id: root

    property string kind: "" // ethernet | wifi | "" (disconnected)
    property string name: ""

    function refresh() {
        status.running = true;
    }

    Process {
        id: status
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Escaped colons only occur in the connection name (last field)
                const devices = text.split("\n").filter(l => l).map(l => {
                    const [type, state, ...rest] = l.split(":");
                    return { type, state, name: rest.join(":").replace(/\\:/g, ":") };
                }).filter(d => d.state === "connected");
                const device = devices.find(d => d.type === "ethernet") ?? devices.find(d => d.type === "wifi");
                root.kind = device?.type ?? "";
                root.name = device?.name ?? "";
            }
        }
    }

    // Any NetworkManager change: refresh a moment later
    Process {
        id: monitor
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: debounce.restart()
        }
        onExited: restart.start()
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.refresh()
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: monitor.running = true
    }

    Component.onCompleted: refresh()
}
