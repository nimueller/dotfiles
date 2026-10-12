import QtQuick

// Flat slider in the bar's chip style. Drag or click to set, wheel for 5%
// steps; `moved` gets the new value (0..1), the owner sets `value`.
Item {
    id: root

    property real value: 0 // 0..1
    property color accent: Theme.blue
    property bool dimmed: false // e.g. muted
    readonly property bool active: mouse.containsMouse || mouse.pressed

    signal moved(real value)

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
            color: root.dimmed ? Theme.overlay0 : root.accent

            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    Rectangle {
        width: root.active ? 14 : 12
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: (root.width - width) * root.value
        color: root.dimmed ? Theme.overlay1 : root.accent
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
            root.moved(Math.max(0, Math.min(1, (x - 4) / root.width)));
        }

        onPressed: e => setFrom(e.x)
        onPositionChanged: e => {
            if (pressed)
                setFrom(e.x);
        }
        onWheel: e => {
            const step = e.angleDelta.y > 0 ? 0.05 : -0.05;
            root.moved(Math.max(0, Math.min(1, Math.round((root.value + step) * 20) / 20)));
        }
    }
}
