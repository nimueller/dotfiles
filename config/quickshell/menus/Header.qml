import QtQuick
import QtQuick.Layouts

// Menu title row: glyph, title, then the menu's own buttons on the right.
RowLayout {
    id: root

    property string glyph: ""
    property color accent: Theme.blue
    property string title: ""
    property string badge: ""
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    spacing: 8

    Label {
        text: root.glyph
        color: root.accent
        font.pixelSize: 16
    }
    Label {
        text: root.title
        font.pixelSize: 14
        font.bold: true
    }
    Rectangle {
        visible: !!root.badge
        implicitWidth: badgeLabel.implicitWidth + 12
        implicitHeight: 18
        radius: 9
        color: Theme.alpha(root.accent, 0.18)

        Label {
            id: badgeLabel
            anchors.centerIn: parent
            text: root.badge
            font.pixelSize: 10
            font.bold: true
            color: root.accent
        }
    }
    Item {
        Layout.fillWidth: true
    }
    RowLayout {
        id: actionRow
        spacing: 6
    }
}
