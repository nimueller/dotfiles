//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Machine Settings: this machine's own settings, which stay out of git.
// Displays (arrangement, mode, scale, rotation, VRR, HDR), environment
// variables (e.g. drivers) and autostart programs, written to
// config/hypr/local.lua (see local.example.lua) between
// "-- BEGIN settings" and "-- END settings"; anything else in that file is
// kept. Apply tries the displays right away and goes back unless kept
// within 15 seconds. Opened from the launcher or with `toggle.sh settings`.
ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // Another file can be given to try the app out
    readonly property string path: Quickshell.env("MACHINE_SETTINGS_FILE") || `${home}/.config/hypr/local.lua`

    property string page: "displays"
    property var monitors: [] // { desc, name, connected, enabled, mode, x, y, scale, transform, vrr, wideColor, hdr, modes }
    property var env: [] // [[name, value]]
    property var autostart: [] // ["command"]
    property int selected: 0
    property bool dirty: false
    property string status: ""

    // Apply: the live state before it, and the countdown to go back to it
    property var before: []
    property int countdown: 0

    readonly property var scales: [1, 1.25, 1.333333, 1.5, 1.6, 1.75, 2, 2.5, 3]
    readonly property var rotations: [{ text: "None", value: 0 }, { text: "90°", value: 1 }, { text: "180°", value: 2 }, { text: "270°", value: 3 }]

    // local.lua ------------------------------------------------------------------

    function luaString(s) {
        return `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
    }

    function monitorLua(m) {
        const f = [`output = ${luaString("desc:" + m.desc)}`];
        if (!m.enabled) {
            f.push("disabled = true");
        } else {
            f.push(`mode = ${luaString(m.mode)}`, `position = "${m.x}x${m.y}"`, `scale = ${m.scale}`);
            if (m.transform)
                f.push(`transform = ${m.transform}`);
            if (m.vrr)
                f.push("vrr = 1");
            if (m.wideColor)
                f.push("supports_wide_color = 1");
            if (m.hdr)
                f.push("supports_hdr = 1");
        }
        return `hl.monitor({ ${f.join(", ")} })`;
    }

    function saved() {
        return {
            monitors: monitors.map(m => ({ desc: m.desc, name: m.name, enabled: m.enabled, mode: m.mode, x: m.x, y: m.y, scale: m.scale, transform: m.transform, vrr: m.vrr, wideColor: m.wideColor, hdr: m.hdr })),
            env: env.filter(e => e[0].trim()),
            autostart: autostart.filter(c => c.trim())
        };
    }

    function block() {
        const s = saved();
        const lines = ["-- BEGIN settings: written by Machine Settings, change them there", `-- settings: ${JSON.stringify(s)}`];
        if (s.monitors.length)
            lines.push("", "-- Displays", ...s.monitors.map(monitorLua));
        if (s.env.length)
            lines.push("", "-- Environment", ...s.env.map(([k, v]) => `hl.env(${luaString(k.trim())}, ${luaString(v)})`));
        if (s.autostart.length)
            lines.push("", "-- Autostart", 'hl.on("hyprland.start", function()', ...s.autostart.map(c => `    hl.exec_cmd(${luaString(c.trim())})`), "end)");
        lines.push("-- END settings");
        return lines.join("\n");
    }

    function save() {
        const text = file.loaded ? file.text() : "-- This machine's settings, not in git (see local.example.lua)\n\n";
        const re = /-- BEGIN settings[\s\S]*?-- END settings\n?/;
        file.setText(re.test(text) ? text.replace(re, block() + "\n") : `${text.replace(/\n*$/, "\n\n")}${block()}\n`);
        dirty = false;
        status = "Saved. Environment and autostart changes apply at the next login.";
    }

    // The saved settings, merged with the monitors connected right now
    function load(live) {
        let s = { monitors: [], env: [], autostart: [] };
        const match = (file.loaded ? file.text() : "").match(/^-- settings: (.*)$/m);
        if (match) {
            try {
                s = Object.assign(s, JSON.parse(match[1]));
            } catch (e) {}
        }
        const list = [];
        for (const l of live) {
            const m = s.monitors.find(m => m.desc === l.description);
            const liveMode = `${l.width}x${l.height}@${l.refreshRate.toFixed(2)}`;
            list.push({
                desc: l.description,
                name: l.name,
                connected: true,
                enabled: m ? m.enabled : !l.disabled,
                mode: m?.mode ?? liveMode,
                x: m?.x ?? l.x,
                y: m?.y ?? l.y,
                scale: m?.scale ?? l.scale,
                transform: m?.transform ?? l.transform,
                vrr: m?.vrr ?? !!l.vrr,
                wideColor: m?.wideColor ?? false,
                hdr: m?.hdr ?? false,
                modes: l.availableModes.map(a => a.replace(/Hz$/, ""))
            });
        }
        for (const m of s.monitors)
            if (!list.some(l => l.desc === m.desc))
                list.push(Object.assign({ connected: false, modes: [] }, m));
        monitors = list;
        env = s.env;
        autostart = s.autostart;
        selected = Math.max(0, list.findIndex(m => m.connected));
    }

    function change(index, props) {
        const list = monitors.slice();
        list[index] = Object.assign({}, list[index], props);
        monitors = list;
        dirty = true;
    }

    // Two modes are the same if resolution and rounded refresh rate match
    function sameMode(a, b) {
        const p = s => {
            const [res, hz] = s.split("@");
            return `${res}@${Math.round(parseFloat(hz || "60"))}`;
        };
        return p(a) === p(b);
    }

    // Apply ----------------------------------------------------------------------

    function apply() {
        if (!monitors.some(m => m.connected && m.enabled)) {
            status = "At least one monitor has to stay on.";
            return;
        }
        snapshot.running = true; // remembers the live state, then applies
    }

    function run(lines) {
        Quickshell.execDetached(["hyprctl", "--batch", lines.map(l => `eval ${l}`).join(" ; ")]);
    }

    Process {
        id: snapshot

        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.before = JSON.parse(text).map(l => ({
                        desc: l.description,
                        enabled: !l.disabled,
                        mode: `${l.width}x${l.height}@${l.refreshRate.toFixed(2)}`,
                        x: l.x,
                        y: l.y,
                        scale: l.scale,
                        transform: l.transform,
                        vrr: !!l.vrr
                    }));
                } catch (e) {
                    root.before = [];
                }
                root.run(root.monitors.filter(m => m.connected).map(root.monitorLua));
                root.countdown = 15;
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.countdown > 0
        onTriggered: {
            if (--root.countdown === 0)
                root.revert();
        }
    }

    function keep() {
        countdown = 0;
        status = "Applied. Save to keep it after the next login.";
    }

    function revert() {
        countdown = 0;
        run(before.map(monitorLua));
        status = "Went back to the previous display settings.";
    }

    // Data -----------------------------------------------------------------------

    FileView {
        id: file

        path: root.path
        blockLoading: true
        printErrors: false
    }

    Process {
        running: true
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.load(JSON.parse(text));
                } catch (e) {
                    root.load([]);
                }
            }
        }
    }

    // Window ---------------------------------------------------------------------

    FloatingWindow {
        id: window

        title: "Machine Settings"
        implicitWidth: 860
        implicitHeight: 600
        color: Theme.base
        onVisibleChanged: if (!visible)
            Qt.quit()

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Pages
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 190
                color: Theme.mantle

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    Header {
                        Layout.bottomMargin: 10
                        glyph: Theme.glyph(0xf0493) // 󰒓
                        accent: Theme.lavender
                        title: "Settings"
                    }

                    Repeater {
                        model: [
                            { id: "displays", text: "Displays", glyph: 0xf0379 },
                            { id: "env", text: "Environment", glyph: 0xf0169 },
                            { id: "autostart", text: "Autostart", glyph: 0xf040a }
                        ]

                        delegate: Rectangle {
                            id: tab

                            required property var modelData
                            readonly property bool current: root.page === modelData.id

                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 8
                            color: current ? Theme.alpha(Theme.lavender, 0.15) : tabMouse.containsMouse ? Theme.surface0 : "transparent"

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                spacing: 10

                                Label {
                                    text: Theme.glyph(tab.modelData.glyph)
                                    color: tab.current ? Theme.lavender : Theme.overlay2
                                }
                                Label {
                                    text: tab.modelData.text
                                    color: tab.current ? Theme.text : Theme.subtext0
                                }
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.page = tab.modelData.id
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        text: "Stored in config/hypr/local.lua, which stays out of git."
                        font.pixelSize: 10
                        color: Theme.overlay0
                    }
                }
            }

            ColumnLayout {
                // The space next to the sidebar, not the width of the content
                Layout.preferredWidth: 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 20
                spacing: 14

                // Displays -------------------------------------------------------
                ColumnLayout {
                    visible: root.page === "displays"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14

                    SectionTitle {
                        text: "Arrangement — drag to move"
                    }

                    DisplayLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 200
                        monitors: root.monitors
                        selected: root.selected
                        onPicked: index => root.selected = index
                        onMoved: (index, x, y) => root.change(index, { x, y })
                    }

                    // The monitors, to pick one (also those switched off or not connected)
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.monitors

                            delegate: IconButton {
                                required property var modelData
                                required property int index

                                glyph: Theme.glyph(0xf0379)
                                text: modelData.connected ? modelData.name : `${modelData.name} (not connected)`
                                active: root.selected === index
                                onClicked: root.selected = index
                            }
                        }
                    }

                    // The selected monitor
                    GridLayout {
                        readonly property var m: root.monitors[root.selected] ?? null

                        visible: !!m
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 14
                        rowSpacing: 10

                        Label {
                            Layout.columnSpan: 4
                            Layout.fillWidth: true
                            text: parent.m?.desc ?? ""
                            color: Theme.subtext0
                        }

                        Label {
                            text: "On"
                        }
                        Switch {
                            checked: parent.m?.enabled ?? false
                            onToggled: root.change(root.selected, { enabled: !parent.m.enabled })
                        }
                        Label {
                            text: "Rotation"
                        }
                        Dropdown {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 100
                            model: root.rotations
                            current: parent.m?.transform ?? 0
                            onPicked: value => root.change(root.selected, { transform: value })
                        }

                        Label {
                            text: "Mode"
                        }
                        Dropdown {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 100
                            model: parent.m?.modes ?? []
                            current: (parent.m?.modes ?? []).find(a => root.sameMode(a, parent.m.mode)) ?? null
                            onPicked: value => root.change(root.selected, { mode: value })
                        }
                        Label {
                            text: "Scale"
                        }
                        Dropdown {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 100
                            model: root.scales.map(s => ({ text: `${Math.round(s * 100)} %`, value: s }))
                            current: root.scales.find(s => Math.abs(s - (parent.m?.scale ?? 1)) < 0.01) ?? null
                            onPicked: value => root.change(root.selected, { scale: value })
                        }

                        Label {
                            text: "Variable refresh"
                        }
                        Switch {
                            checked: parent.m?.vrr ?? false
                            onToggled: root.change(root.selected, { vrr: !parent.m.vrr })
                        }
                        Label {
                            text: "Wide colour / HDR"
                        }
                        Row {
                            spacing: 10

                            Switch {
                                checked: parent.parent.m?.wideColor ?? false
                                onToggled: root.change(root.selected, { wideColor: !parent.parent.m.wideColor })
                            }
                            Switch {
                                checked: parent.parent.m?.hdr ?? false
                                onToggled: root.change(root.selected, { hdr: !parent.parent.m.hdr })
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }

                // Environment ----------------------------------------------------
                ColumnLayout {
                    visible: root.page === "env"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    SectionTitle {
                        text: "Environment variables — e.g. for graphics drivers"
                    }

                    Repeater {
                        model: root.env

                        delegate: RowLayout {
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            spacing: 8

                            InputField {
                                Layout.preferredWidth: 240
                                text: modelData[0]
                                placeholder: "NAME"
                                onTextChanged: if (text !== root.env[index][0]) {
                                    root.env[index][0] = text;
                                    root.dirty = true;
                                }
                            }
                            InputField {
                                Layout.fillWidth: true
                                text: modelData[1]
                                placeholder: "value"
                                onTextChanged: if (text !== root.env[index][1]) {
                                    root.env[index][1] = text;
                                    root.dirty = true;
                                }
                            }
                            IconButton {
                                glyph: Theme.glyph(0xf0156) // 󰅖
                                onClicked: {
                                    root.env = root.env.filter((_, i) => i !== index);
                                    root.dirty = true;
                                }
                            }
                        }
                    }

                    IconButton {
                        glyph: Theme.glyph(0xf0415) // 󰐕
                        text: "Add variable"
                        onClicked: root.env = [...root.env, ["", ""]]
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }

                // Autostart ------------------------------------------------------
                ColumnLayout {
                    visible: root.page === "autostart"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    SectionTitle {
                        text: "Programs started with Hyprland on this machine — $HOME works"
                    }

                    Repeater {
                        model: root.autostart

                        delegate: RowLayout {
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            spacing: 8

                            InputField {
                                Layout.fillWidth: true
                                text: modelData
                                placeholder: "command"
                                onTextChanged: if (text !== root.autostart[index]) {
                                    root.autostart[index] = text;
                                    root.dirty = true;
                                }
                            }
                            IconButton {
                                glyph: Theme.glyph(0xf0156) // 󰅖
                                onClicked: {
                                    root.autostart = root.autostart.filter((_, i) => i !== index);
                                    root.dirty = true;
                                }
                            }
                        }
                    }

                    IconButton {
                        glyph: Theme.glyph(0xf0415) // 󰐕
                        text: "Add program"
                        onClicked: root.autostart = [...root.autostart, ""]
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }

                // Actions --------------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        Layout.fillWidth: true
                        text: root.countdown > 0 ? `Keep these display settings? Going back in ${root.countdown} s` : root.status || (root.dirty ? "Unsaved changes" : "")
                        color: root.countdown > 0 ? Theme.peach : Theme.subtext0
                    }
                    IconButton {
                        visible: root.countdown > 0
                        text: "Keep"
                        accent: Theme.green
                        active: true
                        onClicked: root.keep()
                    }
                    IconButton {
                        visible: root.countdown > 0
                        text: "Go back"
                        onClicked: root.revert()
                    }
                    IconButton {
                        visible: root.countdown === 0 && root.page === "displays"
                        glyph: Theme.glyph(0xf0379)
                        text: "Apply"
                        onClicked: root.apply()
                    }
                    IconButton {
                        visible: root.countdown === 0
                        glyph: Theme.glyph(0xf0193) // 󰆓
                        text: "Save"
                        accent: Theme.blue
                        active: root.dirty
                        onClicked: root.save()
                    }
                }
            }
        }
    }
}
