import QtQuick

// Round power-menu button with its label and shortcut key underneath.
Column {
    id: root

    required property var action
    property bool selected: false
    readonly property bool hovered: mouse.containsMouse

    signal triggered
    signal hoverEntered

    spacing: 12

    Rectangle {
        id: circle

        anchors.horizontalCenter: parent.horizontalCenter
        width: 120
        height: 120
        radius: width / 2
        color: mouse.pressed ? root.action.accent : root.selected ? Qt.tint(Theme.base, Theme.alpha(root.action.accent, 0.15)) : Theme.base
        border.width: 2
        border.color: root.selected ? root.action.accent : Theme.surface0
        scale: root.selected ? 1.06 : 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Label {
            anchors.centerIn: parent
            text: Theme.glyph(root.action.glyph)
            font.pixelSize: 40
            color: mouse.pressed ? Theme.crust : root.selected ? root.action.accent : Theme.text

            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hoverEntered()
            onClicked: root.triggered()
        }
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.action.text
        font.pixelSize: 13
        font.bold: true
        color: root.selected ? root.action.accent : Theme.subtext1
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.action.key
        font.pixelSize: 11
        color: Theme.overlay0
    }
}
