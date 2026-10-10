import QtQuick
import QtQuick.Layouts

// Small chip button with a glyph and optional text. `active` tints it with
// the accent, for toggles like do-not-disturb.
Rectangle {
    id: root

    property string glyph: ""
    property string text: ""
    property color accent: Theme.lavender
    property bool active: false
    readonly property bool hovered: mouse.containsMouse

    signal clicked

    implicitWidth: text ? row.implicitWidth + 20 : 28
    implicitHeight: 28
    radius: 8
    color: active ? Theme.alpha(accent, hovered ? 0.3 : 0.18) : hovered ? Theme.surface1 : Theme.surface0

    Behavior on color { ColorAnimation { duration: 150 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Label {
            text: root.glyph
            color: root.active ? root.accent : root.hovered ? Theme.text : Theme.overlay2
        }
        Label {
            visible: !!root.text
            text: root.text
            font.pixelSize: 11
            color: root.active ? root.accent : root.hovered ? Theme.text : Theme.subtext0
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
