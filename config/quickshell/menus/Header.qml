import QtQuick
import QtQuick.Layouts

// Menu title row: glyph, title, then the menu's own buttons on the right.
RowLayout {
    id: root

    property string glyph: ""
    property color accent: Theme.blue
    property string title: ""
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    spacing: 8

    Label {
        text: root.glyph
        color: root.accent
        font.pixelSize: 16
    }
    Label {
        Layout.fillWidth: true
        text: root.title
        font.pixelSize: 14
        font.bold: true
    }
    RowLayout {
        id: actionRow
        spacing: 6
    }
}
