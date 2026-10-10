import QtQuick
import Quickshell.Services.Pipewire

// Flat slider in the bar's chip style. Drag or click to set, wheel for 5% steps.
Item {
    id: root

    required property PwNode node
    property color accent: Theme.blue

    readonly property bool muted: node?.audio?.muted ?? false
    readonly property real value: Math.min(node?.audio?.volume ?? 0, 1)
    readonly property bool active: mouse.containsMouse || mouse.pressed

    implicitHeight: 18

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.active ? 8 : 6
        radius: height / 2
        color: Theme.surface0

        Behavior on height { NumberAnimation { duration: 120 } }

        Rectangle {
            width: parent.width * root.value
            height: parent.height
            radius: parent.radius
            color: root.muted ? Theme.overlay0 : root.accent

            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    Rectangle {
        width: root.active ? 14 : 12
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: (root.width - width) * root.value
        color: root.muted ? Theme.overlay1 : root.accent
        border.width: 2
        border.color: Theme.base

        Behavior on width { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function setFrom(x) {
            Audio.setVolume(root.node, (x - 4) / root.width);
        }

        onPressed: e => setFrom(e.x)
        onPositionChanged: e => {
            if (pressed)
                setFrom(e.x);
        }
        onWheel: e => {
            const step = e.angleDelta.y > 0 ? 0.05 : -0.05;
            Audio.setVolume(root.node, Math.round((root.value + step) * 20) / 20);
        }
    }
}
