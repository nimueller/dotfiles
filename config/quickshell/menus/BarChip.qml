import QtQuick

// A module of the bar: a rounded chip with its own accent colour on a soft
// tint of it (like the old waybar style). `solid` fills it with the accent,
// `plain` uses the neutral surface instead of a tint.
Rectangle {
    id: root

    property color accent: Theme.text
    property bool solid: false
    property bool plain: false
    property string text: ""
    property bool bold: false
    property int padding: 10
    property bool interactive: true // false: the content handles the mouse (tray)
    readonly property bool hovered: mouse.containsMouse
    readonly property color foreground: solid ? Theme.crust : accent
    default property alias content: row.data

    signal clicked(int button)
    signal scrolled(int steps) // + up, - down

    implicitWidth: row.implicitWidth + 2 * padding
    implicitHeight: 19
    radius: 8
    color: solid ? (hovered ? Qt.lighter(accent, 1.08) : accent) : plain ? (hovered ? Theme.surface1 : Theme.surface0) : Theme.alpha(accent, hovered ? 0.25 : 0.15)

    Behavior on color { ColorAnimation { duration: 200 } }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        Label {
            visible: !!root.text
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.foreground
            font.bold: root.bold || root.solid

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => root.clicked(event.button)
        onWheel: event => {
            if (event.angleDelta.y !== 0)
                root.scrolled(event.angleDelta.y > 0 ? 1 : -1);
        }
    }
}
