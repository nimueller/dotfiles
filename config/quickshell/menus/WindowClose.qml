import QtQuick

// Close button like the GTK windows' (Catppuccin GTK theme, as in Nautilus):
// a 16 px red circle that shows a white × on hover, lighter and shaded while
// pressed, pale while the window isn't focused. Place it 10 px from the top
// right corner.
Rectangle {
    id: root

    signal clicked

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    implicitWidth: 16
    implicitHeight: 16
    radius: width / 2
    color: pressed ? "#eea2ae" : Window.active ? Theme.red : Qt.rgba(239 / 255, 241 / 255, 245 / 255, 0.3)

    // Shade while pressed
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: root.pressed
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    // The ×
    Repeater {
        model: [45, -45]

        delegate: Rectangle {
            required property int modelData

            anchors.centerIn: parent
            width: 8
            height: 1.5
            radius: 0.75
            rotation: modelData
            color: Window.active ? "white" : Qt.rgba(239 / 255, 241 / 255, 245 / 255, 0.5)
            visible: root.hovered || root.pressed
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
