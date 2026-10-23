//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Machine Settings: this machine's own settings, which stay out of git.
// Displays (arrangement, mode, scale, rotation, VRR, HDR, workspaces, the
// main monitor for notifications), environment
// variables (e.g. drivers), autostart programs, the laptop and touch mode
// (config/hypr/modes.lua: detected, or forced on or off) with the touchpad
// (right click in the corner or with two fingers, tapping, scrolling and its
// speed, typing), the bar and when to warn
// about memory, the CPU and the disk (read by the shell through
// LocalSettings.qml), written to
// config/hypr/local.lua (see local.example.lua) between
// "-- BEGIN settings" and "-- END settings"; anything else in that file is
// kept. Apply tries the displays right away and goes back unless kept
// within 15 seconds. The profile picture on the lock screen is ~/.face
// instead, changed right away (face.py). Opened from the launcher or with
// `toggle.sh settings`.
ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // Another file can be given to try the app out
    readonly property string path: Quickshell.env("MACHINE_SETTINGS_FILE") || `${home}/.config/hypr/local.lua`

    property string page: "displays"
    property var monitors: [] // { desc, name, connected, enabled, mode, x, y, scale, transform, vrr, wideColor, hdr, workspaces, main, modes }
    property var caps: ({}) // what each connected monitor supports, by port: { vrr, wideColor, hdr }, missing if unknown
    property var env: [] // [[name, value]]
    property var autostart: [] // ["command"]
    property var bar: ({ windowTitle: false })
    property var modes: ({}) // laptop, touch: true | false when forced, missing when detected
    property var touchpad: ({}) // Hyprland's input:touchpad options set here, e.g. clickfinger_behavior: false; missing ones as by default
    property var warnings: LocalSettings.withDefaults({}) // see LocalSettings.qml
    property int selected: 0
    property bool dirty: false
    property string status: ""
    property bool scrollTried: false // the scrolling speed was changed live and not saved yet
    property int faceVersion: 0 // to load ~/.face again once it's replaced

    // Apply: the live state before it, and the countdown to go back to it
    property var before: []
    property int countdown: 0

    readonly property var scales: [1, 1.25, 1.333333, 1.5, 1.6, 1.75, 2, 2.5, 3]
    readonly property var rotations: [{ text: "None", value: 0 }, { text: "90°", value: 1 }, { text: "180°", value: 2 }, { text: "270°", value: 3 }]

    // local.lua ------------------------------------------------------------------

    function luaString(s) {
        return `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
    }

    function shellQuote(s) {
        return `'${String(s).replace(/'/g, "'\\''")}'`;
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

    // "1-9, 12" -> [1, 2, ..., 9, 12]
    function workspaceList(text) {
        const list = [];
        for (const part of (text || "").split(",")) {
            const [a, b] = part.split("-").map(s => parseInt(s.trim()));
            if (!isNaN(a))
                for (let w = a; w <= (isNaN(b) ? a : b) && w - a < 100; w++)
                    list.push(w);
        }
        return list;
    }

    function saved() {
        return {
            monitors: monitors.map(m => ({ desc: m.desc, name: m.name, enabled: m.enabled, mode: m.mode, x: m.x, y: m.y, scale: m.scale, transform: m.transform, vrr: m.vrr, wideColor: m.wideColor, hdr: m.hdr, workspaces: m.workspaces, main: m.main })),
            env: env.filter(e => e[0].trim()),
            autostart: autostart.filter(c => c.trim()),
            modes: modes,
            touchpad: touchpad,
            bar: bar,
            warnings: warnings
        };
    }

    function block() {
        const s = saved();
        const lines = ["-- BEGIN settings: written by Machine Settings, change them there", `-- settings: ${JSON.stringify(s)}`];
        if (s.monitors.length)
            lines.push("", "-- Displays", ...s.monitors.map(monitorLua));
        // Workspaces on their monitor; the first opens there by default
        const rules = [];
        for (const m of s.monitors.filter(m => m.enabled))
            workspaceList(m.workspaces).forEach((w, i) => rules.push(`hl.workspace_rule({ workspace = "${w}", monitor = ${luaString("desc:" + m.desc)}${i === 0 ? ", default = true" : ""} })`));
        if (rules.length)
            lines.push("", "-- Workspaces", ...rules);
        if (s.env.length)
            lines.push("", "-- Environment", ...s.env.map(([k, v]) => `hl.env(${luaString(k.trim())}, ${luaString(v)})`));
        const forced = Object.entries(s.modes).map(([k, v]) => `${k} = ${v}`);
        if (forced.length)
            lines.push("", "-- Laptop and touch mode, forced (modes.lua)", `require("modes").set({ ${forced.join(", ")} })`);
        const touchpad = Object.entries(s.touchpad).map(([k, v]) => `${k} = ${v}`);
        if (touchpad.length)
            lines.push("", "-- Touchpad (modes.lua applies it after the modes)", `require("modes").touchpad({ ${touchpad.join(", ")} })`);
        if (s.autostart.length)
            lines.push("", "-- Autostart", 'hl.on("hyprland.start", function()', ...s.autostart.map(c => `    hl.exec_cmd(${luaString("after-unlock " + shellQuote(c.trim()))})`), "end)");
        lines.push("-- END settings");
        return lines.join("\n");
    }

    function save() {
        const text = file.loaded ? file.text() : "-- This machine's settings, not in git (see local.example.lua)\n\n";
        const re = /-- BEGIN settings[\s\S]*?-- END settings\n?/;
        file.setText(re.test(text) ? text.replace(re, block() + "\n") : `${text.replace(/\n*$/, "\n\n")}${block()}\n`);
        dirty = false;
        scrollTried = false;
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
                workspaces: m?.workspaces ?? "",
                main: m?.main ?? false,
                modes: l.availableModes.map(a => a.replace(/Hz$/, ""))
            });
        }
        for (const m of s.monitors)
            if (!list.some(l => l.desc === m.desc))
                list.push(Object.assign({ connected: false, modes: [] }, m));
        monitors = list;
        env = s.env;
        bar = Object.assign({ windowTitle: false }, s.bar);
        modes = s.modes ?? {};
        touchpad = s.touchpad ?? {};
        warnings = LocalSettings.withDefaults(s.warnings);
        autostart = s.autostart;
        selected = Math.max(0, list.findIndex(m => m.connected));
    }

    // warn("cpu", { percent: 90 }); a disk level by its index
    function warn(group, props) {
        warnings = Object.assign({}, warnings, { [group]: Object.assign({}, warnings[group], props) });
        dirty = true;
    }

    function warnDisk(index, props) {
        warn("disk", { levels: warnings.disk.levels.map((l, i) => i === index ? Object.assign({}, l, props) : l) });
    }

    // A number of the warnings' limits
    component NumberField: InputField {
        required property real value
        signal edited(real value)

        Layout.preferredWidth: 56
        text: String(value)
        // Typing ends the binding: follow loads and Defaults by hand
        onValueChanged: if (parseFloat(text.replace(",", ".")) !== value)
            text = String(value)
        onTextChanged: {
            const v = parseFloat(text.replace(",", "."));
            if (!isNaN(v) && v >= 0 && v !== value)
                edited(v);
        }
    }

    // The touchpad's scrolling speed, null for the default; tried right away
    function scrollFactor(f) {
        const t = Object.assign({}, touchpad);
        if (f === null || f === 1)
            delete t.scroll_factor;
        else
            t.scroll_factor = f;
        touchpad = t;
        dirty = true;
        scrollTried = true;
        run([`hl.config({ input = { touchpad = { scroll_factor = ${f ?? 1} } } })`]);
    }

    function change(index, props) {
        const list = monitors.slice();
        list[index] = Object.assign({}, list[index], props);
        monitors = list;
        dirty = true;
    }

    // Whether monitor m supports a feature (vrr, wideColor, hdr); yes if unknown
    function supports(m, feature) {
        return !m?.connected || root.caps[m.name]?.[feature] !== false;
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

    // "DP-1 vrr=1 wide=1 hdr=0" for each connected monitor
    Process {
        running: true
        command: [Quickshell.shellPath("monitor-caps.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const keys = { vrr: "vrr", wide: "wideColor", hdr: "hdr" };
                const caps = {};
                for (const line of text.trim().split("\n").filter(l => l)) {
                    const [name, ...fields] = line.split(" ");
                    caps[name] = {};
                    for (const f of fields) {
                        const [k, v] = f.split("=");
                        if (keys[k])
                            caps[name][keys[k]] = v === "1";
                    }
                }
                root.caps = caps;
            }
        }
    }

    // Picks an image and makes it ~/.face
    Process {
        id: face

        command: ["/usr/bin/python3", Quickshell.shellPath("face.py")]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "saved") {
                root.faceVersion++;
                root.status = "Profile picture changed. The lock screen shows it from the next lock.";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim())
                root.status = `Couldn't change the profile picture: ${text.trim().split("\n").pop()}`
        }
    }

    // A scrolling speed tried but not saved: the config's again
    function quit() {
        if (scrollTried)
            Quickshell.execDetached(["hyprctl", "reload"]);
        Qt.quit();
    }

    // Window ---------------------------------------------------------------------

    FloatingWindow {
        id: window

        title: "Machine Settings"
        implicitWidth: 860
        implicitHeight: 600
        color: Theme.base
        onVisibleChanged: if (!visible)
            root.quit()

        WindowClose {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            z: 1
            onClicked: root.quit()
        }

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
                            { id: "autostart", text: "Autostart", glyph: 0xf040a },
                            { id: "modes", text: "Laptop & touch", glyph: 0xf0322 },
                            { id: "bar", text: "Bar", glyph: 0xf10a9 },
                            { id: "warnings", text: "Warnings", glyph: 0xf0026 },
                            { id: "profile", text: "Profile picture", glyph: 0xf0004 }
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
                        text: root.page === "profile" ? "Stored in ~/.face, which stays out of git." : "Stored in config/hypr/local.lua, which stays out of git."
                        font.pixelSize: 10
                        color: Theme.overlay0
                    }

                    // The file and its folder in their default apps
                    IconButton {
                        Layout.fillWidth: true
                        glyph: Theme.glyph(0xf024b) // 󰉋
                        text: "Hyprland folder"
                        onClicked: Quickshell.execDetached(["gio", "open", root.path.replace(/\/[^/]*$/, "")])
                    }
                    IconButton {
                        Layout.fillWidth: true
                        glyph: Theme.glyph(0xf03eb) // 󰏫
                        text: "Edit local.lua"
                        onClicked: Quickshell.execDetached(["gio", "open", root.path])
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
                            text: "Workspaces"
                        }
                        InputField {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 100
                            text: parent.m?.workspaces ?? ""
                            placeholder: "e.g. 1-9"
                            onTextChanged: if (parent.m && text !== parent.m.workspaces)
                                root.change(root.selected, { workspaces: text })
                        }
                        Label {
                            text: "Main monitor"
                        }
                        Switch {
                            checked: parent.m?.main ?? false
                            onToggled: {
                                // Only one is the main monitor
                                const on = !parent.m.main;
                                root.monitors = root.monitors.map((m, i) => Object.assign({}, m, { main: on && i === root.selected }));
                                root.dirty = true;
                            }
                        }

                        Label {
                            text: "Variable refresh"
                        }
                        // Off and locked where the monitor can't; one that's
                        // on can still be switched off
                        Switch {
                            checked: parent.m?.vrr ?? false
                            enabled: checked || root.supports(parent.m, "vrr")
                            onToggled: root.change(root.selected, { vrr: !parent.m.vrr })
                        }
                        Label {
                            text: "Wide colour / HDR"
                        }
                        Row {
                            spacing: 10

                            Switch {
                                checked: parent.parent.m?.wideColor ?? false
                                enabled: checked || root.supports(parent.parent.m, "wideColor")
                                onToggled: root.change(root.selected, { wideColor: !parent.parent.m.wideColor })
                            }
                            Switch {
                                checked: parent.parent.m?.hdr ?? false
                                enabled: checked || root.supports(parent.parent.m, "hdr")
                                onToggled: root.change(root.selected, { hdr: !parent.parent.m.hdr })
                            }
                        }

                        // What the monitor can't do, and a warning if one of
                        // those is on anyway
                        ColumnLayout {
                            id: unsupported

                            readonly property var missing: [["vrr", "variable refresh"], ["wideColor", "wide colour"], ["hdr", "HDR"]].filter(([f]) => !root.supports(parent.m, f))
                            readonly property var stillOn: missing.filter(([f]) => parent.m?.[f])

                            // "a, b or c"
                            function list(items, last) {
                                const t = items.map(([, text]) => text);
                                return t.length > 1 ? `${t.slice(0, -1).join(", ")} ${last} ${t[t.length - 1]}` : t[0];
                            }

                            visible: missing.length > 0
                            Layout.columnSpan: 4
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                text: `This monitor doesn't support ${unsupported.list(unsupported.missing, "or")}.`
                                font.pixelSize: 11
                                color: Theme.subtext0
                            }

                            Rectangle {
                                visible: unsupported.stillOn.length > 0
                                Layout.fillWidth: true
                                implicitHeight: warning.implicitHeight + 16
                                radius: 8
                                color: Theme.alpha(Theme.yellow, 0.12)
                                border.width: 1
                                border.color: Theme.alpha(Theme.yellow, 0.5)

                                RowLayout {
                                    id: warning

                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Label {
                                        text: Theme.glyph(0xf0026) // 󰀦
                                        font.pixelSize: 16
                                        color: Theme.yellow
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        elide: Text.ElideNone
                                        text: {
                                            const on = unsupported.list(unsupported.stillOn, "and") ?? "";
                                            const many = unsupported.stillOn.length > 1;
                                            return `${on.charAt(0).toUpperCase()}${on.slice(1)} ${many ? "are" : "is"} on, but won't work here. Switch ${many ? "them" : "it"} off.`;
                                        }
                                        color: Theme.yellow
                                    }
                                }
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
                        text: "Programs started on this machine once you've unlocked — $HOME works"
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

                // Laptop & touch --------------------------------------------------
                ColumnLayout {
                    visible: root.page === "modes"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    SectionTitle {
                        text: "Modes — on by themselves where the hardware is there"
                    }

                    Repeater {
                        model: [
                            { id: "laptop", text: "Laptop", about: "Tap to click, swipe with three fingers between workspaces, keyboard backlight keys, the screen off with the lid closed while another monitor is connected, dimming when idle and suspending after 15 minutes on battery, the battery menu with power profiles and low battery warnings" },
                            { id: "touch", text: "Touch", about: "A taller bar with bigger buttons, buttons for the launcher, closing the window and the on-screen keyboard (which also shows by itself for text fields), swiping from the screen's edge between workspaces" }
                        ]

                        delegate: RowLayout {
                            id: modeRow

                            required property var modelData
                            readonly property bool detected: Modes.detected[modelData.id] ?? false

                            Layout.fillWidth: true
                            spacing: 14

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: modeRow.modelData.text
                                    font.bold: true
                                }
                                Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideNone
                                    text: modeRow.modelData.about
                                    font.pixelSize: 11
                                    color: Theme.subtext0
                                }
                            }
                            Dropdown {
                                Layout.preferredWidth: 190
                                Layout.alignment: Qt.AlignTop
                                model: [
                                    { text: `Auto (${modeRow.detected ? "on" : "off"} here)`, value: "auto" },
                                    { text: "On", value: true },
                                    { text: "Off", value: false }
                                ]
                                current: root.modes[modeRow.modelData.id] ?? "auto"
                                onPicked: value => {
                                    const m = Object.assign({}, root.modes);
                                    if (value === "auto")
                                        delete m[modeRow.modelData.id];
                                    else
                                        m[modeRow.modelData.id] = value;
                                    root.modes = m;
                                    root.dirty = true;
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        text: `In effect now: laptop ${Modes.laptop ? "on" : "off"}, touch ${Modes.touch ? "on" : "off"}. Saving applies them right away; the on-screen keyboard starts at the next login, or with its button in the bar.`
                        color: Theme.subtext0
                    }

                    SectionTitle {
                        Layout.topMargin: 10
                        text: "Touchpad — every touchpad on this machine"
                    }

                    Repeater {
                        // def: what applies without a setting here (laptop
                        // mode turns on clickfinger_behavior, general.lua
                        // natural_scroll; Hyprland's defaults otherwise)
                        model: [
                            { id: "clickfinger_behavior", text: "Right click", about: "Pressing down in the bottom right corner (the middle: middle click), or anywhere with two fingers (three: middle click)", def: Modes.laptop, on: "With two fingers", off: "In the corner" },
                            { id: "tap_to_click", text: "Tap to click", about: "Two fingers right-click, three middle-click", def: true, on: "On", off: "Off" },
                            { id: "natural_scroll", text: "Natural scrolling", about: "The content follows the fingers, like on a phone", def: true, on: "On", off: "Off" },
                            { id: "disable_while_typing", text: "Off while typing", about: "For a moment after a key press, against touches with the palm", def: true, on: "On", off: "Off" }
                        ]

                        delegate: RowLayout {
                            id: touchpadRow

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 14

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: touchpadRow.modelData.text
                                    font.bold: true
                                }
                                Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideNone
                                    text: touchpadRow.modelData.about
                                    font.pixelSize: 11
                                    color: Theme.subtext0
                                }
                            }
                            Dropdown {
                                Layout.preferredWidth: 190
                                Layout.alignment: Qt.AlignTop
                                model: [
                                    { text: `Default (${(touchpadRow.modelData.def ? touchpadRow.modelData.on : touchpadRow.modelData.off).toLowerCase()})`, value: "default" },
                                    { text: touchpadRow.modelData.on, value: true },
                                    { text: touchpadRow.modelData.off, value: false }
                                ]
                                current: root.touchpad[touchpadRow.modelData.id] ?? "default"
                                onPicked: value => {
                                    const t = Object.assign({}, root.touchpad);
                                    if (value === "default")
                                        delete t[touchpadRow.modelData.id];
                                    else
                                        t[touchpadRow.modelData.id] = value;
                                    root.touchpad = t;
                                    root.dirty = true;
                                }
                            }
                        }
                    }

                    // Scrolling speed: input:touchpad:scroll_factor, 1 by
                    // default; tried right away while dragging, the saved
                    // one comes back on closing without saving
                    RowLayout {
                        id: scrollRow

                        readonly property real factor: root.touchpad.scroll_factor ?? 1

                        Layout.fillWidth: true
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: "Scrolling speed"
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                text: "How far pages move with two fingers; works while you drag"
                                font.pixelSize: 11
                                color: Theme.subtext0
                            }
                        }
                        Slider {
                            Layout.preferredWidth: 130
                            // 0.2 to 2
                            value: (scrollRow.factor - 0.2) / 1.8
                            onMoved: v => root.scrollFactor(Math.round((0.2 + v * 1.8) * 20) / 20)
                        }
                        Label {
                            Layout.preferredWidth: 40
                            horizontalAlignment: Text.AlignRight
                            text: `${Math.round(scrollRow.factor * 100)} %`
                        }
                        IconButton {
                            glyph: Theme.glyph(0xf0450) // 󰑐
                            visible: root.touchpad.scroll_factor !== undefined
                            onClicked: root.scrollFactor(null)
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }

                // Bar --------------------------------------------------------------
                ColumnLayout {
                    visible: root.page === "bar"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    SectionTitle {
                        text: "Bar"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Switch {
                            checked: root.bar.windowTitle
                            onToggled: {
                                root.bar = Object.assign({}, root.bar, { windowTitle: !root.bar.windowTitle });
                                root.dirty = true;
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "Show the focused window's title next to the workspaces"
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }

                // Warnings ---------------------------------------------------------
                ColumnLayout {
                    visible: root.page === "warnings"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    SectionTitle {
                        text: "Notifications when the system runs out of something — again after every unlock"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Switch {
                            checked: root.warnings.memory.on
                            onToggled: root.warn("memory", { on: !root.warnings.memory.on })
                        }
                        Label {
                            text: "Memory: when less than"
                        }
                        NumberField {
                            value: root.warnings.memory.percent
                            onEdited: v => root.warn("memory", { percent: v })
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "% is free, or the system stalls reclaiming it"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Switch {
                            checked: root.warnings.cpu.on
                            onToggled: root.warn("cpu", { on: !root.warnings.cpu.on })
                        }
                        Label {
                            text: "CPU: when programs wait for it more than"
                        }
                        NumberField {
                            value: root.warnings.cpu.percent
                            onEdited: v => root.warn("cpu", { percent: v })
                        }
                        Label {
                            text: "% of the time, for"
                        }
                        NumberField {
                            value: root.warnings.cpu.minutes
                            onEdited: v => root.warn("cpu", { minutes: v })
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "min"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Switch {
                            checked: root.warnings.disk.on
                            onToggled: root.warn("disk", { on: !root.warnings.disk.on })
                        }
                        Label {
                            Layout.fillWidth: true
                            text: "Disks (/ and the home folder's): when less is free than (the smaller of the two)"
                        }
                    }

                    Repeater {
                        model: root.warnings.disk.levels

                        delegate: RowLayout {
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            Layout.leftMargin: 46
                            spacing: 8

                            Label {
                                Layout.preferredWidth: 110
                                text: ["Warning", "Second warning", "Critical"][index] ?? ""
                                color: index === root.warnings.disk.levels.length - 1 ? Theme.red : Theme.text
                            }
                            NumberField {
                                value: modelData.percent
                                onEdited: v => root.warnDisk(index, { percent: v })
                            }
                            Label {
                                text: "% or"
                            }
                            NumberField {
                                value: modelData.gb
                                onEdited: v => root.warnDisk(index, { gb: v })
                            }
                            Label {
                                Layout.fillWidth: true
                                text: "GB"
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        text: "Each warns once and again when it was fine for a while, or after the screen is unlocked. Saving applies right away."
                        color: Theme.subtext0
                    }

                    IconButton {
                        glyph: Theme.glyph(0xf0450) // 󰑐
                        text: "Defaults"
                        onClicked: {
                            root.warnings = LocalSettings.withDefaults({});
                            root.dirty = true;
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }

                // Profile picture --------------------------------------------------
                ColumnLayout {
                    visible: root.page === "profile"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    SectionTitle {
                        text: "Profile picture — on the lock screen"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20

                        Rectangle {
                            implicitWidth: 128
                            implicitHeight: 128
                            radius: 8
                            color: Theme.surface0
                            border.width: 2
                            border.color: Theme.lavender

                            Image {
                                id: faceImage

                                anchors.fill: parent
                                anchors.margins: 2
                                // The query only makes it load the file again
                                source: `file://${root.home}/.face?${root.faceVersion}`
                                sourceSize: Qt.size(256, 256)
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                asynchronous: true
                            }
                            Label {
                                visible: faceImage.status !== Image.Ready
                                anchors.centerIn: parent
                                text: Theme.glyph(0xf0004) // 󰀄
                                font.pixelSize: 48
                                color: Theme.overlay1
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                text: "Any image: cropped to a square from its middle and made 512 pixels wide. The lock screen shows it round."
                                color: Theme.subtext0
                            }
                            IconButton {
                                glyph: Theme.glyph(0xf02e9) // 󰋩
                                text: face.running ? "Choosing…" : "Choose picture…"
                                onClicked: if (!face.running) {
                                    root.status = "";
                                    face.running = true;
                                }
                            }
                        }
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
                        // The profile picture is changed right away
                        visible: root.countdown === 0 && root.page !== "profile"
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
