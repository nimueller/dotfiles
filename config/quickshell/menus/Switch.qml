import QtQuick

// On/off switch; emits toggled() and leaves updating `checked` to the owner.
Rectangle {
    id: root

    property bool checked: false
    property color accent: Theme.blue
    property bool enabled: true

    signal toggled

    implicitWidth: 34
    implicitHeight: 18
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: checked ? accent : Theme.surface1

    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        width: 12
        height: 12
        radius: 6
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        color: root.checked ? Theme.base : Theme.overlay1

        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
