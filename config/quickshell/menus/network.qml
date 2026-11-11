// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Network menu for the bar's network module, on top of nmcli: wired
// devices, Wi-Fi and VPN connections (OpenVPN etc. and WireGuard). Saved
// Wi-Fi networks are matched by their SSID, not the profile's name; a
// saved one whose password stopped working asks for the new one, and
// enterprise networks (802.1X: user name and password) are set up in the
// connection editor. A saved Wi-Fi network can be shared as a QR code
// (qrencode), which phone cameras join it with.
Popup {
    id: popup

    name: "network"

    property string connectivity: ""
    property bool wifiEnabled: false
    property bool wifiHardware: true // false: switched off by a key or switch
    property var wired: [] // { device, state, connection, address, speed }
    property var wifi: null // { device, state, connection }
    property var networks: [] // { ssid, signal, secure, enterprise, active, known, uuid }
    property var wifiProfiles: ({}) // SSID -> uuid of its saved profile
    property var vpns: [] // { name, uuid, kind, state, address, needsPassword, hasChallenge }
    property var vpnInfo: ({}) // uuid -> { service, data } for type "vpn"
    property bool loaded: false

    property string expanded: "" // SSID or VPN uuid with its details open
    property string busy: "" // SSID or VPN uuid being (dis)connected
    property string error: "" // shown on the expanded row
    property string retry: "" // SSID whose saved password didn't work
    property var shared: null // { ssid, qr, password } of the network shown as a QR code

    onExpandedChanged: shared = null

    readonly property var connectivityInfo: ({
            full: [I18n.tr("Online"), Theme.green],
            limited: [I18n.tr("Limited"), Theme.yellow],
            portal: [I18n.tr("Sign-in needed"), Theme.yellow],
            none: [I18n.tr("Offline"), Theme.red]
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
            if (line[i] === "\\" && i + 1 < line.length) {
                out[out.length - 1] += line[++i];
            } else if (line[i] === ":") {
                out.push("");
            } else {
                out[out.length - 1] += line[i];
            }
        }
        return out;
    }

    function parse(text) {
        const sections = {};
        let current = null;
        for (const line of text.split("\n")) {
            if (line.startsWith("@")) {
                sections[current = line.slice(1)] = [];
            } else if (current && line) {
                sections[current].push(line);
            }
        }

        connectivity = (sections.conn ?? [""])[0];
        const radio = fields((sections.radio ?? [""])[0]); // WIFI-HW:WIFI
        wifiHardware = radio[0] !== "disabled";
        wifiEnabled = radio[1] === "enabled";

        const addresses = {};
        try {
            for (const iface of JSON.parse((sections.addr ?? []).join("\n"))) {
                addresses[iface.ifname] = iface.addr_info?.[0]?.local ?? "";
            }
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
        // Profiles by SSID; by name for those saved since the menu opened
        const byName = {};
        for (const f of connections.filter(f => f[2].includes("wireless"))) {
            byName[f[0]] = f[1];
        }
        const bySsid = {};
        for (const f of (sections.wifi ?? []).map(fields)) {
            const [inUse, signal, security, ssid] = f;
            if (!ssid) {
                continue;
            }
            const n = {
                ssid,
                signal: parseInt(signal) || 0,
                secure: !!security && security !== "--",
                enterprise: security.includes("802.1X"),
                active: inUse === "*",
                uuid: wifiProfiles[ssid] ?? byName[ssid] ?? ""
            };
            n.known = !!n.uuid;
            const prev = bySsid[ssid];
            if (!prev || n.active || (!prev.active && n.signal > prev.signal)) {
                bySsid[ssid] = n;
            }
        }
        const byRelevance = (a, b) => b.active - a.active || b.known - a.known || b.signal - a.signal;
        networks = Object.values(bySsid).sort(byRelevance);

        const isVpn = f => f[2] === "vpn" || f[2] === "wireguard";
        vpns = connections.filter(isVpn).map(([name, uuid, type, state, device]) => {
            const info = vpnInfo[uuid] ?? {};
            const service = (info.service ?? "").split(".").pop();
            let kind = service || "VPN";
            if (type === "wireguard") {
                kind = "WireGuard";
            } else if (service === "openvpn") {
                kind = "OpenVPN";
            }
            return {
                name,
                uuid,
                kind,
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
            echo @radio; nmcli -t -f WIFI-HW,WIFI radio
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
    // needs a password, and the SSID of each Wi-Fi profile. At the start and
    // after each change made here: these don't change by themselves.
    Process {
        id: profiles
        running: true
        command: ["sh", "-c", `
            nmcli -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do
                case $type in
                    vpn)
                        printf 'vpn\\t%s\\t%s\\t%s\\n' "$uuid" "$(nmcli -g vpn.service-type connection show uuid "$uuid")" \\
                            "$(nmcli -g vpn.data connection show uuid "$uuid" | tr '\\n' ' ')" ;;
                    802-11-wireless)
                        printf 'wifi\\t%s\\t%s\\n' "$uuid" "$(nmcli -g 802-11-wireless.ssid connection show uuid "$uuid")" ;;
                esac
            done
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {}, ssids = {};
                for (const line of text.split("\n").filter(l => l)) {
                    const [kind, uuid, a, b] = line.split("\t");
                    if (kind === "vpn") {
                        info[uuid] = {
                            service: a,
                            data: b
                        };
                    } else if (a) {
                        ssids[a.replace(/\\(.)/g, "$1")] = uuid; // -g escapes colons
                    }
                }
                popup.vpnInfo = info;
                popup.wifiProfiles = ssids;
                popup.refresh();
            }
        }
    }

    // Share a saved network: read its secret from NetworkManager, then turn
    // it into a Wi-Fi QR code. The image comes back as a data URL, so the
    // password is never written to a file.
    function share(network) {
        error = "";
        if (shared?.ssid === network.ssid) {
            shared = null;
            return;
        }
        secrets.ssid = network.ssid;
        const wireless = "802-11-wireless";
        const security = "802-11-wireless-security";
        const fields = `${wireless}.ssid,${wireless}.hidden,${security}.key-mgmt,${security}.psk,${security}.wep-key0`;
        secrets.command = ["nmcli", "-s", "-g", fields, "connection", "show", "uuid", network.uuid];
        secrets.running = true;
    }

    // The WIFI: format phones read: T(ype), S(SID), P(assword), H(idden),
    // with \ ; , : " escaped
    function wifiCode(text) {
        const unescape = l => l.replace(/\\(.)/g, "$1");
        const [ssid, hidden, keyMgmt, psk, wep] = text.replace(/\n$/, "").split("\n").map(unescape);
        let type = "nopass";
        let password = "";
        if (keyMgmt === "sae") {
            type = "SAE";
            password = psk;
        } else if (keyMgmt === "wpa-psk") {
            type = "WPA";
            password = psk;
        } else if (keyMgmt === "none" && wep) {
            type = "WEP";
            password = wep;
        }
        if (type !== "nopass" && !password) {
            error = I18n.tr("NetworkManager doesn't keep this password itself, so it can't be shared");
            return;
        }
        const esc = s => s.replace(/([\\;,:"])/g, "\\$1");
        let code = `WIFI:T:${type};S:${esc(ssid)};`;
        if (password) {
            code += `P:${esc(password)};`;
        }
        if (hidden === "yes") {
            code += "H:true;";
        }
        qrencode.ssid = secrets.ssid;
        qrencode.password = password;
        qrencode.input = code + ";";
        qrencode.running = true;
    }

    Process {
        id: secrets

        property string ssid: ""

        stdout: StdioCollector {
            onStreamFinished: if (text) {
                popup.wifiCode(text);
            }
        }
        stderr: StdioCollector {
            id: secretsErr
        }
        onExited: code => {
            if (code !== 0) {
                popup.error = secretsErr.text.replace(/^Error:\s*/, "").trim() || I18n.tr("Couldn't read the password");
            }
        }
    }

    Process {
        id: qrencode

        property string ssid: ""
        property string password: ""
        property string input: ""

        command: ["sh", "-c", "qrencode -t PNG -s 5 -m 0 -o - | base64 -w0"]
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text && popup.expanded === qrencode.ssid) {
                    popup.shared = {
                        ssid: qrencode.ssid,
                        qr: `data:image/png;base64,${text.trim()}`,
                        password: qrencode.password
                    };
                }
                qrencode.password = "";
            }
        }
        onStarted: {
            write(input);
            input = "";
            stdinEnabled = false; // EOF: qrencode reads the text until then
        }
        onExited: stdinEnabled = true
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
                popup.error = actionErr.text.replace(/^Error:\s*/, "").trim() || I18n.tr("Something went wrong");
                if (popup.busy) {
                    popup.expanded = popup.busy;
                }
                // A saved Wi-Fi network that didn't connect: ask for its password
                const n = popup.networks.find(n => n.ssid === popup.busy);
                if (n?.secure && !n.enterprise) {
                    popup.retry = n.ssid;
                }
            } else if (popup.busy) {
                if (popup.busy === popup.retry) {
                    popup.retry = "";
                }
                popup.expanded = "";
            }
            popup.busy = "";
            profiles.running = true; // and refresh
        }
    }

    // Look for networks while the menu is open
    Component.onCompleted: Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"])

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: if (!action.running) {
            popup.refresh();
        }
    }

    Header {
        glyph: Theme.glyph(0xf06f3) // 󰛳
        accent: Theme.sapphire
        title: I18n.tr("Network")
        badge: popup.connectivityInfo[0]
        badgeColor: popup.connectivityInfo[1]

        IconButton {
            glyph: Theme.glyph(0xf0493) // 󰒓
            onClicked: {
                Quickshell.execDetached(["nm-connection-editor"]);
                popup.close();
            }
        }
    }

    // Wired
    ColumnLayout {
        Layout.fillWidth: true
        visible: popup.wired.length > 0
        spacing: 8

        SectionTitle {
            text: I18n.tr("Wired")
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
                                if (wiredRow.unplugged) {
                                    return I18n.tr("%1 · cable unplugged", d.device);
                                }
                                if (!wiredRow.connected) {
                                    return `${d.device} · ${d.state}`;
                                }
                                let speed = "";
                                if (d.speed >= 1000) {
                                    speed = `${d.speed / 1000} Gb/s`;
                                } else if (d.speed) {
                                    speed = `${d.speed} Mb/s`;
                                }
                                return [d.device, d.address, speed].filter(x => x).join(" · ");
                            }
                        }
                    }

                    Switch {
                        checked: wiredRow.connected
                        enabled: !wiredRow.unplugged
                        accent: Theme.sapphire
                        onToggled: {
                            const action = wiredRow.connected ? "disconnect" : "connect";
                            popup.nmcli(["device", action, wiredRow.modelData.device]);
                        }
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
                text: I18n.tr("Wi-Fi")
            }
            Switch {
                checked: popup.wifiEnabled && popup.wifiHardware
                enabled: popup.wifiHardware
                accent: Theme.sapphire
                onToggled: popup.nmcli(["radio", "wifi", popup.wifiEnabled ? "off" : "on"])
            }
        }

        Label {
            visible: !popup.wifiHardware
            text: I18n.tr("Switched off by a key or switch (airplane mode)")
            color: Theme.overlay0
            font.italic: true
        }
        Label {
            visible: popup.wifiHardware && !popup.wifiEnabled
            text: I18n.tr("Wi-Fi is off")
            color: Theme.overlay0
            font.italic: true
        }
        Label {
            visible: popup.wifiEnabled && popup.wifiHardware && popup.networks.length === 0
            text: I18n.tr("Looking for networks…")
            color: Theme.overlay0
            font.italic: true
        }

        ListView {
            id: wifiList

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 320)
            visible: popup.wifiEnabled && popup.wifiHardware && popup.networks.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: popup.networks

            delegate: WifiRow {
                required property var modelData
                required property int index

                width: wifiList.width
                network: modelData
                expanded: popup.expanded === modelData.ssid
                busy: popup.busy === modelData.ssid
                askPassword: popup.retry === modelData.ssid
                address: modelData.active && popup.wifi?.address ? `${popup.wifi.device} · ${popup.wifi.address}` : ""
                error: popup.expanded === modelData.ssid ? popup.error : ""
                qr: popup.shared?.ssid === modelData.ssid ? popup.shared.qr : ""
                password: popup.shared?.ssid === modelData.ssid ? popup.shared.password : ""

                // Keep the QR code in view
                onQrChanged: if (qr) {
                    wifiList.positionViewAtIndex(index, ListView.Contain);
                }

                onClicked: {
                    popup.error = "";
                    if (!modelData.active && !modelData.known && !modelData.secure) {
                        popup.nmcli(["device", "wifi", "connect", modelData.ssid], modelData.ssid);
                    } else {
                        popup.expanded = popup.expanded === modelData.ssid ? "" : modelData.ssid;
                    }
                }
                onConnectRequested: password => {
                    // A new password for a saved network goes in through stdin
                    // (passwd-file), and NetworkManager keeps it
                    if (modelData.known && password) {
                        const up = ["connection", "up", "uuid", modelData.uuid, "passwd-file", "/dev/stdin"];
                        popup.nmcli(up, modelData.ssid, `802-11-wireless-security.psk:${password}\n`);
                    } else if (modelData.known) {
                        popup.nmcli(["connection", "up", "uuid", modelData.uuid], modelData.ssid);
                    } else if (password) {
                        const connect = ["device", "wifi", "connect", modelData.ssid, "password", password];
                        popup.nmcli(connect, modelData.ssid);
                    } else {
                        popup.nmcli(["device", "wifi", "connect", modelData.ssid], modelData.ssid);
                    }
                }
                onSetupRequested: {
                    Quickshell.execDetached(["nm-connection-editor", "--create", "--type=802-11-wireless"]);
                    popup.close();
                }
                onDisconnectRequested: popup.nmcli(["device", "disconnect", popup.wifi.device])
                onForgetRequested: popup.nmcli(["connection", "delete", "uuid", modelData.uuid])
                onShareRequested: popup.share(modelData)
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
                text: I18n.tr("Import")
                onClicked: {
                    // The texts go in as $1 to $5, so a translation can't break the script
                    const title = I18n.tr("Import VPN configuration");
                    const vpnFiles = I18n.tr("VPN configuration");
                    const allFiles = I18n.tr("All files");
                    const imported = I18n.tr("VPN imported");
                    const failed = I18n.tr("VPN import failed");
                    Quickshell.execDetached(["sh", "-c", `
                        f=$(zenity --file-selection --title="$1" \\
                            --file-filter="$2 | *.ovpn *.conf" --file-filter="$3 | *") || exit 0
                        case $f in
                            *.conf)
                                # WireGuard names the interface after the file, at most
                                # 15 characters, so import a copy under a valid name and
                                # rename the connection afterwards.
                                type=wireguard
                                name=$(basename "$f" .conf)
                                ifname=$(printf %s "$name" | tr -c 'A-Za-z0-9_-' _ | cut -c1-15)
                                [ -n "$ifname" ] || ifname=wg0
                                dir=$(mktemp -d)
                                trap 'rm -rf "$dir"' EXIT
                                src=$dir/$ifname.conf
                                cp "$f" "$src" ;;
                            *) type=openvpn src=$f ;;
                        esac
                        if out=$(nmcli connection import type "$type" file "$src" 2>&1); then
                            uuid=$(printf %s "$out" | grep -oE '[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}')
                            if [ "$type" = wireguard ] && [ -n "$uuid" ] && [ "$name" != "$ifname" ]; then
                                nmcli connection modify "$uuid" connection.id "$name"
                            fi
                            notify-send -a Network "$4" "$out"
                        else
                            notify-send -u critical -a Network "$5" "$out"
                        fi
                    `, "sh", title, vpnFiles, allFiles, imported, failed]);
                    popup.close();
                }
            }
            IconButton {
                glyph: Theme.glyph(0xf0415) // 󰐕
                text: I18n.tr("New")
                onClicked: {
                    Quickshell.execDetached(["nm-connection-editor", "--create"]);
                    popup.close();
                }
            }
        }

        Label {
            visible: popup.loaded && popup.vpns.length === 0
            text: I18n.tr("No VPN connections yet")
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
                    if (code) {
                        secrets += `vpn.secrets.challenge-response:${code}\n`;
                    }
                    const up = ["connection", "up", "uuid", modelData.uuid, "passwd-file", "/dev/stdin"];
                    popup.nmcli(up, modelData.uuid, secrets);
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
