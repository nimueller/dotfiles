//@ pragma Env QT_QUICK_BACKEND=software
import QtQuick
import Quickshell
import Quickshell.Io

// Screenshot editor, started by screenshot.py once it has frozen every
// monitor (into QS_SCREENSHOT_DIR). Drag to
// select a region or click a window (a click on the desktop takes the whole
// monitor), then adjust the box by its edges and corners or move it, draw on
// it, pick the resolution and copy (Enter) or save (Ctrl+S), or copy the
// text or QR code in it (Ctrl+T). The keys are in
// ShotScreen.qml; Escape cancels.
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("QS_SCREENSHOT_DIR") ?? ""
    readonly property string home: Quickshell.env("HOME")

    // hyprctl monitors -j / clients -j, as they were when the shot was taken
    property var monitors: []
    property var clients: []

    // The selection lives on one monitor, in its logical coordinates;
    // width 0 means nothing is selected yet
    property string screenName: ""
    property rect selection: Qt.rect(0, 0, 0, 0)

    // Drawings on the selected monitor (see ShotScreen.qml for the shapes)
    property var shapes: []
    property var undone: []
    property string tool: "select"

    // Remembered between screenshots
    property int percent: 100
    property string color: Theme.red
    property int size: 1 // 0 thin, 1 medium, 2 thick

    readonly property var colors: [Theme.red, Theme.peach, Theme.yellow, Theme.green, Theme.blue, Theme.mauve, "#ffffff", "#000000"]
    readonly property var percents: [100, 75, 50, 25]

    signal finish(string action) // "copy", "save" or "text", handled by the selected monitor

    function select(name, rect) {
        if (name !== screenName) {
            shapes = [];
            undone = [];
        }
        screenName = name;
        selection = rect;
    }

    function addShape(shape) {
        shapes = [...shapes, shape];
        undone = [];
    }

    function undo() {
        if (!shapes.length)
            return;
        undone = [...undone, shapes[shapes.length - 1]];
        shapes = shapes.slice(0, -1);
    }

    function redo() {
        if (!undone.length)
            return;
        shapes = [...shapes, undone[undone.length - 1]];
        undone = undone.slice(0, -1);
    }

    function cancel() {
        Quickshell.execDetached(["rm", "-rf", dir]);
        Qt.quit();
    }

    property bool loaded: false
    function remember() {
        if (loaded)
            settingsFile.setText(JSON.stringify({ percent, color, size }, null, 2));
    }
    onPercentChanged: remember()
    onColorChanged: remember()
    onSizeChanged: remember()

    // Start with the active window or the focused monitor if asked to
    function preselect(mode) {
        const focused = monitors.find(m => m.focused) ?? monitors[0];
        screenName = focused?.name ?? "";
        if (mode === "screen" && focused) {
            selection = Qt.rect(0, 0, Math.round(focused.width / focused.scale), Math.round(focused.height / focused.scale));
        } else if (mode === "window") {
            const c = clients.find(c => c.focusHistoryID === 0);
            const m = c && monitors.find(m => m.id === c.monitor);
            if (m) {
                screenName = m.name;
                const x = Math.max(0, c.at[0] - m.x), y = Math.max(0, c.at[1] - m.y);
                selection = Qt.rect(x, y, Math.min(c.size[0], m.width / m.scale - x), Math.min(c.size[1], m.height / m.scale - y));
            }
        }
    }

    FileView {
        path: `${root.dir}/monitors.json`
        blockLoading: true
        onLoaded: {
            root.monitors = JSON.parse(text());
            root.filesLoaded++;
        }
    }
    FileView {
        path: `${root.dir}/clients.json`
        blockLoading: true
        onLoaded: {
            root.clients = JSON.parse(text());
            root.filesLoaded++;
        }
    }
    FileView {
        id: settingsFile
        path: `${root.home}/.local/state/quickshell-screenshot.json`
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.percent = root.percents.includes(s.percent) ? s.percent : 100;
                root.color = s.color ?? Theme.red;
                root.size = Math.max(0, Math.min(2, s.size ?? 1));
            } catch (e) {}
        }
    }

    // Once the monitors and windows are known
    property int filesLoaded: 0
    onFilesLoadedChanged: {
        if (filesLoaded === 2)
            preselect(Quickshell.env("QS_SCREENSHOT_MODE") ?? "region");
    }
    Component.onCompleted: loaded = true

    Variants {
        model: Quickshell.screens

        delegate: ShotScreen {
            editor: root
        }
    }
}
