import QtQuick
import Quickshell.Wayland

// A window's picture in the overview, where the window is on its workspace
// (OverviewTile.qml). Click to go to it, drag it onto another workspace to
// move it there. Floating windows lie above the tiled ones, the last
// focused on top.
Item {
    id: picture

    required property var view // the overview's PanelWindow
    required property var toplevel // HyprlandToplevel
    readonly property var ipc: toplevel.lastIpcObject
    readonly property real originX: ((ipc?.at?.[0] ?? 0) - (view.monitor?.x ?? 0)) * view.factor
    readonly property real originY: ((ipc?.at?.[1] ?? 0) - (view.monitor?.y ?? 0)) * view.factor
    readonly property bool dragging: mouse.drag.active

    signal clicked

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

    Drag.active: dragging
    Drag.keys: ["overview-window"]
    Drag.hotSpot: Qt.point(width / 2, height / 2)

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: Theme.surface0
        border.width: mouse.containsMouse ? 2 : 1
        border.color: mouse.containsMouse ? Theme.mauve : Theme.surface2
        clip: true

        // Taken once, as the overview opens
        ScreencopyView {
            anchors.fill: parent
            anchors.margins: 1
            captureSource: picture.toplevel.wayland
            live: false
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - 8
            visible: parent.height > 30
            horizontalAlignment: Text.AlignHCenter
            text: picture.toplevel.title
            style: Text.Outline
            styleColor: Theme.crust
            font.pixelSize: 11
        }
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
}
