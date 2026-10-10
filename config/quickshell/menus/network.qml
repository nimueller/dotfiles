import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Network menu for the waybar network module, on top of nmcli.
Popup {
    id: popup

    name: "network"

    property string connectivity: ""
    property bool wifiEnabled: false
    property var wired: [] // { device, state, connection, address, speed }
    property var wifi: null // { device, state, connection }
    property var networks: [] // { ssid, signal, secure, active, known }
    property bool loaded: false

    property string expanded: "" // SSID with its details open
    property string busy: "" // SSID being connected
    property string error: ""

    readonly property var connectivityInfo: ({
            full: ["Online", Theme.green],
            limited: ["Limited", Theme.yellow],
            portal: ["Sign-in needed", Theme.yellow],
            none: ["Offline", Theme.red]
        })[connectivity] ?? ["", Theme.overlay1]

    function refresh() {
        status.running = true;
    }

    // Run nmcli, show its error if it fails, then refresh
    function nmcli(args, ssid) {
        busy = ssid ?? "";
        error = "";
        action.command = ["nmcli", ...args];
        action.running = true;
    }

    // Split a `nmcli -t` line on unescaped colons
    function fields(line) {
        const out = [""];
        for (let i = 0; i < line.length; i++) {
            if (line[i] === "\\" && i + 1 < line.length)
                out[out.length - 1] += line[++i];
            else if (line[i] === ":")
                out.push("");
            else
                out[out.length - 1] += line[i];
        }
        return out;
    }

    function parse(text) {
        const sections = {};
        let current = null;
        for (const line of text.split("\n")) {
            if (line.startsWith("@"))
                sections[current = line.slice(1)] = [];
            else if (current && line)
                sections[current].push(line);
        }

        connectivity = (sections.conn ?? [""])[0];
        wifiEnabled = (sections.radio ?? [""])[0] === "enabled";

        const addresses = {};
        try {
            for (const iface of JSON.parse((sections.addr ?? []).join("\n")))
                addresses[iface.ifname] = iface.addr_info?.[0]?.local ?? "";
        } catch (e) {}
        const speeds = {};
        for (const line of sections.speed ?? []) {
            const [dev, speed] = line.split(":");
            speeds[dev] = parseInt(speed);
        }

        const devices = (sections.dev ?? []).map(fields).filter(f => f[2] !== "unmanaged").map(f => ({
                    device: f[0],
                    type: f[1],
                    state: f[2],
                    connection: f[3],
                    address: addresses[f[0]] ?? "",
                    speed: speeds[f[0]] > 0 ? speeds[f[0]] : 0
                }));
        wired = devices.filter(d => d.type === "ethernet");
        wifi = devices.find(d => d.type === "wifi") ?? null;

        const known = new Set((sections.known ?? []).map(fields).filter(f => f[1].includes("wireless")).map(f => f[0]));
        const bySsid = {};
        for (const f of (sections.wifi ?? []).map(fields)) {
            const [inUse, signal, security, ssid] = f;
            if (!ssid)
                continue;
            const n = {
                ssid,
                signal: parseInt(signal) || 0,
                secure: !!security && security !== "--",
                active: inUse === "*",
                known: known.has(ssid)
            };
            const prev = bySsid[ssid];
            if (!prev || n.active || (!prev.active && n.signal > prev.signal))
                bySsid[ssid] = n;
        }
        networks = Object.values(bySsid).sort((a, b) => b.active - a.active || b.known - a.known || b.signal - a.signal);
        loaded = true;
    }

    Process {
        id: status
        running: true
        command: ["sh", "-c", `
            echo @conn; nmcli networking connectivity
            echo @radio; nmcli radio wifi
            echo @dev; nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device
            echo @wifi; nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no
            echo @known; nmcli -t -f NAME,TYPE connection show
            echo @addr; ip -j -4 addr
            echo @speed; for d in /sys/class/net/*; do echo "\${d##*/}:$(cat "$d/speed" 2>/dev/null)"; done
        `]
        stdout: StdioCollector {
            onStreamFinished: popup.parse(text)
        }
    }

    Process {
        id: action
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: code => {
            if (code !== 0)
                popup.error = actionErr.text.replace(/^Error:\s*/, "").trim() || "Something went wrong";
            else if (popup.busy)
                popup.expanded = "";
            popup.busy = "";
            popup.refresh();
        }
    }

    // Look for networks while the menu is open
    Component.onCompleted: Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"])

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: if (!action.running) popup.refresh()
    }

    Header {
        glyph: Theme.glyph(0xf06f3) // 󰛳
        accent: Theme.sapphire
        title: "Network"
        badge: popup.connectivityInfo[0]
        badgeColor: popup.connectivityInfo[1]

        IconButton {
            glyph: Theme.glyph(0xf0493) // 󰒓
            onClicked: {
                Quickshell.execDetached(["nm-connection-editor"]);
                Qt.quit();
            }
        }
    }

    // Wired
    ColumnLayout {
        Layout.fillWidth: true
        visible: popup.wired.length > 0
        spacing: 8

        SectionTitle {
            text: "Wired"
        }

        Repeater {
            model: popup.wired

            delegate: Rectangle {
                id: wiredRow

                required property var modelData
                readonly property bool connected: modelData.state === "connected"
                readonly property bool unplugged: modelData.state === "unavailable"

                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 10
                color: Theme.alpha(Theme.surface0, 0.5)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 8
                        color: wiredRow.connected ? Theme.alpha(Theme.sapphire, 0.15) : Theme.surface0

                        Label {
                            anchors.centerIn: parent
                            text: Theme.glyph(0xf0200) // 󰈀
                            font.pixelSize: 16
                            color: wiredRow.connected ? Theme.sapphire : Theme.overlay0
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            Layout.fillWidth: true
                            text: wiredRow.modelData.connection || wiredRow.modelData.device
                            color: wiredRow.connected ? Theme.text : Theme.subtext0
                        }
                        Label {
                            Layout.fillWidth: true
                            font.pixelSize: 10
                            color: Theme.overlay1
                            text: {
                                const d = wiredRow.modelData;
                                if (wiredRow.unplugged)
                                    return `${d.device} · cable unplugged`;
                                if (!wiredRow.connected)
                                    return `${d.device} · ${d.state}`;
                                const speed = d.speed >= 1000 ? `${d.speed / 1000} Gb/s` : d.speed ? `${d.speed} Mb/s` : "";
                                return [d.device, d.address, speed].filter(x => x).join(" · ");
                            }
                        }
                    }

                    Switch {
                        checked: wiredRow.connected
                        enabled: !wiredRow.unplugged
                        accent: Theme.sapphire
                        onToggled: popup.nmcli(["device", wiredRow.connected ? "disconnect" : "connect", wiredRow.modelData.device])
                    }
                }
            }
        }
    }

    // Wi-Fi
    ColumnLayout {
        Layout.fillWidth: true
        visible: !!popup.wifi
        spacing: 8

        RowLayout {
            Layout.fillWidth: true

            SectionTitle {
                Layout.fillWidth: true
                text: "Wi-Fi"
            }
            Switch {
                checked: popup.wifiEnabled
                accent: Theme.sapphire
                onToggled: popup.nmcli(["radio", "wifi", popup.wifiEnabled ? "off" : "on"])
            }
        }

        Label {
            visible: !popup.wifiEnabled
            text: "Wi-Fi is off"
            color: Theme.overlay0
            font.italic: true
        }
        Label {
            visible: popup.wifiEnabled && popup.networks.length === 0
            text: "Looking for networks…"
            color: Theme.overlay0
            font.italic: true
        }

        ListView {
            id: wifiList

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 320)
            visible: popup.wifiEnabled && popup.networks.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: popup.networks

            delegate: WifiRow {
                required property var modelData

                width: wifiList.width
                network: modelData
                expanded: popup.expanded === modelData.ssid
                busy: popup.busy === modelData.ssid
                error: popup.expanded === modelData.ssid ? popup.error : ""

                onClicked: {
                    popup.error = "";
                    if (!modelData.active && !modelData.known && !modelData.secure)
                        popup.nmcli(["device", "wifi", "connect", modelData.ssid], modelData.ssid);
                    else
                        popup.expanded = popup.expanded === modelData.ssid ? "" : modelData.ssid;
                }
                onConnectRequested: password => {
                    if (modelData.known)
                        popup.nmcli(["connection", "up", "id", modelData.ssid], modelData.ssid);
                    else if (password)
                        popup.nmcli(["device", "wifi", "connect", modelData.ssid, "password", password], modelData.ssid);
                    else
                        popup.nmcli(["device", "wifi", "connect", modelData.ssid], modelData.ssid);
                }
                onDisconnectRequested: popup.nmcli(["device", "disconnect", popup.wifi.device])
                onForgetRequested: popup.nmcli(["connection", "delete", "id", modelData.ssid])
            }
        }
    }
}
