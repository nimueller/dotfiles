import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Network menu for the waybar network module, on top of nmcli: wired
// devices, Wi-Fi and VPN connections (OpenVPN etc. and WireGuard).
Popup {
    id: popup

    name: "network"

    property string connectivity: ""
    property bool wifiEnabled: false
    property var wired: [] // { device, state, connection, address, speed }
    property var wifi: null // { device, state, connection }
    property var networks: [] // { ssid, signal, secure, active, known }
    property var vpns: [] // { name, uuid, kind, state, address, needsPassword, hasChallenge }
    property var vpnInfo: ({}) // uuid -> { service, data } for type "vpn"
    property bool loaded: false

    property string expanded: "" // SSID or VPN uuid with its details open
    property string busy: "" // SSID or VPN uuid being (dis)connected
    property string error: "" // shown on the expanded row

    readonly property var connectivityInfo: ({
            full: ["Online", Theme.green],
            limited: ["Limited", Theme.yellow],
            portal: ["Sign-in needed", Theme.yellow],
            none: ["Offline", Theme.red]
        })[connectivity] ?? ["", Theme.overlay1]

    function refresh() {
        status.running = true;
    }

    // Run nmcli, show its error on the row `key` if it fails, then refresh.
    // `input` is written to its stdin (VPN passwords via passwd-file).
    function nmcli(args, key, input) {
        busy = key ?? "";
        error = "";
        action.input = input ?? "";
        action.stdinEnabled = !!input;
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

        const connections = (sections.connections ?? []).map(fields); // NAME,UUID,TYPE,STATE,DEVICE
        const known = new Set(connections.filter(f => f[2].includes("wireless")).map(f => f[0]));
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

        vpns = connections.filter(f => f[2] === "vpn" || f[2] === "wireguard").map(([name, uuid, type, state, device]) => {
            const info = vpnInfo[uuid] ?? {};
            const service = (info.service ?? "").split(".").pop();
            return {
                name,
                uuid,
                kind: type === "wireguard" ? "WireGuard" : service === "openvpn" ? "OpenVPN" : service || "VPN",
                state,
                address: type === "wireguard" ? addresses[device] ?? "" : "",
                // Secrets the profile doesn't store itself (agent-owned or
                // not saved); with no secret agent running we ask for them
                needsPassword: /password-flags\s*=\s*[12]/.test(info.data ?? ""),
                hasChallenge: /challenge-response-flags\s*=\s*[12]/.test(info.data ?? "")
            };
        }).sort((a, b) => (b.state === "activated") - (a.state === "activated") || a.name.localeCompare(b.name));
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
            echo @connections; nmcli -t -f NAME,UUID,TYPE,STATE,DEVICE connection show
            echo @addr; ip -j -4 addr
            echo @speed; for d in /sys/class/net/*; do echo "\${d##*/}:$(cat "$d/speed" 2>/dev/null)"; done
        `]
        stdout: StdioCollector {
            onStreamFinished: popup.parse(text)
        }
    }

    // Service type and (non-secret) settings of each VPN, to know whether it
    // needs a password. Only once: these don't change while the menu is open.
    Process {
        running: true
        command: ["sh", "-c", `
            nmcli -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do
                [ "$type" = vpn ] || continue
                printf '%s\\t%s\\t%s\\n' "$uuid" "$(nmcli -g vpn.service-type connection show uuid "$uuid")" \\
                    "$(nmcli -g vpn.data connection show uuid "$uuid" | tr '\\n' ' ')"
            done
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {};
                for (const line of text.split("\n").filter(l => l)) {
                    const [uuid, service, data] = line.split("\t");
                    info[uuid] = { service, data };
                }
                popup.vpnInfo = info;
                popup.refresh();
            }
        }
    }

    Process {
        id: action

        property string input: ""

        stderr: StdioCollector {
            id: actionErr
        }
        onStarted: {
            if (input) {
                write(input);
                stdinEnabled = false; // EOF for passwd-file /dev/stdin
            }
        }
        onExited: code => {
            input = "";
            if (code !== 0) {
                popup.error = actionErr.text.replace(/^Error:\s*/, "").trim() || "Something went wrong";
                if (popup.busy)
                    popup.expanded = popup.busy;
            } else if (popup.busy) {
                popup.expanded = "";
            }
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

    // VPN
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            SectionTitle {
                Layout.fillWidth: true
                text: "VPN"
            }

            // .ovpn (OpenVPN) or .conf (WireGuard) file. The file chooser
            // would close the menu anyway, so hand over to a detached script
            // that reports back with a notification.
            IconButton {
                glyph: Theme.glyph(0xf0220) // 󰈠
                text: "Import"
                onClicked: {
                    Quickshell.execDetached(["sh", "-c", `
                        f=$(zenity --file-selection --title="Import VPN configuration" \\
                            --file-filter="VPN configuration | *.ovpn *.conf" --file-filter="All files | *") || exit 0
                        case $f in *.conf) type=wireguard ;; *) type=openvpn ;; esac
                        if out=$(nmcli connection import type "$type" file "$f" 2>&1); then
                            notify-send -a Network "VPN imported" "$out"
                        else
                            notify-send -u critical -a Network "VPN import failed" "$out"
                        fi
                    `]);
                    popup.close();
                }
            }
            IconButton {
                glyph: Theme.glyph(0xf0415) // 󰐕
                text: "New"
                onClicked: {
                    Quickshell.execDetached(["nm-connection-editor", "--create"]);
                    popup.close();
                }
            }
        }

        Label {
            visible: popup.loaded && popup.vpns.length === 0
            text: "No VPN connections yet"
            color: Theme.overlay0
            font.italic: true
        }

        Repeater {
            model: popup.vpns

            delegate: VpnRow {
                required property var modelData

                Layout.fillWidth: true
                vpn: modelData
                expanded: popup.expanded === modelData.uuid
                busy: popup.busy === modelData.uuid
                error: popup.expanded === modelData.uuid ? popup.error : ""

                onClicked: {
                    popup.error = "";
                    popup.expanded = popup.expanded === modelData.uuid ? "" : modelData.uuid;
                }
                onToggled: {
                    const on = modelData.state === "activated" || modelData.state === "activating";
                    if (on) {
                        popup.nmcli(["connection", "down", "uuid", modelData.uuid], modelData.uuid);
                    } else if (modelData.needsPassword) {
                        popup.error = "";
                        popup.expanded = modelData.uuid;
                    } else {
                        popup.nmcli(["connection", "up", "uuid", modelData.uuid], modelData.uuid);
                    }
                }
                onConnectRequested: (password, code) => {
                    let secrets = `vpn.secrets.password:${password}\n`;
                    if (code)
                        secrets += `vpn.secrets.challenge-response:${code}\n`;
                    popup.nmcli(["connection", "up", "uuid", modelData.uuid, "passwd-file", "/dev/stdin"], modelData.uuid, secrets);
                }
                onEditRequested: {
                    Quickshell.execDetached(["nm-connection-editor", `--edit=${modelData.uuid}`]);
                    popup.close();
                }
                onRemoveRequested: popup.nmcli(["connection", "delete", "uuid", modelData.uuid])
            }
        }
    }
}
