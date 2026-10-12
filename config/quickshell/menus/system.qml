// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// System menu for the bar's distro logo: the system at a glance (host,
// kernel, uptime, packages, pending updates) and the live use of CPU,
// memory, swap, disk and GPU, read every 2 seconds while it's open, and the
// brightness of the screens (the backlight, or monitors over DDC/CI). The gear
// opens Machine Settings.
Popup {
    id: root

    name: "system"
    atLeft: true
    cardWidth: 400

    property var info: ({}) // os, kernel, host, packages, uptime (s)
    property int updates: -1 // pending pacman updates; -1 while counting, -2 without checkupdates
    property real cpu: 0 // 0..1
    property var cpuTemp: null // °C
    property var lastCpu: null // [busy, total] of the previous reading
    property var mem: ({ used: 0, total: 1 })
    property var swap: ({ used: 0, total: 0 })
    property var disk: ({ used: 0, total: 1 })
    property var gpu: null // { name, load, memUsed, memTotal, temp }
    property var backlight: null // { value, max } of the built-in screen, null without one

    readonly property string toggle: Quickshell.shellPath("toggle.sh")

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

    // Pending updates: checkupdates syncs a copy of the databases, so it takes a moment
    Process {
        running: true
        command: ["sh", "-c", "command -v checkupdates >/dev/null || { echo -2; exit; }; checkupdates 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: root.updates = parseInt(text.trim()) || 0
        }
    }

    // Every 2 seconds: CPU, memory, swap, disk, temperatures, GPU
    Process {
        id: reading

        running: true
        command: ["sh", "-c", `head -1 /proc/stat
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
df -B1 --output=size,used / | tail -1 | sed 's/^/disk /'
for h in /sys/class/hwmon/hwmon*; do case $(cat "$h/name") in coretemp|k10temp|zenpower) echo "cputemp $(cat "$h/temp1_input")"; break ;; esac; done
command -v nvidia-smi >/dev/null && echo "gpu $(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | head -1)"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const kb = {};
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
                        root.disk = { total: Number(f[1]), used: Number(f[2]) };
                    } else if (f[0] === "cputemp") {
                        root.cpuTemp = Math.round(Number(f[1]) / 1000);
                    } else if (f[0] === "gpu") {
                        const g = line.slice(4).split(",").map(s => s.trim());
                        root.gpu = { name: g[0], load: Number(g[1]) / 100, memUsed: Number(g[2]) * 1048576, memTotal: Number(g[3]) * 1048576, temp: Number(g[4]) };
                    }
                }
                root.mem = { total: kb.MemTotal, used: kb.MemTotal - kb.MemAvailable };
                root.swap = { total: kb.SwapTotal, used: kb.SwapTotal - kb.SwapFree };
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
            onClicked: {
                Quickshell.execDetached([root.toggle, "settings"]);
                root.close();
            }
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
                ["Uptime", root.info.uptime ? root.uptime(Number(root.info.uptime)) : ""],
                ["Packages", root.info.packages ? `${root.info.packages} from pacman` : ""],
                ["Updates", root.updates === -1 ? "Checking…" : root.updates === -2 ? "checkupdates isn't installed" : root.updates === 0 ? "Up to date" : `${root.updates} available`]
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
                    color: parent.modelData[0] === "Updates" && root.updates > 0 ? Theme.peach : Theme.text
                }
            }
        }
    }

    // Brightness: a laptop's own screen and external monitors with DDC/CI
    // switched on (Ddc.qml; found a moment after the menu opens)
    SectionTitle {
        visible: !!root.backlight || ddc.names.length > 0
        Layout.topMargin: 6
        text: "Brightness"
    }
    Brightness {
        visible: !!root.backlight
        title: "Built-in screen"
        value: root.backlight ? root.backlight.value / root.backlight.max : 0
        onMoved: v => {
            // At least 5 % so the screen never goes dark, like the keys
            const value = Math.max(0.05, v);
            root.backlight = { value: Math.round(value * root.backlight.max), max: root.backlight.max };
            Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", `${Math.round(value * 100)}%`]);
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

    Ddc {
        id: ddc
    }

    // brightnessctl -m: device,class,current,percent,max
    Process {
        running: true
        command: ["brightnessctl", "-m", "-c", "backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");
                if (f.length >= 5 && parseInt(f[4]) > 0)
                    root.backlight = { value: parseInt(f[2]), max: parseInt(f[4]) };
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
    Usage {
        glyph: 0xf02ca // 󰋊
        title: "Disk /"
        detail: `${root.gib(root.disk.used)} of ${root.gib(root.disk.total)}`
        value: root.disk.used / root.disk.total
        accent: Theme.teal
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
            visible: root.updates > 0
            glyph: Theme.glyph(0xf06b0) // 󰚰
            text: "Update"
            accent: Theme.peach
            active: true
            onClicked: {
                Quickshell.execDetached(["kitty", "--hold", "sudo", "pacman", "-Syu"]);
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
