import QtQuick
import Quickshell
import Quickshell.Wayland

// One monitor of the screenshot editor (screenshot.qml): the frozen screen,
// the selection with its handles, the drawings and the toolbar.
//   Mouse: drag to select a region; click a window to take it, or the
//   desktop for the whole monitor. Drag an edge or corner to resize, inside
//   to move (move tool) or to draw (the other tools; Shift keeps lines at
//   45° and boxes square). Double-click inside copies, right click drops the
//   selection.
//   Keys: Enter / Ctrl+C copy, Ctrl+S save, Ctrl+T copy the text (OCR) or
//   the QR code's content, Ctrl+R record a video, Escape cancel, Ctrl+Z and
//   Ctrl+Shift+Z / Ctrl+Y undo and redo, V P L A R O M T B pick a tool, F
//   takes the whole monitor, 1-4 the resolution (100, 75, 50, 25 %), arrows
//   move the box (Shift: 10 px).
PanelWindow {
    id: win

    required property var modelData // ShellScreen
    required property var editor

    readonly property string name: modelData.name
    readonly property bool active: editor.screenName === name
    readonly property rect sel: editor.selection
    readonly property bool selected: active && sel.width > 0 && sel.height > 0
    readonly property var monitor: editor.monitors.find(m => m.name === name) ?? null
    readonly property string file: `${editor.dir}/${name}.png`

    // Physical pixels per logical one, and the size of the result
    readonly property real factor: frozen.implicitWidth > 0 ? frozen.implicitWidth / width : 1
    readonly property int outWidth: Math.round(sel.width * factor * editor.percent / 100)
    readonly property int outHeight: Math.round(sel.height * factor * editor.percent / 100)

    readonly property var strokes: [2, 4, 8]
    readonly property var textSizes: [16, 24, 36]
    readonly property int block: 16 // pixelate: block size in physical pixels

    // Windows on the workspaces this monitor showed, top-most first
    readonly property var windows: {
        const m = monitor;
        if (!m) {
            return [];
        }
        const shown = [m.activeWorkspace?.id, m.specialWorkspace?.id].filter(id => id);
        const isShown = c => c.mapped && !c.hidden && c.monitor === m.id && shown.includes(c.workspace.id);
        const bySpecial = (a, b) => (b.workspace.id < 0) - (a.workspace.id < 0);
        const byStacking = (a, b) => bySpecial(a, b) || b.floating - a.floating || a.focusHistoryID - b.focusHistoryID;
        const toRect = c => Qt.rect(c.at[0] - m.x, c.at[1] - m.y, c.size[0], c.size[1]);
        return editor.clients.filter(isShown).sort(byStacking).map(toRect);
    }

    property string drag: "" // "new", "move", "resize" or "draw" while the button is down
    property bool moved: false
    property point pressAt
    property rect pressSel
    property var edges: null // { l, r, t, b } while resizing
    property var pending: null // the shape being drawn
    property var hovered: null // window under the pointer while nothing is selected
    property var textAt: null // { x, y } while typing a text
    property int pointer: Qt.CrossCursor

    // The four rectangles around the selection: above, below, left, right
    function shades() {
        const s = sel;
        const below = s.y + s.height;
        const right = s.x + s.width;
        const rects = [];
        rects.push(Qt.rect(0, 0, width, s.y));
        rects.push(Qt.rect(0, below, width, height - below));
        rects.push(Qt.rect(0, s.y, s.x, s.height));
        rects.push(Qt.rect(right, s.y, width - right, s.height));
        return rects;
    }

    function contains(r, p) {
        return p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height;
    }

    function clamp(r) {
        const x = Math.max(0, r.x), y = Math.max(0, r.y);
        const right = Math.min(r.x + r.width, width);
        const bottom = Math.min(r.y + r.height, height);
        return Qt.rect(x, y, Math.max(0, right - x), Math.max(0, bottom - y));
    }

    // A rectangle moved by dx, dy, but kept on the screen
    function movedOnScreen(r, dx, dy) {
        const x = Math.max(0, Math.min(r.x + dx, width - r.width));
        const y = Math.max(0, Math.min(r.y + dy, height - r.height));
        return Qt.rect(x, y, r.width, r.height);
    }

    function rectFrom(a, b) {
        return Qt.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(a.x - b.x), Math.abs(a.y - b.y));
    }

    // Which edges of the selection are under `p`, or null
    function edgesAt(p) {
        if (!selected) {
            return null;
        }
        const t = 8, s = sel;
        if (p.x < s.x - t || p.x > s.x + s.width + t || p.y < s.y - t || p.y > s.y + s.height + t) {
            return null;
        }
        const e = {
            l: Math.abs(p.x - s.x) < t,
            r: Math.abs(p.x - s.x - s.width) < t,
            t: Math.abs(p.y - s.y) < t,
            b: Math.abs(p.y - s.y - s.height) < t
        };
        if (e.l && e.r) {
            e.l = false;
        }
        if (e.t && e.b) {
            e.t = false;
        }
        return e.l || e.r || e.t || e.b ? e : null;
    }

    function pointerAt(p) {
        const e = edgesAt(p);
        if (e) {
            if (e.l && e.t || e.r && e.b) {
                return Qt.SizeFDiagCursor;
            }
            if (e.r && e.t || e.l && e.b) {
                return Qt.SizeBDiagCursor;
            }
            if (e.l || e.r) {
                return Qt.SizeHorCursor;
            }
            return Qt.SizeVerCursor;
        }
        if (selected && contains(sel, p)) {
            if (editor.tool === "select") {
                return Qt.SizeAllCursor;
            }
            if (editor.tool === "text") {
                return Qt.IBeamCursor;
            }
            return Qt.CrossCursor;
        }
        return Qt.CrossCursor;
    }

    // Drawing --------------------------------------------------------------------

    function newShape(p) {
        const tool = editor.tool;
        return {
            type: tool,
            color: editor.color,
            width: tool === "marker" ? strokes[editor.size] * 5 : strokes[editor.size],
            points: [[p.x, p.y]],
            x1: p.x,
            y1: p.y,
            x2: p.x,
            y2: p.y
        };
    }

    // Shift: lines in steps of 45°, boxes square
    function extendShape(p, shift) {
        const s = pending;
        if (s.type === "pen" || s.type === "marker") {
            s.points.push([p.x, p.y]);
            canvas.requestPaint();
            return;
        }
        let x = p.x, y = p.y;
        const dx = x - s.x1, dy = y - s.y1;
        if (shift && (s.type === "line" || s.type === "arrow")) {
            const a = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * Math.PI / 4, len = Math.hypot(dx, dy);
            x = s.x1 + Math.cos(a) * len;
            y = s.y1 + Math.sin(a) * len;
        } else if (shift) {
            const d = Math.max(Math.abs(dx), Math.abs(dy));
            x = s.x1 + Math.sign(dx || 1) * d;
            y = s.y1 + Math.sign(dy || 1) * d;
        }
        pending = Object.assign({}, s, {
            x2: x,
            y2: y
        });
    }

    function finishShape() {
        const s = pending;
        pending = null;
        if (!s) {
            return;
        }
        if (s.type === "pen" || s.type === "marker") {
            if (s.points.length === 1) // a click: a dot
            {
                s.points.push([s.x1 + 0.1, s.y1]);
            }
            editor.addShape(s);
        } else if (Math.abs(s.x2 - s.x1) + Math.abs(s.y2 - s.y1) > 3) {
            editor.addShape(s);
        }
        canvas.requestPaint();
    }

    function paintShape(ctx, s) {
        const x1 = s.x1, y1 = s.y1, x2 = s.x2, y2 = s.y2;
        ctx.save();
        ctx.strokeStyle = s.color;
        ctx.fillStyle = s.color;
        ctx.lineWidth = s.width;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.beginPath();
        switch (s.type) {
        case "marker":
            ctx.globalAlpha = 0.4;
        // fall through
        case "pen":
            ctx.moveTo(s.points[0][0], s.points[0][1]);
            for (const q of s.points) {
                ctx.lineTo(q[0], q[1]);
            }
            ctx.stroke();
            break;
        case "line":
            ctx.moveTo(x1, y1);
            ctx.lineTo(x2, y2);
            ctx.stroke();
            break;
        case "arrow":
            {
                const a = Math.atan2(y2 - y1, x2 - x1);
                const head = Math.min(Math.hypot(x2 - x1, y2 - y1), 12 + s.width * 3);
                // The shaft ends inside the head, so its round cap doesn't show at the tip
                ctx.moveTo(x1, y1);
                ctx.lineTo(x2 - Math.cos(a) * head * 0.7, y2 - Math.sin(a) * head * 0.7);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(x2, y2);
                ctx.lineTo(x2 - head * Math.cos(a - 0.45), y2 - head * Math.sin(a - 0.45));
                ctx.lineTo(x2 - head * Math.cos(a + 0.45), y2 - head * Math.sin(a + 0.45));
                ctx.closePath();
                ctx.fill();
                break;
            }
        case "rect":
            ctx.rect(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1));
            ctx.stroke();
            break;
        case "ellipse":
            ctx.ellipse(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1));
            ctx.stroke();
            break;
        }
        ctx.restore();
    }

    function commitText() {
        if (textAt && textInput.text.trim()) {
            editor.addShape({
                type: "text",
                x: textAt.x,
                y: textAt.y,
                text: textInput.text,
                color: editor.color,
                size: textSizes[editor.size]
            });
        }
        textAt = null;
        textInput.text = "";
        keys.forceActiveFocus();
    }

    // Result -------------------------------------------------------------------

    // Grab the drawings (without the screenshot under them) at the physical
    // size, then screenshot.py puts them onto the shot, crops and scales it.
    // It runs detached, so the editor can close right away.
    function exportShot(action) {
        if (!selected) {
            return;
        }
        if (action === "record") {
            recordShot();
            return;
        }
        commitText();
        const f = factor;
        const size = `${Math.round(sel.width * f)}x${Math.round(sel.height * f)}`;
        const offset = `+${Math.round(sel.x * f)}+${Math.round(sel.y * f)}`;
        const geometry = size + offset;
        const script = Quickshell.shellPath("screenshot.py");
        const percent = String(editor.percent);
        const run = layerFile => {
            Quickshell.execDetached([script, "--export", editor.dir, file, layerFile, geometry, percent, action]);
            Qt.quit();
        };
        if (!editor.shapes.length) {
            run("-");
            return;
        }
        // The window's scale applies on top of the size asked for
        layer.grabToImage(result => {
            result.saveToFile(`${editor.dir}/layer.png`);
            run(`${editor.dir}/layer.png`);
        }, Qt.size(width, height));
    }

    // A video of the selection, in the layout's logical coordinates, which
    // wf-recorder takes; screenshot.py records until the bar or the
    // screenshot key stops it
    function recordShot() {
        const position = `${Math.round(monitor.x + sel.x)},${Math.round(monitor.y + sel.y)}`;
        const size = `${Math.round(sel.width)}x${Math.round(sel.height)}`;
        const script = Quickshell.shellPath("screenshot.py");
        const audio = editor.sound ? "sound" : "mute";
        Quickshell.execDetached([script, "--record", editor.dir, name, position, size, String(editor.percent), audio]);
        Qt.quit();
    }

    Connections {
        target: win.editor

        function onFinish(action) {
            if (win.active) {
                win.exportShot(action);
            }
        }
        function onShapesChanged() {
            canvas.requestPaint();
        }
    }

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "black"

    WlrLayershell.namespace: "quickshell-screenshot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // The frozen screen
    Image {
        id: frozen
        anchors.fill: parent
        source: `file://${win.file}`
        cache: false
        smooth: true
    }

    // What gets exported on top of the screenshot: pixelated areas, strokes, texts
    Item {
        id: layer

        anchors.fill: parent
        visible: win.active

        Repeater {
            model: {
                if (!win.active) {
                    return [];
                }
                const shapes = win.pending ? [...win.editor.shapes, win.pending] : win.editor.shapes;
                return shapes.filter(s => s.type === "pixelate");
            }

            // A window onto the whole screen scaled down to one pixel per block
            delegate: Item {
                required property var modelData

                x: Math.min(modelData.x1, modelData.x2)
                y: Math.min(modelData.y1, modelData.y2)
                width: Math.abs(modelData.x2 - modelData.x1)
                height: Math.abs(modelData.y2 - modelData.y1)
                clip: true

                Image {
                    x: -parent.x
                    y: -parent.y
                    width: win.width
                    height: win.height
                    source: frozen.source
                    sourceSize: {
                        const columns = Math.ceil(frozen.implicitWidth / win.block);
                        const rows = Math.ceil(frozen.implicitHeight / win.block);
                        return Qt.size(columns, rows);
                    }
                    smooth: false
                    asynchronous: true
                }
            }
        }

        Canvas {
            id: canvas

            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                for (const s of win.editor.shapes) {
                    if (s.type !== "pixelate" && s.type !== "text") {
                        win.paintShape(ctx, s);
                    }
                }
                if (win.pending && win.pending.type !== "pixelate") {
                    win.paintShape(ctx, win.pending);
                }
            }
        }

        Repeater {
            model: win.active ? win.editor.shapes.filter(s => s.type === "text") : []

            delegate: Text {
                required property var modelData

                x: modelData.x
                y: modelData.y
                text: modelData.text
                color: modelData.color
                font.family: Theme.font
                font.pixelSize: modelData.size
                font.bold: true
            }
        }
    }

    onPendingChanged: canvas.requestPaint()

    // Dim what's outside the selection
    Rectangle {
        anchors.fill: parent
        visible: !win.selected
        color: Theme.alpha(Theme.crust, 0.35)
    }
    Item {
        anchors.fill: parent
        visible: win.selected

        Repeater {
            model: win.shades()

            delegate: Rectangle {
                required property rect modelData

                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                color: Theme.alpha(Theme.crust, 0.6)
            }
        }
    }

    // The window a click would take
    Rectangle {
        visible: !win.selected && !win.drag && !!win.hovered
        x: win.hovered?.x ?? 0
        y: win.hovered?.y ?? 0
        width: win.hovered?.width ?? 0
        height: win.hovered?.height ?? 0
        color: Theme.alpha(Theme.lavender, 0.1)
        border.width: 2
        border.color: Theme.lavender
    }

    // Selection frame and handles
    Rectangle {
        visible: win.selected
        x: win.sel.x - 1
        y: win.sel.y - 1
        width: win.sel.width + 2
        height: win.sel.height + 2
        color: "transparent"
        border.width: 1
        border.color: Theme.lavender

        Repeater {
            model: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]]

            delegate: Rectangle {
                required property var modelData

                x: modelData[0] * (parent.width - 1) - 4
                y: modelData[1] * (parent.height - 1) - 4
                width: 9
                height: 9
                radius: 2
                color: Theme.text
                border.width: 1
                border.color: Theme.crust
            }
        }
    }

    // Size while selecting
    Rectangle {
        visible: win.selected && (win.drag === "new" || win.drag === "resize")
        x: win.sel.x
        y: win.sel.y >= 30 ? win.sel.y - 28 : win.sel.y + 6
        width: sizeLabel.implicitWidth + 16
        height: 22
        radius: 6
        color: Theme.base

        Label {
            id: sizeLabel
            anchors.centerIn: parent
            text: `${win.outWidth} × ${win.outHeight}`
            color: Theme.subtext1
        }
    }

    TextInput {
        id: textInput

        visible: !!win.textAt
        x: win.textAt?.x ?? 0
        y: win.textAt?.y ?? 0
        color: win.editor.color
        font.family: Theme.font
        font.pixelSize: win.textSizes[win.editor.size]
        font.bold: true
        cursorVisible: true
        onAccepted: win.commitText()
        Keys.onEscapePressed: {
            text = "";
            win.textAt = null;
            keys.forceActiveFocus();
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: win.pointer

        onPressed: mouse => {
            const p = Qt.point(mouse.x, mouse.y);
            if (win.textAt) {
                win.commitText();
                return;
            }
            if (mouse.button === Qt.RightButton) {
                if (win.active) {
                    win.editor.selection = Qt.rect(0, 0, 0, 0);
                }
                return;
            }
            win.pressAt = p;
            win.pressSel = win.sel;
            win.moved = false;
            const e = win.edgesAt(p);
            const inside = win.selected && win.contains(win.sel, p);
            if (e) {
                win.drag = "resize";
                win.edges = e;
            } else if (inside && win.editor.tool === "select") {
                win.drag = "move";
            } else if (inside && win.editor.tool === "text") {
                // The click marks the middle of the first line
                win.textAt = {
                    x: p.x,
                    y: p.y - win.textSizes[win.editor.size] * 0.65
                };
                textInput.text = "";
                textInput.forceActiveFocus();
            } else if (inside) {
                win.drag = "draw";
                win.pending = win.newShape(p);
            } else {
                win.drag = "new";
            }
        }

        onPositionChanged: mouse => {
            const p = Qt.point(mouse.x, mouse.y);
            if (!win.drag) {
                win.pointer = win.pointerAt(p);
                win.hovered = win.selected ? null : win.windows.find(r => win.contains(r, p)) ?? null;
                return;
            }
            const dx = p.x - win.pressAt.x, dy = p.y - win.pressAt.y;
            if (Math.abs(dx) + Math.abs(dy) > 3) {
                win.moved = true;
            }
            const s = win.pressSel;
            if (win.drag === "new" && win.moved) {
                win.editor.select(win.name, win.clamp(win.rectFrom(win.pressAt, p)));
            } else if (win.drag === "move") {
                win.editor.selection = win.movedOnScreen(s, dx, dy);
            } else if (win.drag === "resize") {
                const e = win.edges;
                const l = s.x + (e.l ? dx : 0), r = s.x + s.width + (e.r ? dx : 0);
                const t = s.y + (e.t ? dy : 0), b = s.y + s.height + (e.b ? dy : 0);
                win.editor.selection = win.clamp(win.rectFrom(Qt.point(l, t), Qt.point(r, b)));
            } else if (win.drag === "draw") {
                win.extendShape(p, mouse.modifiers & Qt.ShiftModifier);
            }
        }

        onReleased: mouse => {
            const p = Qt.point(mouse.x, mouse.y);
            if (win.drag === "new" && !win.moved) {
                // A click: the window under it, or the whole monitor
                const w = win.windows.find(r => win.contains(r, p));
                win.editor.select(win.name, w ? win.clamp(w) : Qt.rect(0, 0, win.width, win.height));
            } else if (win.drag === "draw") {
                win.finishShape();
            }
            win.drag = "";
            win.edges = null;
            win.hovered = null;
            win.pointer = win.pointerAt(p);
        }

        onDoubleClicked: mouse => {
            if (win.selected && win.editor.tool === "select" && win.contains(win.sel, Qt.point(mouse.x, mouse.y))) {
                win.exportShot("copy");
            }
        }
    }

    // Before anything is selected
    Rectangle {
        visible: win.active && !win.selected && !win.drag
        anchors.horizontalCenter: parent.horizontalCenter
        y: 24
        width: hint.implicitWidth + 32
        height: 36
        radius: 10
        color: Theme.base
        border.width: 1
        border.color: Theme.surface0

        Label {
            id: hint
            anchors.centerIn: parent
            text: I18n.tr("Drag to select  ·  click a window, or the desktop for the whole screen  ·  F whole screen  ·  Esc cancel")
            color: Theme.subtext1
        }
    }

    ShotToolbar {
        id: toolbar

        readonly property real below: win.sel.y + win.sel.height + 10
        readonly property real above: win.sel.y - height - 34

        editor: win.editor
        outWidth: win.outWidth
        outHeight: win.outHeight
        visible: win.selected && win.drag !== "new" && win.drag !== "move" && win.drag !== "resize"
        x: Math.max(8, Math.min(win.sel.x + (win.sel.width - width) / 2, win.width - width - 8))
        // Below the selection, else above it, else inside at the bottom (room for the hint underneath)
        y: {
            if (below + height + 34 <= win.height) {
                return below;
            }
            if (above >= 8) {
                return above;
            }
            return win.sel.y + win.sel.height - height - 40;
        }
    }

    Item {
        id: keys

        focus: true
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier;
            const k = event.key, e = win.editor;
            const tools = {
                V: "select",
                P: "pen",
                L: "line",
                A: "arrow",
                R: "rect",
                O: "ellipse",
                M: "marker",
                T: "text",
                B: "pixelate"
            };
            const letter = event.text.toUpperCase();
            if (k === Qt.Key_Escape) {
                e.cancel();
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter || ctrl && k === Qt.Key_C) {
                win.exportShot("copy");
            } else if (ctrl && k === Qt.Key_S) {
                win.exportShot("save");
            } else if (ctrl && k === Qt.Key_T) {
                win.exportShot("text");
            } else if (ctrl && k === Qt.Key_R) {
                win.exportShot("record");
            } else if (ctrl && (k === Qt.Key_Y || k === Qt.Key_Z && shift)) {
                e.redo();
            } else if (ctrl && k === Qt.Key_Z) {
                e.undo();
            } else if (win.selected && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(k)) {
                const step = shift ? 10 : 1, s = win.sel;
                let dx = 0;
                let dy = 0;
                if (k === Qt.Key_Left) {
                    dx = -step;
                } else if (k === Qt.Key_Right) {
                    dx = step;
                } else if (k === Qt.Key_Up) {
                    dy = -step;
                } else {
                    dy = step;
                }
                e.selection = win.movedOnScreen(s, dx, dy);
            } else if (ctrl) {
                return;
            } else if (tools[letter]) {
                e.tool = tools[letter];
            } else if (letter === "F") {
                e.select(win.name, Qt.rect(0, 0, win.width, win.height));
            } else if (letter >= "1" && letter <= "4") {
                e.percent = e.percents[Number(letter) - 1];
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
