// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// System menu for the bar's distro logo: the system at a glance (host,
// kernel, the monitors' resolutions, uptime, packages, waiting updates of
// pacman, the AUR and Flatpak, the last upgrade, security fixes and Arch
// news among them, and the age of flake.lock) and the live use of CPU,
// memory, swap, the disks (/ and the home folder's, if that's another
// partition) and GPU, read every 2 seconds while it's open, and the
// brightness of the screens (the backlight, or monitors over DDC/CI), switches
// to keep the screen awake (Awake.qml) and for the night light (hyprsunset,
// scheduled by night-light.py; a click on it shows when it's on). The gear
// opens Machine Settings. Also
// Bluetooth, the on-screen keyboard and power, which a compact bar
// (Modes.compactBar) leaves out.
Popup {
    id: root

    name: "system"
    atLeft: true
    cardWidth: 400

    property var info: ({}) // os, kernel, host, packages, uptime (s)
    property var monitors: [] // hyprctl monitors: name, model, width, height, refreshRate, scale
    property real cpu: 0 // 0..1
    property var cpuTemp: null // °C
    property var lastCpu: null // [busy, total] of the previous reading
    property var mem: ({ used: 0, total: 1 })
    property var swap: ({ used: 0, total: 0 })
    property var disks: [] // { target, used, total }
    property var gpu: null // { name, load, memUsed, memTotal, temp }
    property var backlight: null // { percent } of the built-in screen (backlight.py), null without one
    property var nightLight: null // { on } from hyprsunset, null while it isn't running
    property var nightTimes: null // { night, schedule, from, until, place, temperature } from night-light.py
    readonly property int nightTemperature: nightTimes?.temperature ?? LocalSettings.nightLight.temperature
    property bool nightOpen: false // the night light's schedule shown

    readonly property var adapter: Bluetooth.defaultAdapter
    property bool bluetoothHardware: false

    function open(menu) {
        Menus.toggle(menu);
        close();
    }

    // Machine Settings on one of its pages
    function openSettings(page) {
        Menus.settingsPage = page;
        open("settings");
    }

    function gib(bytes) {
        return `${(bytes / 1073741824).toFixed(1)} GiB`;
    }

    function uptime(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return `${d ? `${d} d ` : ""}${h ? `${h} h ` : ""}${m} min`;
    }

    // Once: what doesn't change while the menu is open
    Process {
        running: true
        command: ["sh", "-c", '. /etc/os-release; echo "os=$PRETTY_NAME"; echo "kernel=$(uname -r)"; echo "host=$(cat /etc/hostname 2>/dev/null || uname -n)"; echo "packages=$(pacman -Qq 2>/dev/null | wc -l)"; echo "uptime=$(cut -d. -f1 /proc/uptime)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {};
                for (const line of text.trim().split("\n")) {
                    const i = line.indexOf("=");
                    info[line.slice(0, i)] = line.slice(i + 1);
                }
                root.info = info;
            }
        }
    }

    Process {
        running: true
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    // Waiting updates (Updates.qml): fresh ones while the menu is open
    Component.onCompleted: Updates.refresh()

    // "12 from pacman · 2 from the AUR", "Up to date"
    function updatesText() {
        if (!Updates.checked)
            return "Checking…";
        const parts = [[Updates.pacman, "pacman"], [Updates.aur, "the AUR"], [Updates.flatpak, "Flatpak"]].filter(([n]) => n > 0).map(([n, from]) => `${n} from ${from}`);
        return parts.length ? parts.join(" · ") : "Up to date";
    }

    // Every 2 seconds: CPU, memory, swap, disks, temperatures, GPU
    Process {
        id: reading

        running: true
        command: ["sh", "-c", `head -1 /proc/stat
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
df -B1 --output=source,size,used,target / "$HOME" | tail -n +2 | awk '!seen[$1]++ {$1 = "disk"; print}'
for h in /sys/class/hwmon/hwmon*; do case $(cat "$h/name") in coretemp|k10temp|zenpower) echo "cputemp $(cat "$h/temp1_input")"; break ;; esac; done
command -v nvidia-smi >/dev/null && echo "gpu $(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | head -1)"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const kb = {};
                const disks = [];
                for (const line of text.trim().split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f[0] === "cpu") {
                        const n = f.slice(1).map(Number);
                        const total = n.reduce((a, b) => a + b, 0), busy = total - n[3] - n[4];
                        if (root.lastCpu && total > root.lastCpu[1])
                            root.cpu = (busy - root.lastCpu[0]) / (total - root.lastCpu[1]);
                        root.lastCpu = [busy, total];
                    } else if (f[0].endsWith(":")) {
                        kb[f[0].slice(0, -1)] = Number(f[1]) * 1024;
                    } else if (f[0] === "disk") {
                        disks.push({ total: Number(f[1]), used: Number(f[2]), target: f.slice(3).join(" ") });
                    } else if (f[0] === "cputemp") {
                        root.cpuTemp = Math.round(Number(f[1]) / 1000);
                    } else if (f[0] === "gpu") {
                        const g = line.slice(4).split(",").map(s => s.trim());
                        root.gpu = { name: g[0], load: Number(g[1]) / 100, memUsed: Number(g[2]) * 1048576, memTotal: Number(g[3]) * 1048576, temp: Number(g[4]) };
                    }
                }
                root.mem = { total: kb.MemTotal, used: kb.MemTotal - kb.MemAvailable };
                root.swap = { total: kb.SwapTotal, used: kb.SwapTotal - kb.SwapFree };
                root.disks = disks;
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: reading.running = true
    }

    Header {
        glyph: Theme.glyph(0xf303) //
        accent: Theme.blue
        title: root.info.os ?? "System"

        IconButton {
            glyph: Theme.glyph(0xf0493) // 󰒓
            onClicked: root.open("settings")
        }
        IconButton {
            glyph: Theme.glyph(0xf0425) // 󰐥
            accent: Theme.red
            active: hovered
            onClicked: root.open("power")
        }
    }

    // At a glance
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 14
        rowSpacing: 6

        Repeater {
            model: [
                ["Host", root.info.host ?? ""],
                ["Kernel", root.info.kernel ?? ""],
                ...root.monitors.map(m => [m.name, [m.model, `${m.width} × ${m.height}`, `${Math.round(m.refreshRate)} Hz`, m.scale !== 1 ? `scale ${m.scale}` : ""].filter(s => s).join(" · ")]),
                ["Uptime", root.info.uptime ? root.uptime(Number(root.info.uptime)) : ""],
                ["Packages", root.info.packages ? `${root.info.packages} from pacman` : ""],
                ["Updates", root.updatesText()],
                ...(Updates.lastUpgrade !== null ? [["Last upgrade", Updates.lastUpgrade === 0 ? "Today" : `${Updates.lastUpgrade} ${Updates.lastUpgrade === 1 ? "day" : "days"} ago`]] : []),
                ...(Updates.security.length ? [["Security", Updates.security.map(s => s.package).join(", ")]] : []),
                ...(Updates.news.length ? [["Arch news", Updates.news.length === 1 ? Updates.news[0].title : `${Updates.news.length} since the last upgrade`]] : []),
                ...(Updates.flakeAge !== null ? [["flake.lock", Updates.flakeAge === 0 ? "Updated today" : `${Updates.flakeAge} ${Updates.flakeAge === 1 ? "day" : "days"} old${Updates.flakeStale ? " · git pull, then switch" : ""}`]] : [])
            ]

            delegate: Item {
                required property var modelData

                Layout.columnSpan: 2
                Layout.fillWidth: true
                implicitHeight: 18

                Label {
                    width: 90
                    text: parent.modelData[0]
                    color: Theme.overlay1
                }
                Label {
                    x: 90
                    width: parent.width - 90
                    text: parent.modelData[1]
                    color: parent.modelData[0] === "Arch news" ? Theme.red : (parent.modelData[0] === "Updates" && Updates.total > 0) || parent.modelData[0] === "Security" || (parent.modelData[0] === "Last upgrade" && Updates.upgradeStale) || (parent.modelData[0] === "flake.lock" && Updates.flakeStale) ? Theme.peach : Theme.text
                }
            }
        }
    }

    // Bluetooth (the row opens its menu, the switch turns it on and off) and
    // the on-screen keyboard
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 6

        Rectangle {
            id: bluetooth

            readonly property bool on: root.adapter?.enabled ?? false
            readonly property var connected: (root.adapter?.devices.values ?? []).filter(d => d.connected)
            readonly property var device: connected.length === 1 ? connected[0] : null

            visible: !!root.adapter || root.bluetoothHardware
            Layout.fillWidth: true
            implicitHeight: Modes.touch ? 36 : 28
            radius: 8
            color: btMouse.containsMouse ? Theme.surface1 : Theme.surface0

            Behavior on color { ColorAnimation { duration: 150 } }

            MouseArea {
                id: btMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open("bluetooth")
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 8

                Label {
                    text: Theme.glyph(!bluetooth.on ? 0xf00b2 : bluetooth.connected.length ? 0xf00b1 : 0xf00af) // 󰂲 󰂱 󰂯
                    color: bluetooth.on ? Theme.blue : Theme.overlay1
                }
                Label {
                    text: "Bluetooth"
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: {
                        if (!bluetooth.on)
                            return "Off";
                        const d = bluetooth.device;
                        if (d)
                            return `${d.name}${d.batteryAvailable ? ` · ${Math.round(d.battery * 100)} %` : ""}`;
                        return bluetooth.connected.length ? `${bluetooth.connected.length} connected` : "On";
                    }
                    color: Theme.subtext0
                }
                Switch {
                    visible: !!root.adapter
                    checked: bluetooth.on
                    accent: Theme.blue
                    onToggled: root.adapter.enabled = !bluetooth.on
                }
            }
        }

        Item {
            visible: !bluetooth.visible
            Layout.fillWidth: true
        }
        IconButton {
            glyph: Theme.glyph(0xf030c) // 󰌌
            text: "Keyboard"
            onClicked: {
                Quickshell.execDetached([Quickshell.shellPath("osk.sh")]);
                root.close();
            }
        }
    }

    // The screen: stay awake by hand, and the night light, which its switch
    // turns on or off until the next sunset or sunrise (night-light.py); a
    // click elsewhere on it shows the schedule
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Toggle {
            glyph: Awake.manual ? 0xf0176 : 0xf04b2 // 󰅶 / 󰒲
            title: "Stay awake"
            detail: Awake.manual ? "No lock" : "Off"
            checked: Awake.manual
            accent: Theme.lavender
            onToggled: Awake.manual = !Awake.manual
        }
        Toggle {
            glyph: 0xf0594 // 󰖔
            title: "Night light"
            detail: {
                if (!root.nightLight)
                    return "Unavailable";
                const t = root.nightTimes;
                if (!t?.from)
                    return root.nightLight.on ? "On" : "Off";
                return root.nightLight.on ? `Until ${t.until}` : t.night ? "Off tonight" : `From ${t.from}`;
            }
            checked: root.nightLight?.on ?? false
            enabled: !!root.nightLight
            expandable: true
            expanded: root.nightOpen
            onClicked: root.nightOpen = !root.nightOpen
            accent: Theme.peach
            onToggled: {
                const on = !root.nightLight.on;
                root.nightLight = { on: on };
                Quickshell.execDetached(on ? ["hyprctl", "hyprsunset", "temperature", String(root.nightTemperature)] : ["hyprctl", "hyprsunset", "identity"]);
            }
        }
    }

    // The night light's schedule, from the click on it
    Rectangle {
        Layout.fillWidth: true
        visible: root.nightOpen
        implicitHeight: nightColumn.implicitHeight + 20
        radius: 8
        color: Theme.alpha(Theme.peach, 0.08)

        ColumnLayout {
            id: nightColumn

            readonly property var t: root.nightTimes

            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                font.bold: true
                text: {
                    const t = nightColumn.t;
                    if (!t)
                        return "No schedule: night-light.py isn't running";
                    if (t.schedule === "off")
                        return "Only by hand";
                    if (!t.from)
                        return t.night ? "On all day: the sun doesn't rise today" : "Off all day: the sun doesn't set today";
                    if (t.place)
                        return `On from ${t.from} (sunset) until ${t.until} (sunrise)`;
                    return `On from ${t.from} until ${t.until}`;
                }
            }
            // Where the times come from, and where to change that
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                color: Theme.subtext0
                text: {
                    const t = nightColumn.t;
                    if (!t)
                        return "";
                    let why;
                    if (t.schedule === "times")
                        why = "The times set in Machine Settings.";
                    else if (t.schedule === "off")
                        why = "It doesn't turn on by itself: set so in Machine Settings.";
                    else if (t.placeFrom === "machine")
                        why = `Today's sunset and sunrise in ${t.place}, this computer's location in Machine Settings.`;
                    else if (t.placeFrom === "calendar")
                        why = `Today's sunset and sunrise in ${t.place}, the calendar's weather location: Machine Settings has no location.`;
                    else
                        why = "Fixed times, as no location is set to work out the sunset and sunrise.";
                    return `${why} Warmer colours at ${t.temperature ?? root.nightTemperature} K.`;
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                IconButton {
                    visible: nightColumn.t?.schedule === "sun"
                    glyph: Theme.glyph(0xf034e) // 󰍎
                    text: "Location"
                    onClicked: root.openSettings("location")
                }
                IconButton {
                    glyph: Theme.glyph(0xf0493) // 󰒓
                    text: "Night light settings"
                    onClicked: root.openSettings("night")
                }
            }
        }
    }

    // hyprsunset's state: on when it tints, i.e. no identity matrix and a
    // temperature below its default of 6000 K. hyprctl fails without it.
    Process {
        running: true
        command: ["sh", "-c", "hyprctl hyprsunset identity get && hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [identity, kelvin] = text.trim().split("\n");
                if (identity === "true" || identity === "false")
                    root.nightLight = { on: identity === "false" && parseInt(kelvin) < 6000 };
            }
        }
    }

    // Today's sunset and sunrise at the location (night-light.py)
    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/night-light.json`
        printErrors: false
        onLoaded: {
            try {
                root.nightTimes = JSON.parse(text());
            } catch (e) {}
        }
    }

    // A Bluetooth controller BlueZ doesn't list (the Bluetooth menu says why)
    Process {
        running: true
        command: ["sh", "-c", "ls -A /sys/class/bluetooth"]
        stdout: StdioCollector {
            onStreamFinished: root.bluetoothHardware = !!text.trim()
        }
    }

    // Brightness: a laptop's own screen and external monitors with DDC/CI
    // switched on (Ddc.qml; found a moment after the menu opens)
    SectionTitle {
        visible: !!root.backlight || ddc.names.length > 0 || ddc.loading
        Layout.topMargin: 6
        text: "Brightness"
    }
    Brightness {
        visible: !!root.backlight
        title: "Built-in screen"
        value: root.backlight ? root.backlight.percent / 100 : 0
        onMoved: v => {
            // backlight.py keeps it above dark, like the keys
            root.backlight = { percent: Math.max(2, Math.round(v * 100)) };
            Quickshell.execDetached([Quickshell.shellPath("backlight.py"), "set", String(Math.round(v * 100))]);
        }
    }
    Repeater {
        model: ddc.names

        delegate: Brightness {
            required property string modelData

            title: [modelData, ddc.displays[modelData]?.model].filter(s => s).join(" · ")
            value: ddc.displays[modelData] ? ddc.value(modelData) : 0
            onMoved: v => ddc.set(modelData, v)
        }
    }

    // Placeholder while ddcutil looks for monitors (about a second)
    RowLayout {
        visible: ddc.loading
        Layout.fillWidth: true
        spacing: 8

        // A quarter-open ring, turning
        Shape {
            implicitWidth: 14
            implicitHeight: 14
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.yellow
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: 7
                    centerY: 7
                    radiusX: 6
                    radiusY: 6
                    startAngle: 0
                    sweepAngle: 270
                }
            }

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                running: ddc.loading
            }
        }
        Label {
            Layout.fillWidth: true
            text: "Looking for monitors…"
            color: Theme.subtext0
        }
    }

    Ddc {
        id: ddc
    }

    // backlight.py: the percent, nothing without a backlight
    Process {
        running: true
        command: [Quickshell.shellPath("backlight.py"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const percent = parseInt(text);
                if (!isNaN(percent))
                    root.backlight = { percent: percent };
            }
        }
    }

    SectionTitle {
        Layout.topMargin: 6
        text: "Usage"
    }

    Usage {
        glyph: 0xf035b // 󰍛
        title: "CPU"
        detail: `${Math.round(root.cpu * 100)} %${root.cpuTemp !== null ? ` · ${root.cpuTemp} °C` : ""}`
        value: root.cpu
        accent: Theme.blue
    }
    Usage {
        glyph: 0xf061a // 󰘚
        title: "Memory"
        detail: `${root.gib(root.mem.used)} of ${root.gib(root.mem.total)}`
        value: root.mem.used / root.mem.total
        accent: Theme.mauve
    }
    Usage {
        visible: root.swap.total > 0
        glyph: 0xf04e1 // 󰓡
        title: "Swap"
        detail: `${root.gib(root.swap.used)} of ${root.gib(root.swap.total)}`
        value: root.swap.total ? root.swap.used / root.swap.total : 0
        accent: Theme.lavender
    }
    Repeater {
        model: root.disks

        delegate: Usage {
            required property var modelData

            glyph: 0xf02ca // 󰋊
            title: `Disk ${modelData.target}`
            detail: `${root.gib(modelData.used)} of ${root.gib(modelData.total)}`
            value: modelData.used / modelData.total
            accent: Theme.teal
        }
    }
    Usage {
        visible: !!root.gpu
        glyph: 0xf08ae // 󰢮
        title: "GPU"
        detail: root.gpu ? `${Math.round(root.gpu.load * 100)} % · ${root.gib(root.gpu.memUsed)} of ${root.gib(root.gpu.memTotal)} · ${root.gpu.temp} °C` : ""
        value: root.gpu?.load ?? 0
        accent: Theme.green
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6

        Item {
            Layout.fillWidth: true
        }
        IconButton {
            visible: Updates.total > 0
            glyph: Theme.glyph(0xf06b0) // 󰚰
            text: "Update"
            accent: Theme.peach
            active: true
            // With Arch news: those first (updates.qml)
            onClicked: {
                if (Updates.news.length)
                    Menus.toggle("updates");
                else
                    Updates.update();
                root.close();
            }
        }
        IconButton {
            glyph: Theme.glyph(0xf0128) // 󰄨
            text: "System monitor"
            onClicked: {
                Quickshell.execDetached(["kitty", "btop"]);
                root.close();
            }
        }
    }

    // A switch with a glyph, its name and state; the whole tile toggles
    component Toggle: Rectangle {
        id: toggle

        property int glyph
        property string title
        property string detail
        property bool checked
        property bool enabled: true
        property color accent
        // A click besides the switch: clicked() instead of toggled(), e.g. for details
        property bool expandable: false
        property bool expanded: false
        signal toggled
        signal clicked

        Layout.fillWidth: true
        implicitHeight: Modes.touch ? 36 : 28
        radius: 8
        opacity: enabled ? 1 : 0.5
        color: toggleMouse.containsMouse && enabled ? Theme.surface1 : Theme.surface0

        Behavior on color { ColorAnimation { duration: 150 } }

        MouseArea {
            id: toggleMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: toggle.enabled || toggle.expandable
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.expandable ? toggle.clicked() : toggle.toggled()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 8

            Label {
                text: Theme.glyph(toggle.glyph)
                color: toggle.checked ? toggle.accent : Theme.overlay1
            }
            Label {
                text: toggle.title
                font.bold: true
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: toggle.detail
                color: Theme.subtext0
            }
            Label {
                visible: toggle.expandable
                text: Theme.glyph(toggle.expanded ? 0xf0143 : 0xf0140) // 󰅃 / 󰅀
                color: Theme.overlay1
            }
            Switch {
                checked: toggle.checked
                enabled: toggle.enabled
                accent: toggle.accent
                onToggled: toggle.toggled()
            }
        }
    }

    // One screen: name and percentage above a slider
    component Brightness: ColumnLayout {
        id: brightness

        property string title
        property real value
        signal moved(real value)

        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: Theme.glyph(0xf00e0) // 󰃠
                color: Theme.yellow
            }
            Label {
                Layout.fillWidth: true
                text: brightness.title
                font.bold: true
            }
            Label {
                text: `${Math.round(brightness.value * 100)} %`
                color: Theme.subtext0
            }
        }

        Slider {
            Layout.fillWidth: true
            value: brightness.value
            accent: Theme.yellow
            onMoved: v => brightness.moved(v)
        }
    }

    // One resource: name and figures above a bar
    component Usage: ColumnLayout {
        id: usage

        property int glyph
        property string title
        property string detail
        property real value
        property color accent

        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: Theme.glyph(usage.glyph)
                color: usage.accent
            }
            Label {
                text: usage.title
                font.bold: true
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: usage.detail
                color: Theme.subtext0
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Theme.surface0

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, usage.value))
                height: parent.height
                radius: 3
                color: usage.accent

                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
    }
}
