import QtQuick
import Quickshell
import Quickshell.Wayland

// A window's picture in the overview, where the window is on its workspace
// (OverviewTile.qml). Click to go to it, drag it onto another workspace to
// move it there, the x closes it. Floating windows lie above the tiled ones,
// the last focused on top.
Item {
    id: picture

    required property var view // the overview's PanelWindow
    required property var toplevel // HyprlandToplevel
    readonly property var ipc: toplevel.lastIpcObject
    readonly property real originX: ((ipc?.at?.[0] ?? 0) - view.originX) * view.factor
    readonly property real originY: ((ipc?.at?.[1] ?? 0) - view.originY) * view.factor
    readonly property bool dragging: mouse.drag.active
    readonly property var entry: Windows.entry(toplevel)

    signal clicked
    signal closeRequested

    x: originX
    y: originY
    width: Math.max(8, (ipc?.size?.[0] ?? 0) * view.factor)
    height: Math.max(8, (ipc?.size?.[1] ?? 0) * view.factor)
    // Above 0: below it, it would be under the workspace's frame
    z: dragging ? 1000 : (ipc?.floating ? 200 : 100) - Math.min(99, ipc?.focusHistoryID ?? 0)
    visible: !!ipc?.mapped && !ipc?.hidden

    // While dragged it lives on the window, above the other workspaces
    states: State {
        when: picture.dragging
        ParentChange {
            target: picture
            parent: picture.view.contentItem
        }
    }

    HoverHandler {
        id: hover
    }

    Drag.active: dragging
    Drag.keys: ["overview-window"]
    Drag.hotSpot: Qt.point(width / 2, height / 2)

    // Taken once, as the overview opens
    ScreencopyView {
        anchors.fill: parent
        captureSource: picture.toplevel.wayland
        live: false
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 2
        border.color: Theme.mauve
        visible: mouse.containsMouse
    }

    // Which app it is, as a window this small has nothing to read
    Image {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        width: 28
        height: 28
        visible: parent.height > 40 && status === Image.Ready
        opacity: picture.view.progress
        source: picture.entry?.icon ? Quickshell.iconPath(picture.entry.icon, true) : ""
        sourceSize: Qt.size(56, 56)
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        drag.target: picture
        drag.threshold: 8
        onClicked: picture.clicked()
        onReleased: {
            if (!picture.dragging)
                return;
            picture.Drag.drop();
            // Back to its place until Hyprland reports the move
            picture.x = Qt.binding(() => picture.originX);
            picture.y = Qt.binding(() => picture.originY);
        }
    }

    IconButton {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        visible: (hover.hovered || Modes.touch) && parent.height > 90 && parent.width > 60
        opacity: picture.view.progress
        glyph: Theme.glyph(0xf0156) // 󰅖
        accent: Theme.red
        onClicked: picture.closeRequested()
    }
}
