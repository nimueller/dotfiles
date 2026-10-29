import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// App launcher. Type to filter, ↑/↓ (or Ctrl+J/K, Tab) to move, Enter to
// launch. Apps you launch often float to the top. The last row runs the text
// as a command ("ssh host" opens in a terminal).
//
// Open windows whose title or app match the text come before the apps
// (the most recently used first); Enter goes to the window, also on a
// scratchpad.
//
// Arithmetic ("2^10/3", "sqrt(2)*pi", "=e") and conversions ("10 km in mi",
// "20 c to f", "100 usd in eur") show their result in the first row; Enter
// copies it. ":" searches emoji instead (":heart", in English or German);
// Enter pastes the emoji into the window you came from. The emoji list
// comes from Nix (pkgs/emoji.py), in ~/.local/share/quickshell-launcher.
// "/" searches files and folders in the home folder by name; Enter opens
// them. The SSH hosts from ~/.ssh/config (and what it includes) come up for
// "ssh <host>" or their name; Enter connects with kitty's `kitten ssh`.
// Conversions, files and the hosts come from launcher.py, which runs while
// the launcher is shown.
//
// Part of the resident daemon.qml, so SUPER+D only has to show it. The key
// sends the Hyprland event "quickshell-launcher" (hl.dsp.event), which
// arrives here over Hyprland's event socket without starting any process;
// `toggle.sh launcher` (IPC) does the same from scripts.
//
// Not a GlobalShortcut: in Quickshell 0.3.1 its destructor segfaults when the
// instance exits, and the crash handler then restarts it.
PanelWindow {
    id: root

    property bool shown: false

    function show() {
        Windows.refresh(); // workspaces and focus order of the windows
        helper.running = true;
        search.text = "";
        list.positionViewAtBeginning();
        shown = true;
        search.forceActiveFocus();
    }

    function hide() {
        shown = false;
        helper.running = false;
        found = [];
    }

    function toggle() {
        if (shown)
            hide();
        else
            show();
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle();
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "custom" || event.data !== "quickshell-launcher")
                return;
            // Looking Glass passes SUPER+D on to the VM
            if (root.shown || ToplevelManager.activeToplevel?.appId !== "looking-glass-client")
                root.toggle();
        }
    }

    readonly property int rows: 8
    readonly property int rowHeight: 52
    readonly property string historyPath: `${Quickshell.env("HOME")}/.local/state/quickshell-launcher.json`

    property string query: ""
    property var counts: ({}) // launches per desktop entry id

    // From launcher.py: the SSH hosts, and what it found for the text
    // (conversions, files), for the request `asked`
    property var sshHosts: [] // [{ host, detail }]
    property var found: []
    property int asked: 0

    onQueryChanged: {
        asked++;
        // File results stay until the next ones arrive, so the list doesn't flicker
        if (!fileMode)
            found = [];
        if (helper.running)
            helper.write(JSON.stringify({ id: asked, q: query }) + "\n");
    }

    Process {
        id: helper
        command: ["/usr/bin/python3", Quickshell.shellPath("launcher.py")]
        stdinEnabled: true
        // What was typed while it started
        onStarted: write(JSON.stringify({ id: root.asked, q: root.query }) + "\n")
        stdout: SplitParser {
            onRead: line => {
                let message = {};
                try {
                    message = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (message.hosts)
                    root.sshHosts = message.hosts;
                else if (message.id === root.asked)
                    root.found = message.results;
            }
        }
    }

    readonly property var apps: {
        const seen = new Set();
        return DesktopEntries.applications.values.filter(a => {
            if (a.noDisplay || seen.has(a.name))
                return false;
            seen.add(a.name);
            return true;
        });
    }
    readonly property bool emojiMode: query.startsWith(":")
    readonly property bool fileMode: query.startsWith("/")
    readonly property var results: {
        if (emojiMode)
            return emojiResults(query.slice(1).trim().toLowerCase());
        if (fileMode)
            return found.filter(r => r.kind === "file").map(r => ({ file: r.path, name: r.name, dir: r.dir, folder: r.folder }));
        const q = query.trim().toLowerCase();
        const ranked = apps.map(app => ({ app, score: score(app, q) })).filter(r => r.score >= 0);
        ranked.sort((a, b) => b.score - a.score || a.app.name.localeCompare(b.app.name));
        // "ssh " before it's trimmed
        const typed = query.replace(/^\s+/, "").toLowerCase();
        const ssh = typed.startsWith("ssh ");
        const hosts = sshResults(ssh ? typed.slice(4).trim() : q, ssh);
        const list = [...(ssh ? hosts : []), ...windowResults(q), ...ranked.map(r => r.app), ...(ssh ? [] : hosts)];
        const result = calculate(query);
        if (result !== null)
            list.unshift({ result });
        for (const r of found.filter(r => r.kind === "convert"))
            list.unshift({ result: r.value, display: r.text, detail: r.detail });
        if (q)
            list.push({ run: query.trim() });
        return list;
    }

    // SSH hosts for "ssh <start of the name>", or whose name starts with the
    // text (two letters at least, so they don't crowd out the apps)
    function sshResults(part, ssh) {
        if (!ssh && part.length < 2)
            return [];
        return sshHosts.filter(h => h.host.toLowerCase().startsWith(part)).map(h => ({ ssh: h.host, detail: h.detail }));
    }

    function score(app, q) {
        const used = Math.min(counts[app.id] ?? 0, 50) * 4;
        if (!q)
            return used;
        const name = app.name.toLowerCase();
        const extra = `${app.genericName} ${app.keywords} ${app.comment} ${app.categories}`.toLowerCase();
        let s = -1;
        if (name === q)
            s = 1000;
        else if (name.startsWith(q))
            s = 800;
        else if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            s = 600;
        else if (name.includes(q))
            s = 400;
        else if (`${app.genericName} ${app.keywords}`.toLowerCase().includes(q))
            s = 250;
        else if (initials(name).startsWith(q))
            s = 150;
        else if (extra.includes(q))
            s = 100;
        return s < 0 ? -1 : s + used;
    }

    // Open windows matching the text: { window, name, app, icon }
    function windowResults(q) {
        if (!q)
            return [];
        const ranked = [];
        for (const w of Hyprland.toplevels.values) {
            const entry = Windows.entry(w);
            const app = entry?.name ?? w.lastIpcObject?.class ?? "";
            const title = (w.title ?? "").toLowerCase();
            let s = -1;
            if (app.toLowerCase().startsWith(q))
                s = 800;
            else if (title.split(/[\s\-_.:|\/]+/).some(x => x.startsWith(q)))
                s = 600;
            else if (title.includes(q) || app.toLowerCase().includes(q) || (w.lastIpcObject?.class ?? "").toLowerCase().includes(q))
                s = 400;
            if (s >= 0)
                ranked.push({ w, entry, app, score: s, recent: w.lastIpcObject?.focusHistoryID ?? 1e9 });
        }
        ranked.sort((a, b) => b.score - a.score || a.recent - b.recent);
        return ranked.map(r => ({ window: r.w, name: r.w.title || r.app || "Window", app: r.app, icon: r.entry?.icon ?? "" }));
    }

    // "Brave · workspace 1", "KeePassXC · passwords scratchpad"
    function windowPlace(item) {
        const ws = item.window.workspace?.name ?? "";
        const place = ws.startsWith("special:") ? `${ws.slice(8)} scratchpad` : ws ? `workspace ${ws}` : "";
        return [item.app, place].filter(x => x).join(" · ");
    }

    // "visual studio code" -> "vsc"
    function initials(name) {
        return name.split(/[\s\-_.:]+/).map(w => w[0] ?? "").join("");
    }

    // Emoji whose name or keywords match, the ones you use often first;
    // otherwise in Unicode's order (faces, people, animals, ...)
    function emojiResults(q) {
        const ranked = [];
        emoji.forEach((e, i) => {
            const used = Math.min(counts[`emoji:${e.e}`] ?? 0, 50) * 4;
            const name = e.n.toLowerCase(); // "flag: Germany"
            let s = -1;
            if (!q)
                s = 0;
            else if (name === q)
                s = 1000;
            else if (name.startsWith(q))
                s = 800;
            else if (e.k.split(" ").includes(q))
                s = 700;
            else if (name.split(/[\s:]+/).some(w => w.startsWith(q)))
                s = 600;
            else if (e.k.split(" ").some(w => w.startsWith(q)))
                s = 300;
            else if (name.includes(q) || e.k.includes(q))
                s = 100;
            if (s >= 0)
                ranked.push({ e, i, score: s + used });
        });
        ranked.sort((a, b) => b.score - a.score || a.i - b.i);
        return ranked.map(r => ({ emoji: r.e.e, name: r.e.n[0].toUpperCase() + r.e.n.slice(1), keywords: r.e.k }));
    }

    // The value of an arithmetic expression, or null for anything else.
    // + - * / % ^ (or **), !, parentheses, pi and e, and sqrt, abs, exp, ln,
    // log (base 10), sin, cos, tan, asin, acos, atan (radians), round, floor
    // and ceil. "," works as the decimal point too. Only text with a digit
    // that isn't just a number counts, unless it starts with "=", so app
    // names don't turn into sums.
    function calculate(text) {
        let src = text.trim();
        if (src.startsWith("="))
            src = src.slice(1);
        else if (!/\d/.test(src) || /^[\d.,\s]+$/.test(src))
            return null;
        const tokens = src.toLowerCase().replace(/,/g, ".").match(/\d*\.?\d+(?:e[+-]?\d+)?|[a-zπ]+|\*\*|\S/g);
        if (!tokens)
            return null;
        const constants = { pi: Math.PI, "π": Math.PI, e: Math.E };
        const functions = {
            sqrt: Math.sqrt, abs: Math.abs, exp: Math.exp, ln: Math.log, log: Math.log10,
            sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
            round: Math.round, floor: Math.floor, ceil: Math.ceil
        };
        let pos = 0;
        const peek = () => tokens[pos];
        const take = t => {
            if (tokens[pos] !== t)
                throw t;
            pos++;
        };
        // expr: term (+|- term)*, term: unary (*|/|% unary)*,
        // unary: -unary | power, power: factorial (^ unary)?
        const expr = () => {
            let v = term();
            while (peek() === "+" || peek() === "-")
                v = tokens[pos++] === "+" ? v + term() : v - term();
            return v;
        };
        const term = () => {
            let v = unary();
            while (["*", "/", "%", "×", "÷"].includes(peek())) {
                const op = tokens[pos++];
                const r = unary();
                v = op === "/" || op === "÷" ? v / r : op === "%" ? v % r : v * r;
            }
            return v;
        };
        const unary = () => {
            if (peek() === "-") {
                pos++;
                return -unary();
            }
            if (peek() === "+") {
                pos++;
                return unary();
            }
            return power();
        };
        const power = () => {
            const v = factorial();
            if (peek() === "^" || peek() === "**") {
                pos++;
                return Math.pow(v, unary());
            }
            return v;
        };
        const factorial = () => {
            let v = primary();
            while (peek() === "!") {
                pos++;
                if (v < 0 || v > 170 || !Number.isInteger(v))
                    throw "!";
                let f = 1;
                for (let i = 2; i <= v; i++)
                    f *= i;
                v = f;
            }
            return v;
        };
        const primary = () => {
            const t = tokens[pos++];
            if (t === "(") {
                const v = expr();
                take(")");
                return v;
            }
            if (/^\d|^\./.test(t ?? ""))
                return parseFloat(t);
            // Own properties only: "constructor" isn't a function here
            if (Object.prototype.hasOwnProperty.call(constants, t))
                return constants[t];
            if (Object.prototype.hasOwnProperty.call(functions, t))
                return functions[t](factorial());
            throw t;
        };
        try {
            const v = expr();
            if (pos !== tokens.length || !isFinite(v))
                return null;
            // 0.1+0.2 reads 0.3
            return String(parseFloat(v.toPrecision(12)));
        } catch (e) {
            return null;
        }
    }

    function launch(item) {
        if (!item)
            return;
        if (item.window !== undefined) {
            hide();
            const address = item.window.address.startsWith("0x") ? item.window.address : `0x${item.window.address}`;
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`);
            return;
        }
        if (item.ssh !== undefined) {
            Quickshell.execDetached(["kitty", "kitten", "ssh", item.ssh]);
            hide();
            return;
        }
        if (item.file !== undefined) {
            Quickshell.execDetached(["xdg-open", item.file]);
            hide();
            return;
        }
        if (item.result !== undefined) {
            Quickshell.execDetached(["wl-copy", "--", item.result]);
            hide();
            return;
        }
        if (item.emoji !== undefined) {
            hide();
            Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | "$2"', "sh", item.emoji, Quickshell.shellPath("paste.sh")]);
            const key = `emoji:${item.emoji}`;
            counts[key] = (counts[key] ?? 0) + 1;
            store.setText(JSON.stringify(counts));
            return;
        }
        if (item.run !== undefined) {
            const ssh = item.run.startsWith("ssh ");
            Quickshell.execDetached(ssh ? ["xdg-terminal-exec", "sh", "-c", item.run] : ["sh", "-c", item.run]);
            hide();
            return;
        }
        if (item.runInTerminal) {
            const cmd = typeof item.command === "string" ? ["sh", "-c", item.command] : Array.from(item.command);
            Quickshell.execDetached(["xdg-terminal-exec", ...cmd]);
        } else {
            item.execute();
        }
        counts[item.id] = (counts[item.id] ?? 0) + 1;
        store.setText(JSON.stringify(counts));
        hide();
    }

    // Launch counts survive restarts
    FileView {
        id: store
        path: root.historyPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                root.counts = JSON.parse(text());
            } catch (e) {}
        }
    }

    // [{ e: emoji, n: name, k: keywords }], from home-manager/desktop
    property var emoji: []

    FileView {
        path: `${Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"}/quickshell-launcher/emoji.json`
        printErrors: false
        onLoaded: {
            try {
                root.emoji = JSON.parse(text());
            } catch (e) {}
        }
    }

    visible: shown
    implicitWidth: 560
    implicitHeight: card.implicitHeight
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    HyprlandFocusGrab {
        active: root.shown
        windows: [root]
        onCleared: root.hide()
    }

    Rectangle {
        id: card

        width: parent.width
        implicitHeight: content.implicitHeight
        radius: 14
        color: Theme.base
        border.width: 1
        border.color: Theme.surface0

        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: content

            width: parent.width
            spacing: 0

            // Search field
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                spacing: 12

                Label {
                    text: Theme.glyph(0xf0349) // 󰍉
                    font.pixelSize: 18
                    color: Theme.lavender
                }

                TextInput {
                    id: search

                    Layout.fillWidth: true
                    focus: true
                    color: Theme.text
                    selectionColor: Theme.alpha(Theme.lavender, 0.35)
                    selectedTextColor: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15
                    clip: true
                    onTextChanged: {
                        root.query = text;
                        list.currentIndex = 0;
                    }

                    Label {
                        visible: !search.text
                        text: "Search apps, :emoji, /files or calculate…"
                        font.pixelSize: 15
                        color: Theme.overlay0
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Escape)
                            root.hide();
                        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N)))
                            list.incrementCurrentIndex();
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P)))
                            list.decrementCurrentIndex();
                        else if (event.key === Qt.Key_PageDown)
                            list.currentIndex = Math.min(list.count - 1, list.currentIndex + root.rows);
                        else if (event.key === Qt.Key_PageUp)
                            list.currentIndex = Math.max(0, list.currentIndex - root.rows);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            root.launch(root.results[list.currentIndex]);
                        else
                            return;
                        event.accepted = true;
                    }
                }

                Label {
                    readonly property int count: root.results.filter(r => r.run === undefined && r.result === undefined && r.window === undefined && r.ssh === undefined).length
                    readonly property int windows: root.results.filter(r => r.window !== undefined).length

                    text: root.emojiMode ? `${count} emoji` : root.fileMode ? `${count} ${count === 1 ? "file" : "files"}` : `${windows ? `${windows} ${windows === 1 ? "window" : "windows"} · ` : ""}${count} ${count === 1 ? "app" : "apps"}`
                    font.pixelSize: 11
                    color: Theme.overlay0
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.surface0
            }

            ListView {
                id: list

                Layout.fillWidth: true
                Layout.preferredHeight: root.rows * root.rowHeight + 16
                Layout.margins: 0
                topMargin: 8
                bottomMargin: 8
                clip: true
                model: root.results
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 80
                keyNavigationWraps: true

                highlight: Item {
                    width: list.width

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        radius: 10
                        color: Theme.alpha(Theme.lavender, 0.14)
                    }
                }

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool isCommand: modelData.run !== undefined
                    readonly property bool isResult: modelData.result !== undefined
                    readonly property bool isEmoji: modelData.emoji !== undefined
                    readonly property bool isWindow: modelData.window !== undefined
                    readonly property bool isSsh: modelData.ssh !== undefined
                    readonly property bool isFile: modelData.file !== undefined
                    readonly property bool isApp: !isCommand && !isResult && !isEmoji && !isWindow && !isSsh && !isFile
                    readonly property string icon: isApp || isWindow ? Quickshell.iconPath(modelData.icon, true) : ""
                    readonly property bool current: ListView.isCurrentItem
                    readonly property color accent: isCommand ? Theme.green : isResult ? Theme.peach : isSsh ? Theme.teal : isFile ? Theme.blue : Theme.lavender

                    width: list.width
                    height: root.rowHeight

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 14

                        Item {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32

                            IconImage {
                                anchors.fill: parent
                                visible: !!row.icon
                                source: row.icon
                                asynchronous: true
                            }
                            Label {
                                anchors.centerIn: parent
                                visible: row.isEmoji
                                text: row.isEmoji ? row.modelData.emoji : ""
                                font.pixelSize: 24
                            }
                            // Command or result row, or an app without a themed icon
                            Rectangle {
                                anchors.fill: parent
                                visible: !row.icon && !row.isEmoji
                                radius: 8
                                color: Theme.alpha(row.accent, 0.15)

                                Label {
                                    anchors.centerIn: parent
                                    text: row.isCommand ? Theme.glyph(0xf018d) : row.isResult ? Theme.glyph(0xf00ec) : row.isSsh ? Theme.glyph(0xf048b) : row.isFile ? Theme.glyph(row.modelData.folder ? 0xf024b : 0xf0214) : row.modelData.name[0].toUpperCase() // 󰆍 󰃬 󰒋 󰈔 󰉋
                                    font.pixelSize: row.isApp || row.isWindow ? 14 : 16
                                    font.bold: true
                                    color: row.accent
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: row.isCommand ? `Run “${row.modelData.run}”` : row.isResult ? `= ${row.modelData.display ?? row.modelData.result}` : row.isSsh ? `ssh ${row.modelData.ssh}` : row.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: 13
                                font.bold: row.current
                                color: row.current ? Theme.lavender : Theme.text
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: !!text
                                text: row.isCommand ? (row.modelData.run.startsWith("ssh ") ? "Open in terminal" : "Run as a command") : row.isResult ? (row.modelData.detail ?? "Copy the result") : row.isSsh ? (row.modelData.detail || "SSH host") : row.isFile ? row.modelData.dir : row.isEmoji ? row.modelData.keywords : row.isWindow ? root.windowPlace(row.modelData) : row.modelData.comment || row.modelData.genericName
                                font.pixelSize: 11
                                color: Theme.overlay1
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.currentIndex = row.index
                        onClicked: root.launch(row.modelData)
                    }
                }
            }

            // Key hints
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.surface0
            }
            Label {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                horizontalAlignment: Text.AlignHCenter
                readonly property var item: root.results[list.currentIndex]

                text: `↑↓  select     ⏎  ${root.emojiMode ? "paste" : item?.result !== undefined ? "copy" : item?.window !== undefined ? "go to window" : item?.ssh !== undefined ? "connect" : item?.file !== undefined ? "open" : "launch"}     esc  close`
                font.pixelSize: 10
                color: Theme.overlay0
            }
        }
    }
}
