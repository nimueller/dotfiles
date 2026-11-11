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

    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
    readonly property string dir: `${stateHome}/battery-history`
    readonly property real gap: 180 // s, see battery-log.py

    property int span: 86400
    property real now: Date.now() / 1000
    readonly property real from: now - span
    property var samples: [] // [{ t, percent, energy, power, state }], oldest first
    property var hours: ({}) // apps.json

    readonly property var ranges: [
        {
            text: "24 h",
            span: 86400
        },
        {
            text: I18n.tr("7 days"),
            span: 7 * 86400
        },
        {
            text: I18n.tr("30 days"),
            span: 30 * 86400
        }
    ]

    // "Mon 3.2. 09:15 – 11:40", or "– now" while it lasts
    function sessionTimes(s) {
        const start = I18n.formatDateTime(new Date(s.start * 1000), "ddd d.M. HH:mm");
        const end = s.ongoing ? I18n.tr("now") : Qt.formatTime(new Date(s.end * 1000), "HH:mm");
        return `${start} – ${end}`;
    }

    // How long it lasted, and how long it was awake if it slept for a while
    function sessionLength(s) {
        const length = s.end - s.start;
        const awakeNote = length - s.awake > 600 ? I18n.tr(", %1 awake", duration(s.awake)) : "";
        return duration(length) + awakeNote;
    }

    function duration(seconds) {
        const d = Math.floor(seconds / 86400);
        const h = Math.floor(seconds % 86400 / 3600);
        const m = Math.round(seconds % 3600 / 60);
        if (d) {
            return I18n.tr("%1 d %2 h", d, h);
        }
        if (h) {
            return `${h} h ${m} min`;
        }
        if (seconds < 60) {
            return `${Math.round(seconds)} s`;
        }
        return `${m} min`;
    }

    // From the first sample in the range on
    readonly property int first: {
        let lo = 0, hi = samples.length;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (samples[mid].t < from) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
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

    // Where no samples were written on battery (suspended, off, the logger
    // restarting): the average draw from the energy used in between. Not
    // when it charged meanwhile: then an end isn't on battery, or it gained.
    function drawInGap(before, after) {
        const seconds = after.t - before.t;
        const used = before.energy - after.energy;
        const isOnBattery = before.state === "d" && after.state === "d";
        const isEstimable = seconds > gap && isOnBattery && used >= 0;
        if (isEstimable) {
            return {
                from: before.t,
                to: after.t,
                v: used / (seconds / 3600)
            };
        }
        return null;
    }
    readonly property var gapDraws: {
        const out = [];
        for (let i = Math.max(1, first); i < samples.length; i++) {
            const estimate = drawInGap(samples[i - 1], samples[i]);
            if (estimate) {
                out.push(estimate);
            }
        }
        return out;
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
                cur = {
                    start: s.t,
                    end: s.t,
                    from: s.percent,
                    to: s.percent,
                    awake: 0,
                    energy: 0
                };
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
            if (Number(key) + 3600 <= from) {
                continue;
            }
            for (const name in hours[key].apps) {
                sums[name] = (sums[name] ?? 0) + hours[key].apps[name];
                total += hours[key].apps[name];
            }
        }
        return Object.keys(sums).map(name => ({
                    name: name,
                    cpu: sums[name],
                    share: total ? sums[name] / total : 0
                })).sort((a, b) => b.cpu - a.cpu).slice(0, 10);
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
                if (f.length >= 5) {
                    out.push({
                        t: Number(f[0]),
                        percent: Number(f[1]),
                        energy: Number(f[2]),
                        power: Number(f[3]),
                        state: f[4]
                    });
                }
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
    // battery-log.py writes what it has collected so far on SIGUSR1
    Component.onCompleted: {
        const logger = `/usr/bin/python3 ${Quickshell.shellPath("battery-log.py")}`;
        Quickshell.execDetached(["pkill", "-USR1", "-fx", logger]);
    }

    FloatingWindow {
        title: I18n.tr("Battery History")
        implicitWidth: 760
        implicitHeight: 720
        color: Theme.base
        onVisibleChanged: if (!visible) {
            Menus.close("battery-history");
        }

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
                    title: I18n.tr("Battery History")

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
                    text: I18n.tr("No history yet: the shell writes it once a minute in laptop mode (battery-log.py), so it fills from now on.")
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
                            {
                                label: I18n.tr("On battery"),
                                value: root.totals.seconds ? root.duration(root.totals.seconds) : "–",
                                accent: Theme.yellow
                            },
                            {
                                label: I18n.tr("Average draw"),
                                value: root.totals.watts ? `${root.totals.watts.toFixed(1)} W` : "–",
                                accent: Theme.peach
                            },
                            {
                                label: I18n.tr("Pace"),
                                value: root.totals.pace ? `${root.totals.pace.toFixed(1)}% / h` : "–",
                                accent: Theme.blue
                            },
                            {
                                label: I18n.tr("Full charge lasts"),
                                value: root.totals.full ? root.duration(root.totals.full) : "–",
                                accent: Theme.green
                            }
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
                    text: I18n.tr("Time awake on battery; pace and draw from the charge and energy used in that time.")
                    font.pixelSize: 10
                    color: Theme.overlay0
                }

                // Charts
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    SectionTitle {
                        text: I18n.tr("Charge")
                    }
                    HistoryChart {
                        Layout.fillWidth: true
                        implicitHeight: 150
                        samples: root.shown.map(s => ({
                                    t: s.t,
                                    v: s.percent,
                                    charging: s.state !== "d"
                                }))
                        from: root.from
                        to: root.now
                        color: Theme.green
                        gap: root.gap
                        connectGaps: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    SectionTitle {
                        text: I18n.tr("Power draw")
                    }
                    // On battery only: while charging it's the charger's power.
                    // Gaps show the average draw over them.
                    HistoryChart {
                        readonly property var points: root.shown.filter(s => s.state === "d").map(s => ({
                                    t: s.t,
                                    v: s.power,
                                    charging: false
                                }))

                        Layout.fillWidth: true
                        implicitHeight: 110
                        samples: points
                        estimates: root.gapDraws
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
                        text: I18n.tr("Busiest apps on battery")
                    }

                    Label {
                        visible: root.apps.length === 0
                        text: I18n.tr("None recorded in this time yet.")
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
                                    text: {
                                        const share = Math.round(app.modelData.share * 100);
                                        return `${root.duration(app.modelData.cpu)} CPU · ${share}%`;
                                    }
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
                                    color: {
                                        if (app.index === 0) {
                                            return Theme.peach;
                                        }
                                        if (app.index < 3) {
                                            return Theme.yellow;
                                        }
                                        return Theme.overlay1;
                                    }
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
                        text: I18n.tr("Times on battery")
                    }

                    Repeater {
                        model: root.sessions.slice(0, 30)

                        delegate: Rectangle {
                            id: session

                            required property var modelData
                            readonly property real used: modelData.from - modelData.to
                            readonly property real pace: {
                                const isLongEnough = modelData.awake >= 600 && used >= 2;
                                return isLongEnough ? used / (modelData.awake / 3600) : 0;
                            }

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
                                        text: root.sessionTimes(session.modelData)
                                    }
                                    Label {
                                        text: root.sessionLength(session.modelData)
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
                                    text: {
                                        if (!session.pace) {
                                            return "";
                                        }
                                        const s = session.modelData;
                                        const watts = (s.energy / (s.awake / 3600)).toFixed(1);
                                        return `${session.pace.toFixed(1)}% / h · ${watts} W`;
                                    }
                                    color: Theme.subtext0
                                }
                                Label {
                                    Layout.preferredWidth: 110
                                    horizontalAlignment: Text.AlignRight
                                    text: session.pace ? I18n.tr("full: %1", root.duration(100 / session.pace * 3600)) : ""
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
