//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Battery History: the charge and the power draw over the last day, week or
// month, the time on battery with the average draw and pace, how long a full
// charge lasts at that pace, the times it ran on battery, and the apps that
// kept the CPU busiest meanwhile. From the daemon's log (battery-log.py,
// laptop mode, one sample a minute). Opened from the battery menu or with
// `toggle.sh battery-history`.
ShellRoot {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/battery-history`
    readonly property real gap: 180 // s, see battery-log.py

    property int span: 86400
    property real now: Date.now() / 1000
    readonly property real from: now - span
    property var samples: [] // [{ t, percent, energy, power, state }], oldest first
    property var hours: ({}) // apps.json

    readonly property var ranges: [{ text: "24 h", span: 86400 }, { text: "7 days", span: 7 * 86400 }, { text: "30 days", span: 30 * 86400 }]

    function duration(seconds) {
        const d = Math.floor(seconds / 86400), h = Math.floor(seconds % 86400 / 3600), m = Math.round(seconds % 3600 / 60);
        return d ? `${d} d ${h} h` : h ? `${h} h ${m} min` : seconds < 60 ? `${Math.round(seconds)} s` : `${m} min`;
    }

    // From the first sample in the range on
    readonly property int first: {
        let lo = 0, hi = samples.length;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (samples[mid].t < from)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo;
    }
    readonly property var shown: samples.slice(Math.max(0, first - 1))

    // On battery and awake within the range: time, percent and energy used
    readonly property var totals: {
        let seconds = 0, used = 0, energy = 0;
        for (let i = Math.max(1, first); i < samples.length; i++) {
            const a = samples[i - 1], b = samples[i];
            if (a.state === "d" && b.state === "d" && b.t - a.t <= gap) {
                seconds += b.t - a.t;
                used += a.percent - b.percent;
                energy += a.energy - b.energy;
            }
        }
        const hoursOn = seconds / 3600;
        const enough = seconds >= 600 && used >= 2;
        return {
            seconds: seconds,
            watts: hoursOn && energy > 0 ? energy / hoursOn : 0,
            pace: enough ? used / hoursOn : 0,
            full: enough ? 100 / (used / hoursOn) * 3600 : 0 // s
        };
    }

    // Each time on battery (suspends included), newest first
    readonly property var sessions: {
        const out = [];
        let cur = null;
        for (let i = 0; i < samples.length; i++) {
            const s = samples[i];
            if (s.state !== "d") {
                cur = null;
                continue;
            }
            if (!cur) {
                cur = { start: s.t, end: s.t, from: s.percent, to: s.percent, awake: 0, energy: 0 };
                out.push(cur);
            } else {
                const p = samples[i - 1];
                if (s.t - p.t <= gap) {
                    cur.awake += s.t - p.t;
                    cur.energy += p.energy - s.energy;
                }
                cur.end = s.t;
                cur.to = s.percent;
            }
        }
        const last = samples[samples.length - 1];
        return out.filter(x => x.end >= from).reverse().map(x => Object.assign(x, {
            ongoing: x === out[out.length - 1] && last?.state === "d" && now - last.t <= gap
        }));
    }

    // CPU time by app on battery within the range (whole hours)
    readonly property var apps: {
        const sums = {};
        let total = 0;
        for (const key in hours) {
            if (Number(key) + 3600 <= from)
                continue;
            for (const name in hours[key].apps) {
                sums[name] = (sums[name] ?? 0) + hours[key].apps[name];
                total += hours[key].apps[name];
            }
        }
        return Object.keys(sums).map(name => ({ name: name, cpu: sums[name], share: total ? sums[name] / total : 0 })).sort((a, b) => b.cpu - a.cpu).slice(0, 10);
    }

    FileView {
        path: `${root.dir}/samples.csv`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const f = line.split(",");
                if (f.length >= 5)
                    out.push({ t: Number(f[0]), percent: Number(f[1]), energy: Number(f[2]), power: Number(f[3]), state: f[4] });
            }
            root.now = Date.now() / 1000;
            root.samples = out;
        }
    }

    FileView {
        path: `${root.dir}/apps.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.hours = JSON.parse(text());
            } catch (e) {}
        }
    }

    // The logger keeps the apps' hours in memory for a while: write them now
    // (only the daemon's own command line, not e.g. an editor with the file)
    Component.onCompleted: Quickshell.execDetached(["pkill", "-USR1", "-fx", `/usr/bin/python3 ${Quickshell.shellPath("battery-log.py")}`])

    FloatingWindow {
        title: "Battery History"
        implicitWidth: 760
        implicitHeight: 720
        color: Theme.base
        onVisibleChanged: if (!visible)
            Menus.close("battery-history")

        WindowClose {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            z: 1
            onClicked: Menus.close("battery-history")
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Menus.close("battery-history")
        }

        Flickable {
            anchors.fill: parent
            contentHeight: page.implicitHeight + 40
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: page

                x: 20
                y: 16
                width: parent.width - 40
                spacing: 18

                Header {
                    Layout.rightMargin: 24
                    glyph: Theme.glyph(0xf0079) // 󰁹
                    accent: Theme.green
                    title: "Battery History"

                    Repeater {
                        model: root.ranges

                        delegate: IconButton {
                            required property var modelData
                            text: modelData.text
                            active: root.span === modelData.span
                            accent: Theme.green
                            onClicked: {
                                root.now = Date.now() / 1000;
                                root.span = modelData.span;
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: root.samples.length < 2
                    text: "No history yet: the shell writes it once a minute in laptop mode (battery-log.py), so it fills from now on."
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    color: Theme.subtext0
                }

                // On battery in the range
                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: 8

                    Repeater {
                        model: [
                            { label: "On battery", value: root.totals.seconds ? root.duration(root.totals.seconds) : "–", accent: Theme.yellow },
                            { label: "Average draw", value: root.totals.watts ? `${root.totals.watts.toFixed(1)} W` : "–", accent: Theme.peach },
                            { label: "Pace", value: root.totals.pace ? `${root.totals.pace.toFixed(1)}% / h` : "–", accent: Theme.blue },
                            { label: "Full charge lasts", value: root.totals.full ? root.duration(root.totals.full) : "–", accent: Theme.green }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 62
                            radius: 10
                            color: Theme.mantle

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.pixelSize: 10
                                    color: Theme.overlay1
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: modelData.accent
                                }
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: -10
                    text: "Time awake on battery; pace and draw from the charge and energy used in that time."
                    font.pixelSize: 10
                    color: Theme.overlay0
                }

                // Charts
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    SectionTitle {
                        text: "Charge"
                    }
                    HistoryChart {
                        Layout.fillWidth: true
                        implicitHeight: 150
                        samples: root.shown.map(s => ({ t: s.t, v: s.percent, charging: s.state !== "d" }))
                        from: root.from
                        to: root.now
                        color: Theme.green
                        gap: root.gap
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    SectionTitle {
                        text: "Power draw"
                    }
                    // On battery only: while charging it's the charger's power
                    HistoryChart {
                        readonly property var points: root.shown.filter(s => s.state === "d").map(s => ({ t: s.t, v: s.power, charging: false }))

                        Layout.fillWidth: true
                        implicitHeight: 110
                        samples: points
                        from: root.from
                        to: root.now
                        maxValue: Math.max(5, Math.ceil(points.reduce((m, p) => Math.max(m, p.v), 0) / 5) * 5)
                        unit: "W"
                        decimals: 1
                        color: Theme.peach
                        gap: root.gap
                    }
                }

                // Busiest apps
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    SectionTitle {
                        text: "Busiest apps on battery"
                    }

                    Label {
                        visible: root.apps.length === 0
                        text: "None recorded in this time yet."
                        color: Theme.subtext0
                    }

                    Repeater {
                        model: root.apps

                        delegate: ColumnLayout {
                            id: app

                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Label {
                                    Layout.fillWidth: true
                                    text: app.modelData.name
                                }
                                Label {
                                    text: `${root.duration(app.modelData.cpu)} CPU · ${Math.round(app.modelData.share * 100)}%`
                                    color: Theme.subtext0
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: Theme.surface0

                                Rectangle {
                                    width: parent.width * app.modelData.cpu / root.apps[0].cpu
                                    height: parent.height
                                    radius: 3
                                    color: app.index === 0 ? Theme.peach : app.index < 3 ? Theme.yellow : Theme.overlay1
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: root.apps.length > 0
                        text: "CPU time while on battery, the share of all of it. That shows what keeps the processor busy; the screen, Wi-Fi and the graphics draw power as well."
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        font.pixelSize: 10
                        color: Theme.overlay0
                    }
                }

                // Times on battery
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.sessions.length > 0
                    spacing: 6

                    SectionTitle {
                        text: "Times on battery"
                    }

                    Repeater {
                        model: root.sessions.slice(0, 30)

                        delegate: Rectangle {
                            id: session

                            required property var modelData
                            readonly property real used: modelData.from - modelData.to
                            readonly property real pace: modelData.awake >= 600 && used >= 2 ? used / (modelData.awake / 3600) : 0

                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 8
                            color: Theme.mantle

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                ColumnLayout {
                                    Layout.preferredWidth: 190
                                    spacing: 1

                                    Label {
                                        text: `${Qt.formatDateTime(new Date(session.modelData.start * 1000), "ddd d.M. HH:mm")} – ${session.modelData.ongoing ? "now" : Qt.formatTime(new Date(session.modelData.end * 1000), "HH:mm")}`
                                    }
                                    Label {
                                        text: `${root.duration(session.modelData.end - session.modelData.start)}${session.modelData.end - session.modelData.start - session.modelData.awake > 600 ? `, ${root.duration(session.modelData.awake)} awake` : ""}`
                                        font.pixelSize: 10
                                        color: Theme.overlay1
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: `${session.modelData.from}% → ${session.modelData.to}%`
                                    color: Theme.subtext1
                                }
                                Label {
                                    text: session.pace ? `${session.pace.toFixed(1)}% / h · ${(session.modelData.energy / (session.modelData.awake / 3600)).toFixed(1)} W` : ""
                                    color: Theme.subtext0
                                }
                                Label {
                                    Layout.preferredWidth: 110
                                    horizontalAlignment: Text.AlignRight
                                    text: session.pace ? `full: ${root.duration(100 / session.pace * 3600)}` : ""
                                    color: Theme.green
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
