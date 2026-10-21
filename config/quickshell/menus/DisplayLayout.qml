import QtQuick

// The monitors as boxes in their real arrangement (logical size), scaled to
// fit. Click to select one, drag to move it; while dragged it snaps to the
// edges of the others, and on release moved(index, x, y) reports the new
// position.
Item {
    id: root

    property var monitors: [] // settings.qml's monitor entries
    property int selected: 0

    signal picked(int index)
    signal moved(int index, int x, int y)

    function size(m) {
        const [w, h] = (m.mode || "0x0").split("@")[0].split("x").map(Number);
        const rotated = m.transform % 2 === 1;
        return { w: Math.round((rotated ? h : w) / m.scale), h: Math.round((rotated ? w : h) / m.scale) };
    }

    readonly property var shown: monitors.map((m, i) => ({ m, i })).filter(e => e.m.connected && e.m.enabled)
    readonly property var bounds: {
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const { m } of shown) {
            const s = size(m);
            x0 = Math.min(x0, m.x);
            y0 = Math.min(y0, m.y);
            x1 = Math.max(x1, m.x + s.w);
            y1 = Math.max(y1, m.y + s.h);
        }
        return shown.length ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : { x: 0, y: 0, w: 1, h: 1 };
    }
    // Room around the layout so a box can be dragged past the others
    readonly property real factor: Math.min(width / (bounds.w * 1.6), height / (bounds.h * 1.6))
    readonly property real originX: (width - bounds.w * factor) / 2 - bounds.x * factor
    readonly property real originY: (height - bounds.h * factor) / 2 - bounds.y * factor

    // Snap one edge to the closest edge of another monitor within `reach`
    // (in pixels on screen, so it feels the same however small the boxes are)
    function snap(index, x, y) {
        const me = size(monitors[index]), reach = 16 / factor;
        let bestX = x, bestY = y, dx = reach, dy = reach;
        for (const { m, i } of shown) {
            if (i === index)
                continue;
            const o = size(m);
            for (const cx of [m.x - me.w, m.x + o.w, m.x, m.x + o.w - me.w])
                if (Math.abs(cx - x) < dx) {
                    dx = Math.abs(cx - x);
                    bestX = cx;
                }
            for (const cy of [m.y - me.h, m.y + o.h, m.y, m.y + o.h - me.h])
                if (Math.abs(cy - y) < dy) {
                    dy = Math.abs(cy - y);
                    bestY = cy;
                }
        }
        return { x: Math.round(bestX), y: Math.round(bestY) };
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.mantle
        border.width: 1
        border.color: Theme.surface0
    }

    Repeater {
        model: root.shown

        delegate: Rectangle {
            id: box

            required property var modelData

            readonly property var m: modelData.m
            readonly property var s: root.size(m)
            readonly property bool current: root.selected === modelData.i
            property bool dragging: false
            property point grab // where in the box it was grabbed
            property point pressedAt
            property var to: null // the snapped position while dragged

            // Back to the binding, at the reported position (or where it was)
            function settle() {
                dragging = false;
                x = Qt.binding(() => root.originX + m.x * root.factor);
                y = Qt.binding(() => root.originY + m.y * root.factor);
            }

            x: root.originX + m.x * root.factor
            y: root.originY + m.y * root.factor
            width: s.w * root.factor
            height: s.h * root.factor
            radius: 6
            color: current ? Theme.alpha(Theme.lavender, 0.22) : Theme.surface0
            border.width: current ? 2 : 1
            border.color: current ? Theme.lavender : Theme.surface2
            z: dragging ? 2 : current ? 1 : 0

            Column {
                anchors.centerIn: parent
                spacing: 2

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: box.m.name
                    font.bold: true
                    color: box.current ? Theme.lavender : Theme.text
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: `${box.s.w} × ${box.s.h}`
                    font.pixelSize: 10
                    color: Theme.subtext0
                }
            }

            // Dragged by hand rather than with drag.target, so the box can
            // jump to where it snaps
            MouseArea {
                anchors.fill: parent
                cursorShape: box.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: mouse => {
                    root.picked(box.modelData.i);
                    box.grab = Qt.point(mouse.x, mouse.y);
                    box.pressedAt = mapToItem(root, mouse.x, mouse.y);
                }
                onPositionChanged: mouse => {
                    const p = mapToItem(root, mouse.x, mouse.y);
                    if (!box.dragging && Math.hypot(p.x - box.pressedAt.x, p.y - box.pressedAt.y) < 4)
                        return;
                    box.dragging = true;
                    box.to = root.snap(box.modelData.i, (p.x - box.grab.x - root.originX) / root.factor, (p.y - box.grab.y - root.originY) / root.factor);
                    box.x = root.originX + box.to.x * root.factor;
                    box.y = root.originY + box.to.y * root.factor;
                }
                onReleased: {
                    if (!box.dragging)
                        return;
                    root.moved(box.modelData.i, box.to.x, box.to.y);
                    box.settle();
                }
                onCanceled: box.settle()
            }
        }
    }
}
