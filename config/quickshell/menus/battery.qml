// Software rendering: as fast to open, a fraction of the memory (see daemon.qml)
//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Battery menu for the bar's battery module (laptops): the charge, how long
// it lasts or until it's full (and at what time), the power it draws and
// its health, how long it has run since unplugged with an estimate at that
// pace or since plugged in with the pace of charging, the
// power profile (power-profiles-daemon, which system/setup.sh starts) and
// the batteries of other devices (mouse, headset, ...). The button in the
// title opens the history (battery-history.qml).
Popup {
    id: popup

    name: "battery"
    cardWidth: 340

    readonly property var battery: UPower.displayDevice
    readonly property real percent: battery ? (battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage) : 0
    readonly property int batteryState: battery?.state ?? UPowerDeviceState.Unknown
    readonly property bool charging: batteryState === UPowerDeviceState.Charging
    readonly property bool full: batteryState === UPowerDeviceState.FullyCharged || (batteryState === UPowerDeviceState.PendingCharge && percent >= 95)
    readonly property var others: UPower.devices.values.filter(d => !d.isLaptopBattery && d.isPresent && d.type !== UPowerDeviceType.LinePower && d.type !== UPowerDeviceType.Battery && d.percentage > 0)
    property bool profiles: false // power-profiles-daemon runs

    readonly property var profileList: [
        { profile: PowerProfile.PowerSaver, text: "Power saver", glyph: 0xf032a, accent: Theme.green }, // 󰌪
        { profile: PowerProfile.Balanced, text: "Balanced", glyph: 0xf05d1, accent: Theme.blue }, // 󰗑
        { profile: PowerProfile.Performance, text: "Performance", glyph: 0xf04c5, accent: Theme.peach } // 󰓅
    ]

    function duration(seconds) {
        const h = Math.floor(seconds / 3600), m = Math.round(seconds % 3600 / 60);
        return h ? `${h} h ${m} min` : `${m} min`;
    }

    function clock(seconds) {
        return Qt.formatTime(new Date(Date.now() + seconds * 1000), "HH:mm");
    }

    // Until full: from the pace while charging when there's enough of it,
    // else UPower's timeToFull (charge left / charging power now)
    readonly property real toFull: stats?.toFull || (charging ? battery.timeToFull : 0)

    readonly property string summary: {
        if (full)
            return "Fully charged";
        if (charging)
            return toFull > 0 ? `Full at ${clock(toFull)} · in ${duration(toFull)}` : "Charging";
        if (batteryState === UPowerDeviceState.Discharging)
            return battery.timeToEmpty > 0 ? `${duration(battery.timeToEmpty)} left` : "On battery";
        return UPower.onBattery ? "On battery" : "Plugged in, not charging";
    }

    // Since unplugged or plugged in: UPower's charge history (one entry per
    // percent, kept across reboots) back to the last change between charging
    // and discharging. The pace leaves out gaps over 30 minutes (suspend), so
    // on battery it is percent per hour awake; unlike timeToEmpty (UPower:
    // energy now / power draw right now) it doesn't jump with every load
    // spike.
    readonly property var cell: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
    readonly property bool discharging: batteryState === UPowerDeviceState.Discharging
    property var history: [] // [[time, percent, state]], newest first
    readonly property var stats: {
        const gap = 1800, now = Date.now() / 1000;
        const state = discharging ? UPowerDeviceState.Discharging : charging ? UPowerDeviceState.Charging : -1;
        let i = 0;
        while (i < history.length && (history[i][2] === state || history[i][2] === UPowerDeviceState.Unknown))
            i++;
        const run = history.slice(0, i).filter(e => e[2] === state);
        if (state < 0 || !run.length)
            return null;
        // Percent used (on battery) or gained (charging) in the time awake;
        // while charging only the last 15 minutes, as the pace changes with
        // the charge
        const sign = discharging ? 1 : -1;
        let awake = now - run[0][0] <= gap ? now - run[0][0] : 0;
        let moved = awake ? sign * (run[0][1] - percent) : 0;
        for (let j = 1; j < run.length && (discharging || now - run[j][0] <= 900); j++) {
            const dt = run[j - 1][0] - run[j][0];
            if (dt <= gap) {
                awake += dt;
                moved += sign * (run[j][1] - run[j - 1][1]);
            }
        }
        const pace = awake >= (discharging ? 600 : 300) && moved >= 2 ? moved / awake : 0; // percent per second
        return {
            since: now - run[run.length - 1][0],
            moved: sign * (run[run.length - 1][1] - percent),
            pace: pace,
            left: discharging && pace ? percent / pace : 0,
            total: discharging && pace ? 100 / pace : 0,
            toFull: !discharging && pace ? untilFull(pace) : 0
        };
    }

    // Charging slows down towards full (measured on this Surface Pro X:
    // 80-90 % at about 0.6 and 90-100 % at about 0.27 of the pace below 80 %),
    // so add up the time percent by percent from the pace now
    function chargeFactor(p) {
        return p < 80 ? 1 : p < 90 ? 0.6 : 0.27;
    }
    function untilFull(pace) {
        const base = pace / chargeFactor(percent);
        let seconds = 0;
        for (let p = Math.floor(percent); p < 100; p++)
            seconds += 1 / (base * chargeFactor(p));
        return seconds;
    }

    function loadHistory() {
        if (!cell || historyProc.running)
            return;
        historyProc.command = ["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower", `/org/freedesktop/UPower/devices/battery_${cell.nativePath.replace(/[^A-Za-z0-9]/g, "_")}`, "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", "604800", "5000"];
        historyProc.running = true;
    }

    onCellChanged: loadHistory()
    onPercentChanged: loadHistory()
    Component.onCompleted: loadHistory()

    Process {
        id: historyProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    popup.history = JSON.parse(text).data[0].sort((a, b) => b[0] - a[0]);
                } catch (e) {
                    popup.history = [];
                }
            }
        }
    }

    Process {
        running: true
        command: ["systemctl", "is-active", "--quiet", "power-profiles-daemon"]
        onExited: code => popup.profiles = code === 0
    }

    Header {
        glyph: Theme.glyph(popup.charging ? 0xf0084 : 0xf0079) // 󰂄 / 󰁹
        accent: popup.charging || popup.full ? Theme.teal : popup.percent <= 15 ? Theme.red : Theme.green
        title: "Battery"
        badge: UPower.onBattery ? "On battery" : "Plugged in"
        badgeColor: UPower.onBattery ? Theme.yellow : Theme.teal

        // The history: charge, draw, times on battery, busiest apps
        IconButton {
            glyph: Theme.glyph(0xf0128) // 󰄨
            onClicked: {
                Menus.toggle("battery-history");
                popup.close();
            }
        }
    }

    // Charge
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: `${Math.round(popup.percent)}%`
                font.pixelSize: 26
                font.bold: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: popup.summary
                    color: Theme.subtext1
                }
                Label {
                    Layout.fillWidth: true
                    visible: Math.abs(popup.battery?.changeRate ?? 0) > 0.1
                    text: `${Math.abs(popup.battery?.changeRate ?? 0).toFixed(1)} W ${popup.charging ? "in" : "drawn"}`
                    font.pixelSize: 10
                    color: Theme.overlay1
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 8
            radius: 4
            color: Theme.surface0

            Rectangle {
                width: parent.width * Math.min(1, popup.percent / 100)
                height: parent.height
                radius: 4
                color: popup.charging || popup.full ? Theme.teal : popup.percent <= 15 ? Theme.red : popup.percent <= 30 ? Theme.yellow : Theme.green

                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }

        Label {
            Layout.fillWidth: true
            // The display device has no health; the laptop's own battery does
            readonly property var cell: UPower.devices.values.find(d => d.isLaptopBattery && d.healthSupported) ?? null

            visible: !!cell
            text: cell ? `Health ${Math.round(cell.healthPercentage)}%${cell.model ? ` · ${cell.model}` : ""}` : ""
            font.pixelSize: 10
            color: Theme.overlay1
        }
    }

    // Since unplugged / plugged in
    ColumnLayout {
        Layout.fillWidth: true
        visible: !!popup.stats
        spacing: 6

        SectionTitle {
            text: popup.discharging ? "Since unplugged" : "Since plugged in"
        }

        Repeater {
            model: {
                const s = popup.stats;
                if (!s)
                    return [];
                if (!popup.discharging) {
                    const rows = [["Charging", `${popup.duration(s.since)} · ${Math.max(0, Math.round(s.moved))}% gained`]];
                    if (!s.pace)
                        return rows.concat([["Full at", popup.toFull > 0 ? `${popup.clock(popup.toFull)} (UPower)` : "Not enough data yet"]]);
                    // Full is in the summary; 80 % comes sooner, as charging slows down after it
                    return rows.concat([["Pace", `${(s.pace * 3600).toFixed(0)}% per hour`]]).concat(popup.percent < 80 ? [["80% at", `about ${popup.clock((80 - popup.percent) / s.pace)}`]] : []);
                }
                const rows = [["On battery", `${popup.duration(s.since)} · ${Math.max(0, Math.round(s.moved))}% used`]];
                if (!s.pace)
                    return rows.concat([["At this pace", "Not enough data yet"]]);
                return rows.concat([
                    ["Pace", `${(s.pace * 3600).toFixed(1)}% per hour`],
                    ["At this pace", `${popup.duration(s.left)} left`],
                    ["Full charge lasts", `about ${popup.duration(s.total)}`]
                ]);
            }

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: modelData[0]
                    color: Theme.subtext1
                }
                Label {
                    text: modelData[1]
                }
            }
        }
    }

    // Power profile
    ColumnLayout {
        Layout.fillWidth: true
        visible: popup.profiles
        spacing: 8

        SectionTitle {
            text: "Power profile"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: popup.profileList.filter(p => p.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

                delegate: Rectangle {
                    id: tile

                    required property var modelData
                    readonly property bool current: PowerProfiles.profile === modelData.profile

                    Layout.fillWidth: true
                    Layout.preferredHeight: Modes.touch ? 64 : 54
                    radius: 8
                    color: current ? Theme.alpha(modelData.accent, 0.2) : tileMouse.containsMouse ? Theme.surface1 : Theme.surface0
                    border.width: current ? 1 : 0
                    border.color: modelData.accent

                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 3

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: Theme.glyph(tile.modelData.glyph)
                            font.pixelSize: 16
                            color: tile.current ? tile.modelData.accent : Theme.overlay2
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.modelData.text
                            font.pixelSize: 11
                            color: tile.current ? Theme.text : Theme.subtext0
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = tile.modelData.profile
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            text: PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature ? "Performance is held back: the laptop is too hot" : "Performance is held back: the laptop is on a lap"
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: 10
            color: Theme.yellow
        }
    }

    // Other devices' batteries
    ColumnLayout {
        Layout.fillWidth: true
        visible: popup.others.length > 0
        spacing: 6

        SectionTitle {
            text: "Devices"
        }

        Repeater {
            model: popup.others

            delegate: RowLayout {
                id: other

                required property var modelData
                readonly property real charge: modelData.percentage <= 1 ? modelData.percentage * 100 : modelData.percentage

                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: modelData.model || UPowerDeviceType.toString(modelData.type)
                    color: Theme.subtext1
                }
                Label {
                    text: `${Math.round(other.charge)}%`
                    color: other.charge <= 15 ? Theme.red : other.charge <= 30 ? Theme.yellow : Theme.green
                }
            }
        }
    }
}
