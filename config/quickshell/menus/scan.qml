//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Scanner: scans from the network scanners SANE finds (scan.py). Pick the
// scanner, glass or feeder, colour or grey and the resolution; a preview of
// the glass lets you drag the area to scan. From the feeder, it can take one
// page at a time (for scanners that pull in every page but hand over only
// the first) and both sides (the stack turned over for the backs, put in
// order afterwards). The pages collect in the strip
// below, where they can be turned, moved and removed, then go into one PDF
// (searchable with OCR if asked) or one image each, in Documents/Scans.
// Opened with `toggle.sh scan` or as "Scanner" from the launcher. Escape stops a scan or closes the window
// (asking first while pages aren't saved), Ctrl+S saves, Delete removes the
// page shown, the arrow keys go through the pages.
ShellRoot {
    id: root

    readonly property string helper: Quickshell.shellPath("scan.py")
    readonly property string home: Quickshell.env("HOME")
    readonly property string session: `${Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"}/qs-scan/session-${Date.now()}`
    property string folder: `${home}/Documents/Scans`

    property var devices: [] // [{ device, name, backend, ip }]
    property bool searching: false
    property var options: null // scan.py options
    property bool asking: false
    property string error: ""

    // Remembered between runs
    property string device: ""
    property string source: ""
    property string mode: ""
    property int dpi: 300
    property string format: "pdf" // pdf, jpg or png
    property bool ocr: false
    property bool oneByOne: false // feeder: a scan for each page
    property bool bothSides: false // feeder: fronts, then the backs

    // A run of scans from the feeder, from pages[start] on: the fronts
    // (pass 1), then the backs (pass 2), put in order by finishBatch().
    // `waiting` between scans: for the next page (one by one) or for the
    // stack turned over.
    property var batch: null // { start, fronts, pass, waiting }
    property bool stopping: false

    // The area to scan in mm, on the glass; null for all of it
    property var area: null
    property string preview: ""

    property var pages: [] // [{ file, turn }]
    property int current: -1 // the page shown, -1 for the preview
    property bool unsaved: false
    property bool confirmClose: false

    property string scanning: "" // "", "preview" or "pages"
    property real progress: 0
    property int scannedNow: 0 // pages in the running scan
    property int runs: 0
    property bool saving: false
    property string status: ""

    readonly property bool feeder: /adf|feeder|auto/i.test(source)
    readonly property bool busy: !!scanning || saving || !!batch
    readonly property string ip: devices.find(d => d.device === device)?.ip ?? ""

    function deviceLabel(d) {
        const backend = ({ airscan: "AirScan", epsonscan2: "Epson Scan 2" })[d.backend] ?? d.backend;
        return backend ? `${d.name} · ${backend}` : d.name;
    }

    function sourceLabel(s) {
        // Epson's "Auto": the feeder if there are pages in it, else the glass
        return /adf|feeder/i.test(s) ? "Feeder" : /auto/i.test(s) ? "Feeder (auto)" : /flatbed/i.test(s) ? "Glass" : s;
    }
    function modeLabel(m) {
        return ({ Color: "Colour", Gray: "Grey", Grayscale: "Grey", Lineart: "Black & white", Monochrome: "Black & white" })[m] ?? m;
    }
    function pick(list, wanted, fallback) {
        return list.includes(wanted) ? wanted : fallback ?? list[0] ?? "";
    }

    function searchDevices() {
        searching = true;
        error = "";
        devicesProc.running = true;
    }

    function loadOptions() {
        options = null;
        preview = "";
        area = null;
        if (!device)
            return;
        asking = true;
        error = "";
        optionsProc.command = [helper, "options", device];
        optionsProc.running = true;
    }

    function startScan(kind) {
        if (scanning || saving || !options || batch && !batch.waiting)
            return;
        const full = [0, 0, options.width, options.height];
        const a = kind === "pages" && area && !feeder ? [area.l, area.t, area.w, area.h] : full;
        const res = kind === "preview" ? Math.min(...options.resolutions) : dpi;
        const src = kind === "preview" ? options.sources.find(s => !/adf|feeder|auto/i.test(s)) ?? source : source;
        const count = kind === "preview" || !feeder || oneByOne ? ["1"] : [];
        if (kind === "pages" && feeder && (oneByOne || bothSides)) {
            if (!batch)
                batch = { start: pages.length, fronts: 0, pass: 1, waiting: false };
            else
                batch = Object.assign({}, batch, { waiting: false });
        }
        stopping = false;
        runs++;
        scanning = kind;
        progress = 0;
        scannedNow = 0;
        error = "";
        status = "";
        scanProc.errors = [];
        scanProc.command = [helper, "scan", device, session, `${kind}-${runs}`, src, kind === "preview" ? pick(options.modes, "Color") : mode, String(res), ...a.map(v => v.toFixed(2)), ...count];
        scanProc.running = true;
    }

    function stopScan() {
        if (scanning) {
            stopping = true;
            scanProc.running = false;
        } else if (batch) {
            finishBatch();
        }
    }

    // After a scan of the batch: wait for the next page or the turned stack
    function scanned() {
        if (stopping) {
            finishBatch();
            return;
        }
        const got = pages.length - batch.start - (batch.pass === 2 ? batch.fronts : 0);
        if (!oneByOne && batch.pass === 1 && !got)
            batch = null; // nothing in the feeder
        else if (!oneByOne && batch.pass === 1 && bothSides)
            batch = Object.assign({}, batch, { fronts: got, pass: 2, waiting: true });
        else if (!oneByOne)
            finishBatch();
        else
            batch = Object.assign({}, batch, { fronts: batch.pass === 1 ? got : batch.fronts, waiting: true });
    }

    // One by one: now the backs
    function startBacks() {
        if (batch && batch.waiting)
            batch = Object.assign({}, batch, { fronts: pages.length - batch.start, pass: 2 });
    }

    // The turned stack gives the backs last page first: front 1, back 1, …
    function finishBatch() {
        const b = batch;
        batch = null;
        if (!b || b.pass !== 2)
            return;
        const fronts = pages.slice(b.start, b.start + b.fronts);
        const backs = pages.slice(b.start + b.fronts).reverse();
        if (!backs.length)
            return;
        const merged = [];
        for (let i = 0; i < Math.max(fronts.length, backs.length); i++) {
            if (i < fronts.length)
                merged.push(fronts[i]);
            if (i < backs.length)
                merged.push(backs[i]);
        }
        pages = [...pages.slice(0, b.start), ...merged];
        current = b.start;
        status = fronts.length === backs.length ? `${fronts.length} sheets, both sides, put in order` : `${fronts.length} fronts but ${backs.length} backs: check the order`;
    }

    function save() {
        if (busy || !pages.length)
            return;
        const stamp = new Date().toLocaleString(Qt.locale(), "yyyy-MM-dd_HH-mm-ss");
        const base = (nameField.text.trim() || `Scan_${stamp}`).replace(/\//g, "-");
        const ext = format === "pdf" ? "pdf" : format;
        const kind = format === "pdf" && ocr ? "ocr" : format;
        saving = true;
        error = "";
        status = "";
        saveProc.command = [helper, "save", kind, `${folder}/${base}.${ext}`, ...pages.map(p => `${p.file}:${p.turn}`)];
        saveProc.running = true;
    }

    function turn(i, by) {
        pages = pages.map((p, j) => j === i ? { file: p.file, turn: (p.turn + by + 360) % 360 } : p);
        unsaved = true;
    }
    function move(i, by) {
        const j = i + by;
        if (j < 0 || j >= pages.length)
            return;
        const list = pages.slice();
        [list[i], list[j]] = [list[j], list[i]];
        pages = list;
        if (current === i)
            current = j;
        unsaved = true;
    }
    function remove(i) {
        pages = pages.filter((p, j) => j !== i);
        current = pages.length ? Math.min(current, pages.length - 1) : -1;
        unsaved = pages.length > 0;
    }
    function clearPages() {
        pages = [];
        current = -1;
        unsaved = false;
        confirmClose = false;
    }

    function close(force) {
        if (unsaved && !force) {
            confirmClose = true;
            return;
        }
        stopScan();
        Quickshell.execDetached(["rm", "-rf", session]);
        Menus.close("scan");
    }

    property bool loaded: false
    function remember() {
        if (loaded)
            settingsFile.setText(JSON.stringify({ device, source, mode, dpi, format, ocr, oneByOne, bothSides }, null, 2));
    }
    onOneByOneChanged: remember()
    onBothSidesChanged: remember()
    onDeviceChanged: remember()
    onSourceChanged: remember()
    onModeChanged: remember()
    onDpiChanged: remember()
    onFormatChanged: remember()
    onOcrChanged: remember()

    FileView {
        id: settingsFile
        path: `${root.home}/.local/state/quickshell-scan.json`
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.device = s.device ?? "";
                root.source = s.source ?? "";
                root.mode = s.mode ?? "";
                root.dpi = s.dpi ?? 300;
                root.format = ["pdf", "jpg", "png"].includes(s.format) ? s.format : "pdf";
                root.ocr = !!s.ocr;
                root.oneByOne = !!s.oneByOne;
                root.bothSides = !!s.bothSides;
            } catch (e) {}
        }
    }

    Component.onCompleted: {
        loaded = true;
        // Sessions of windows that didn't close cleanly
        Quickshell.execDetached(["sh", "-c", 'find "$1" -mindepth 1 -maxdepth 1 -name "session-*" -mmin +1440 -exec rm -rf {} +', "sh", session.replace(/\/[^/]*$/, "")]);
        searchDevices();
    }

    // Documents in the user's language (xdg-user-dirs)
    Process {
        running: true
        command: ["xdg-user-dir", "DOCUMENTS"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = text.trim();
                if (dir && dir !== root.home)
                    root.folder = `${dir}/Scans`;
            }
        }
    }

    Process {
        id: devicesProc
        command: [root.helper, "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text);
                } catch (e) {}
                root.devices = list;
                root.searching = false;
                const wanted = list.find(d => d.device === root.device) ?? list[0];
                if (!wanted) {
                    root.options = null;
                    return;
                }
                if (wanted.device !== root.device)
                    root.device = wanted.device;
                root.loadOptions();
            }
        }
    }

    Process {
        id: optionsProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.asking = false;
                let o = null;
                try {
                    o = JSON.parse(text);
                } catch (e) {}
                if (!o || o.error) {
                    root.error = o?.error ?? "The scanner doesn't answer";
                    return;
                }
                root.source = root.pick(o.sources, root.source, o.source);
                root.mode = root.pick(o.modes, root.mode, o.mode);
                root.dpi = o.resolutions.includes(root.dpi) ? root.dpi : o.resolutions.includes(300) ? 300 : o.resolution ?? o.resolutions[0];
                root.options = o;
            }
        }
    }

    Process {
        id: scanProc

        property var errors: []

        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf(" ");
                const what = line.slice(0, i), rest = line.slice(i + 1);
                if (what === "progress") {
                    root.progress = Number(rest) / 100;
                } else if (what === "page") {
                    root.scannedNow++;
                    root.progress = 0;
                    if (root.scanning === "preview") {
                        if (root.preview)
                            Quickshell.execDetached(["rm", "-f", root.preview]);
                        root.preview = rest;
                        root.current = -1;
                    } else {
                        root.pages = [...root.pages, { file: rest, turn: 0 }];
                        root.current = root.pages.length - 1;
                        root.unsaved = true;
                    }
                } else if (what === "error") {
                    scanProc.errors = [...scanProc.errors, rest];
                }
            }
        }
        onExited: (code, status) => {
            // The feeder running out ends every scan from it
            const errors = scanProc.errors.filter(e => !(root.scannedNow && /feeder is empty/.test(e)));
            if (!root.scannedNow)
                root.error = errors[errors.length - 1] ?? (root.scanning ? "Stopped" : "");
            else if (errors.length)
                root.error = errors[errors.length - 1];
            if (root.scanning === "pages" && root.scannedNow && !root.batch)
                root.status = root.scannedNow === 1 ? "1 page scanned" : `${root.scannedNow} pages scanned`;
            const kind = root.scanning;
            root.scanning = "";
            if (kind === "pages" && root.batch)
                root.scanned();
        }
    }

    // One by one: the next scan starts once the next page is in (seen twice
    // in a row, so it's all the way in)
    property int seenLoaded: 0
    Timer {
        interval: 1000
        repeat: true
        running: !!root.batch && root.batch.waiting && root.oneByOne && !!root.ip && !feederProc.running
        onTriggered: feederProc.running = true
        onRunningChanged: root.seenLoaded = 0
    }
    Process {
        id: feederProc
        command: [root.helper, "feeder", root.ip]
        stdout: StdioCollector {
            onStreamFinished: {
                root.seenLoaded = text.trim() === "loaded" ? root.seenLoaded + 1 : 0;
                if (root.seenLoaded >= 2 && root.batch?.waiting) {
                    root.seenLoaded = 0;
                    root.startScan("pages");
                }
            }
        }
    }

    Process {
        id: saveProc
        stdout: StdioCollector {
            id: saved
        }
        onExited: code => {
            root.saving = false;
            const files = saved.text.trim().split("\n").filter(f => f);
            if (code === 0 && files.length) {
                root.unsaved = false;
                root.confirmClose = false;
                root.status = `Saved as ${files[0].split("/").pop()}${files.length > 1 ? ` and ${files.length - 1} more` : ""}`;
            } else {
                root.error = "Couldn't save the scan";
            }
        }
    }

    // An image fitted into its parent, turned by `turn` degrees
    component Page: Item {
        id: page

        property string file: ""
        property int turn: 0
        property int detail: 1600
        readonly property alias image: img
        readonly property bool sideways: turn % 180 !== 0
        readonly property real fit: img.implicitWidth && img.implicitHeight ? Math.min(width / (sideways ? img.implicitHeight : img.implicitWidth), height / (sideways ? img.implicitWidth : img.implicitHeight)) : 0

        Image {
            id: img

            anchors.centerIn: parent
            width: implicitWidth * page.fit
            height: implicitHeight * page.fit
            rotation: page.turn
            source: page.file ? `file://${page.file}` : ""
            sourceSize.height: page.detail
            asynchronous: true
            smooth: true
            mipmap: true
            cache: false
        }
    }

    FloatingWindow {
        id: window

        title: "Scanner"
        implicitWidth: 1040
        implicitHeight: 740
        color: Theme.base
        onVisibleChanged: if (!visible)
            root.close(true)

        WindowClose {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            z: 2
            onClicked: root.close(false)
        }

        Item {
            id: keys

            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (root.scanning || root.batch)
                        root.stopScan();
                    else if (root.confirmClose)
                        root.confirmClose = false;
                    else
                        root.close(false);
                } else if (event.key === Qt.Key_S && event.modifiers & Qt.ControlModifier) {
                    root.save();
                } else if (event.key === Qt.Key_Delete && root.current >= 0) {
                    root.remove(root.current);
                } else if (event.key === Qt.Key_Left) {
                    root.current = Math.max(root.preview ? -1 : 0, root.current - 1);
                } else if (event.key === Qt.Key_Right) {
                    root.current = Math.min(root.pages.length - 1, root.current + 1);
                } else {
                    return;
                }
                event.accepted = true;
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Settings and saving
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 290
                color: Theme.mantle

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 10

                    Header {
                        glyph: Theme.glyph(0xf06ab) // 󰚫
                        accent: Theme.sapphire
                        title: "Scanner"

                        IconButton {
                            glyph: Theme.glyph(0xf0450) // 󰑐
                            accent: Theme.sapphire
                            active: root.searching
                            onClicked: if (!root.searching && !root.busy)
                                root.searchDevices()
                        }
                    }

                    Dropdown {
                        Layout.fillWidth: true
                        enabled: !root.busy
                        model: root.devices.length ? root.devices.map(d => ({ text: root.deviceLabel(d), value: d.device })) : [{ text: root.searching ? "Looking for scanners…" : "No scanner found", value: "" }]
                        current: root.devices.length ? root.device : ""
                        onPicked: value => {
                            if (value && value !== root.device) {
                                root.device = value;
                                root.loadOptions();
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: !root.searching && !root.devices.length
                        text: "Is it on and in this network? Only network scanners (eSCL/AirScan, WSD) are looked for."
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        color: Theme.subtext0
                        font.pixelSize: 11
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.options
                        enabled: !root.busy
                        opacity: enabled ? 1 : 0.5
                        spacing: 10

                        SectionTitle {
                            Layout.topMargin: 6
                            text: "Source"
                        }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: root.options?.sources ?? []
                                delegate: IconButton {
                                    required property string modelData
                                    text: root.sourceLabel(modelData)
                                    accent: Theme.sapphire
                                    active: root.source === modelData
                                    onClicked: root.source = modelData
                                }
                            }
                        }

                        SectionTitle {
                            text: "Colour"
                        }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: root.options?.modes ?? []
                                delegate: IconButton {
                                    required property string modelData
                                    text: root.modeLabel(modelData)
                                    accent: Theme.sapphire
                                    active: root.mode === modelData
                                    onClicked: root.mode = modelData
                                }
                            }
                        }

                        SectionTitle {
                            text: "Resolution"
                        }
                        Dropdown {
                            Layout.fillWidth: true
                            model: (root.options?.resolutions ?? []).map(r => ({ text: `${r} dpi${r === 150 || r === 200 ? " · documents" : r === 300 ? " · documents, text" : r >= 600 ? " · photos" : ""}`, value: r }))
                            current: root.dpi
                            onPicked: value => root.dpi = value
                        }

                        // The feeder's two ways
                        Repeater {
                            model: root.feeder ? [
                                { text: "One page at a time", on: root.oneByOne, flip: () => root.oneByOne = !root.oneByOne,
                                  hint: "For scanners that pull in every page but hand over only the first, as some do over AirScan. Put in one page; the next scan starts once the next one is in." },
                                { text: "Both sides", on: root.bothSides, flip: () => root.bothSides = !root.bothSides,
                                  hint: "The fronts first, then the stack turned over for the backs; the pages are put in order afterwards." }
                            ] : []

                            delegate: ColumnLayout {
                                required property var modelData

                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.text
                                        color: Theme.subtext1
                                    }
                                    Switch {
                                        checked: modelData.on
                                        accent: Theme.sapphire
                                        onToggled: modelData.flip()
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.hint
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideNone
                                    color: Theme.overlay1
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: !root.feeder || !root.oneByOne
                            text: root.feeder ? "All pages in the feeder are scanned." : root.area ? `Area ${(root.area.w / 10).toFixed(1)} × ${(root.area.h / 10).toFixed(1)} cm, from the preview` : "The whole glass. Drag over the preview to scan only a part of it."
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            color: Theme.subtext0
                            font.pixelSize: 11
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!root.options && (!root.batch || !!root.scanning)
                        spacing: 6

                        IconButton {
                            visible: !root.feeder
                            glyph: Theme.glyph(0xf0349) // 󰍉
                            text: "Preview"
                            enabled: !root.busy
                            opacity: enabled ? 1 : 0.5
                            onClicked: root.startScan("preview")
                        }
                        IconButton {
                            Layout.fillWidth: true
                            glyph: Theme.glyph(root.scanning ? 0xf04db : 0xf06ab) // 󰓛 / 󰚫
                            text: root.scanning ? "Stop" : root.pages.length ? "Scan another page" : "Scan"
                            accent: root.scanning ? Theme.red : Theme.sapphire
                            active: true
                            enabled: !root.saving
                            onClicked: root.scanning ? root.stopScan() : root.startScan("pages")
                        }
                    }

                    // Between the scans of a run from the feeder
                    Rectangle {
                        Layout.fillWidth: true
                        visible: !!root.batch && root.batch.waiting && !root.scanning
                        implicitHeight: between.implicitHeight + 20
                        radius: 10
                        color: Theme.alpha(Theme.sapphire, 0.12)

                        ColumnLayout {
                            id: between

                            readonly property int done: root.batch ? root.pages.length - root.batch.start - (root.batch.pass === 2 ? root.batch.fronts : 0) : 0
                            readonly property string side: root.bothSides ? (root.batch?.pass === 2 ? "back" : "front") : "page"

                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                text: !root.oneByOne ? `${root.batch?.fronts ?? 0} fronts scanned. Turn the stack over like a book page and put it in again.`
                                    : between.done === 0 && root.batch?.pass === 2 ? `${root.batch.fronts} fronts scanned. Turn the stack over like a book page, then put in the sheets one at a time for the backs.`
                                    : `${between.done === 1 ? `1 ${between.side}` : `${between.done} ${between.side}s`} scanned. Put in the next one${root.ip ? ", it starts by itself" : ""}.`
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                IconButton {
                                    glyph: Theme.glyph(0xf06ab) // 󰚫
                                    text: !root.oneByOne ? "Scan the backs" : "Scan now"
                                    accent: Theme.sapphire
                                    active: true
                                    onClicked: root.startScan("pages")
                                }
                                IconButton {
                                    visible: root.oneByOne && root.bothSides && root.batch?.pass === 1
                                    text: "On to the backs"
                                    onClicked: root.startBacks()
                                }
                                IconButton {
                                    text: "Done"
                                    onClicked: root.finishBatch()
                                }
                            }
                        }
                    }

                    // Progress of the running scan
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !!root.scanning || root.asking
                        spacing: 4

                        Label {
                            Layout.fillWidth: true
                            text: root.asking ? "Asking the scanner…" : root.scanning === "preview" ? "Preview…" : root.feeder ? `Page ${root.scannedNow + 1}…` : "Scanning…"
                            color: Theme.subtext0
                            font.pixelSize: 11
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 4
                            radius: 2
                            color: Theme.surface0

                            Rectangle {
                                width: parent.width * root.progress
                                height: parent.height
                                radius: 2
                                color: Theme.sapphire

                                Behavior on width { NumberAnimation { duration: 200 } }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: !!root.error
                        text: `${Theme.glyph(0xf0028)}  ${root.error}` // 󰀨
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        color: Theme.red
                        font.pixelSize: 11
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    // Saving
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.pages.length > 0
                        spacing: 10

                        SectionTitle {
                            text: root.pages.length === 1 ? "Save 1 page" : `Save ${root.pages.length} pages`
                        }
                        InputField {
                            id: nameField
                            Layout.fillWidth: true
                            placeholder: "Name (else Scan_<date>)"
                            onAccepted: root.save()
                            onKeyPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    keys.forceActiveFocus();
                                    event.accepted = true;
                                }
                            }
                        }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: [{ text: "PDF", value: "pdf" }, { text: "JPEG", value: "jpg" }, { text: "PNG", value: "png" }]
                                delegate: IconButton {
                                    required property var modelData
                                    text: modelData.text
                                    accent: Theme.green
                                    active: root.format === modelData.value
                                    onClicked: root.format = modelData.value
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.format === "pdf"
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                text: "Searchable text (OCR)"
                                color: Theme.subtext1
                            }
                            Switch {
                                checked: root.ocr
                                accent: Theme.green
                                onToggled: root.ocr = !root.ocr
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: root.format !== "pdf" && root.pages.length > 1
                            text: "One image per page."
                            color: Theme.subtext0
                            font.pixelSize: 11
                        }
                        IconButton {
                            Layout.fillWidth: true
                            glyph: Theme.glyph(0xf0193) // 󰆓
                            text: root.saving ? (root.format === "pdf" && root.ocr ? "Reading the text…" : "Saving…") : `Save to ${root.folder.replace(root.home, "~")}`
                            accent: Theme.green
                            active: true
                            enabled: !root.busy
                            onClicked: root.save()
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: !!root.status
                        text: root.status
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        color: Theme.green
                        font.pixelSize: 11
                    }

                    // Closing with pages not saved
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.confirmClose
                        implicitHeight: confirm.implicitHeight + 20
                        radius: 10
                        color: Theme.alpha(Theme.red, 0.12)

                        ColumnLayout {
                            id: confirm

                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                text: "The pages aren't saved. Close anyway?"
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                            }
                            RowLayout {
                                spacing: 6
                                IconButton {
                                    text: "Discard and close"
                                    accent: Theme.red
                                    active: true
                                    onClicked: root.close(true)
                                }
                                IconButton {
                                    text: "Keep"
                                    onClicked: root.confirmClose = false
                                }
                            }
                        }
                    }
                }
            }

            // The page or the preview, and the strip of pages
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Item {
                    id: stage

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 20
                    Layout.topMargin: 36

                    readonly property bool showingPreview: root.current < 0

                    Page {
                        id: big

                        anchors.fill: parent
                        file: stage.showingPreview ? root.preview : root.pages[root.current]?.file ?? ""
                        turn: stage.showingPreview ? 0 : root.pages[root.current]?.turn ?? 0
                        visible: !!file
                    }

                    // The area to scan, dragged on the preview
                    Item {
                        id: overlay

                        readonly property var img: big.image
                        readonly property real mmPerPx: root.options && img.width ? root.options.width / img.width : 0

                        visible: stage.showingPreview && !!root.preview && !root.feeder && img.status === Image.Ready
                        x: big.x + img.x
                        y: big.y + img.y
                        width: img.width
                        height: img.height

                        property point start

                        function clamp(v, max) {
                            return Math.max(0, Math.min(max, v));
                        }

                        Rectangle {
                            visible: !!root.area
                            x: (root.area?.l ?? 0) / overlay.mmPerPx
                            y: (root.area?.t ?? 0) / overlay.mmPerPx
                            width: (root.area?.w ?? 0) / overlay.mmPerPx
                            height: (root.area?.h ?? 0) / overlay.mmPerPx
                            color: Theme.alpha(Theme.sapphire, 0.15)
                            border.width: 2
                            border.color: Theme.sapphire
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.busy
                            cursorShape: Qt.CrossCursor
                            onPressed: mouse => overlay.start = Qt.point(mouse.x, mouse.y)
                            onPositionChanged: mouse => {
                                const x1 = overlay.clamp(Math.min(overlay.start.x, mouse.x), overlay.width), x2 = overlay.clamp(Math.max(overlay.start.x, mouse.x), overlay.width);
                                const y1 = overlay.clamp(Math.min(overlay.start.y, mouse.y), overlay.height), y2 = overlay.clamp(Math.max(overlay.start.y, mouse.y), overlay.height);
                                const m = overlay.mmPerPx;
                                root.area = { l: x1 * m, t: y1 * m, w: (x2 - x1) * m, h: (y2 - y1) * m };
                            }
                            // A click (or a tiny drag) takes the whole glass again
                            onReleased: if (root.area && (root.area.w < 5 || root.area.h < 5))
                                root.area = null
                        }
                    }

                    // Nothing to show yet
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, 360)
                        visible: !big.visible
                        spacing: 8

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: Theme.glyph(0xf06ab) // 󰚫
                            font.pixelSize: 48
                            color: Theme.surface2
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: !root.options ? "" : root.feeder ? "Put the pages in the feeder and scan." : "Put the page on the glass. A preview shows it, to scan only a part of it."
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            color: Theme.subtext0
                        }
                    }

                    Label {
                        anchors.top: parent.top
                        anchors.topMargin: -26
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: big.visible
                        text: stage.showingPreview ? "Preview" : `Page ${root.current + 1} of ${root.pages.length}`
                        color: Theme.overlay1
                        font.pixelSize: 11
                    }
                }

                // The pages
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 168
                    visible: root.pages.length > 0 || !!root.preview
                    color: Theme.mantle

                    ListView {
                        id: strip

                        anchors.fill: parent
                        anchors.margins: 12
                        orientation: ListView.Horizontal
                        spacing: 10
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        // The preview first, then the pages
                        model: [...(root.preview ? [{ file: root.preview, turn: 0, index: -1 }] : []), ...root.pages.map((p, i) => ({ file: p.file, turn: p.turn, index: i }))]

                        delegate: Rectangle {
                            id: thumb

                            required property var modelData
                            readonly property int page: modelData.index
                            readonly property bool shown: root.current === page
                            readonly property bool hovered: hover.containsMouse || tools.hovered

                            width: 110
                            height: strip.height
                            radius: 10
                            color: shown ? Theme.alpha(Theme.sapphire, 0.18) : hovered ? Theme.surface0 : "transparent"
                            border.width: shown ? 1 : 0
                            border.color: Theme.sapphire

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.current = thumb.page
                            }

                            Page {
                                anchors.fill: parent
                                anchors.margins: 8
                                anchors.bottomMargin: 26
                                file: thumb.modelData.file
                                turn: thumb.modelData.turn
                                detail: 320
                            }

                            Label {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: !(thumb.hovered && thumb.page >= 0)
                                text: thumb.page < 0 ? "Preview" : String(thumb.page + 1)
                                color: thumb.shown ? Theme.sapphire : Theme.subtext0
                                font.pixelSize: 11
                            }

                            // Turn, move and remove the page
                            Row {
                                id: tools

                                readonly property bool hovered: toolHover.hovered

                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: thumb.hovered && thumb.page >= 0 && !root.saving && !root.batch
                                spacing: 0

                                HoverHandler {
                                    id: toolHover
                                }

                                Repeater {
                                    model: [
                                        { glyph: 0xf0141, tip: "left", act: () => root.move(thumb.page, -1) }, // 󰅁
                                        { glyph: 0xf0465, tip: "turn left", act: () => root.turn(thumb.page, -90) }, // 󰑥
                                        { glyph: 0xf0467, tip: "turn right", act: () => root.turn(thumb.page, 90) }, // 󰑧
                                        { glyph: 0xf01b4, tip: "remove", act: () => root.remove(thumb.page) }, // 󰆴
                                        { glyph: 0xf0142, tip: "right", act: () => root.move(thumb.page, 1) } // 󰅂
                                    ]

                                    delegate: Label {
                                        required property var modelData

                                        width: 20
                                        height: 20
                                        horizontalAlignment: Text.AlignHCenter
                                        text: Theme.glyph(modelData.glyph)
                                        font.pixelSize: 13
                                        color: tool.containsMouse ? (modelData.glyph === 0xf01b4 ? Theme.red : Theme.text) : Theme.overlay1

                                        MouseArea {
                                            id: tool
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: modelData.act()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
