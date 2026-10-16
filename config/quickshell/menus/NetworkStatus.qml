import QtQuick
import Quickshell.Io

// What the bar shows for the network: the connected device's type and
// connection name, kept current by `nmcli monitor`, and on Wi-Fi its
// signal, which nmcli doesn't report changes of: every 30 seconds.
Item {
    id: root

    property string kind: "" // ethernet | wifi | "" (disconnected)
    property string name: ""
    property int signal: 100 // Wi-Fi, 0-100

    function refresh() {
        status.running = true;
    }

    Process {
        id: wifiSignal
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.split("\n").find(l => l.startsWith("*:"));
                if (line)
                    root.signal = parseInt(line.slice(2)) || 0;
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.kind === "wifi"
        triggeredOnStart: true
        onTriggered: wifiSignal.running = true
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
