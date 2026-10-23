import QtQuick

// A module of the bar: a rounded chip with its own accent colour on a soft
// tint of it. `solid` fills it with the accent, `plain` uses the neutral
// surface instead of a tint.
//
// Touch mode: holding a finger on it is a right click (the actions the bar
// has on the right button), it lights up while pressed, and the area that
// takes taps reaches over the gaps to the next chip and the bar's edges.
Rectangle {
    id: root

    property color accent: Theme.text
    property bool solid: false
    property bool plain: false
    property string text: ""
    property bool bold: false
    property int padding: Modes.barSize(10, 14, 16)
    property bool interactive: true // false: the content handles the mouse (tray)
    readonly property bool hovered: mouse.containsMouse || mouse.pressed
    readonly property color foreground: solid ? Theme.crust : accent
    default property alias content: row.data

    signal clicked(int button)
    signal scrolled(int steps) // + up, - down

    implicitWidth: row.implicitWidth + 2 * padding
    implicitHeight: Modes.barSize(19, 30, 36)
    radius: 8
    color: solid ? (hovered ? Qt.lighter(accent, 1.08) : accent) : plain ? (hovered ? Theme.surface1 : Theme.surface0) : Theme.alpha(accent, hovered ? 0.25 : 0.15)

    Behavior on color { ColorAnimation { duration: 200 } }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        BarLabel {
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
        // Half the bar's spacing to each side, and to the bar's edges
        anchors.leftMargin: Modes.touch ? -3 : 0
        anchors.rightMargin: Modes.touch ? -3 : 0
        anchors.topMargin: Modes.touch ? -5 : 0
        anchors.bottomMargin: Modes.touch ? -5 : 0
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => root.clicked(event.button)
        // A held press doesn't click as well
        onPressAndHold: event => root.clicked(Modes.touch ? Qt.RightButton : event.button)
        onWheel: event => {
            if (event.angleDelta.y !== 0)
                root.scrolled(event.angleDelta.y > 0 ? 1 : -1);
        }
    }
}
